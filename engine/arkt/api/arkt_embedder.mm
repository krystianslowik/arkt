#include "arkt/api/arkt_embedder.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#import "arkt/api/arkt_engine.h"
#import "arkt/api/arkt_engine_facade.h"
#include "arkt/api/arkt_reentrancy_probe.h"
#import "arkt/api/arkt_selftest_embedder.h"
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
#include "chrome/browser/ui/browser_init_state.h"
// //chrome/browser/ui reaches //arkt through //chrome/browser, so this
// target cannot depend on it; the symbol is in the same framework.
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/chrome_paths_internal.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "url/gurl.h"

// A window request as plain values (arkt_engine.h).
@interface ArktEmbedderWindowRequest : NSObject <ArktWindowRequest>
@property(nonatomic) ArktWindowRequestKind kind;
@property(nonatomic, nullable) id<ArktBrowserHandle> opener;
@property(nonatomic) NSRect bounds;
@property(nonatomic) BOOL hasBounds;
@property(nonatomic) BOOL isPopup;
@property(nonatomic, copy) NSString* profileId;
@property(nonatomic, nullable, copy) NSURL* initialURL;
@end

@implementation ArktEmbedderWindowRequest
@synthesize kind = _kind;
@synthesize opener = _opener;
@synthesize bounds = _bounds;
@synthesize hasBounds = _hasBounds;
@synthesize isPopup = _isPopup;
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

// A window request as the factory knows it: why the Browser exists, from its
// call site (week-3 plan, Interface boundary).
struct RequestFields {
  ArktWindowRequestKind kind = ArktWindowRequestKindReopen;
  GURL url;
  gfx::Rect bounds;
  // How the kind was found, for logs.
  const char* source = "";
  // Default params: Dock reopen, New Window, a page's NEW_WINDOW, or a URL
  // opened by another application (#299).
  bool default_params = false;
  // A popup Browser (TYPE_POPUP or TYPE_APP_POPUP), not a normal window.
  bool popup = false;
};

