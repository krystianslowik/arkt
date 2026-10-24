#import "arkt/api/arkt_selftest_embedder.h"

#import <AppKit/AppKit.h>

#include <map>
#include <string>
#include <vector>

#include "base/command_line.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "ui/base/window_open_disposition.h"

namespace {

constexpr char kSelfTestURLSwitch[] = "arkt-facade-selftest-url";
constexpr char kDefaultURL[] =
    "data:text/html,<title>W3-4 shell window</title><h1>Shell-initiated "
    "window</h1>";
constexpr NSTimeInterval kDelayedStart = 5.0;
// A page title starting with this runs a self-test command on its tab
// (the scripted runs set it over CDP): "arkt-selftest <command> [argument]";
// words starting with '#' are ignored, so a command can be repeated.
constexpr char kCommandPrefix[] = "arkt-selftest ";
// The pending-handle check (W3-3 review): the URL its tab navigates to.
constexpr char kPendingURL[] =
    "data:text/html,<title>W3-5 pending</title><h1>Pending handle</h1>";

std::string Describe(NSURL* url) {
  return url ? base::SysNSStringToUTF8(url.absoluteString) : "none";
}

const char* KindName(ArktWindowRequestKind kind) {
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

const char* ReasonName(ArktCloseReason reason) {
  switch (reason) {
    case ArktCloseReasonNone:
      return "none";
    case ArktCloseReasonClient:
      return "client";
    case ArktCloseReasonPage:
      return "page";
    case ArktCloseReasonExtension:
      return "extension";
    case ArktCloseReasonWindowClosing:
      return "windowClosing";
    case ArktCloseReasonAppTerminating:
      return "appTerminating";
  }
  return "unknown";
}

}  // namespace

// A plain NSWindow host. The close button asks the engine (closeRequested)
// and never closes the window itself.
@interface ArktSelfTestWindowHost : NSObject <ArktWindowHost, NSWindowDelegate>
- (instancetype)initWithFrame:(NSRect)frame title:(NSString*)title;
// Shows `tab`'s container as the card's only subview.
- (void)mountTab:(id<ArktTabHandle>)tab;
// A small view above the card that extension popups anchor to.
@property(nonatomic, readonly) NSView* anchorView;
@end

@implementation ArktSelfTestWindowHost {
  NSWindow* _window;
  NSView* _cardView;
  NSView* _anchorView;
}

@synthesize closeRequested = _closeRequested;
@synthesize validateCommand = _validateCommand;
@synthesize executeCommand = _executeCommand;

- (instancetype)initWithFrame:(NSRect)frame title:(NSString*)title {
  if ((self = [super init])) {
    _window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.releasedWhenClosed = NO;
    _window.title = title;
    _window.delegate = self;
    _cardView = [[NSView alloc] initWithFrame:_window.contentView.bounds];
    _cardView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_window.contentView addSubview:_cardView];
    // Top left, above the card (the content view is not flipped).
    NSRect content = _window.contentView.bounds;
    _anchorView = [[NSView alloc]
        initWithFrame:NSMakeRect(8, NSHeight(content) - 32, 96, 24)];
    _anchorView.autoresizingMask = NSViewMinYMargin;
    _anchorView.wantsLayer = YES;
    _anchorView.layer.backgroundColor = NSColor.systemBlueColor.CGColor;
    [_window.contentView addSubview:_anchorView
                         positioned:NSWindowAbove
                         relativeTo:_cardView];
  }
  return self;
}

- (NSView*)anchorView {
  return _anchorView;
}

- (NSWindow*)window {
  return _window;
}

- (NSView*)cardView {
  return _cardView;
}

