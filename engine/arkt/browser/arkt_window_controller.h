#ifndef ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_
#define ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_

#import <AppKit/AppKit.h>

namespace content {
class WebContents;
}

// Chrome sends web content's unhandled key events back through the browser
// window's CommandDispatcher, which retargets them at Chrome's (hidden) window
// and calls -[NSApp sendEvent:]. AppKit delivers that to the key window, which
// is ours, and the page would see the key twice. Treat such events the way
// CommandDispatcher treats a redispatch: never hand them to the responder
// chain again, only offer key equivalents to the main menu (Copy, Paste, ...).
@interface ArktWindow : NSWindow
@end

// Hosts one WebContents NSView inside an Arkt-owned layout: a 190 pt sidebar
// placeholder and an inset, rounded content card.
@interface ArktWindowController : NSWindowController
- (instancetype)initWithWebContents:(content::WebContents*)webContents;
// Runs the measured card slide `runs` times, starting after `delay` seconds.
// The same run is bound to Ctrl-Opt-A.
- (void)scheduleAnimationRuns:(int)runs afterDelay:(NSTimeInterval)delay;
// Placeholder sidebar button that extension popups anchor to.
@property(nonatomic, readonly) NSButton* extensionsButton;
// Runs when the placeholder button is clicked.
@property(nonatomic, copy) void (^extensionsButtonAction)(void);
@end

#endif  // ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_
