#import "arkt/browser/arkt_infobar_view.h"

#import <QuartzCore/QuartzCore.h>

#import "arkt/browser/arkt_dialog_sheet.h"

// Chrome's infobar is 40 dip high with a single elided line of text; the row
// keeps that height so the page moves by a predictable amount.
const CGFloat kArktInfobarRowHeight = 40;

namespace {

constexpr CGFloat kInset = 12;
constexpr CGFloat kIconSize = 20;
constexpr CGFloat kGap = 8;
constexpr CGFloat kButtonGap = 8;
constexpr CGFloat kCloseSize = 22;
constexpr CGFloat kMessageFontSize = 13;
// Fade-in only, as the permission panel: an infobar is occasional, and the
// page moves down once (no height animation, which would resize the page on
// every frame). No exit animation: the close is often a click the user
// expects to act at once.
constexpr NSTimeInterval kFadeIn = 0.14;

NSString* const kLinkScheme = @"arkt-infobar-link";

}  // namespace

@implementation ArktInfobarButton
@synthesize title = _title;
@synthesize tooltip = _tooltip;
@synthesize enabled = _enabled;
@synthesize prominent = _prominent;
- (instancetype)init {
  if ((self = [super init])) {
    _enabled = YES;
  }
  return self;
}
@end

@implementation ArktInfobarContent
@synthesize message = _message;
@synthesize messageLinkRanges = _messageLinkRanges;
@synthesize icon = _icon;
@synthesize linkTitle = _linkTitle;
@synthesize linkAccessibilityLabel = _linkAccessibilityLabel;
@synthesize linkBeforeButtons = _linkBeforeButtons;
@synthesize okButton = _okButton;
@synthesize cancelButton = _cancelButton;
@synthesize closeAccessibilityLabel = _closeAccessibilityLabel;
@synthesize rightToLeft = _rightToLeft;
@synthesize identifier = _identifier;
@end

// The close button: an xmark in the secondary text color on a round hover
// fill.
@interface ArktInfobarCloseButton : NSButton
@end

@implementation ArktInfobarCloseButton {
  BOOL _hovered;
  NSTrackingArea* _tracking;
}

- (instancetype)initWithLabel:(NSString*)label {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, kCloseSize, kCloseSize)])) {
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.imagePosition = NSImageOnly;
    NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration
        configurationWithPointSize:11
                            weight:NSFontWeightSemibold];
    self.image = [[NSImage imageWithSystemSymbolName:@"xmark"
                            accessibilityDescription:label]
        imageWithSymbolConfiguration:config];
    self.contentTintColor = arkt::SheetSecondaryTextColor();
    self.accessibilityLabel = label;
    self.toolTip = label;
  }
  return self;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_tracking) {
    [self removeTrackingArea:_tracking];
  }
  _tracking = [[NSTrackingArea alloc]
      initWithRect:NSZeroRect
           options:NSTrackingMouseEnteredAndExited |
                   NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
             owner:self
          userInfo:nil];
  [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent*)event {
  _hovered = YES;
  self.needsDisplay = YES;
}

- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  if (_hovered || self.cell.isHighlighted) {
    NSColor* fill = arkt::SheetDividerColor();
    [fill setFill];
    [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
  }
  [super drawRect:dirtyRect];
}

- (void)drawFocusRingMask {
  [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}

- (NSRect)focusRingMaskBounds {
  return self.bounds;
}
@end

// The message: one line, truncated at the end, with inline links. A text
// view, so the links are real links to VoiceOver and to the pointer.
@interface ArktInfobarMessageView : NSTextView
@end

@implementation ArktInfobarMessageView
@end

// The 1 px line under a row, in the divider color over the surface.
@interface ArktInfobarDividerView : NSView
@end

@implementation ArktInfobarDividerView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
  }
  return self;
}
- (BOOL)wantsUpdateLayer {
  return YES;
}
- (void)updateLayer {
  self.layer.backgroundColor = arkt::SheetDividerColor().CGColor;
}
@end