- (void)mountTab:(id<ArktTabHandle>)tab {
  NSView* container = tab.containerView;
  if (container.superview == _cardView) {
    return;
  }
  for (NSView* view in [_cardView.subviews copy]) {
    [view removeFromSuperview];
  }
  container.frame = _cardView.bounds;
  container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  container.hidden = NO;
  [_cardView addSubview:container];
  LOG(WARNING) << "ARKT selftest mounted tab=" << tab.sessionId
               << " container=" << (__bridge void*)container
               << " subviews=" << container.subviews.count;
}

// NSWindowDelegate:
- (BOOL)windowShouldClose:(NSWindow*)sender {
  LOG(WARNING) << "ARKT selftest close button window title "
               << base::SysNSStringToUTF8(sender.title);
  if (_closeRequested) {
    _closeRequested();
  }
  return NO;
}

@end

@interface ArktSelfTestEmbedder : NSObject <ArktEngineEmbedder>
@end

@implementation ArktSelfTestEmbedder {
  id<ArktEngine> _engine;
  NSMutableArray<ArktSelfTestWindowHost*>* _hosts;
  NSInteger _windowCount;
  // When each tab's close was asked for (session id), for held durations.
  std::map<int32_t, NSDate*> _closeStarts;
}

+ (id<ArktEngineEmbedder>)sharedEmbedder {
  static base::NoDestructor<ArktSelfTestEmbedder*> embedder(
      [[ArktSelfTestEmbedder alloc] init]);
  return *embedder;
}

- (instancetype)init {
  if ((self = [super init])) {
    _hosts = [[NSMutableArray alloc] init];
  }
  return self;
}

- (ArktSelfTestWindowHost*)newHostWithFrame:(NSRect)frame {
  ++_windowCount;
  if (NSIsEmptyRect(frame)) {
    frame = NSMakeRect(80 + 40 * _windowCount, 120 + 30 * _windowCount, 900,
                       600);
  }
  ArktSelfTestWindowHost* host = [[ArktSelfTestWindowHost alloc]
      initWithFrame:frame
              title:[NSString stringWithFormat:@"Arkt selftest %ld",
                                               static_cast<long>(
                                                   _windowCount)]];
  [_hosts addObject:host];
  return host;
}

- (void)engineDidStart:(id<ArktEngine>)engine {
  _engine = engine;
  ArktSelfTestEmbedder* __weak weakSelf = self;
  [engine addEventSink:^(NSArray<id<ArktEngineEvent>>* events) {
    [weakSelf handleEvents:events];
  }];
  std::string mode =
      base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
          arkt::kFacadeSelfTestSwitch);
  LOG(WARNING) << "ARKT selftest engineDidStart mode="
               << (mode.empty() ? "ready" : mode);
  if (mode == "fail") {
    [self performSelector:@selector(fail) withObject:nil afterDelay:kDelayedStart];
  } else {
    [self performSelector:@selector(ready)
               withObject:nil
               afterDelay:mode == "hold" ? kDelayedStart : 0];
  }
}

- (void)ready {
  LOG(WARNING) << "ARKT selftest embedderReady";
  [_engine embedderReady];
  // The shell's own window, as ShellUI does at launch and on Cmd-N: build the
  // window, then ask for a Browser in it.
  ArktSelfTestWindowHost* host = [self newHostWithFrame:NSZeroRect];
  id<ArktBrowserHandle> browser = [_engine createBrowserWithHost:host];
  LOG(WARNING) << "ARKT selftest createBrowser window=" << browser.windowId;
  [host.window makeKeyAndOrderFront:nil];
  LOG(WARNING) << "ARKT selftest window number " << host.window.windowNumber
               << " window=" << browser.windowId;
  std::string url = base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
      kSelfTestURLSwitch);
  NSURL* first = [NSURL
      URLWithString:base::SysUTF8ToNSString(url.empty() ? kDefaultURL : url)];
  id<ArktTabHandle> tab = [browser createTabWithURL:first active:YES];
  LOG(WARNING) << "ARKT selftest createTab tab=" << tab.sessionId;
}

