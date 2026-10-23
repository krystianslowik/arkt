#import "arkt/browser/arkt_window_controller.h"

#include <stdlib.h>

#include <algorithm>
#include <cmath>
#include <vector>

#import <QuartzCore/QuartzCore.h>

#include "base/logging.h"
#include "base/system/sys_info.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#import "ui/base/cocoa/views_hostable.h"
#include "ui/gfx/native_ui_types.h"

namespace {
constexpr CGFloat kSidebarWidth = 190;
constexpr CGFloat kCardInset = 10;
constexpr CGFloat kCardRadius = 10;

// Task 5 measurement: slide the card 300 pt right and back with a critically
// damped spring (damping ratio 1.0, response 0.35 s) and record display-link
// timestamps for 2 s.
constexpr CGFloat kSlideDistance = 300;
constexpr double kSpringResponse = 0.35;
constexpr double kSpringDampingRatio = 1.0;
constexpr NSTimeInterval kMeasureSeconds = 2.0;
constexpr NSTimeInterval kRunGapSeconds = 1.0;
constexpr double kSlowFrameMs = 8.6;  // 120 Hz frame budget plus slack.

CASpringAnimation* SlideSpring(CGFloat from, CGFloat to) {
  CASpringAnimation* spring =
      [CASpringAnimation animationWithKeyPath:@"transform.translation.x"];
  spring.mass = 1;
  spring.stiffness = std::pow(2 * M_PI / kSpringResponse, 2);
  spring.damping = 4 * M_PI * kSpringDampingRatio / kSpringResponse;
  spring.fromValue = @(from);
  spring.toValue = @(to);
  spring.duration = spring.settlingDuration;
  spring.fillMode = kCAFillModeForwards;
  spring.removedOnCompletion = NO;
  return spring;
}
}  // namespace

@implementation ArktWindow
- (void)sendEvent:(NSEvent*)event {
  NSEventType type = event.type;
  BOOL isKey = type == NSEventTypeKeyDown || type == NSEventTypeKeyUp ||
               type == NSEventTypeFlagsChanged;
  if (isKey && event.windowNumber != self.windowNumber) {
    if (type == NSEventTypeKeyDown &&
        (event.modifierFlags & NSEventModifierFlagCommand)) {
      [NSApp.mainMenu performKeyEquivalent:event];
    }
    return;
  }
  [super sendEvent:event];
}
@end

@implementation ArktWindowController {
  // Not owned; the tab strip owns it.
  raw_ptr<content::WebContents> _webContents;
  NSView* _card;
  NSButton* _extensionsButton;
  id _keyMonitor;
  CADisplayLink* _displayLink API_AVAILABLE(macos(14.0));
  std::vector<CFTimeInterval> _frameTimes;
  BOOL _measuring;
  int _runsLeft;
  int _runIndex;
  double _load1;
  double _maxOffset;
}

- (instancetype)initWithWebContents:(content::WebContents*)webContents {
  NSWindow* window = [[ArktWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 1400, 900)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskFullSizeContentView
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.titlebarAppearsTransparent = YES;
  window.titleVisibility = NSWindowTitleHidden;
  window.title = @"Arkt";
  window.releasedWhenClosed = NO;
  if ((self = [super initWithWindow:window])) {
    _webContents = webContents;
    [self buildLayout];
    // Scripts check this line before sending synthetic input to the window.
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(windowDidBecomeKey:)
               name:NSWindowDidBecomeKeyNotification
             object:window];
    __weak ArktWindowController* weakSelf = self;
    _keyMonitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                     handler:^NSEvent*(NSEvent* event) {
                                       NSEventModifierFlags flags =
                                           event.modifierFlags &
                                           NSEventModifierFlagDeviceIndependentFlagsMask;
                                       if (flags == (NSEventModifierFlagControl |
                                                     NSEventModifierFlagOption) &&
                                           [event.charactersIgnoringModifiers
                                               isEqualToString:@"a"]) {
                                         [weakSelf startAnimationRun];
                                         return nil;
                                       }
                                       return event;
                                     }];
  }
  return self;
}

