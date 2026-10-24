#include "arkt/api/arkt_embedder.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#import "arkt/api/arkt_engine.h"
#import "arkt/api/arkt_engine_facade.h"
#include "arkt/api/arkt_reentrancy_probe.h"
#include "arkt/browser/arkt_browser_window.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/callback_list.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/run_loop.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/lifetime/termination_notification.h"
#include "chrome/browser/ui/browser_commands.h"
// //chrome/browser/ui reaches //arkt through //chrome/browser, so this
// target cannot depend on it; the symbol is in the same framework.
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/chrome_paths_internal.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "url/gurl.h"

// A window request as plain values (arkt_engine.h).
@interface ArktEmbedderWindowRequest : NSObject <ArktWindowRequest>
@property(nonatomic) ArktWindowRequestKind kind;
@property(nonatomic, nullable) id<ArktBrowserHandle> opener;
@property(nonatomic) NSRect bounds;
@property(nonatomic) BOOL hasBounds;
@property(nonatomic, copy) NSString* profileId;
@property(nonatomic, nullable, copy) NSURL* initialURL;
@end

@implementation ArktEmbedderWindowRequest
@synthesize kind = _kind;
@synthesize opener = _opener;
@synthesize bounds = _bounds;
@synthesize hasBounds = _hasBounds;
@synthesize profileId = _profileId;
@synthesize initialURL = _initialURL;
@end

namespace arkt {
namespace {

// The Swift embedder's class name (Decision 1). Defined in the app's main
// executable; registered with the Objective-C runtime when the executable
// loads, whatever its symbol visibility.
NSString* const kEmbedderClassName = @"ArktShellEmbedder";

// Debug switch for the readiness gate: a Dock-style reopen
// (chrome::NewEmptyWindow, as AppController's reopen handler does) posted
// before the embedder is ready.
constexpr char kDebugReopenBeforeReadySwitch[] =
    "arkt-debug-reopen-before-ready";
constexpr char kReentrancyProbeSwitch[] = "arkt-reentrancy-probe";

// Upper bound for the embedder's flush after -engineWillTerminate:
// (Decision 13).
constexpr base::TimeDelta kTerminateFlushLimit = base::Seconds(5);
constexpr base::TimeDelta kProbeDelayAfterReady = base::Seconds(4);

// The lifetime keep-alive (Decision 13) needs an existing origin other than
// BROWSER (AppController CHECKs that BROWSER is gone at terminate). PANEL_VIEW
// is referenced only by tests in 156, so no shipped code path changes
// behaviour because it is registered.
constexpr KeepAliveOrigin kLifetimeKeepAliveOrigin = KeepAliveOrigin::PANEL_VIEW;

const char* RequestKindName(ArktWindowRequestKind kind) {
  switch (kind) {
    case ArktWindowRequestKindExtension:
      return "extension";
    case ArktWindowRequestKindPage:
      return "page";
    case ArktWindowRequestKindReopen:
      return "reopen";
    case ArktWindowRequestKindStartupURL:
      return "startupURL";
  }
  return "unknown";
}

bool IsBlankURL(const GURL& url) {
  return !url.is_valid() || url.IsAboutBlank() ||
         url.spec() == "chrome://newtab/";
}

// Every selector of ArktEngineEmbedder. The stand-in Swift class (Task W3-3)
// does not import the header, so it implements them without declaring the
// protocol; the hook checks the selectors instead of conformsToProtocol:.
bool RespondsToEmbedderSelectors(Class embedder, std::string* missing) {
  if (![embedder respondsToSelector:@selector(sharedEmbedder)]) {
    *missing = "+sharedEmbedder";
    return false;
  }
  for (NSString* name in @[
         @"engineDidStart:", @"hostForEngineWindowRequest:",
         @"engineWillBeginTerminating", @"engineDidCancelTerminating",
         @"engineWillTerminate:"
       ]) {
    if (![embedder instancesRespondToSelector:NSSelectorFromString(name)]) {
      *missing = base::SysNSStringToUTF8(name);
      return false;
    }
  }
  return true;
}

class Embedder : public FacadeDelegate {
 public:
  Embedder() = default;
  Embedder(const Embedder&) = delete;
  Embedder& operator=(const Embedder&) = delete;

