#include "arkt/browser/arkt_extension_batch_install.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <memory>
#include <set>
#include <utility>

#import "arkt/browser/arkt_dialog_sheet.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/webstore_install_with_prompt.h"
#include "chrome/browser/profiles/profile.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/webstore_install_result.h"
#include "extensions/common/extension.h"

namespace arkt {

namespace {

namespace wi = extensions::webstore_install;

// At most this many names are listed in the sheet; the rest are counted.
constexpr size_t kMaxListedNames = 8;

// WebstoreInstallWithPrompt without its prompt: the listing is fetched and
// parsed as usual, then the installer waits in OnManifestParsed for the batch
// to be confirmed. Resume() takes the Web Store path from there (download,
// unpack, CrxInstaller); Decline() completes it as cancelled.
class BatchInstaller : public extensions::WebstoreInstallWithPrompt {
 public:
  BatchInstaller(const std::string& id,
                 Profile* profile,
                 Callback callback,
                 base::OnceCallback<void(std::u16string)> on_ready)
      : WebstoreInstallWithPrompt(id,
                                  profile,
                                  gfx::NativeWindow(),
                                  std::move(callback)),
        on_ready_(std::move(on_ready)) {
    set_show_post_install_ui(false);
  }

  void Resume() { ProceedWithInstallPrompt(); }
  void Decline() {
    CompleteInstall(wi::USER_CANCELLED, wi::kUserCancelledError);
  }

 protected:
  ~BatchInstaller() override = default;

  // No per-extension prompt: ProceedWithInstallPrompt() accepts at once.
  std::unique_ptr<extensions::InstallPromptData> CreateInstallPrompt()
      const override {
    return nullptr;
  }

  void OnManifestParsed() override {
    scoped_refptr<const extensions::Extension> extension =
        GetLocalizedExtensionForDisplay();
    if (!extension) {
      CompleteInstall(wi::INVALID_MANIFEST, wi::kInvalidManifestError);
      return;
    }
    std::move(on_ready_).Run(base::UTF8ToUTF16(extension->name()));
  }

 private:
  base::OnceCallback<void(std::u16string)> on_ready_;
};

// The window the sheet attaches to: the key window, else the main one, else
// the frontmost visible window that can be main (the app is not active when a
// script starts the import).
NSWindow* ConfirmationWindow() {
  if (NSWindow* window = NSApp.keyWindow ?: NSApp.mainWindow) {
    return window;
  }
  for (NSWindow* window in NSApp.orderedWindows) {
    if (window.isVisible && window.canBecomeMainWindow) {
      return window;
    }
  }
  return nil;
}

const char* ReasonFor(wi::Result result) {
  switch (result) {
    case wi::INVALID_ID:
      return "not a Web Store id";
    case wi::WEBSTORE_REQUEST_ERROR:
    case wi::INVALID_WEBSTORE_RESPONSE:
      return "not available from the Web Store";
    case wi::INVALID_MANIFEST:
    case wi::ICON_ERROR:
      return "the Web Store listing could not be read";
    case wi::USER_CANCELLED:
    case wi::ABORTED:
      return "not confirmed";
    case wi::INSTALL_IN_PROGRESS:
      return "already being installed";
    case wi::NOT_PERMITTED:
    case wi::BLOCKED_BY_POLICY:
      return "blocked by policy";
    case wi::BLOCKLISTED:
      return "flagged as unsafe";
    case wi::MISSING_DEPENDENCIES:
    case wi::REQUIREMENT_VIOLATIONS:
      return "not supported on this Mac";
    default:
      return "install failed";
  }
}

// One batch; owns itself until every id has an outcome, then posts `done`.
class Batch {
 public:
  using Done =
      base::OnceCallback<void(std::vector<ExtensionInstallOutcome>)>;

  Batch(Profile* profile, std::vector<std::string> ids, Done done)
      : profile_(profile), done_(std::move(done)) {
    std::set<std::string> seen;
    for (std::string& id : ids) {
      if (seen.insert(id).second) {
        entries_.emplace_back();
        entries_.back().outcome.id = std::move(id);
      }
    }
  }
  Batch(const Batch&) = delete;
  Batch& operator=(const Batch&) = delete;
  ~Batch() { [sheet_ close]; }

  void Start() {
    busy_ = true;
    extensions::ExtensionRegistry* registry =
        extensions::ExtensionRegistry::Get(profile_);
    for (size_t i = 0; i < entries_.size(); ++i) {
      Entry& entry = entries_[i];
      if (registry->GetExtensionById(entry.outcome.id,
                                     extensions::ExtensionRegistry::EVERYTHING)) {
        entry.outcome.status = ExtensionInstallOutcome::Status::kAlreadyInstalled;
        entry.phase = Phase::kDone;
        continue;
      }
      entry.installer = base::MakeRefCounted<BatchInstaller>(
          entry.outcome.id, profile_,
          base::BindOnce(&Batch::OnInstallerDone, weak_factory_.GetWeakPtr(),
                         i),
          base::BindOnce(&Batch::OnReady, weak_factory_.GetWeakPtr(), i));
    }
    // BeginInstall can complete at once (a bad id), so every installer exists
    // before the first one starts and Settle() waits for the loop.
    for (Entry& entry : entries_) {
      if (entry.installer) {
        entry.installer->BeginInstall();
      }
    }
    busy_ = false;
    Settle();
  }

 private:
  enum class Phase { kFetching, kReady, kInstalling, kDone };