- (void)fail {
  LOG(WARNING) << "ARKT selftest embedderFailed";
  [_engine embedderFailed];
}

- (ArktSelfTestWindowHost*)hostOf:(id<ArktBrowserHandle>)browser {
  id<ArktWindowHost> host = browser.host;
  return [host isKindOfClass:[ArktSelfTestWindowHost class]]
             ? static_cast<ArktSelfTestWindowHost*>(host)
             : nil;
}

- (void)handleEvents:(NSArray<id<ArktEngineEvent>>*)events {
  bool windows_changed = false;
  for (id<ArktEngineEvent> event in events) {
    int32_t window = event.browser ? event.browser.windowId : -1;
    int32_t tab = event.tab ? event.tab.sessionId : -1;
    switch (event.kind) {
      case ArktEngineEventKindTabCreated:
        LOG(WARNING) << "ARKT selftest tabCreated window=" << window
                     << " tab=" << tab << " origin="
                     << (event.origin == ArktTabOriginEngine ? "engine"
                                                             : "client")
                     << " active=" << (event.isActive ? "yes" : "no")
                     << " opener=" << (event.opener ? event.opener.sessionId : -1)
                     << " url=" << Describe(event.url);
        if (event.isActive) {
          [[self hostOf:event.browser] mountTab:event.tab];
        }
        break;
      case ArktEngineEventKindTabClosed: {
        std::string elapsed;
        auto start = _closeStarts.find(tab);
        if (start != _closeStarts.end()) {
          elapsed = " after " +
                    base::NumberToString(static_cast<int>(
                        -[start->second timeIntervalSinceNow] * 1000)) +
                    " ms";
          _closeStarts.erase(start);
        }
        LOG(WARNING) << "ARKT selftest tabClosed window=" << window
                     << " tab=" << tab
                     << " reason=" << ReasonName(event.closeReason)
                     << elapsed;
        break;
      }
      case ArktEngineEventKindActiveTabChanged:
        LOG(WARNING) << "ARKT selftest activeTabChanged window=" << window
                     << " tab=" << tab;
        [[self hostOf:event.browser] mountTab:event.tab];
        break;
      case ArktEngineEventKindCloseCancelled:
        _closeStarts.erase(tab);
        LOG(WARNING) << "ARKT selftest closeCancelled window=" << window
                     << " tab=" << tab
                     << " isClosing=" << (event.tab.isClosing ? "yes" : "no");
        break;
      case ArktEngineEventKindURLChanged:
        LOG(WARNING) << "ARKT selftest urlChanged tab=" << tab
                     << " url=" << Describe(event.url);
        break;
      case ArktEngineEventKindTitleChanged: {
        std::string title = base::SysNSStringToUTF8(event.title);
        LOG(WARNING) << "ARKT selftest titleChanged tab=" << tab
                     << " title=" << title;
        if (title.starts_with(kCommandPrefix)) {
          [self runCommand:title.substr(sizeof(kCommandPrefix) - 1)
                     onTab:event.tab];
        }
        break;
      }
      case ArktEngineEventKindLoadingChanged:
        LOG(WARNING) << "ARKT selftest loadingChanged tab=" << tab
                     << " loading=" << (event.isLoading ? "yes" : "no");
        break;
      case ArktEngineEventKindHistoryChanged:
        LOG(WARNING) << "ARKT selftest historyChanged tab=" << tab
                     << " back=" << (event.canGoBack ? "yes" : "no")
                     << " forward=" << (event.canGoForward ? "yes" : "no");
        break;
      case ArktEngineEventKindFaviconChanged:
        LOG(WARNING) << "ARKT selftest faviconChanged tab=" << tab << " png="
                     << (event.faviconPNG
                             ? base::NumberToString(event.faviconPNG.length) +
                                   " bytes"
                             : std::string("none"));
        break;
      case ArktEngineEventKindTabReplaced:
        LOG(WARNING) << "ARKT selftest tabReplaced window=" << window
                     << " tab=" << tab << " container="
                     << (__bridge void*)event.tab.containerView;
        [[self hostOf:event.browser] mountTab:event.tab];
        break;
      case ArktEngineEventKindTabMoved:
        LOG(WARNING) << "ARKT selftest tabMoved window=" << window
                     << " tab=" << tab
                     << " active=" << (event.isActive ? "yes" : "no");
        if (event.isActive) {
          [[self hostOf:event.browser] mountTab:event.tab];
        }
        break;
      case ArktEngineEventKindWindowOpened:
        windows_changed = true;
        LOG(WARNING) << "ARKT selftest windowOpened window=" << window
                     << " host="
                     << base::SysNSStringToUTF8(
                            NSStringFromClass([event.browser.host class]));
        break;
      case ArktEngineEventKindWindowClosed: {
        windows_changed = true;
        LOG(WARNING) << "ARKT selftest windowClosed window=" << window;
        ArktSelfTestWindowHost* host = [self hostOf:event.browser];
        if (host) {
          [_hosts removeObject:host];
        }
        break;
      }
      case ArktEngineEventKindExtensionActionsChanged:
        LOG(WARNING) << "ARKT selftest extensionActionsChanged window="
                     << window;
        [self logActionsOf:event.browser];
        break;
    }
  }
  if (windows_changed) {
    std::string ids;
    for (id<ArktBrowserHandle> browser in _engine.browsers) {
      ids += (ids.empty() ? "" : ",") + std::to_string(browser.windowId);
    }
    LOG(WARNING) << "ARKT selftest windows ids=" << (ids.empty() ? "none" : ids);
  }
}

