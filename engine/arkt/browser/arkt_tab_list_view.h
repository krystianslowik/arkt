#ifndef ARKT_BROWSER_ARKT_TAB_LIST_VIEW_H_
#define ARKT_BROWSER_ARKT_TAB_LIST_VIEW_H_

#import <AppKit/AppKit.h>

@class ArktTabEvent;

// The placeholder host's tab list: one NSTableView row per tab, title text.
// An engine test surface, not the ShellKit sidebar. It mirrors the tab list
// from ArktTabEvents only; it never reads Chromium's model, and nothing in the
// engine knows about it.
@interface ArktTabListView : NSScrollView
// Run when the user selects a row (click, keyboard or accessibility), with
// that row's tab id. Not run for selection changes that mirror an
// ArktTabEventKindActivated event.
@property(nonatomic, copy) void (^tabSelected)(int32_t tabId);
@property(nonatomic, readonly) NSTableView* tableView;
- (void)applyEvents:(NSArray<ArktTabEvent*>*)events;
@end

#endif  // ARKT_BROWSER_ARKT_TAB_LIST_VIEW_H_