@interface ArktInfobarView () <NSTextViewDelegate>
- (void)fadeIn;
@end

@implementation ArktInfobarView {
  ArktInfobarContent* _content;
  NSImageView* _icon;
  ArktInfobarMessageView* _message;
  ArktSheetLinkButton* _link;
  ArktSheetButton* _ok;
  ArktSheetButton* _cancel;
  ArktInfobarCloseButton* _close;
  ArktInfobarDividerView* _divider;
}

@synthesize onOk = _onOk;
@synthesize onCancel = _onCancel;
@synthesize onLink = _onLink;
@synthesize onMessageLink = _onMessageLink;
@synthesize onClose = _onClose;

- (instancetype)initWithContent:(ArktInfobarContent*)content {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 600,
                                              kArktInfobarRowHeight)])) {
    _content = content;
    self.wantsLayer = YES;

    if (content.icon) {
      _icon = [NSImageView imageViewWithImage:content.icon];
      _icon.imageScaling = NSImageScaleProportionallyDown;
      _icon.accessibilityElement = NO;
      [self addSubview:_icon];
    }

    _message = [[ArktInfobarMessageView alloc]
        initWithFrame:NSMakeRect(0, 0, 100, kArktInfobarRowHeight)];
    _message.editable = NO;
    _message.selectable = content.messageLinkRanges.count > 0;
    _message.drawsBackground = NO;
    _message.richText = YES;
    _message.textContainerInset = NSZeroSize;
    _message.textContainer.lineFragmentPadding = 0;
    _message.textContainer.maximumNumberOfLines = 1;
    _message.textContainer.lineBreakMode = NSLineBreakByTruncatingTail;
    _message.textContainer.widthTracksTextView = YES;
    _message.horizontallyResizable = NO;
    _message.verticallyResizable = NO;
    _message.delegate = self;
    _message.linkTextAttributes = @{
      NSForegroundColorAttributeName : arkt::SheetAccentTextColor(),
      NSCursorAttributeName : NSCursor.pointingHandCursor,
    };
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    paragraph.alignment =
        content.rightToLeft ? NSTextAlignmentRight : NSTextAlignmentLeft;
    paragraph.baseWritingDirection = content.rightToLeft
                                         ? NSWritingDirectionRightToLeft
                                         : NSWritingDirectionLeftToRight;
    NSMutableAttributedString* text = [[NSMutableAttributedString alloc]
        initWithString:content.message ?: @""
            attributes:@{
              NSFontAttributeName : [NSFont systemFontOfSize:kMessageFontSize],
              NSForegroundColorAttributeName : arkt::SheetPrimaryTextColor(),
              NSParagraphStyleAttributeName : paragraph,
            }];
    NSUInteger index = 0;
    for (NSValue* value in content.messageLinkRanges) {
      NSRange range = value.rangeValue;
      if (NSMaxRange(range) <= text.length) {
        [text addAttribute:NSLinkAttributeName
                     value:[NSString stringWithFormat:@"%@:%lu", kLinkScheme,
                                                      (unsigned long)index]
                     range:range];
      }
      ++index;
    }
    [_message.textStorage setAttributedString:text];
    // The full message when it is truncated. Read as text, not as an
    // editable text area; inline links stay links.
    _message.toolTip = content.message;
    if (content.messageLinkRanges.count == 0) {
      _message.accessibilityRole = NSAccessibilityStaticTextRole;
    }
    [self addSubview:_message];

    if (content.linkTitle.length) {
      _link = [[ArktSheetLinkButton alloc] initWithTitle:content.linkTitle];
      _link.translatesAutoresizingMaskIntoConstraints = YES;
      _link.target = self;
      _link.action = @selector(linkPressed:);
      if (content.linkAccessibilityLabel.length) {
        _link.accessibilityLabel = content.linkAccessibilityLabel;
      }
    }
    // Subviews in reading order (VoiceOver follows it): the link where it is
    // drawn, before or after the buttons.
    if (_link && content.linkBeforeButtons) {
      [self addSubview:_link];
    }
    _ok = [self buttonFor:content.okButton action:@selector(okPressed:)];
    _cancel = [self buttonFor:content.cancelButton
                       action:@selector(cancelPressed:)];
    if (_link && !content.linkBeforeButtons) {
      [self addSubview:_link];
    }
    if (content.closeAccessibilityLabel) {
      _close = [[ArktInfobarCloseButton alloc]
          initWithLabel:content.closeAccessibilityLabel];
      _close.target = self;
      _close.action = @selector(closePressed:);
      [self addSubview:_close];
    }

    _divider = [[ArktInfobarDividerView alloc] initWithFrame:NSZeroRect];
    [self addSubview:_divider];

    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = content.message;
    self.identifier = content.identifier;
  }
  return self;
}

