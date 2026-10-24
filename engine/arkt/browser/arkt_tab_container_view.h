#ifndef ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_
#define ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_

#import <AppKit/AppKit.h>

// The stable container of one tab (week-3 plan, Decision 6). The tab's
// current contents view is its only subview and fills it; when the contents
// are replaced the subview is swapped, so the container keeps its identity.
// Embedder hosts mount and remove containers; the placeholder host mounts
// contents views directly and never uses one.
//
// Declared here, apart from the facade, so the window code can recognise a
// container (a tab-modal dialog belongs to its tab's container).
@interface ArktTabContainerView : NSView
// Makes `view` the only subview, filling the container. Nil empties it.
- (void)showContentsView:(nullable NSView*)view;
@end

#endif  // ARKT_BROWSER_ARKT_TAB_CONTAINER_VIEW_H_
