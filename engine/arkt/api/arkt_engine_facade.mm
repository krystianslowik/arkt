#import "arkt/api/arkt_engine_facade.h"

#import <AppKit/AppKit.h>

#include <map>
#include <string>

#include "arkt/api/arkt_embedder.h"
#include "arkt/browser/arkt_browser_window.h"
#include "base/check.h"
#include "base/check_op.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/tab_list/tab_removed_reason.h"
// //chrome/browser/ui reaches //arkt through //chrome/browser, so this
// target cannot depend on it; the symbol is in the same framework.
#include "chrome/browser/ui/browser_tabstrip.h"  // nogncheck
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/native_ui_types.h"
#include "url/gurl.h"

@class ArktFacadeBrowser;
@class ArktFacadeTab;

namespace arkt {
namespace {

class Facade;
Facade* g_facade = nullptr;

NSURL* ToNSURL(const GURL& url) {
  if (!url.is_valid()) {
    return nil;
  }
  return [NSURL URLWithString:base::SysUTF8ToNSString(url.spec())];
}

GURL ToGURL(NSURL* url) {
  return url ? GURL(base::SysNSStringToUTF8(url.absoluteString))
             : GURL("about:blank");
}

const char* KindName(ArktEngineEventKind kind) {
  switch (kind) {
    case ArktEngineEventKindTabCreated:
      return "TabCreated";
    case ArktEngineEventKindTabClosed:
      return "TabClosed";
    case ArktEngineEventKindActiveTabChanged:
      return "ActiveTabChanged";
    case ArktEngineEventKindCloseCancelled:
      return "CloseCancelled";
    case ArktEngineEventKindURLChanged:
      return "URLChanged";
    case ArktEngineEventKindTitleChanged:
      return "TitleChanged";
    case ArktEngineEventKindFaviconChanged:
      return "FaviconChanged";
    case ArktEngineEventKindLoadingChanged:
      return "LoadingChanged";
    case ArktEngineEventKindHistoryChanged:
      return "HistoryChanged";
    case ArktEngineEventKindTabReplaced:
      return "TabReplaced";
    case ArktEngineEventKindTabMoved:
      return "TabMoved";
    case ArktEngineEventKindWindowOpened:
      return "WindowOpened";
    case ArktEngineEventKindWindowClosed:
      return "WindowClosed";
    case ArktEngineEventKindExtensionActionsChanged:
      return "ExtensionActionsChanged";
  }
  return "unknown";
}

}  // namespace
}  // namespace arkt

// -----------------------------------------------------------------------------
// Event

@interface ArktFacadeEvent : NSObject <ArktEngineEvent>
@property(nonatomic) ArktEngineEventKind kind;
@property(nonatomic, nullable) id<ArktTabHandle> tab;
@property(nonatomic, nullable) id<ArktBrowserHandle> browser;
@property(nonatomic) ArktCloseReason closeReason;
@property(nonatomic, nullable, copy) NSURL* url;
@property(nonatomic, nullable, copy) NSString* title;
@property(nonatomic, nullable, copy) NSData* faviconPNG;
@property(nonatomic) BOOL isLoading;
@property(nonatomic) BOOL canGoBack;
@property(nonatomic) BOOL canGoForward;
@property(nonatomic, nullable) id<ArktTabHandle> opener;
@property(nonatomic) ArktTabOrigin origin;
@property(nonatomic) BOOL isActive;
@end

@implementation ArktFacadeEvent
@synthesize kind = _kind;
@synthesize tab = _tab;
@synthesize browser = _browser;
@synthesize closeReason = _closeReason;
@synthesize url = _url;
@synthesize title = _title;
@synthesize faviconPNG = _faviconPNG;
@synthesize isLoading = _isLoading;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize opener = _opener;
@synthesize origin = _origin;
@synthesize isActive = _isActive;
@end

// One registered event sink.
@interface ArktFacadeSink : NSObject
@property(nonatomic, copy) void (^block)(NSArray<id<ArktEngineEvent>>*);
@end

@implementation ArktFacadeSink
@synthesize block = _block;
@end

// -----------------------------------------------------------------------------
// Tab handle

@interface ArktFacadeTab : NSObject <ArktTabHandle>
- (instancetype)initWithOrigin:(ArktTabOrigin)origin;
- (void)bindTab:(tabs::TabInterface*)tab browser:(ArktFacadeBrowser*)browser;
- (void)unbind;
- (tabs::TabInterface*)tabInterface;
- (content::WebContents*)contents;
@property(nonatomic) BOOL closingByClient;
@property(nonatomic) BOOL closing;
@end