- (void)logStateOf:(id<ArktTabHandle>)tab {
  NSView* container = tab.containerView;
  LOG(WARNING) << "ARKT selftest state tab=" << tab.sessionId
               << " window=" << (tab.browser ? tab.browser.windowId : -1)
               << " url=" << Describe(tab.url)
               << " title=" << base::SysNSStringToUTF8(tab.title)
               << " loading=" << (tab.isLoading ? "yes" : "no")
               << " back=" << (tab.canGoBack ? "yes" : "no")
               << " forward=" << (tab.canGoForward ? "yes" : "no")
               << " active=" << (tab.isActive ? "yes" : "no")
               << " closing=" << (tab.isClosing ? "yes" : "no")
               << " wouldHoldClose=" << (tab.wouldHoldClose ? "yes" : "no")
               << " favicon="
               << (tab.faviconPNG ? base::NumberToString(tab.faviconPNG.length)
                                  : std::string("none"))
               << " opener=" << (tab.opener ? tab.opener.sessionId : -1)
               << " container=" << (__bridge void*)container
               << " subviews=" << container.subviews.count
               << " inWindow=" << (container.window ? "yes" : "no");
}

- (void)logActionsOf:(id<ArktBrowserHandle>)browser {
  NSArray<id<ArktExtensionAction>>* actions =
      [_engine extensionActionsForBrowser:browser];
  LOG(WARNING) << "ARKT selftest actions window=" << browser.windowId
               << " count=" << actions.count;
  for (id<ArktExtensionAction> action in actions) {
    LOG(WARNING) << "ARKT selftest action "
                 << base::SysNSStringToUTF8(action.actionId) << " "
                 << base::SysNSStringToUTF8(action.name)
                 << " enabled=" << (action.isEnabled ? "1" : "0") << " icon="
                 << (action.iconPNG
                         ? base::NumberToString(action.iconPNG.length) + " bytes"
                         : std::string("none"));
  }
}

