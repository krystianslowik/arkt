#import "arkt/browser/arkt_tab_container_view.h"

void ArktLayoutBelowTopBar(NSView* host, NSView* contents, NSView* bar) {
  NSRect bounds = host.bounds;
  CGFloat height = bar ? MIN(NSHeight(bar.frame), NSHeight(bounds)) : 0;
  if (bar && height <= 0) {
    [bar removeFromSuperview];
  }
  if (height > 0) {
    // The bar stays on top of the contents view in z-order too.
    if (bar.superview != host) {
      [host addSubview:bar positioned:NSWindowAbove relativeTo:nil];
    }
    bar.frame = NSMakeRect(NSMinX(bounds),
                           host.isFlipped ? NSMinY(bounds)
                                          : NSMaxY(bounds) - height,
                           NSWidth(bounds), height);
    bar.autoresizingMask =
        NSViewWidthSizable |
        (host.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
  }
  if (contents) {
    NSRect frame = bounds;
    frame.size.height -= height;
    if (host.isFlipped) {
      frame.origin.y += height;
    }
    contents.frame = frame;
    contents.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
}

@implementation ArktTabContainerView {
  NSView* __strong _topBarView;
  NSView* __weak _contentsView;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.autoresizesSubviews = YES;
  }
  return self;
}

- (NSView*)topBarView {
  return _topBarView;
}

- (void)showContentsView:(NSView*)view {
  for (NSView* subview in [self.subviews copy]) {
    if (subview != view && subview != _topBarView) {
      [subview removeFromSuperview];
    }
  }
  _contentsView = view;
  if (!view) {
    return;
  }
  view.hidden = NO;
  if (view.superview != self) {
    [self addSubview:view positioned:NSWindowBelow relativeTo:_topBarView];
  }
  ArktLayoutBelowTopBar(self, view, _topBarView);
}

- (void)setTopBarView:(NSView*)bar {
  if (_topBarView && _topBarView != bar) {
    [_topBarView removeFromSuperview];
  }
  _topBarView = bar;
  NSView* contents = _contentsView;
  ArktLayoutBelowTopBar(self, contents.superview == self ? contents : nil,
                        bar);
}

@end