// Chromium's New Tab page or the initial about:blank: no page of its own.
bool IsEmptyPage(const GURL& url) {
  return !url.is_valid() || url.IsAboutBlank() ||
         (url.SchemeIs("chrome") &&
          (url.host() == "newtab" || url.host() == "new-tab-page"));
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
      // The engine lane's check of the facade without the Swift app.
      embedder_ = CreateSelfTestEmbedder();
      if (!embedder_) {
        return;
      }
      LOG(WARNING) << "ARKT: self-test embedder in use (--"
                   << kFacadeSelfTestSwitch << ")";
    } else {
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
      embedder_ = [embedder_class sharedEmbedder];
    }
    base::FilePath user_data;
    if (chrome::GetDefaultUserDataDirectory(&user_data)) {
      LOG(WARNING) << "ARKT: default user data dir " << user_data.value();
    }

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
      request.fields.kind = ArktWindowRequestKindStartupURL;
      request.fields.url = url;
      request.fields.source = "launch argument";
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

  // Inside Browser construction, before the window exists.
  id<ArktWindowHost> HostForWindow(BrowserWindowInterface* browser) {
    if (pending_host_) {
      // -createBrowserWithHost: (shell-initiated window).
      id<ArktWindowHost> host = pending_host_;
      pending_host_ = nil;
      LOG(WARNING) << "ARKT: window host from createBrowser(host:) "
                   << base::SysNSStringToUTF8(NSStringFromClass([host class]))
                   << " window session id " << browser->GetSessionID().id();
      return host;
    }
    if (!present() || state_ != State::kReady) {
      return nil;
    }
    return AskHost(ClassifyRequest(browser), browser);
  }

  void OnWindowCreated(BrowserWindowInterface* browser,
                       ArktBrowserWindow* window) {
    if (!present() || window->host_mode()) {
      return;
    }
    switch (state_) {
      case State::kStarting: {
        // No seam exists before Browser construction (Decision 2): hold the
        // window hidden and queue its host request, with the kind its call
        // site gives.
        window->HoldShow();
        QueuedRequest request;
        request.fields = ClassifyRequest(browser);
        request.window = window->GetWeakPtr();
        LOG(WARNING) << "ARKT: window request queued kind="
                     << RequestKindName(request.fields.kind) << " ("
                     << request.fields.source << ") window session id "
                     << browser->GetSessionID().id() << " (window held hidden)";
        queue_.push_back(std::move(request));
        return;
      }
      case State::kFailed:
        // The shell is quitting after a failed start: never show the window
        // (W3-3 review).
        window->HoldShow();
        LOG(WARNING) << "ARKT: window after embedderFailed held and closed, "
                        "window session id "
                     << browser->GetSessionID().id();
        base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(
                           [](base::WeakPtr<ArktBrowserWindow> window) {
                             if (window) {
                               window->Close();
                             }
                           },
                           window->GetWeakPtr()));
        return;
      case State::kReady:
        // The embedder had no usable host for it (logged by AskHost).
        return;
    }
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
    // Replayed before this call returns, as createBrowser(host:) creates at
    // once: the shell decides right after it whether a launch window is
    // still needed, and a posted replay ran after that decision (W3-9: a
    // cold launch with a URL showed the launch window and the URL's window).
    // The embedder answers -hostForEngineWindowRequest: re-entrantly; only a
    // nested loop still defers the replay to a posted task.
    if (IsInNestedLoop()) {
      LOG(WARNING) << "ARKT: embedderReady inside a nested loop ("
                   << DescribeRunLoopNesting() << "), replay posted";
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(&Embedder::Replay, weak_factory_.GetWeakPtr()));
    } else {
      Replay();
    }
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

  BrowserWindowInterface* CreateBrowserForHost(
      id<ArktWindowHost> host) override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    // The initial profile is loaded before the hook runs
    // (chrome_browser_main.cc:1919, :2167); profile-picker mode is out of
    // scope.
    CHECK(profile_) << "ARKT: createBrowser(host:) before the initial profile";
    std::string missing;
    CHECK(IsUsableWindowHost(host, &missing))
        << "ARKT: createBrowser(host:) with a host without " << missing;
    if (IsInNestedLoop()) {
      // A deferred creation could not return the handle (Decision 3 lists
      // createBrowser among the deferred mutators; W3-4 deviation).
      LOG(WARNING) << "ARKT: createBrowser(host:) inside a nested loop ("
                   << DescribeRunLoopNesting() << "), created at once";
    }
    CHECK(!pending_host_);
    pending_host_ = host;
    BrowserWindowInterface* browser = CreateBrowserWindow(
        BrowserWindowCreateParams(BrowserWindowInterface::TYPE_NORMAL,
                                  profile_.get(), true));
    // The factory took the host: the window is an ArktBrowserWindow in it.
    CHECK(!pending_host_);
    ArktBrowserWindow* window = ArktBrowserWindow::FromBrowser(browser);
    CHECK(window && window->host() == host);
    return browser;
  }

 private:
  enum class State { kStarting, kReady, kFailed };

  struct QueuedRequest {
    RequestFields fields;
    // A Browser Chromium created before readiness, its window held hidden;
    // unset for a startup URL with no Browser yet.
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

  // Why `browser` exists, from what its call site passed (no patch): the
  // seam's own creations name their kind; otherwise the Browser's create
  // params tell startup windows (StartupBrowserCreator, also for a URL opened
  // by another application; the last-and-URLs startup preference), session
  // restore and desk templates, and chrome.windows.create (it always sets a show
  // state and usually bounds, tabs_api.cc:189-190) from the rest, which have
  // default params: Dock reopen and New Window, a page's NEW_WINDOW
  // navigation and a URL opened by another application, which cannot be told
  // apart without a patch (a held window is looked at again at replay,
  // ReclassifyHeld).
  RequestFields ClassifyRequest(BrowserWindowInterface* browser) const {
    RequestFields fields;
    const BrowserInitState* init = BrowserInitState::From(browser);
    if (init) {
      fields.bounds = init->create_params().initial_bounds;
    }
    if (creating_kind_) {
      fields.kind = *creating_kind_;
      fields.url = creating_url_;
      fields.source = "seam call site";
      return fields;
    }
    if (!init) {
      fields.source = "no create params";
      return fields;
    }
    const BrowserWindowCreateParams& params = init->create_params();
    // Sources that set bounds and a show state of their own are named before
    // the bounds check below (#255 review). Session restore is out of scope
    // this week (#116); Arkt owns tab persistence.
    switch (init->creation_source()) {
      case BrowserWindowCreateParams::CreationSource::kStartupCreator:
        fields.kind = ArktWindowRequestKindStartupURL;
        fields.source = "startup browser creator";
        return fields;
      case BrowserWindowCreateParams::CreationSource::kLastAndUrlsStartupPref:
        fields.kind = ArktWindowRequestKindStartupURL;
        fields.source = "last-and-URLs startup preference";
        return fields;
      case BrowserWindowCreateParams::CreationSource::kSessionRestore:
        fields.kind = ArktWindowRequestKindReopen;
        fields.source = "session restore";
        return fields;
      case BrowserWindowCreateParams::CreationSource::kDeskTemplate:
        fields.kind = ArktWindowRequestKindReopen;
        fields.source = "desk template";
        return fields;
      case BrowserWindowCreateParams::CreationSource::kUnknown:
        break;
    }
    // Popups are told apart by their Browser type (no patch): a page's
    // window.open with window features navigates with NEW_POPUP, which
    // creates a TYPE_POPUP Browser with the features' bounds
    // (browser_navigator.cc); chrome.windows.create({type: "popup"}) creates
    // a TYPE_APP_POPUP Browser with a show state (tabs_api.cc).
    switch (params.type) {
      case BrowserWindowInterface::TYPE_POPUP:
        fields.kind = ArktWindowRequestKindPage;
        fields.popup = true;
        fields.source = "popup Browser (window.open with window features)";
        return fields;
      case BrowserWindowInterface::TYPE_APP_POPUP:
        fields.kind = ArktWindowRequestKindExtension;
        fields.popup = true;
        fields.source = "app popup Browser (chrome.windows.create popup)";
        return fields;
      default:
        break;
    }
    if (params.initial_show_state != ui::mojom::WindowShowState::kDefault ||
        !params.initial_bounds.IsEmpty()) {
      fields.kind = ArktWindowRequestKindExtension;
      fields.source = "show state or bounds given (chrome.windows.create)";
    } else {
      fields.kind = ArktWindowRequestKindReopen;
      fields.source = "default params (reopen, New Window, page NEW_WINDOW)";
      fields.default_params = true;
    }
    return fields;
  }

  void Replay() {
    std::vector<QueuedRequest> queue;
    queue.swap(queue_);
    for (QueuedRequest& request : queue) {
      if (request.window) {
        base::WeakPtr<ArktBrowserWindow> window = request.window;
        id<ArktWindowHost> host =
            AskHost(ReclassifyHeld(request.fields, window->browser()),
                    window->browser());
        // The embedder may have closed it from inside the call; it must not.
        if (!window) {
          continue;
        }
        if (host) {
          window->ReplaceHost(host);
        }
        window->ReleaseHeldShow();
        AdoptHeldBrowser(window->browser());
        continue;
      }
      if (!request.fields.url.is_valid()) {
        continue;
      }
      if (!profile_) {
        LOG(ERROR) << "ARKT: startup URL request without a profile";
        continue;
      }
      creating_kind_ = request.fields.kind;
      creating_url_ = request.fields.url;
      BrowserWindowInterface* browser =
          CreateBrowserWindow(BrowserWindowCreateParams(profile_, true));
      creating_kind_.reset();
      creating_url_ = GURL();
      chrome::AddTabAt(browser, request.fields.url, -1, true);
      browser->GetWindow()->Show();
    }
  }

  // A window with default params held before readiness: no page has a window
  // to open one from yet and a Dock reopen gets the New Tab page, so a window
  // that already shows a page of its own was opened for a URL from another
  // application (AppController's -application:openURLs:, at a cold launch
  // from -applicationDidFinishLaunching:). It reports startupURL, as the
  // W3-4 table expects for that case (#299). After readiness the request is
  // answered inside construction, before the window has a tab, and stays
  // reopen.
  static RequestFields ReclassifyHeld(RequestFields fields,
                                      BrowserWindowInterface* browser) {
    if (!fields.default_params) {
      return fields;
    }
    TabStripModel* model = browser->GetTabStripModel();
    for (int index = 0; index < model->count(); ++index) {
      const GURL& url = model->GetWebContentsAt(index)->GetVisibleURL();
      if (!IsEmptyPage(url)) {
        fields.kind = ArktWindowRequestKindStartupURL;
        fields.url = url;
        fields.source =
            "default params, held before ready with a page (URL from another "
            "application)";
        return fields;
      }
    }
    return fields;
  }

  // Asks the embedder for a host. Returns nil (the placeholder host stays)
  // when it answers nil or a host the window cannot use.
  id<ArktWindowHost> AskHost(const RequestFields& fields,
                             BrowserWindowInterface* browser) {
    ArktEmbedderWindowRequest* request =
        [[ArktEmbedderWindowRequest alloc] init];
    request.kind = fields.kind;
    request.profileId = @"default";
    request.isPopup = fields.popup;
    if (fields.url.is_valid()) {
      request.initialURL =
          [NSURL URLWithString:base::SysUTF8ToNSString(fields.url.spec())];
    }
    if (!fields.bounds.IsEmpty()) {
      request.bounds = gfx::ScreenRectToNSRect(fields.bounds);
      request.hasBounds = YES;
    }
    id<ArktWindowHost> host = [embedder_ hostForEngineWindowRequest:request];
    std::string missing;
    bool usable = host && IsUsableWindowHost(host, &missing);
    LOG(WARNING) << "ARKT: host asked kind=" << RequestKindName(fields.kind)
                 << (fields.popup ? " popup" : "")
                 << " (" << fields.source << ") window session id "
                 << browser->GetSessionID().id()
                 << (fields.bounds.IsEmpty()
                         ? std::string()
                         : " bounds " + fields.bounds.ToString())
                 << " answered "
                 << (host ? base::SysNSStringToUTF8(
                                NSStringFromClass([host class]))
                          : std::string("nil"))
                 << (usable ? ""
                     : host ? "; unusable (no " + missing +
                                  "), placeholder host kept"
                            : "; placeholder host kept");
    return usable ? host : nil;
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
  // Set by CreateBrowserForHost for the factory, which takes it.
  id<ArktWindowHost> __strong pending_host_ = nil;
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

id<ArktWindowHost> HostForArktBrowserWindow(BrowserWindowInterface* browser) {
  return GetEmbedder().HostForWindow(browser);
}

bool IsUsableWindowHost(id host, std::string* missing) {
  // Selectors, not conformsToProtocol: the W3-3 Swift stand-in implements
  // methods without declaring the protocol (it cannot import the header).
  for (NSString* name in @[
         @"window", @"cardView", @"setCloseRequested:", @"setValidateCommand:",
         @"setExecuteCommand:"
       ]) {
    if (![host respondsToSelector:NSSelectorFromString(name)]) {
      *missing = base::SysNSStringToUTF8(name);
      return false;
    }
  }
  id<ArktWindowHost> typed = host;
  if (!typed.window) {
    *missing = "a window";
    return false;
  }
  if (!typed.cardView) {
    *missing = "a card view";
    return false;
  }
  return true;
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
