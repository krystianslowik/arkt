#ifndef ARKT_BROWSER_ARKT_WINDOW_HOST_H_
#define ARKT_BROWSER_ARKT_WINDOW_HOST_H_

#import <AppKit/AppKit.h>

#import "arkt/api/arkt_engine.h"

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

// The ArktWindowHost protocol is declared in arkt/api/arkt_engine.h, the
// facade header (week-3 plan, Task W3-2). Its activateTab block and
// tabListChanged: (with ArktTabEvent elements) are optional there and used by
// the placeholder host only.

#endif  // ARKT_BROWSER_ARKT_WINDOW_HOST_H_
