#import "arkt/browser/arkt_tab_container_view.h"

@implementation ArktTabContainerView

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.autoresizesSubviews = YES;
  }
  return self;
}

- (void)showContentsView:(NSView*)view {
  for (NSView* subview in [self.subviews copy]) {
    if (subview != view) {
      [subview removeFromSuperview];
    }
  }
  if (!view) {
    return;
  }
  view.frame = self.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  view.hidden = NO;
  if (view.superview != self) {
    [self addSubview:view];
  }
}

@end