- (void)buildLayout {
  NSView* root = self.window.contentView;
  root.wantsLayer = YES;
  root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

  _card = [[NSView alloc] initWithFrame:NSZeroRect];
  _card.wantsLayer = YES;
  _card.layer.cornerRadius = kCardRadius;
  _card.layer.masksToBounds = YES;
  _card.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:_card];

  _extensionsButton = [NSButton buttonWithTitle:@"Extensions"
                                         target:self
                                         action:@selector(extensionsButtonClicked:)];
  _extensionsButton.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:_extensionsButton];
  [NSLayoutConstraint activateConstraints:@[
    [_extensionsButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor
                                                    constant:16],
    [_extensionsButton.topAnchor constraintEqualToAnchor:root.topAnchor
                                                constant:44],
  ]];

  NSView* page = _webContents->GetNativeView().GetNativeNSView();
  LOG(WARNING) << "ARKT: page view class "
               << base::SysNSStringToUTF8(NSStringFromClass([page class]))
               << ", old superview "
               << base::SysNSStringToUTF8(
                      NSStringFromClass([page.superview class]));
  // Chrome's views::NativeViewHost attached this view as a ViewsHostable, which
  // makes the RenderWidgetHostViewMac draw into the Chrome widget's ui::Layer
  // instead of its own NSView. Detaching gives it its own compositor again.
  if ([page conformsToProtocol:@protocol(ViewsHostable)]) {
    id<ViewsHostable> hostable = (id<ViewsHostable>)page;
    ui::ViewsHostableView* hostable_view = [hostable viewsHostableView];
    if (hostable_view) {
      hostable_view->ViewsHostableDetach();
      LOG(WARNING) << "ARKT: detached WebContents view from Chrome views host";
    }
  }
  [page removeFromSuperview];
  page.hidden = NO;
  page.translatesAutoresizingMaskIntoConstraints = NO;
  [_card addSubview:page];

  [NSLayoutConstraint activateConstraints:@[
    [_card.leadingAnchor constraintEqualToAnchor:root.leadingAnchor
                                        constant:kSidebarWidth],
    [_card.trailingAnchor constraintEqualToAnchor:root.trailingAnchor
                                         constant:-kCardInset],
    [_card.topAnchor constraintEqualToAnchor:root.topAnchor constant:kCardInset],
    [_card.bottomAnchor constraintEqualToAnchor:root.bottomAnchor
                                       constant:-kCardInset],
    [page.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
    [page.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
    [page.topAnchor constraintEqualToAnchor:_card.topAnchor],
    [page.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
  ]];
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
  LOG(WARNING) << "ARKT: key window " << self.window.windowNumber;
}

@synthesize extensionsButtonAction = _extensionsButtonAction;

- (NSButton*)extensionsButton {
  return _extensionsButton;
}

- (void)extensionsButtonClicked:(id)sender {
  if (self.extensionsButtonAction) {
    self.extensionsButtonAction();
  }
}

- (void)scheduleAnimationRuns:(int)runs afterDelay:(NSTimeInterval)delay {
  _runsLeft = runs;
  [self performSelector:@selector(nextScheduledRun)
             withObject:nil
             afterDelay:delay];
}

- (void)nextScheduledRun {
  if (_runsLeft <= 0) {
    return;
  }
  _runsLeft--;
  [self startAnimationRun];
}

- (void)startAnimationRun {
  if (_measuring) {
    return;
  }
  if (@available(macOS 14.0, *)) {
    double loads[3] = {0, 0, 0};
    getloadavg(loads, 3);
    _load1 = loads[0];
    _runIndex++;
    _frameTimes.clear();
    _maxOffset = 0;
    _measuring = YES;

    _displayLink = [self.window.contentView
        displayLinkWithTarget:self
                     selector:@selector(onDisplayLink:)];
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop
                       forMode:NSRunLoopCommonModes];

    __weak ArktWindowController* weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
      ArktWindowController* strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      CASpringAnimation* back = SlideSpring(kSlideDistance, 0);
      back.removedOnCompletion = YES;
      [strongSelf->_card.layer addAnimation:back forKey:@"arkt.slide"];
    }];
    [_card.layer addAnimation:SlideSpring(0, kSlideDistance)
                       forKey:@"arkt.slide"];
    [CATransaction commit];

    [self performSelector:@selector(finishAnimationRun)
               withObject:nil
               afterDelay:kMeasureSeconds];
  } else {
    LOG(ERROR) << "ARKT: display link needs macOS 14";
  }
}

- (void)onDisplayLink:(CADisplayLink*)link API_AVAILABLE(macos(14.0)) {
  _frameTimes.push_back(link.timestamp);
  // Sample what is on screen, so the log proves the card actually moved.
  NSNumber* offset = [_card.layer.presentationLayer
      valueForKeyPath:@"transform.translation.x"];
  _maxOffset = std::max(_maxOffset, offset.doubleValue);
}

- (void)finishAnimationRun {
  if (@available(macOS 14.0, *)) {
    [_displayLink invalidate];
    _displayLink = nil;
  }
  _measuring = NO;
  size_t count = _frameTimes.size();
  double max_interval_ms = 0;
  int slow_frames = 0;
  for (size_t i = 1; i < count; ++i) {
    double interval_ms = (_frameTimes[i] - _frameTimes[i - 1]) * 1000.0;
    max_interval_ms = std::max(max_interval_ms, interval_ms);
    if (interval_ms > kSlowFrameMs) {
      slow_frames++;
    }
  }
  LOG(WARNING) << "ARKT frames=" << count << " max_ms=" << max_interval_ms
               << " over_8_6ms=" << slow_frames << " run=" << _runIndex
               << " max_offset_pt=" << _maxOffset
               << " settle_s=" << SlideSpring(0, kSlideDistance).settlingDuration
               << " load1=" << _load1
               << " cores=" << base::SysInfo::NumberOfProcessors();
  if (_runsLeft > 0) {
    [self performSelector:@selector(nextScheduledRun)
               withObject:nil
               afterDelay:kRunGapSeconds];
  }
}

- (void)showWindow:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  [super showWindow:sender];
  [self.window makeKeyAndOrderFront:sender];
  content::RenderWidgetHostView* rwhv =
      _webContents->GetRenderWidgetHostView();
  NSView* widget = rwhv ? rwhv->GetNativeView().GetNativeNSView() : nil;
  BOOL ok = widget ? [self.window makeFirstResponder:widget] : NO;
  LOG(WARNING) << "ARKT: makeFirstResponder(RenderWidgetHostViewCocoa) "
               << (ok ? "ok" : "failed") << ", first responder "
               << base::SysNSStringToUTF8(NSStringFromClass(
                      [self.window.firstResponder class]))
               << ", window number " << self.window.windowNumber
               << ", page hidden " << widget.isHiddenOrHasHiddenAncestor;
  LOG(WARNING) << "ARKT: window number " << self.window.windowNumber;
}

@end
