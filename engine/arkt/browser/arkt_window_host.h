#ifndef ARKT_BROWSER_ARKT_WINDOW_HOST_H_
#define ARKT_BROWSER_ARKT_WINDOW_HOST_H_

#import <AppKit/AppKit.h>

// What changed in an Arkt window's tab list.
typedef NS_ENUM(NSInteger, ArktTabEventKind) {
  ArktTabEventKindInserted,
  ArktTabEventKindRemoved,
  ArktTabEventKindMoved,
  // The tab at `index` became the active tab.
  ArktTabEventKindActivated,
  // The tab at `index` changed its title or URL, or its contents were
  // replaced (then `previousTabId` names the tab id it had before).
  ArktTabEventKindUpdated,
};

// One tab list change, in model order. Plain values only, so a host (the
// placeholder below, ShellUI in week 3) can mirror the list without knowing
// Chromium types. Indices are valid in the order the events arrive: apply them
// one after the other.
@interface ArktTabEvent : NSObject
@property(nonatomic, readonly) ArktTabEventKind kind;
// The tab's session id, the same id chrome.tabs reports.
@property(nonatomic, readonly) int32_t tabId;
@property(nonatomic, readonly) NSInteger index;
// Moved: the index before the move. Otherwise -1.
@property(nonatomic, readonly) NSInteger fromIndex;
// Updated after a contents replacement: the old tab id. Otherwise -1.
@property(nonatomic, readonly) int32_t previousTabId;
// Inserted and updated: the tab's title and URL. Otherwise nil.
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* url;
- (instancetype)initWithKind:(ArktTabEventKind)kind
                       tabId:(int32_t)tabId
                       index:(NSInteger)index;
- (instancetype)initWithKind:(ArktTabEventKind)kind
                       tabId:(int32_t)tabId
                       index:(NSInteger)index
                   fromIndex:(NSInteger)fromIndex
               previousTabId:(int32_t)previousTabId
                       title:(NSString*)title
                         url:(NSString*)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// "inserted", "removed", ... for logs.
@property(nonatomic, readonly) NSString* kindName;
@end

// The embedder seam of the engine window. ArktBrowserWindow never creates or
// lays out a window: it asks its host for the NSWindow and for the view tab
// content is mounted in, and reports tab changes back. This week's host is
// ArktPlaceholderWindowHost; in week 3 ShellUI hands over its own borderless
// window and card through the same protocol.
@protocol ArktWindowHost <NSObject>
@property(nonatomic, readonly) NSWindow* window;
// The view that holds the mounted tab content.
@property(nonatomic, readonly) NSView* cardView;
// Called by the host when the user asks to close the window (close button,
// Close Window menu item). The host must not close the window itself; the
// engine closes the Browser and then releases the host.
@property(nonatomic, copy) void (^closeRequested)(void);
// Chrome's main menu sends browser commands (commandDispatch:, tag = command
// id) down the key window's responder chain. The host answers them for its
// window through these blocks, which the engine sets. `disposition` is a
// WindowOpenDisposition value (ui::WindowOpenDispositionFromNSEventWithFlags);
// commandDispatch: passes CURRENT_TAB.
@property(nonatomic, copy) BOOL (^validateCommand)(NSInteger command);
@property(nonatomic, copy) void (^executeCommand)
    (NSInteger command, NSInteger disposition);
// Set by the engine: the host calls it when the user picks a tab in its tab
// list. The engine activates that tab in its model, and the change comes back
// as an ArktTabEventKindActivated event.
@property(nonatomic, copy) void (^activateTab)(int32_t tabId);
// Tab list changes, in order.
- (void)tabListChanged:(NSArray<ArktTabEvent*>*)events;
@end

#endif  // ARKT_BROWSER_ARKT_WINDOW_HOST_H_
