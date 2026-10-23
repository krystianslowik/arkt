#ifndef ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_
#define ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_

#import <AppKit/AppKit.h>

namespace content {
class WebContents;
}

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