- (void)logHistoryOf:(id<ArktTabHandle>)tab {
  std::string back;
  for (id<ArktHistoryEntry> entry in tab.backEntries) {
    back += (back.empty() ? "" : ",") +
            base::SysNSStringToUTF8(entry.url.absoluteString) + "|" +
            base::SysNSStringToUTF8(entry.title);
  }
  std::string forward;
  for (id<ArktHistoryEntry> entry in tab.forwardEntries) {
    forward += (forward.empty() ? "" : ",") +
               base::SysNSStringToUTF8(entry.url.absoluteString) + "|" +
               base::SysNSStringToUTF8(entry.title);
  }
  LOG(WARNING) << "ARKT selftest history tab=" << tab.sessionId
               << " url=" << Describe(tab.url) << " back=[" << back
               << "] forward=[" << forward << "]";
}

- (void)evaluate:(NSString*)script
           inTab:(id<ArktTabHandle>)tab
     userGesture:(BOOL)userGesture
           label:(const char*)label {
  int32_t sessionId = tab.sessionId;
  std::string name(label);
  [_engine evaluateScript:script
                    inTab:tab
              userGesture:userGesture
               completion:^(id result, NSError* error) {
                 LOG(WARNING) << "ARKT selftest eval " << name
                              << " tab=" << sessionId << " result="
                              << base::SysNSStringToUTF8(
                                     [result description] ?: @"nil")
                              << " class="
                              << base::SysNSStringToUTF8(
                                     result ? NSStringFromClass([result class])
                                            : @"none")
                              << " error="
                              << base::SysNSStringToUTF8(
                                     error.localizedDescription ?: @"none");
               }];
}

- (id<ArktTabHandle>)tabWithSessionId:(int32_t)sessionId {
  for (id<ArktBrowserHandle> browser in _engine.browsers) {
    for (id<ArktTabHandle> tab in browser.tabs) {
      if (tab.sessionId == sessionId) {
        return tab;
      }
    }
  }
  return nil;
}

- (void)closeTab:(id<ArktTabHandle>)tab mode:(ArktCloseMode)mode {
  int32_t sessionId = tab.sessionId;
  _closeStarts[sessionId] = [NSDate date];
  ArktCloseResult result = [tab closeWithMode:mode];
  LOG(WARNING) << "ARKT selftest close tab=" << sessionId << " mode="
               << (mode == ArktCloseModeSkipUnloadHandlers ? "skip" : "honour")
               << " result="
               << (result == ArktCloseResultHeld ? "held" : "closed")
               << " isClosing=" << (tab.isClosing ? "yes" : "no");
  if (result == ArktCloseResultClosed) {
    _closeStarts.erase(sessionId);
  }
}

// The W3-3 review case: a createTab deferred inside a nested loop, then
// navigate, activate and close on its handle after the loop has ended but
// before the deferred insert has run. They queue behind the insert; the close
// answers held, and the tab ends with TabClosed(client).
- (void)runPendingCheckIn:(id<ArktBrowserHandle>)browser {
  ArktSelfTestWindowHost* host = [self hostOf:browser];
  if (!host) {
    return;
  }
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Arkt selftest"];
  [menu addItemWithTitle:@"Pending handle check" action:nil keyEquivalent:@""];
  __block id<ArktTabHandle> pending = nil;
  NSTimer* timer = [NSTimer
      timerWithTimeInterval:0.3
                    repeats:NO
                      block:^(NSTimer*) {
                        pending = [browser createTabWithURL:nil active:NO];
                        LOG(WARNING) << "ARKT selftest pending createTab "
                                        "inside the menu, session id "
                                     << pending.sessionId;
                        [menu cancelTracking];
                      }];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
  LOG(WARNING) << "ARKT selftest pending menu open";
  [menu popUpMenuPositioningItem:nil
                      atLocation:NSMakePoint(20, 20)
                          inView:host.cardView];
  LOG(WARNING) << "ARKT selftest pending menu closed";
  if (!pending) {
    LOG(WARNING) << "ARKT selftest pending check: no handle";
    return;
  }
  [pending navigateToURL:[NSURL URLWithString:base::SysUTF8ToNSString(
                                                  kPendingURL)]];
  [pending activate];
  ArktCloseResult result =
      [pending closeWithMode:ArktCloseModeHonourUnloadHandlers];
  LOG(WARNING) << "ARKT selftest pending close result="
               << (result == ArktCloseResultHeld ? "held" : "closed")
               << " isClosing=" << (pending.isClosing ? "yes" : "no");
}

