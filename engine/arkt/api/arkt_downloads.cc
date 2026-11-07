#include "arkt/api/arkt_downloads.h"

#include <algorithm>
#include <memory>
#include <utility>

#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/download/download_prefs.h"  // nogncheck
#include "chrome/browser/profiles/profile.h"
#include "components/download/public/common/download_danger_type.h"
#include "components/download/public/common/download_interrupt_reasons.h"
#include "components/download/public/common/download_url_parameters.h"
#include "components/download/public/common/simple_download_manager.h"
#include "content/public/browser/download_request_utils.h"
#include "content/public/browser/web_contents.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "ui/shell_dialogs/select_file_dialog.h"
#include "ui/shell_dialogs/select_file_dialog_factory.h"
#include "ui/shell_dialogs/select_file_policy.h"
#include "ui/shell_dialogs/selected_file_info.h"

namespace arkt {
namespace {

constexpr net::NetworkTrafficAnnotationTag kDownloadTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("arkt_download", R"(
      semantics {
        sender: "Arkt downloads"
        description:
          "Starts a download the user asked for in the Arkt downloads list: "
          "Retry of a cancelled or failed download, or Save Link As. The "
          "request is the same one the earlier download made."
        trigger: "The user presses Retry on a download, or saves a link."
        data: "The URL of the download."
        destination: WEBSITE
      }
      policy {
        cookies_allowed: YES
        cookies_store: "user"
        setting: "Downloads can be cancelled in the downloads list."
        policy_exception_justification: "Not implemented."
      })");

bool IsOpenable(int danger_type) {
  switch (static_cast<download::DownloadDangerType>(danger_type)) {
    case download::DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS:
    case download::DOWNLOAD_DANGER_TYPE_USER_VALIDATED:
    case download::DOWNLOAD_DANGER_TYPE_ALLOWLISTED_BY_POLICY:
    case download::DOWNLOAD_DANGER_TYPE_DEEP_SCANNED_SAFE:
      return true;
    default:
      return false;
  }
}

// The file is held for the user's answer: not openable and not a scan still
// running. The same set as the shell's `DownloadDangerType.isHeldForDecision`
// (it includes types `DownloadItem::IsDangerous()` reports false for, such as
// a failed deep scan and maybe-dangerous content).
bool IsHeld(int danger_type) {
  switch (static_cast<download::DownloadDangerType>(danger_type)) {
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_SCANNING:
    case download::DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING:
      return false;
    default:
      return !IsOpenable(danger_type);
  }
}

// The danger types for which the only answer is Delete (a policy, a failed
// scan, a forced upload): not kept, only discarded.
bool IsBlocked(int danger_type) {
  switch (static_cast<download::DownloadDangerType>(danger_type)) {
    case download::DOWNLOAD_DANGER_TYPE_BLOCKED_PASSWORD_PROTECTED:
    case download::DOWNLOAD_DANGER_TYPE_BLOCKED_TOO_LARGE:
    case download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_BLOCK:
    case download::DOWNLOAD_DANGER_TYPE_BLOCKED_SCAN_FAILED:
    case download::DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_GDRIVE:
    case download::DOWNLOAD_DANGER_TYPE_FORCE_SAVE_TO_ONEDRIVE:
      return true;
    default:
      return false;
  }
}

DownloadSnapshot MakeSnapshot(download::DownloadItem* item) {
  DownloadSnapshot snapshot;
  snapshot.guid = item->GetGuid();
  snapshot.url = item->GetURL();
  snapshot.target_path = item->GetTargetFilePath();
  snapshot.filename = item->GetFileNameToReportUser().AsUTF8Unsafe();
  if (snapshot.filename.empty()) {
    snapshot.filename = item->GetSuggestedFilename();
  }
  if (snapshot.filename.empty()) {
    snapshot.filename = item->GetURL().ExtractFileName();
  }
  if (snapshot.filename.empty()) {
    snapshot.filename = "download";
  }
  snapshot.total_bytes = std::max<int64_t>(item->GetTotalBytes(), 0);
  snapshot.received_bytes = item->GetReceivedBytes();
  switch (item->GetState()) {
    case download::DownloadItem::IN_PROGRESS:
      snapshot.state = item->IsPaused() ? DownloadSnapshot::State::kPaused
                                        : DownloadSnapshot::State::kInProgress;
      break;
    case download::DownloadItem::COMPLETE:
      snapshot.state = DownloadSnapshot::State::kComplete;
      break;
    case download::DownloadItem::CANCELLED:
      snapshot.state = DownloadSnapshot::State::kCancelled;
      break;
    case download::DownloadItem::INTERRUPTED:
    case download::DownloadItem::MAX_DOWNLOAD_STATE:
      snapshot.state = DownloadSnapshot::State::kInterrupted;
      snapshot.interrupt_reason = static_cast<int>(item->GetLastReason());
      break;
  }
  snapshot.danger_type = static_cast<int>(item->GetDangerType());
  snapshot.mime_type = item->GetMimeType();
  snapshot.start_time = item->GetStartTime();
  snapshot.end_time = item->GetEndTime();
  snapshot.bytes_per_second =
      snapshot.state == DownloadSnapshot::State::kInProgress
          ? item->CurrentSpeed()
          : 0;
  snapshot.can_resume = item->CanResume();
  return snapshot;
}

void DeleteFileOnDisk(const base::FilePath& path) {
  if (path.empty()) {
    return;
  }
  base::ThreadPool::PostTask(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::BEST_EFFORT},
      base::BindOnce(base::IgnoreResult(&base::DeleteFile), path));
}

}  // namespace