- (ArktSheetButton*)buttonFor:(ArktInfobarButton*)spec action:(SEL)action {
  if (!spec) {
    return nil;
  }
  ArktSheetButton* button =
      [[ArktSheetButton alloc] initWithTitle:spec.title accent:spec.prominent];
  button.translatesAutoresizingMaskIntoConstraints = YES;
  button.enabled = spec.enabled;
  if (spec.tooltip.length) {
    button.toolTip = spec.tooltip;
  }
  button.target = self;
  button.action = action;
  [self addSubview:button];
  return button;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)wantsUpdateLayer {
  return YES;
}

- (void)updateLayer {
  // Resolved in the view's appearance, so light and dark follow the window.
  self.layer.backgroundColor = arkt::SheetSurfaceColor().CGColor;
}

- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
}

// Lays out leading to trailing: icon, message, (link), buttons, (link),
// close; mirrored in right-to-left UI. The message takes what is left.
- (void)layout {
  [super layout];
  const CGFloat width = NSWidth(self.bounds);
  const CGFloat height = NSHeight(self.bounds);
  const BOOL rtl = _content.rightToLeft;
  _divider.frame = NSMakeRect(0, height - 1, width, 1);
  // Places a view of `size` at leading offset `x`, centred vertically.
  auto place = ^(NSView* view, NSSize size, CGFloat x) {
    CGFloat origin_x = rtl ? width - x - size.width : x;
    view.frame = NSMakeRect(round(origin_x), round((height - size.height) / 2),
                            size.width, size.height);
  };

  // Trailing group, from the trailing edge inward.
  __block CGFloat trailing = kInset;
  auto place_trailing = ^(NSView* view, NSSize size) {
    place(view, size, width - trailing - size.width);
  };
  if (_close) {
    place_trailing(_close, NSMakeSize(kCloseSize, kCloseSize));
    trailing += kCloseSize + kGap;
  }
  if (_link && !_content.linkBeforeButtons) {
    NSSize size = [self linkSize];
    place_trailing(_link, size);
    trailing += size.width + kGap * 2;
  }

  CGFloat x = kInset;
  if (_icon) {
    place(_icon, NSMakeSize(kIconSize, kIconSize), x);
    x += kIconSize + kGap;
  }
  // Buttons and a leading link follow the message; they keep their size,
  // and the message shrinks (truncated) first.
  NSMutableArray<NSView*>* after = [NSMutableArray array];
  if (_link && _content.linkBeforeButtons) {
    [after addObject:_link];
  }
  if (_ok) {
    [after addObject:_ok];
  }
  if (_cancel) {
    [after addObject:_cancel];
  }
  CGFloat after_width = 0;
  for (NSView* view in after) {
    after_width += [self sizeOf:view].width + kButtonGap;
  }
  CGFloat available = width - trailing - x;
  NSSize text = [_message.textStorage size];
  CGFloat message_width =
      MAX(0, MIN(ceil(text.width) + 2, available - after_width - kGap));
  CGFloat line = ceil(text.height);
  place(_message, NSMakeSize(message_width, line), x);
  _message.textContainer.size = NSMakeSize(message_width, line);
  x += message_width + kGap;
  for (NSView* view in after) {
    NSSize size = [self sizeOf:view];
    place(view, size, x);
    x += size.width + kButtonGap;
  }
}