- (void)runCommand:(const std::string&)line onTab:(id<ArktTabHandle>)tab {
  std::vector<std::string> words;
  for (const std::string& word : base::SplitString(
           line, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY)) {
    if (!word.starts_with("#")) {
      words.push_back(word);
    }
  }
  if (words.empty()) {
    return;
  }
  const std::string& command = words[0];
  const std::string argument = words.size() > 1 ? words[1] : std::string();
  // "@<session id>" as the last word runs history, goto and duplicate on
  // that tab instead: a page restored from the back-forward cache shows its
  // old title again, which would repeat a command it ran itself.
  if (words.size() > 1 && words.back().starts_with("@")) {
    int32_t sessionId = 0;
    if (base::StringToInt(words.back().substr(1), &sessionId)) {
      if (id<ArktTabHandle> target = [self tabWithSessionId:sessionId]) {
        tab = target;
      }
    }
  }
  LOG(WARNING) << "ARKT selftest command " << command << " " << argument
               << " tab=" << tab.sessionId;
  if (command == "close") {
    [self closeTab:tab
              mode:argument == "skip" ? ArktCloseModeSkipUnloadHandlers
                                      : ArktCloseModeHonourUnloadHandlers];
  } else if (command == "close-other") {
    // Closes the tab with session id `argument`, from another tab (whose
    // page is not blocked by a dialog).
    int32_t sessionId = 0;
    id<ArktTabHandle> target =
        base::StringToInt(argument, &sessionId)
            ? [self tabWithSessionId:sessionId]
            : nil;
    if (target) {
      [self closeTab:target mode:ArktCloseModeHonourUnloadHandlers];
    }
  } else if (command == "state") {
    [self logStateOf:tab];
  } else if (command == "navigate") {
    [tab navigateToURL:[NSURL URLWithString:base::SysUTF8ToNSString(argument)]];
  } else if (command == "reload") {
    // Of this tab, or of the tab with session id `argument` (a crashed page
    // cannot set its own title).
    int32_t sessionId = 0;
    id<ArktTabHandle> target =
        base::StringToInt(argument, &sessionId)
            ? [self tabWithSessionId:sessionId]
            : tab;
    LOG(WARNING) << "ARKT selftest reload tab=" << target.sessionId
                 << " container=" << (__bridge void*)target.containerView;
    [target reload];
  } else if (command == "activate") {
    int32_t sessionId = 0;
    if (base::StringToInt(argument, &sessionId)) {
      [[self tabWithSessionId:sessionId] activate];
    }
  } else if (command == "pending") {
    [self runPendingCheckIn:tab.browser];
  } else if (command == "history") {
    [self logHistoryOf:tab];
  } else if (command == "goto") {
    int offset = 0;
    if (base::StringToInt(argument, &offset)) {
      [tab goToHistoryOffset:offset];
    }
  } else if (command == "duplicate") {
    id<ArktTabHandle> copy = [tab duplicate];
    LOG(WARNING) << "ARKT selftest duplicate of tab=" << tab.sessionId
                 << " copy=" << (copy ? copy.sessionId : -2) << " origin="
                 << (copy && copy.origin == ArktTabOriginClient ? "client"
                                                                : "-");
    if (copy) {
      [self logHistoryOf:copy];
    }
  } else if (command == "actions") {
    [self logActionsOf:tab.browser];
  } else if (command == "run") {
    ArktSelfTestWindowHost* host = [self hostOf:tab.browser];
    LOG(WARNING) << "ARKT selftest run action " << argument << " anchor="
                 << (__bridge void*)host.anchorView;
    [_engine runExtensionAction:base::SysUTF8ToNSString(argument)
                      inBrowser:tab.browser
                         anchor:host.anchorView];
  } else if (command == "eval") {
    LOG(WARNING) << "ARKT selftest testAPIEnabled="
                 << (_engine.testAPIEnabled ? "yes" : "no");
    [self evaluate:@"({sum: 1 + 2, list: [1, 'two', null], ok: true, "
                   @"title: document.title})"
             inTab:tab
       userGesture:NO
             label:"value"];
    [self evaluate:@"navigator.userActivation.isActive"
             inTab:tab
       userGesture:NO
             label:"no-gesture"];
    [self evaluate:@"navigator.userActivation.isActive"
             inTab:tab
       userGesture:YES
             label:"gesture"];
    [self evaluate:@"Promise.resolve(7)" inTab:tab userGesture:NO
             label:"promise"];
    [self evaluate:@"undefinedName.x" inTab:tab userGesture:NO
             label:"throws"];
  } else if (command == "hold") {
    // The harness's holdClose: a beforeunload handler with sticky user
    // activation, through the test API.
    [self evaluate:@"window.onbeforeunload = e => { e.preventDefault(); "
                   @"e.returnValue = ''; }; "
                   @"navigator.userActivation.hasBeenActive"
             inTab:tab
       userGesture:YES
             label:"hold"];
  } else if (command == "answer") {
    // answer <session id> accept|cancel (from another tab: the dialog's page
    // cannot run script).
    int32_t sessionId = 0;
    id<ArktTabHandle> target =
        base::StringToInt(argument, &sessionId)
            ? [self tabWithSessionId:sessionId]
            : nil;
    const bool accept = words.size() > 2 && words[2] == "accept";
    BOOL answered = target && [_engine answerDialogInTab:target accept:accept];
    LOG(WARNING) << "ARKT selftest answer tab=" << sessionId
                 << " accept=" << (accept ? "yes" : "no")
                 << " answered=" << (answered ? "yes" : "no");
  } else if (command == "devtools") {
    id<ArktWindowHost> host = tab.browser.host;
    if (host.executeCommand) {
      host.executeCommand(IDC_DEV_TOOLS, static_cast<NSInteger>(
                                             WindowOpenDisposition::CURRENT_TAB));
    }
  } else {
    LOG(WARNING) << "ARKT selftest unknown command " << command;
  }
}