  void SetProfile(Profile* profile) { profile_ = profile; }
  bool present() const { return embedder_ != nil; }

  void Start() {
    Class embedder_class = NSClassFromString(kEmbedderClassName);
    if (!embedder_class) {
      LOG(WARNING) << "ARKT: embedder class "
                   << base::SysNSStringToUTF8(kEmbedderClassName) << " absent";
      return;
    }
    std::string missing;
    if (!RespondsToEmbedderSelectors(embedder_class, &missing)) {
      LOG(ERROR) << "ARKT: embedder class "
                 << base::SysNSStringToUTF8(kEmbedderClassName)
                 << " found without " << missing
                 << "; keeping the placeholder host";
      return;
    }
    LOG(WARNING) << "ARKT: embedder class "
                 << base::SysNSStringToUTF8(kEmbedderClassName)
                 << " found (conforms to ArktEngineEmbedder "
                 << ([embedder_class
                        conformsToProtocol:@protocol(ArktEngineEmbedder)]
                         ? "yes"
                         : "no")
                 << ", responds to every selector yes)";
    base::FilePath user_data;
    if (chrome::GetDefaultUserDataDirectory(&user_data)) {
      LOG(WARNING) << "ARKT: default user data dir " << user_data.value();
    }

    embedder_ = [embedder_class sharedEmbedder];
    facade_ = CreateEngineFacade(this);

    // Registered now, while registration is still allowed
    // (KeepAliveRegistry::Register CHECKs !is_shutting_down_), and held until
    // the embedder has flushed at terminate.
    keep_alive_ = std::make_unique<ScopedKeepAlive>(
        kLifetimeKeepAliveOrigin, KeepAliveRestartOption::DISABLED);
    LOG(WARNING) << "ARKT: lifetime keep-alive registered (origin "
                 << kLifetimeKeepAliveOrigin << ")";
    closing_all_subscription_ =
        chrome::AddClosingAllBrowsersCallback(base::BindRepeating(
            &Embedder::OnClosingAllBrowsers, base::Unretained(this)));
    terminating_subscription_ = browser_shutdown::AddAppTerminatingCallback(
        base::BindOnce(&Embedder::OnAppTerminating, base::Unretained(this)));

    // --no-startup-window (Decision 2) makes StartupBrowserCreator drop the
    // URL arguments, so the seam records them as startup window requests.
    for (const auto& arg : base::CommandLine::ForCurrentProcess()->GetArgs()) {
      GURL url(arg);
      if (!url.is_valid() || !url.has_scheme()) {
        LOG(WARNING) << "ARKT: ignored launch argument (not a URL)";
        continue;
      }
      QueuedRequest request;
      request.kind = ArktWindowRequestKindStartupURL;
      request.url = url;
      queue_.push_back(std::move(request));
      LOG(WARNING) << "ARKT: window request queued kind=startupURL url="
                   << url.possibly_invalid_spec();
    }

    LOG(WARNING) << "ARKT: engineDidStart";
    [embedder_ engineDidStart:facade_];

    if (base::CommandLine::ForCurrentProcess()->HasSwitch(
            kDebugReopenBeforeReadySwitch)) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&Embedder::DebugReopen,
                                    weak_factory_.GetWeakPtr()));
    }
  }

  void OnWindowCreated(BrowserWindowInterface* browser,
                       ArktBrowserWindow* window) {
    if (!present() || state_ == State::kFailed) {
      return;
    }
    if (state_ == State::kStarting) {
      // No seam exists before Browser construction (Decision 2): hold the
      // window hidden and queue its host request.
      window->HoldShow();
      QueuedRequest request;
      request.kind = creating_kind_;
      request.window = window->GetWeakPtr();
      queue_.push_back(std::move(request));
      LOG(WARNING) << "ARKT: window request queued kind="
                   << (creating_kind_ ? RequestKindName(*creating_kind_)
                                      : "pending")
                   << " window session id " << browser->GetSessionID().id()
                   << " (window held hidden)";
      return;
    }
    ArktWindowRequestKind kind =
        creating_kind_.value_or(ArktWindowRequestKindReopen);
    AskHost(kind, creating_url_, browser,
            creating_kind_ ? "" : " (kind not known to the factory, W3-4)");
  }

  // FacadeDelegate:
  void OnEmbedderReady() override {
    if (state_ != State::kStarting) {
      LOG(WARNING) << "ARKT: embedderReady ignored (not starting)";
      return;
    }
    state_ = State::kReady;
    LOG(WARNING) << "ARKT: embedderReady (" << queue_.size()
                 << " queued request(s))";
    // Replayed from a posted task: the embedder is on the stack, and replay
    // calls back into it (-hostForEngineWindowRequest:).
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&Embedder::Replay, weak_factory_.GetWeakPtr()));
    if (base::CommandLine::ForCurrentProcess()->HasSwitch(
            kReentrancyProbeSwitch)) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
          FROM_HERE, base::BindOnce(&StartReentrancyProbe),
          kProbeDelayAfterReady);
    }
  }

  void OnEmbedderFailed() override {
    if (state_ != State::kStarting) {
      LOG(WARNING) << "ARKT: embedderFailed ignored (not starting)";
      return;
    }
    state_ = State::kFailed;
    LOG(WARNING) << "ARKT: embedderFailed (dropping " << queue_.size()
                 << " queued request(s))";
    std::vector<QueuedRequest> dropped;
    dropped.swap(queue_);
    for (QueuedRequest& request : dropped) {
      if (request.window) {
        request.window->Close();
      }
    }
  }

 private:
  enum class State { kStarting, kReady, kFailed };

  struct QueuedRequest {
    // Unset for a Browser Chromium created before the embedder was ready; it
    // is resolved from the window's first tab at replay.
    std::optional<ArktWindowRequestKind> kind;
    // A startup URL with no Browser yet.
    GURL url;
    // A Browser Chromium created before readiness, its window held hidden.
    base::WeakPtr<ArktBrowserWindow> window;
  };

  void DebugReopen() {
    if (!profile_) {
      LOG(ERROR) << "ARKT: debug reopen without a profile";
      return;
    }
    LOG(WARNING) << "ARKT: debug reopen (chrome::NewEmptyWindow) before ready";
    creating_kind_ = ArktWindowRequestKindReopen;
    chrome::NewEmptyWindow(profile_);
    creating_kind_.reset();
  }

  void Replay() {
    std::vector<QueuedRequest> queue;
    queue.swap(queue_);
    for (QueuedRequest& request : queue) {
      if (request.window) {
        BrowserWindowInterface* browser = request.window->browser();
        content::WebContents* contents =
            browser->GetTabStripModel()->GetActiveWebContents();
        GURL url = contents ? contents->GetVisibleURL() : GURL();
        ArktWindowRequestKind kind = request.kind.value_or(
            IsBlankURL(url) ? ArktWindowRequestKindReopen
                            : ArktWindowRequestKindStartupURL);
        AskHost(kind, url, browser,
                request.kind ? "" : " (kind resolved from the first tab)");
        request.window->ReleaseHeldShow();
        continue;
      }
      if (!request.url.is_valid()) {
        continue;
      }
      if (!profile_) {
        LOG(ERROR) << "ARKT: startup URL request without a profile";
        continue;
      }
      creating_kind_ = ArktWindowRequestKindStartupURL;
      creating_url_ = request.url;
      BrowserWindowInterface* browser =
          CreateBrowserWindow(BrowserWindowCreateParams(profile_, true));
      creating_kind_.reset();
      creating_url_ = GURL();
      chrome::AddTabAt(browser, request.url, -1, true);
      browser->GetWindow()->Show();
    }
  }

  void AskHost(ArktWindowRequestKind kind,
               const GURL& url,
               BrowserWindowInterface* browser,
               const char* note) {
    ArktEmbedderWindowRequest* request =
        [[ArktEmbedderWindowRequest alloc] init];
    request.kind = kind;
    request.profileId = @"default";
    if (url.is_valid()) {
      request.initialURL =
          [NSURL URLWithString:base::SysUTF8ToNSString(url.spec())];
    }
    id<ArktWindowHost> host = [embedder_ hostForEngineWindowRequest:request];
    LOG(WARNING) << "ARKT: host asked kind=" << RequestKindName(kind) << note
                 << " window session id " << browser->GetSessionID().id()
                 << " answered "
                 << (host ? base::SysNSStringToUTF8(
                                NSStringFromClass([host class]))
                          : std::string("nil"))
                 << "; placeholder host kept until W3-4";
  }

  void OnClosingAllBrowsers(bool closing) {
    if (closing && !quit_started_) {
      quit_started_ = true;
      SetFacadeTerminating(true);
      LOG(WARNING) << "ARKT: quit started (trying to quit "
                   << (browser_shutdown::IsTryingToQuit() ? "yes" : "no")
                   << ")";
      [embedder_ engineWillBeginTerminating];
    } else if (!closing && quit_started_) {
      // Notified once per browser whose unload processing was reset; the
      // embedder hears it once per quit attempt.
      quit_started_ = false;
      SetFacadeTerminating(false);
      LOG(WARNING) << "ARKT: quit cancelled";
      [embedder_ engineDidCancelTerminating];
    }
  }

  void OnAppTerminating() {
    LOG(WARNING) << "ARKT: app terminating";
    base::WeakPtr<Embedder> weak = weak_factory_.GetWeakPtr();
    [embedder_ engineWillTerminate:^{
      if (weak) {
        weak->ReleaseKeepAlive("embedder flushed");
      }
    }];
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(&Embedder::ReleaseKeepAlive, weak, "flush time limit"),
        kTerminateFlushLimit);
  }

  void ReleaseKeepAlive(const char* why) {
    if (!keep_alive_) {
      return;
    }
    LOG(WARNING) << "ARKT: lifetime keep-alive released (" << why << ")";
    keep_alive_.reset();
  }

  raw_ptr<Profile> profile_ = nullptr;
  id<ArktEngineEmbedder> __strong embedder_ = nil;
  id<ArktEngine> __strong facade_ = nil;
  State state_ = State::kStarting;
  std::vector<QueuedRequest> queue_;
  // Set while the seam itself creates a Browser for a request, so the window
  // factory knows why the window exists.
  std::optional<ArktWindowRequestKind> creating_kind_;
  GURL creating_url_;
  std::unique_ptr<ScopedKeepAlive> keep_alive_;
  base::CallbackListSubscription closing_all_subscription_;
  base::CallbackListSubscription terminating_subscription_;
  bool quit_started_ = false;
  base::WeakPtrFactory<Embedder> weak_factory_{this};
};

