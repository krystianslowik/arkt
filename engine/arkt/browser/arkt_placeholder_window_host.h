#ifndef ARKT_BROWSER_ARKT_PLACEHOLDER_WINDOW_HOST_H_
#define ARKT_BROWSER_ARKT_PLACEHOLDER_WINDOW_HOST_H_

#import <AppKit/AppKit.h>

#import "arkt/browser/arkt_window_host.h"

@class ArktTabListView;

// This week's host: an ArktWindow with the 190 pt sidebar placeholder (the
// Extensions button and a tab list) and an inset, rounded card.
@interface ArktPlaceholderWindowHost : NSObject <ArktWindowHost>
@property(nonatomic, readonly) NSButton* extensionsButton;
// Run when the Extensions button is clicked.
@property(nonatomic, copy) void (^extensionsButtonAction)(void);
// One consumer of the tab events: an NSTableView in the sidebar.
@property(nonatomic, readonly) ArktTabListView* tabList;
// Set by the engine. Validates a main menu item (or button) for a browser
// command and updates its toggle state, hidden state and title, as Chrome's
// BrowserWindowCommandHandler does. Preferred over validateCommand, which
// sees the command id only.
@property(nonatomic, copy) BOOL (^validateItem)
    (id<NSValidatedUserInterfaceItem> item);
@end

#endif  // ARKT_BROWSER_ARKT_PLACEHOLDER_WINDOW_HOST_H_
