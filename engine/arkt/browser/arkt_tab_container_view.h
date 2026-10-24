#ifndef ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_
#define ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_

#import <AppKit/AppKit.h>

// The stable container of one tab (week-3 plan, Decision 6). The tab's
// current contents view fills it, below the tab's infobars when it has any
// (Task W3-10); when the contents are replaced the contents view is swapped,
// so the container keeps its identity. Embedder hosts mount and remove
// containers; the placeholder host mounts contents views directly and never
// uses one.
//
// Declared here, apart from the facade, so the window code can recognise a
// container (a tab-modal dialog belongs to its tab's container).
@interface ArktTabContainerView : NSView
// Makes `view` the contents view, filling the container below the top bar.
// Nil empties it (the top bar stays).
- (void)showContentsView:(nullable NSView*)view;
// The tab's infobars, pinned to the container's top edge at their frame's
// height; the contents view gets the rest. Nil, or a zero height, removes it.
// Call again after the bar's height changed.
- (void)setTopBarView:(nullable NSView*)bar;
@property(nonatomic, readonly, nullable) NSView* topBarView;
@end

// Lays out `contents` (a direct subview of `host`, or nil) below `bar` (made
// a subview of `host` when its height is above zero, removed otherwise), both
// following `host`'s size. Shared by the container and the placeholder card.
void ArktLayoutBelowTopBar(NSView* _Nonnull host,
                           NSView* _Nullable contents,
                           NSView* _Nullable bar);

#endif  // ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_