  struct Entry {
    ExtensionInstallOutcome outcome;
    Phase phase = Phase::kFetching;
    scoped_refptr<BatchInstaller> installer;
    std::u16string name;
  };

  void OnReady(size_t index, std::u16string name) {
    entries_[index].name = std::move(name);
    entries_[index].phase = Phase::kReady;
    Settle();
  }

  void OnInstallerDone(size_t index,
                       bool success,
                       const std::string& error,
                       wi::Result result) {
    Entry& entry = entries_[index];
    entry.phase = Phase::kDone;
    if (success) {
      entry.outcome.status = ExtensionInstallOutcome::Status::kInstalled;
    } else {
      entry.outcome.status = ExtensionInstallOutcome::Status::kFailed;
      entry.outcome.reason = ReasonFor(result);
      LOG(WARNING) << "ARKT: extension install failed result=" << result;
    }
    Settle();
  }

  bool Has(Phase phase) const {
    return std::any_of(entries_.begin(), entries_.end(),
                       [phase](const Entry& e) { return e.phase == phase; });
  }

  void Settle() {
    if (busy_ || Has(Phase::kFetching) || Has(Phase::kInstalling)) {
      return;
    }
    if (Has(Phase::kReady)) {
      Ask();
      return;
    }
    Finish();
  }

  void Ask() {
    std::vector<std::u16string> names;
    for (const Entry& entry : entries_) {
      if (entry.phase == Phase::kReady) {
        names.push_back(entry.name);
      }
    }
    NSWindow* parent = ConfirmationWindow();
    if (!parent) {
      LOG(WARNING) << "ARKT: extension install has no window to confirm in";
      Answer(false);
      return;
    }
    sheet_ = [[ArktDialogSheet alloc] initWithContent:BuildContent(names)];
    base::WeakPtr<Batch> weak = weak_factory_.GetWeakPtr();
    sheet_.onPrimary = ^{
      if (weak) {
        weak->Answer(true);
      }
    };
    sheet_.onCancel = ^{
      if (weak) {
        weak->Answer(false);
      }
    };
    sheet_.onDismiss = sheet_.onCancel;
    LOG(WARNING) << "ARKT: extension install sheet shown count="
                 << names.size();
    [sheet_ beginOnWindow:parent];
  }

  static ArktDialogSheetContent* BuildContent(
      const std::vector<std::u16string>& names) {
    ArktDialogSheetContent* content = [[ArktDialogSheetContent alloc] init];
    content.title = names.size() == 1
                        ? @"Install 1 extension?"
                        : [NSString stringWithFormat:@"Install %zu extensions?",
                                                     names.size()];
    ArktDialogSheetParagraph* intro = [[ArktDialogSheetParagraph alloc] init];
    intro.text = @"These extensions came with your browser data. Arkt adds "
                 @"them from the Chrome Web Store.";
    intro.linkRange = NSMakeRange(NSNotFound, 0);
    ArktDialogSheetParagraph* warning = [[ArktDialogSheetParagraph alloc] init];
    warning.text = @"An extension can read and change data on the sites you "
                   @"visit. You can remove any of them later from Extensions.";
    warning.linkRange = NSMakeRange(NSNotFound, 0);
    warning.secondary = YES;
    content.paragraphs = @[ intro, warning ];

    NSMutableArray<ArktDialogSheetItem*>* items = [NSMutableArray array];
    for (size_t i = 0; i < names.size() && i < kMaxListedNames; ++i) {
      ArktDialogSheetItem* item = [[ArktDialogSheetItem alloc] init];
      item.text = base::SysUTF16ToNSString(names[i]);
      item.details = @[];
      [items addObject:item];
    }
    if (names.size() > kMaxListedNames) {
      ArktDialogSheetItem* more = [[ArktDialogSheetItem alloc] init];
      more.text = [NSString
          stringWithFormat:@"and %zu more", names.size() - kMaxListedNames];
      more.details = @[];
      [items addObject:more];
    }
    content.listHeading = @"Extensions";
    content.listItems = items;
    content.primaryTitle = @"Install";
    content.cancelTitle = @"Not now";
    content.defaultButton = ArktDialogSheetDefaultCancel;
    return content;
  }

  void Answer(bool accepted) {
    [sheet_ close];
    sheet_ = nil;
    busy_ = true;
    for (Entry& entry : entries_) {
      if (entry.phase != Phase::kReady) {
        continue;
      }
      entry.phase = Phase::kInstalling;
      if (accepted) {
        entry.installer->Resume();
      } else {
        entry.installer->Decline();
      }
    }
    busy_ = false;
    Settle();
  }

  void Finish() {
    std::vector<ExtensionInstallOutcome> outcomes;
    for (Entry& entry : entries_) {
      outcomes.push_back(std::move(entry.outcome));
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done_), std::move(outcomes)));
    delete this;
  }

  raw_ptr<Profile> profile_;
  Done done_;
  std::vector<Entry> entries_;
  // Set while a loop over the entries runs, so an installer that completes at
  // once does not settle the batch before the loop is done.
  bool busy_ = false;
  ArktDialogSheet* __strong sheet_ = nil;
  base::WeakPtrFactory<Batch> weak_factory_{this};
};

}  // namespace

void InstallWebstoreExtensions(
    Profile* profile,
    std::vector<std::string> ids,
    base::OnceCallback<void(std::vector<ExtensionInstallOutcome>)> done) {
  // The batch deletes itself in Finish().
  (new Batch(profile, std::move(ids), std::move(done)))->Start();
}

}  // namespace arkt