DownloadWatcher::DownloadWatcher(Profile* profile,
                                 DownloadWatcherDelegate* delegate)
    : delegate_(delegate), manager_(profile->GetDownloadManager()) {
  manager_observation_.Observe(manager_);
  // Downloads the manager already holds (history loaded before this point).
  download::SimpleDownloadManager::DownloadVector existing;
  manager_->GetAllDownloads(&existing);
  std::sort(existing.begin(), existing.end(),
            [](download::DownloadItem* a, download::DownloadItem* b) {
              return a->GetStartTime() < b->GetStartTime();
            });
  for (download::DownloadItem* item : existing) {
    Track(item);
  }
}

DownloadWatcher::~DownloadWatcher() {
  for (download::DownloadItem* item : items_) {
    item->RemoveObserver(this);
  }
}

std::vector<DownloadSnapshot> DownloadWatcher::Snapshots() const {
  std::vector<DownloadSnapshot> snapshots;
  snapshots.reserve(items_.size());
  for (download::DownloadItem* item : items_) {
    snapshots.push_back(MakeSnapshot(item));
  }
  return snapshots;
}

void DownloadWatcher::Track(download::DownloadItem* item) {
  if (std::find(items_.begin(), items_.end(), item) != items_.end()) {
    return;
  }
  items_.push_back(item);
  item->AddObserver(this);
}

void DownloadWatcher::Untrack(download::DownloadItem* item) {
  std::erase(items_, item);
}

void DownloadWatcher::OnDownloadCreated(content::DownloadManager* manager,
                                        download::DownloadItem* item) {
  if (std::find(items_.begin(), items_.end(), item) != items_.end()) {
    return;
  }
  Track(item);
  delegate_->DownloadCreated(MakeSnapshot(item));
}

void DownloadWatcher::ManagerGoingDown(content::DownloadManager* manager) {
  for (download::DownloadItem* item : items_) {
    item->RemoveObserver(this);
  }
  items_.clear();
  manager_observation_.Reset();
  manager_ = nullptr;
}

void DownloadWatcher::OnDownloadUpdated(download::DownloadItem* item) {
  if (std::find(items_.begin(), items_.end(), item) == items_.end()) {
    return;
  }
  delegate_->DownloadUpdated(MakeSnapshot(item));
}

void DownloadWatcher::OnDownloadRemoved(download::DownloadItem* item) {
  if (std::find(items_.begin(), items_.end(), item) == items_.end()) {
    return;
  }
  item->RemoveObserver(this);
  Untrack(item);
  delegate_->DownloadRemoved(MakeSnapshot(item));
}