// The link's text size (a borderless button's fitting size is not reliable
// outside Auto Layout).
- (NSSize)linkSize {
  NSSize text = [_link.attributedTitle size];
  return NSMakeSize(ceil(text.width) + 4, ceil(text.height) + 4);
}

- (NSSize)sizeOf:(NSView*)view {
  return view == _link ? [self linkSize] : view.intrinsicContentSize;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) {
    return;
  }
  self.needsLayout = YES;
}

- (void)fadeIn {
  self.alphaValue = 0;
  [NSAnimationContext
      runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = kFadeIn;
        context.timingFunction =
            [CAMediaTimingFunction functionWithControlPoints:0.23:1:0.32:1];
        self.animator.alphaValue = 1;
      }
      completionHandler:nil];
}

- (void)okPressed:(id)sender {
  if (_onOk) {
    _onOk();
  }
}

- (void)cancelPressed:(id)sender {
  if (_onCancel) {
    _onCancel();
  }
}

- (void)linkPressed:(id)sender {
  if (_onLink) {
    _onLink();
  }
}

- (void)closePressed:(id)sender {
  if (_onClose) {
    _onClose();
  }
}

// NSTextViewDelegate:
- (BOOL)textView:(NSTextView*)textView
    clickedOnLink:(id)link
          atIndex:(NSUInteger)charIndex {
  NSString* value = [link isKindOfClass:[NSURL class]]
                        ? [(NSURL*)link absoluteString]
                        : [link description];
  NSString* prefix = [kLinkScheme stringByAppendingString:@":"];
  if (![value hasPrefix:prefix]) {
    return YES;
  }
  NSUInteger index = (NSUInteger)
      [[value substringFromIndex:prefix.length] integerValue];
  if (_onMessageLink) {
    _onMessageLink(index);
  }
  return YES;
}

@end

@implementation ArktInfobarStackView {
  NSMutableArray<ArktInfobarView*>* _rows;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _rows = [NSMutableArray array];
    self.autoresizesSubviews = YES;
    self.wantsLayer = YES;
    self.accessibilityElement = NO;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (NSArray<ArktInfobarView*>*)rows {
  return [_rows copy];
}

- (void)insertRow:(ArktInfobarView*)row atIndex:(NSUInteger)index {
  index = MIN(index, _rows.count);
  [_rows insertObject:row atIndex:index];
  [self addSubview:row];
  [self relayout];
  // A row that appears while the bar is on screen fades in; one that is
  // there when the tab is shown is simply there.
  if (self.window) {
    [row fadeIn];
  }
}

- (void)removeRow:(ArktInfobarView*)row {
  [row removeFromSuperview];
  [_rows removeObject:row];
  [self relayout];
  // The row may be running the click that led here; it lives to the next
  // turn of the run loop.
  dispatch_async(dispatch_get_main_queue(), ^{
    (void)row;
  });
}

// Rows top to bottom; each row draws the line under it (the bottom one
// separates the bar from the page).
- (void)relayout {
  NSRect frame = self.frame;
  frame.size.height = kArktInfobarRowHeight * _rows.count;
  self.frame = frame;
  CGFloat y = 0;
  for (ArktInfobarView* row in _rows) {
    row.frame = NSMakeRect(0, y, NSWidth(self.bounds), kArktInfobarRowHeight);
    row.autoresizingMask = NSViewWidthSizable;
    row.needsLayout = YES;
    y += kArktInfobarRowHeight;
  }
}

@end