- (id<ArktWindowHost>)hostForEngineWindowRequest:
    (id<ArktWindowRequest>)request {
  // Inside Browser construction: build the window, never call the engine.
  LOG(WARNING) << "ARKT selftest host requested kind="
               << KindName(request.kind) << " url="
               << Describe(request.initialURL) << " bounds="
               << (request.hasBounds
                       ? base::SysNSStringToUTF8(NSStringFromRect(request.bounds))
                       : std::string("none"))
               << " opener="
               << (request.opener ? request.opener.windowId : -1);
  return [self newHostWithFrame:request.hasBounds ? request.bounds
                                                  : NSZeroRect];
}

- (void)engineWillBeginTerminating {
  LOG(WARNING) << "ARKT selftest engineWillBeginTerminating";
}

- (void)engineDidCancelTerminating {
  LOG(WARNING) << "ARKT selftest engineDidCancelTerminating";
}

- (void)engineWillTerminate:(void (^)(void))completion {
  LOG(WARNING) << "ARKT selftest engineWillTerminate";
  completion();
}

@end

namespace arkt {

id<ArktEngineEmbedder> CreateSelfTestEmbedder() {
  if (!base::CommandLine::ForCurrentProcess()->HasSwitch(
          kFacadeSelfTestSwitch)) {
    return nil;
  }
  return [ArktSelfTestEmbedder sharedEmbedder];
}

}  // namespace arkt