// -----------------------------------------------------------------------------
// Browser handle

@interface ArktFacadeBrowser : NSObject <ArktBrowserHandle>
- (instancetype)initWithBrowser:(BrowserWindowInterface*)browser;
- (BrowserWindowInterface*)browserInterface;
- (void)unbind;
@end

namespace arkt {
namespace {

// The facade's model: handles, the pending event batch and the sinks.
class Facade : public BrowserCollectionObserver, public TabStripModelObserver {
 public:
  explicit Facade(FacadeDelegate* delegate) : delegate_(delegate) {
    pending_ = [[NSMutableArray alloc] init];
    sinks_ = [[NSMutableArray alloc] init];
    browsers_ = [[NSMutableArray alloc] init];
  }

  void Start() {
    observation_.Observe(GlobalBrowserCollection::GetInstance());
    GlobalBrowserCollection::GetInstance()->ForEach(
        [this](BrowserWindowInterface* browser) {
          Adopt(browser);
          return true;
        });
  }

  FacadeDelegate* delegate() { return delegate_; }
  NSArray<ArktFacadeBrowser*>* browsers() { return [browsers_ copy]; }

  // Facade calls from the embedder must never arrive while the facade is
  // inside a Chromium notification (Decision 3).
  void CheckNotInNotification(const char* call) {
    CHECK_EQ(in_notification_, 0)
        << "ARKT: facade " << call << " called inside a Chromium notification";
  }

  ArktFacadeBrowser* HandleForBrowser(BrowserWindowInterface* browser) {
    auto it = browser_handles_.find(browser);
    return it == browser_handles_.end() ? nil : it->second;
  }

  ArktFacadeBrowser* HandleForModel(TabStripModel* model) {
    for (auto& [browser, handle] : browser_handles_) {
      if (browser->GetTabStripModel() == model) {
        return handle;
      }
    }
    return nil;
  }

  ArktFacadeTab* HandleForTab(tabs::TabInterface* tab) {
    auto it = tab_handles_.find(tab);
    return it == tab_handles_.end() ? nil : it->second;
  }

  // The next inserted tab is bound to `handle` (a client createTab).
  void SetBinding(ArktFacadeTab* handle) { binding_ = handle; }

  void SetTerminating(bool terminating) { terminating_ = terminating; }

  id<NSObject> AddSink(void (^block)(NSArray<id<ArktEngineEvent>>*)) {
    ArktFacadeSink* sink = [[ArktFacadeSink alloc] init];
    sink.block = block;
    [sinks_ addObject:sink];
    return sink;
  }

  void RemoveSink(id<NSObject> token) { [sinks_ removeObject:token]; }

  void Record(ArktFacadeEvent* event) {
    [pending_ addObject:event];
    if (posted_) {
      return;
    }
    posted_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&Facade::Deliver, base::Unretained(this)));
  }

  // BrowserCollectionObserver:
  void OnBrowserCreated(BrowserWindowInterface* browser) override {
    ++in_notification_;
    Adopt(browser);
    --in_notification_;
  }

  void OnBrowserClosed(BrowserWindowInterface* browser) override {
    ++in_notification_;
    ArktFacadeBrowser* handle = HandleForBrowser(browser);
    if (handle) {
      if (TabStripModel* model = browser->GetTabStripModel()) {
        model->RemoveObserver(this);
      }
      ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
      event.kind = ArktEngineEventKindWindowClosed;
      event.browser = handle;
      Record(event);
      [handle unbind];
      [browsers_ removeObject:handle];
      browser_handles_.erase(browser);
    }
    --in_notification_;
  }

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override {
    ++in_notification_;
    ArktFacadeBrowser* browser = HandleForModel(model);
    if (browser) {
      if (change.type() == TabStripModelChange::kInserted) {
        for (const auto& inserted : change.GetInsert()->contents) {
          Inserted(inserted.tab, browser, model);
        }
      } else if (change.type() == TabStripModelChange::kRemoved) {
        for (const auto& removed : change.GetRemove()->contents) {
          Removed(removed.tab, removed.remove_reason);
        }
      }
      if (selection.active_tab_changed() && selection.new_tab) {
        ArktFacadeTab* tab = HandleForTab(selection.new_tab);
        if (tab) {
          ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
          event.kind = ArktEngineEventKindActiveTabChanged;
          event.tab = tab;
          event.browser = browser;
          event.isActive = YES;
          Record(event);
        }
      }
    }
    --in_notification_;
  }