void DownloadWatcher::OnDownloadDestroyed(download::DownloadItem* item) {
  item->RemoveObserver(this);
  Untrack(item);
}

void DownloadWatcher::StartDownload(const GURL& url) {
  if (!manager_) {
    return;
  }
  content::WebContents* contents = delegate_->ContentsForNewDownload();
  std::unique_ptr<download::DownloadUrlParameters> parameters;
  if (contents) {
    parameters = content::DownloadRequestUtils::
        CreateDownloadForWebContentsMainFrame(contents, url,
                                              kDownloadTrafficAnnotation);
  } else if (content::DownloadRequestUtils::IsURLSafe(-1, url)) {
    parameters = std::make_unique<download::DownloadUrlParameters>(
        url, kDownloadTrafficAnnotation);
  } else {
    return;
  }
  // The user asked for it in the shell: that is a gesture, so a file type that
  // is only held without one (a disk image) is not held for this reason.
  parameters->set_has_user_gesture(true);
  manager_->DownloadUrl(std::move(parameters),
                        /*blob_url_loader_factory=*/nullptr);
}

void DownloadWatcher::Perform(DownloadCommand command,
                              const std::string& guid) {
  if (!manager_) {
    return;
  }
  download::DownloadItem* item = manager_->GetDownloadByGuid(guid);
  if (!item || std::find(items_.begin(), items_.end(), item) == items_.end()) {
    return;
  }
  const auto state = item->GetState();
  const bool active = state == download::DownloadItem::IN_PROGRESS;
  const int danger = static_cast<int>(item->GetDangerType());
  switch (command) {
    case DownloadCommand::kCancel:
      if (active) {
        item->Cancel(/*user_cancel=*/true);
      }
      break;
    case DownloadCommand::kPause:
      if (active && !item->IsPaused()) {
        item->Pause();
      }
      break;
    case DownloadCommand::kResume:
      if ((active && item->IsPaused()) ||
          (state == download::DownloadItem::INTERRUPTED &&
           item->CanResume())) {
        item->Resume(/*user_resume=*/true);
      }
      break;
    case DownloadCommand::kOpen:
      if (state == download::DownloadItem::COMPLETE && IsOpenable(danger) &&
          !item->IsDangerous()) {
        item->OpenDownload();
      }
      break;
    case DownloadCommand::kShowInFinder:
      if (!item->GetTargetFilePath().empty()) {
        item->ShowDownloadInShell();
      }
      break;
    case DownloadCommand::kRetry:
      if (state == download::DownloadItem::INTERRUPTED && item->CanResume()) {
        item->Resume(/*user_resume=*/true);
      } else if (state == download::DownloadItem::INTERRUPTED ||
                 state == download::DownloadItem::CANCELLED) {
        const GURL url = item->GetURL();
        item->Remove();
        StartDownload(url);
      }
      break;
    case DownloadCommand::kKeepDangerous:
      // Chromium can validate only what it reports as dangerous; a held type
      // it does not (failed scan, maybe dangerous) has nothing to validate.
      if (item->IsDangerous() && !IsBlocked(danger)) {
        item->ValidateDangerousDownload();
      }
      break;
    case DownloadCommand::kDiscardDangerous:
      if (IsHeld(danger) || item->IsDangerous()) {
        // Cancel deletes the partial file of an active download; the target
        // of a finished one is deleted here.
        const base::FilePath target = item->GetTargetFilePath();
        const bool was_active = active;
        if (was_active) {
          item->Cancel(/*user_cancel=*/true);
        }
        if (!was_active) {
          DeleteFileOnDisk(target);
        }
        item->Remove();
      }
      break;
    case DownloadCommand::kRemove:
      // Remove() cancels an active download first and keeps a finished file.
      item->Remove();
      break;
  }
}

