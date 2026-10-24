#import "arkt/api/arkt_selftest_embedder.h"

#import <AppKit/AppKit.h>

#include <string>

#include "base/command_line.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"

namespace {

constexpr char kSelfTestURLSwitch[] = "arkt-facade-selftest-url";
constexpr char kDefaultURL[] =
    "data:text/html,<title>W3-4 shell window</title><h1>Shell-initiated "
    "window</h1>";
constexpr NSTimeInterval kDelayedStart = 5.0;

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
@end

@implementation ArktSelfTestWindowHost {
  NSWindow* _window;
  NSView* _cardView;
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
  }
  return self;
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
  LOG(WARNING) << "ARKT selftest mounted tab=" << tab.sessionId;
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
                     << " url=" << Describe(event.url);
        if (event.isActive) {
          [[self hostOf:event.browser] mountTab:event.tab];
        }
        break;
      case ArktEngineEventKindTabClosed:
        LOG(WARNING) << "ARKT selftest tabClosed window=" << window
                     << " tab=" << tab
                     << " reason=" << ReasonName(event.closeReason);
        break;
      case ArktEngineEventKindActiveTabChanged:
        LOG(WARNING) << "ARKT selftest activeTabChanged window=" << window
                     << " tab=" << tab;
        [[self hostOf:event.browser] mountTab:event.tab];
        break;
      case ArktEngineEventKindCloseCancelled:
        LOG(WARNING) << "ARKT selftest closeCancelled window=" << window
                     << " tab=" << tab;
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
      default:
        LOG(WARNING) << "ARKT selftest event kind="
                     << static_cast<int>(event.kind) << " window=" << window
                     << " tab=" << tab;
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