 private:
  void Adopt(BrowserWindowInterface* browser) {
    if (HandleForBrowser(browser) || !ArktBrowserWindow::FromBrowser(browser)) {
      return;
    }
    ArktFacadeBrowser* handle =
        [[ArktFacadeBrowser alloc] initWithBrowser:browser];
    browser_handles_[browser] = handle;
    [browsers_ addObject:handle];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindWindowOpened;
    event.browser = handle;
    Record(event);
    TabStripModel* model = browser->GetTabStripModel();
    model->AddObserver(this);
    for (int i = 0; i < model->count(); ++i) {
      Inserted(model->GetTabAtIndex(i), handle, model);
    }
  }

  void Inserted(tabs::TabInterface* tab,
                ArktFacadeBrowser* browser,
                TabStripModel* model) {
    ArktFacadeTab* handle = HandleForTab(tab);
    ArktEngineEventKind kind = ArktEngineEventKindTabMoved;
    if (!handle) {
      kind = ArktEngineEventKindTabCreated;
      if (binding_) {
        handle = binding_;
        binding_ = nil;
      } else {
        handle = [[ArktFacadeTab alloc] initWithOrigin:ArktTabOriginEngine];
      }
      tab_handles_[tab] = handle;
    }
    [handle bindTab:tab browser:browser];
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = kind;
    event.tab = handle;
    event.browser = browser;
    event.url = handle.url;
    event.title = handle.title;
    event.origin = handle.origin;
    event.isActive = model->GetActiveTab() == tab;
    Record(event);
  }

  void Removed(tabs::TabInterface* tab, TabRemovedReason reason) {
    if (!TabRemoveReasonUtils::WillDeleteTab(reason)) {
      // Moving to another window: the handle stays and TabMoved follows.
      return;
    }
    ArktFacadeTab* handle = HandleForTab(tab);
    if (!handle) {
      return;
    }
    ArktFacadeEvent* event = [[ArktFacadeEvent alloc] init];
    event.kind = ArktEngineEventKindTabClosed;
    event.tab = handle;
    event.browser = handle.browser;
    // Page and extension closes and window closes are told apart in W3-5
    // (Decision 12); until then they report ArktCloseReasonNone.
    event.closeReason = handle.closingByClient ? ArktCloseReasonClient
                        : terminating_         ? ArktCloseReasonAppTerminating
                                               : ArktCloseReasonNone;
    Record(event);
    [handle unbind];
    tab_handles_.erase(tab);
  }

  void Deliver() {
    posted_ = false;
    NSArray<id<ArktEngineEvent>>* batch = [pending_ copy];
    [pending_ removeAllObjects];
    if (batch.count == 0) {
      return;
    }
    std::string kinds;
    for (id<ArktEngineEvent> event in batch) {
      kinds += kinds.empty() ? "" : ",";
      kinds += KindName(event.kind);
    }
    LOG(WARNING) << "ARKT: facade batch " << batch.count << " event(s) "
                 << kinds << " to " << sinks_.count << " sink(s)";
    for (ArktFacadeSink* sink in [sinks_ copy]) {
      sink.block(batch);
    }
  }

  const raw_ptr<FacadeDelegate> delegate_;
  int in_notification_ = 0;
  bool posted_ = false;
  bool terminating_ = false;
  NSMutableArray<ArktFacadeEvent*>* __strong pending_;
  NSMutableArray<ArktFacadeSink*>* __strong sinks_;
  NSMutableArray<ArktFacadeBrowser*>* __strong browsers_;
  std::map<BrowserWindowInterface*, ArktFacadeBrowser* __strong>
      browser_handles_;
  std::map<tabs::TabInterface*, ArktFacadeTab* __strong> tab_handles_;
  ArktFacadeTab* __strong binding_ = nil;
  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver>
      observation_{this};
};

// Runs `work` now, or, inside a nested run loop, from a posted task (Decision
// 3). Returns true when the work was deferred.
bool RunOrDefer(const char* call, base::OnceClosure work) {
  g_facade->CheckNotInNotification(call);
  if (!IsInNestedLoop()) {
    std::move(work).Run();
    return false;
  }
  LOG(WARNING) << "ARKT: facade " << call << " deferred ("
               << DescribeRunLoopNesting() << ")";
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
                                                           std::move(work));
  return true;
}

void LogNotYet(const char* call, const char* task) {
  LOG(WARNING) << "ARKT: facade " << call << " not available before " << task;
}

}  // namespace
}  // namespace arkt

