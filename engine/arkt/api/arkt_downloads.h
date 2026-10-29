#ifndef ARKT_API_ARKT_DOWNLOADS_H_
#define ARKT_API_ARKT_DOWNLOADS_H_

#include <stdint.h>

#include <optional>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/time/time.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"
#include "url/gurl.h"

class Profile;

namespace content {
class WebContents;
}

namespace arkt {

// The downloads half of the engine facade (#132), in plain C++: the facade
// (arkt_engine_facade.mm) turns these values into Objective-C objects and
// events. Nothing here touches the Views download bubble, shelf or toolbar
// button: Arkt windows have no BrowserView, so Chromium creates none of them
// (BrowserWindowFeatures builds the DownloadToolbarUIController only with a
// BrowserView, and ArktBrowserWindow::GetDownloadBubbleUIController is null).

// One download as plain values, read when the change happened.
struct DownloadSnapshot {
  enum class State { kInProgress, kPaused, kComplete, kCancelled, kInterrupted };

  std::string guid;
  GURL url;
  std::string filename;
  base::FilePath target_path;
  int64_t total_bytes = 0;
  int64_t received_bytes = 0;
  State state = State::kInProgress;
  int interrupt_reason = 0;
  int danger_type = 0;
  std::string mime_type;
  base::Time start_time;
  base::Time end_time;
  int64_t bytes_per_second = 0;
  bool can_resume = false;
};

// Mirrors ArktDownloadCommand.
enum class DownloadCommand {
  kCancel,
  kPause,
  kResume,
  kOpen,
  kShowInFinder,
  kRetry,
  kKeepDangerous,
  kDiscardDangerous,
  kRemove,
};

class DownloadWatcherDelegate {
 public:
  virtual ~DownloadWatcherDelegate() = default;
  virtual void DownloadCreated(const DownloadSnapshot& download) = 0;
  virtual void DownloadUpdated(const DownloadSnapshot& download) = 0;
  // The download as it was last; its file stays unless it was deleted.
  virtual void DownloadRemoved(const DownloadSnapshot& download) = 0;
  // The contents a download of a bare URL is attributed to (a retry, Save
  // Link As): an Arkt tab, or null when there is none.
  virtual content::WebContents* ContentsForNewDownload() = 0;
};

// Observes one profile's DownloadManager and every item in it.
class DownloadWatcher : public content::DownloadManager::Observer,
                        public download::DownloadItem::Observer {
 public:
  DownloadWatcher(Profile* profile, DownloadWatcherDelegate* delegate);
  DownloadWatcher(const DownloadWatcher&) = delete;
  DownloadWatcher& operator=(const DownloadWatcher&) = delete;
  ~DownloadWatcher() override;

  // Every download of the profile, in creation order.
  std::vector<DownloadSnapshot> Snapshots() const;

  // Runs `command` on the download with that guid; a no-op for an unknown
  // guid or a state the command does not apply to.
  void Perform(DownloadCommand command, const std::string& guid);

  // DownloadManager::DownloadUrl for `url`, as a download the user asked for.
  void StartDownload(const GURL& url);

  // content::DownloadManager::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void ManagerGoingDown(content::DownloadManager* manager) override;

  // download::DownloadItem::Observer:
  void OnDownloadUpdated(download::DownloadItem* item) override;
  void OnDownloadRemoved(download::DownloadItem* item) override;
  void OnDownloadDestroyed(download::DownloadItem* item) override;

 private:
  void Track(download::DownloadItem* item);
  void Untrack(download::DownloadItem* item);

  const raw_ptr<DownloadWatcherDelegate> delegate_;
  raw_ptr<content::DownloadManager> manager_;
  // Creation order; an item leaves the list when it is removed or destroyed.
  std::vector<raw_ptr<download::DownloadItem>> items_;
  base::ScopedObservation<content::DownloadManager,
                          content::DownloadManager::Observer>
      manager_observation_{this};
};

// Answers a save panel: the suggested file name, the folder it would open in,
// and the callback that takes the chosen file or nullopt when the user
// cancels. The answer may come at any time on the UI thread.
using DownloadDestinationHandler = base::RepeatingCallback<void(
    const std::string& suggested_name,
    const base::FilePath& directory,
    base::OnceCallback<void(std::optional<base::FilePath>)> answer)>;

// While a handler is set, a SELECT_SAVEAS_FILE dialog (the download panel of
// download.prompt_for_download, and Save As of other saves) goes to it instead
// of Chromium's panel; every other kind of file dialog keeps the platform
// dialog. A null handler restores Chromium's panels.
void SetDownloadDestinationHandler(DownloadDestinationHandler handler);

}  // namespace arkt

#endif  // ARKT_API_ARKT_DOWNLOADS_H_