namespace {

DownloadDestinationHandler& Handler() {
  static base::NoDestructor<DownloadDestinationHandler> handler;
  return *handler;
}

class ArktSaveDialogFactory;

// The platform dialog, which is what SelectFileDialog::Create returns without
// a factory. ui::CreateSelectFileDialog is not exported from the shell_dialogs
// component, so the factory steps aside for the call. It runs from SelectFile,
// never from inside the factory's own Create.
scoped_refptr<ui::SelectFileDialog> CreatePlatformDialog(
    ui::SelectFileDialog::Listener* listener);

// A SelectFileDialog that hands save panels to the shell and leaves every other
// kind to the platform dialog. The shell's answer is posted, never delivered
// inside SelectFile: DownloadFilePicker deletes itself when the answer comes.
class ArktSaveDialog : public ui::SelectFileDialog {
 public:
  ArktSaveDialog(Listener* listener,
                 std::unique_ptr<ui::SelectFilePolicy> policy)
      : ui::SelectFileDialog(listener, std::move(policy)) {}

  bool IsRunning(gfx::NativeWindow owning_window) const override {
    return pending_ || (platform_ && platform_->IsRunning(owning_window));
  }

  void ListenerDestroyed() override {
    listener_ = nullptr;
    weak_factory_.InvalidateWeakPtrs();
    if (platform_) {
      platform_->ListenerDestroyed();
    }
  }

 protected:
  ~ArktSaveDialog() override = default;

  void SelectFileImpl(Type type,
                      const std::u16string& title,
                      const base::FilePath& default_path,
                      const FileTypeInfo* file_types,
                      int file_type_index,
                      const base::FilePath::StringType& default_extension,
                      gfx::NativeWindow owning_window,
                      const GURL* caller) override {
    if (type != SELECT_SAVEAS_FILE || Handler().is_null()) {
      if (!platform_) {
        platform_ = CreatePlatformDialog(listener_);
      }
      platform_->SelectFile(type, title, default_path, file_types,
                            file_type_index, default_extension, owning_window,
                            caller);
      return;
    }
    pending_ = true;
    file_type_index_ = file_type_index;
    Handler().Run(
        default_path.BaseName().AsUTF8Unsafe(), default_path.DirName(),
        base::BindOnce(&ArktSaveDialog::Answered, weak_factory_.GetWeakPtr()));
  }

  bool HasMultipleFileTypeChoicesImpl() override {
    return platform_ && platform_->HasMultipleFileTypeChoices();
  }

 private:
  void Answered(std::optional<base::FilePath> chosen) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&ArktSaveDialog::Finish, weak_factory_.GetWeakPtr(),
                       std::move(chosen)));
  }

  void Finish(std::optional<base::FilePath> chosen) {
    pending_ = false;
    if (!listener_) {
      return;
    }
    if (chosen && !chosen->empty()) {
      // The index is the one the caller offered: Save Page As reads its save
      // type from it.
      listener_->FileSelected(ui::SelectedFileInfo(*chosen), file_type_index_);
    } else {
      listener_->FileSelectionCanceled();
    }
  }

  scoped_refptr<ui::SelectFileDialog> platform_;
  bool pending_ = false;
  int file_type_index_ = 0;
  base::WeakPtrFactory<ArktSaveDialog> weak_factory_{this};
};

class ArktSaveDialogFactory : public ui::SelectFileDialogFactory {
 public:
  ui::SelectFileDialog* Create(
      ui::SelectFileDialog::Listener* listener,
      std::unique_ptr<ui::SelectFilePolicy> policy) override {
    return new ArktSaveDialog(listener, std::move(policy));
  }
};

scoped_refptr<ui::SelectFileDialog> CreatePlatformDialog(
    ui::SelectFileDialog::Listener* listener) {
  const bool restore = !Handler().is_null();
  ui::SelectFileDialog::SetFactory(nullptr);
  scoped_refptr<ui::SelectFileDialog> dialog =
      ui::SelectFileDialog::Create(listener, nullptr);
  if (restore) {
    ui::SelectFileDialog::SetFactory(std::make_unique<ArktSaveDialogFactory>());
  }
  return dialog;
}

}  // namespace

void SetDownloadDestinationHandler(DownloadDestinationHandler handler) {
  const bool install = !handler.is_null();
  Handler() = std::move(handler);
  ui::SelectFileDialog::SetFactory(
      install ? std::make_unique<ArktSaveDialogFactory>() : nullptr);
}

}  // namespace arkt