// -----------------------------------------------------------------------------

@implementation ArktFacadeTab {
  raw_ptr<tabs::TabInterface> _tab;
  ArktFacadeBrowser* __weak _browser;
  NSView* _emptyContainer;
  ArktTabOrigin _origin;
}

@synthesize closingByClient = _closingByClient;
@synthesize closing = _closing;

- (instancetype)initWithOrigin:(ArktTabOrigin)origin {
  if ((self = [super init])) {
    _origin = origin;
  }
  return self;
}

- (void)bindTab:(tabs::TabInterface*)tab browser:(ArktFacadeBrowser*)browser {
  _tab = tab;
  _browser = browser;
}

- (void)unbind {
  _tab = nullptr;
  _browser = nil;
  _closing = NO;
}

- (tabs::TabInterface*)tabInterface {
  return _tab;
}

- (content::WebContents*)contents {
  return _tab ? _tab->GetContents() : nullptr;
}

- (NSView*)containerView {
  // The stable per-tab container is Task W3-5 (Decision 6); until then the
  // current contents view, or an empty view before insertion.
  if (content::WebContents* contents = self.contents) {
    return contents->GetNativeView().GetNativeNSView();
  }
  if (!_emptyContainer) {
    _emptyContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  }
  return _emptyContainer;
}

- (int32_t)sessionId {
  content::WebContents* contents = self.contents;
  return contents ? sessions::SessionTabHelper::IdForTab(contents).id() : -1;
}

- (id<ArktBrowserHandle>)browser {
  return _browser;
}

- (NSURL*)url {
  content::WebContents* contents = self.contents;
  return contents ? arkt::ToNSURL(contents->GetVisibleURL()) : nil;
}

- (NSString*)title {
  content::WebContents* contents = self.contents;
  return contents ? base::SysUTF16ToNSString(contents->GetTitle()) : @"";
}

- (NSData*)faviconPNG {
  return nil;
}

- (BOOL)isLoading {
  content::WebContents* contents = self.contents;
  return contents && contents->IsLoading();
}

- (BOOL)canGoBack {
  content::WebContents* contents = self.contents;
  return contents && contents->GetController().CanGoBack();
}

- (BOOL)canGoForward {
  content::WebContents* contents = self.contents;
  return contents && contents->GetController().CanGoForward();
}

- (NSArray<id<ArktHistoryEntry>>*)backEntries {
  return @[];
}

- (NSArray<id<ArktHistoryEntry>>*)forwardEntries {
  return @[];
}

- (id<ArktTabHandle>)opener {
  return nil;
}

- (ArktTabOrigin)origin {
  return _origin;
}

- (BOOL)isActive {
  return _tab && _browser &&
         _browser.browserInterface->GetTabStripModel()->GetActiveTab() == _tab;
}

- (BOOL)isClosing {
  return _closing;
}

- (BOOL)wouldHoldClose {
  content::WebContents* contents = self.contents;
  return contents && contents->NeedToFireBeforeUnloadOrUnloadEvents();
}

- (void)navigateToURL:(NSURL*)url {
  GURL target = arkt::ToGURL(url);
  arkt::RunOrDefer("navigate", base::BindOnce(
                                   [](ArktFacadeTab* that, GURL target) {
                                     content::WebContents* contents =
                                         that.contents;
                                     if (!contents) {
                                       return;
                                     }
                                     content::NavigationController::
                                         LoadURLParams params(target);
                                     params.transition_type =
                                         ui::PAGE_TRANSITION_TYPED;
                                     contents->GetController()
                                         .LoadURLWithParams(params);
                                   },
                                   self, target));
}

- (void)reload {
  arkt::RunOrDefer("reload", base::BindOnce(
                                 [](ArktFacadeTab* that) {
                                   if (content::WebContents* contents =
                                           that.contents) {
                                     contents->GetController().Reload(
                                         content::ReloadType::NORMAL, true);
                                   }
                                 },
                                 self));
}

- (void)goBack {
  arkt::RunOrDefer("goBack", base::BindOnce(
                                 [](ArktFacadeTab* that) {
                                   content::WebContents* contents =
                                       that.contents;
                                   if (contents &&
                                       contents->GetController().CanGoBack()) {
                                     contents->GetController().GoBack();
                                   }
                                 },
                                 self));
}