Embedder& GetEmbedder() {
  static base::NoDestructor<Embedder> embedder;
  return *embedder;
}

}  // namespace

void SetEmbedderProfile(Profile* profile) {
  GetEmbedder().SetProfile(profile);
}

void StartEmbedder() {
  GetEmbedder().Start();
}

bool HasEmbedder() {
  return GetEmbedder().present();
}

void OnArktBrowserWindowCreated(BrowserWindowInterface* browser,
                                ArktBrowserWindow* window) {
  GetEmbedder().OnWindowCreated(browser, window);
}

bool IsInNestedLoop() {
  if (base::RunLoop::IsNestedOnCurrentThread()) {
    return true;
  }
  // [NSApp run] spins the main run loop in the default mode; menu tracking,
  // modal sessions, live resize and drags spin it in other modes. Outside
  // any run loop (AppKit event dispatch) there is no current mode.
  base::apple::ScopedCFTypeRef<CFStringRef> mode(
      CFRunLoopCopyCurrentMode(CFRunLoopGetMain()));
  return mode && !CFEqual(mode.get(), kCFRunLoopDefaultMode);
}

std::string DescribeRunLoopNesting() {
  base::apple::ScopedCFTypeRef<CFStringRef> mode(
      CFRunLoopCopyCurrentMode(CFRunLoopGetMain()));
  return std::string("base run loop nested ") +
         (base::RunLoop::IsNestedOnCurrentThread() ? "yes" : "no") +
         ", run loop mode " +
         (mode ? base::SysCFStringRefToUTF8(mode.get()) : std::string("none"));
}

}  // namespace arkt