- (void)goForward {
  arkt::RunOrDefer(
      "goForward", base::BindOnce(
                       [](ArktFacadeTab* that) {
                         content::WebContents* contents = that.contents;
                         if (contents &&
                             contents->GetController().CanGoForward()) {
                           contents->GetController().GoForward();
                         }
                       },
                       self));
}

- (void)goToHistoryOffset:(NSInteger)offset {
  arkt::RunOrDefer(
      "goToHistoryOffset",
      base::BindOnce(
          [](ArktFacadeTab* that, int offset) {
            content::WebContents* contents = that.contents;
            if (offset != 0 && contents &&
                contents->GetController().CanGoToOffset(offset)) {
              contents->GetController().GoToOffset(offset);
            }
          },
          self, static_cast<int>(offset)));
}

- (void)activate {
  arkt::RunOrDefer(
      "activate", base::BindOnce(
                      [](ArktFacadeTab* that) {
                        ArktFacadeTab* tab = that;
                        if (!tab.tabInterface || !tab.browser) {
                          return;
                        }
                        TabStripModel* model =
                            static_cast<ArktFacadeBrowser*>(tab.browser)
                                .browserInterface->GetTabStripModel();
                        int index = model->GetIndexOfTab(tab.tabInterface);
                        if (index != TabStripModel::kNoTab) {
                          model->ActivateTabAt(index);
                        }
                      },
                      self));
}

- (ArktCloseResult)closeWithMode:(ArktCloseMode)mode {
  if (mode == ArktCloseModeSkipUnloadHandlers) {
    // The close that skips beforeunload is chosen and verified in W3-5
    // (Decision 11); until then it honours unload handlers.
    arkt::LogNotYet("close(mode: skipUnloadHandlers)", "W3-5");
  }
  self.closingByClient = YES;
  bool deferred = arkt::RunOrDefer(
      "close", base::BindOnce(
                   [](ArktFacadeTab* that) {
                     ArktFacadeTab* tab = that;
                     if (!tab.tabInterface || !tab.browser) {
                       return;
                     }
                     TabStripModel* model =
                         static_cast<ArktFacadeBrowser*>(tab.browser)
                             .browserInterface->GetTabStripModel();
                     int index = model->GetIndexOfTab(tab.tabInterface);
                     if (index != TabStripModel::kNoTab) {
                       model->CloseWebContentsAt(
                           index, TabCloseTypes::CLOSE_USER_GESTURE);
                     }
                   },
                   self));
  // Still bound after the close ran: unload processing holds it.
  if (deferred || _tab) {
    _closing = YES;
    return ArktCloseResultHeld;
  }
  return ArktCloseResultClosed;
}

- (void)focus {
  if (content::WebContents* contents = self.contents) {
    contents->Focus();
  }
}

- (id<ArktTabHandle>)duplicate {
  arkt::LogNotYet("duplicate", "W3-5");
  return nil;
}

@end

// -----------------------------------------------------------------------------

@implementation ArktFacadeBrowser {
  raw_ptr<BrowserWindowInterface> _browser;
  id<ArktWindowHost> __weak _host;
  int32_t _windowId;
}

- (instancetype)initWithBrowser:(BrowserWindowInterface*)browser {
  if ((self = [super init])) {
    _browser = browser;
    _windowId = browser->GetSessionID().id();
    if (arkt::ArktBrowserWindow* window =
            arkt::ArktBrowserWindow::FromBrowser(browser)) {
      _host = window->host();
    }
  }
  return self;
}

- (BrowserWindowInterface*)browserInterface {
  return _browser;
}

- (void)unbind {
  _browser = nullptr;
}

- (int32_t)windowId {
  return _windowId;
}

- (id<ArktWindowHost>)host {
  return _host;
}

- (NSArray<id<ArktTabHandle>>*)tabs {
  NSMutableArray<id<ArktTabHandle>>* tabs = [NSMutableArray array];
  if (!_browser) {
    return tabs;
  }
  TabStripModel* model = _browser->GetTabStripModel();
  for (int i = 0; i < model->count(); ++i) {
    if (ArktFacadeTab* tab =
            arkt::g_facade->HandleForTab(model->GetTabAtIndex(i))) {
      [tabs addObject:tab];
    }
  }
  return tabs;
}

- (id<ArktTabHandle>)activeTab {
  return _browser ? arkt::g_facade->HandleForTab(
                        _browser->GetTabStripModel()->GetActiveTab())
                  : nil;
}

- (id<ArktTabHandle>)createTabWithURL:(NSURL*)url active:(BOOL)active {
  // The handle exists at once; the tab is inserted now or, inside a nested
  // run loop, when the posted task runs (Decision 3).
  ArktFacadeTab* handle =
      [[ArktFacadeTab alloc] initWithOrigin:ArktTabOriginClient];
  arkt::RunOrDefer(
      "createTab",
      base::BindOnce(
          [](ArktFacadeBrowser* that, ArktFacadeTab* handle, GURL url,
             bool active) {
            BrowserWindowInterface* browser = that.browserInterface;
            if (!browser) {
              LOG(WARNING) << "ARKT: facade createTab dropped: window gone";
              return;
            }
            arkt::g_facade->SetBinding(handle);
            chrome::AddTabAt(browser, url, -1, active);
            arkt::g_facade->SetBinding(nil);
            LOG(WARNING) << "ARKT: facade createTab inserted session id "
                         << handle.sessionId;
          },
          self, handle, arkt::ToGURL(url), static_cast<bool>(active)));
  return handle;
}

- (void)close {
  arkt::RunOrDefer("closeBrowser",
                   base::BindOnce(
                       [](ArktFacadeBrowser* that) {
                         BrowserWindowInterface* browser =
                             that.browserInterface;
                         if (arkt::ArktBrowserWindow* window =
                                 browser ? arkt::ArktBrowserWindow::FromBrowser(
                                               browser)
                                         : nullptr) {
                           window->Close();
                         }
                       },
                       self));
}

@end

// -----------------------------------------------------------------------------

@interface ArktFacadeEngine : NSObject <ArktEngine>
@end

@implementation ArktFacadeEngine

- (void)embedderReady {
  arkt::g_facade->CheckNotInNotification("embedderReady");
  arkt::g_facade->delegate()->OnEmbedderReady();
}

- (void)embedderFailed {
  arkt::g_facade->CheckNotInNotification("embedderFailed");
  arkt::g_facade->delegate()->OnEmbedderFailed();
}

- (NSArray<id<ArktBrowserHandle>>*)browsers {
  return arkt::g_facade->browsers();
}

- (id<ArktBrowserHandle>)createBrowserWithHost:(id<ArktWindowHost>)host {
  // Host mode is Task W3-4; nothing calls this before it lands.
  NOTREACHED() << "ARKT: facade createBrowser(host:) not available before W3-4";
}

- (NSArray<id<ArktExtensionAction>>*)extensionActionsForBrowser:
    (id<ArktBrowserHandle>)browser {
  arkt::LogNotYet("extensionActions(in:)", "W3-5");
  return @[];
}

- (void)runExtensionAction:(NSString*)actionId
                 inBrowser:(id<ArktBrowserHandle>)browser
                    anchor:(NSView*)anchor {
  arkt::LogNotYet("runExtensionAction", "W3-5");
}

- (id<NSObject>)addEventSink:
    (void (^)(NSArray<id<ArktEngineEvent>>* events))sink {
  return arkt::g_facade->AddSink(sink);
}

- (void)removeEventSink:(id<NSObject>)token {
  arkt::g_facade->RemoveSink(token);
}

- (BOOL)testAPIEnabled {
  return NO;
}

- (void)evaluateScript:(NSString*)script
                 inTab:(id<ArktTabHandle>)tab
           userGesture:(BOOL)userGesture
            completion:(void (^)(id _Nullable result,
                                 NSError* _Nullable error))completion {
  arkt::LogNotYet("evaluateScript", "W3-5");
  completion(nil, [NSError errorWithDomain:@"ArktEngine"
                                      code:1
                                  userInfo:@{
                                    NSLocalizedDescriptionKey :
                                        @"The test API is not available yet"
                                  }]);
}

- (BOOL)answerDialogInTab:(id<ArktTabHandle>)tab accept:(BOOL)accept {
  arkt::LogNotYet("answerDialog", "W3-5");
  return NO;
}

@end

namespace arkt {

id<ArktEngine> CreateEngineFacade(FacadeDelegate* delegate) {
  CHECK(!g_facade);
  static base::NoDestructor<Facade> facade(delegate);
  g_facade = facade.get();
  g_facade->Start();
  return [[ArktFacadeEngine alloc] init];
}

id<ArktBrowserHandle> BrowserHandleFor(BrowserWindowInterface* browser) {
  return g_facade ? g_facade->HandleForBrowser(browser) : nil;
}

void SetFacadeTerminating(bool terminating) {
  if (g_facade) {
    g_facade->SetTerminating(terminating);
  }
}

}  // namespace arkt
