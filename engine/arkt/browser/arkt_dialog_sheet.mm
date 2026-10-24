#import "arkt/browser/arkt_dialog_sheet.h"

#import <QuartzCore/QuartzCore.h>

// Colors mirror the shell's tokens (the engine cannot link ShellKit):
// app/ArktShell/ShellKit/Sources/ShellUI/Theme/ShellTokens.swift and
// BrandTokens.swift. Keep the values in step when those change.
namespace {

struct Rgba {
  enum Space { kSRGB, kP3 } space;
  CGFloat r, g, b, a;
};

constexpr Rgba Srgb(uint32_t hex, CGFloat alpha = 1) {
  return {Rgba::kSRGB, ((hex >> 16) & 0xFF) / 255.0, ((hex >> 8) & 0xFF) / 255.0,
          (hex & 0xFF) / 255.0, alpha};
}
constexpr Rgba P3(uint32_t hex, CGFloat alpha) {
  return {Rgba::kP3, ((hex >> 16) & 0xFF) / 255.0, ((hex >> 8) & 0xFF) / 255.0,
          (hex & 0xFF) / 255.0, alpha};
}
constexpr Rgba Black(CGFloat alpha) {
  return {Rgba::kSRGB, 0, 0, 0, alpha};
}
constexpr Rgba White(CGFloat alpha) {
  return {Rgba::kSRGB, 1, 1, 1, alpha};
}

NSColor* ToColor(const Rgba& c) {
  return c.space == Rgba::kP3
             ? [NSColor colorWithDisplayP3Red:c.r green:c.g blue:c.b alpha:c.a]
             : [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a];
}

bool IsDark(NSAppearance* appearance) {
  return [[appearance bestMatchFromAppearancesWithNames:@[
    NSAppearanceNameAqua, NSAppearanceNameDarkAqua
  ]] isEqualToString:NSAppearanceNameDarkAqua];
}

NSColor* Dynamic(Rgba light, Rgba dark) {
  NSColor* light_color = ToColor(light);
  NSColor* dark_color = ToColor(dark);
  return [NSColor colorWithName:nil
                dynamicProvider:^NSColor*(NSAppearance* appearance) {
                  return IsDark(appearance) ? dark_color : light_color;
                }];
}

// BrandTokens.surfaceBrand: porcelain / graphite.
NSColor* SurfaceColor() {
  return Dynamic(Srgb(0xFAF9F5), Srgb(0x202321));
}
// ShellTokens.primaryText.
NSColor* PrimaryTextColor() {
  return Dynamic(P3(0x0E0F10, 0.90), White(0.84));
}
// ShellTokens.secondaryText.
NSColor* SecondaryTextColor() {
  return Dynamic(Black(0.64), White(0.76));
}
// ShellTokens.sidebarDivider.
NSColor* DividerColor() {
  return Dynamic(P3(0x0E0F10, 0.10), White(0.075));
}
// ShellTokens.sidebarItemBackground / sidebarItemHovered / tabPressed level
// above hovered.
NSColor* NeutralFill() {
  return Dynamic(P3(0x0E0F10, 0.05), P3(0xFAFBFF, 0.10));
}
NSColor* NeutralFillHovered() {
  return Dynamic(P3(0x0E0F10, 0.10), P3(0xFAFBFF, 0.15));
}
NSColor* NeutralFillPressed() {
  return Dynamic(P3(0x0E0F10, 0.15), P3(0xFAFBFF, 0.20));
}
// BrandTokens.accent / accentHighlight / accentPressed / onAccent. Mustard is a
// fill only; text on it is graphite.
NSColor* AccentFill() {
  return ToColor(Srgb(0xE9B520));
}
NSColor* AccentFillHovered() {
  return ToColor(Srgb(0xF3CA3D));
}
NSColor* AccentFillPressed() {
  return ToColor(Srgb(0xDCA319));
}
NSColor* OnAccentColor() {
  return ToColor(Srgb(0x202321));
}
// BrandTokens.accentText.
NSColor* AccentTextColor() {
  return Dynamic(Srgb(0x8A5A0E), Srgb(0xE9B520));
}

constexpr CGFloat kSheetWidth = 420;
constexpr CGFloat kInset = 20;
constexpr CGFloat kContentWidth = kSheetWidth - 2 * kInset;
constexpr CGFloat kIconSize = 32;
constexpr CGFloat kIconGap = 12;
constexpr CGFloat kListMaxHeight = 260;
constexpr CGFloat kButtonHeight = 28;
constexpr CGFloat kButtonRadius = 7;
constexpr CGFloat kButtonPadding = 14;
constexpr CGFloat kButtonMinWidth = 80;

NSTextField* Label(NSString* text,
                   NSFont* font,
                   NSColor* color,
                   CGFloat width) {
  NSTextField* label = [NSTextField wrappingLabelWithString:text ?: @""];
  label.font = font;
  label.textColor = color;
  label.selectable = NO;
  label.preferredMaxLayoutWidth = width;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [label setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                  forOrientation:
                                      NSLayoutConstraintOrientationVertical];
  return label;
}

}  // namespace

@implementation ArktDialogSheetParagraph
@synthesize text = _text;
@synthesize linkRange = _linkRange;
@synthesize secondary = _secondary;
- (instancetype)init {
  if ((self = [super init])) {
    _linkRange = NSMakeRange(NSNotFound, 0);
  }
  return self;
}
@end

@implementation ArktDialogSheetItem
@synthesize text = _text;
@synthesize details = _details;
@end

@implementation ArktDialogSheetContent
@synthesize title = _title;
@synthesize icon = _icon;
@synthesize subtitle = _subtitle;
@synthesize subtitleAccessibilityLabel = _subtitleAccessibilityLabel;
@synthesize paragraphs = _paragraphs;
@synthesize listHeading = _listHeading;
@synthesize listItems = _listItems;
@synthesize checkboxTitle = _checkboxTitle;
@synthesize checkboxChecked = _checkboxChecked;
@synthesize footerLinkTitle = _footerLinkTitle;
@synthesize primaryTitle = _primaryTitle;
@synthesize cancelTitle = _cancelTitle;
@synthesize defaultButton = _defaultButton;
@synthesize primaryEnableDelay = _primaryEnableDelay;
@end

// A filled, rounded push button in Arkt's colors. The title stays the
// button's title, so VoiceOver reads it as usual.
@interface ArktSheetButton : NSButton
@property(nonatomic) BOOL accent;
@end

@implementation ArktSheetButton {
  BOOL _hovered;
  NSTrackingArea* _tracking;
}
@synthesize accent = _accent;

- (instancetype)initWithTitle:(NSString*)title accent:(BOOL)accent {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _accent = accent;
    self.title = title ?: @"";
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.focusRingType = NSFocusRingTypeDefault;
    self.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  NSSize text = [self.title sizeWithAttributes:@{NSFontAttributeName : self.font}];
  return NSMakeSize(MAX(kButtonMinWidth, ceil(text.width) + 2 * kButtonPadding),
                    kButtonHeight);
}

- (void)setTitle:(NSString*)title {
  [super setTitle:title];
  [self invalidateIntrinsicContentSize];
  self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  self.needsDisplay = YES;
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
  BOOL pressed = self.cell.isHighlighted;
  NSColor* fill;
  if (_accent) {
    fill = pressed ? AccentFillPressed()
                   : (_hovered && self.enabled ? AccentFillHovered()
                                               : AccentFill());
  } else {
    fill = pressed ? NeutralFillPressed()
                   : (_hovered && self.enabled ? NeutralFillHovered()
                                               : NeutralFill());
  }
  CGFloat alpha = self.enabled ? 1.0 : 0.45;
  [[fill colorWithAlphaComponent:fill.alphaComponent * alpha] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds
                                   xRadius:kButtonRadius
                                   yRadius:kButtonRadius] fill];

  NSColor* text_color = _accent ? OnAccentColor() : PrimaryTextColor();
  NSDictionary* attributes = @{
    NSFontAttributeName : self.font,
    NSForegroundColorAttributeName :
        [text_color colorWithAlphaComponent:text_color.alphaComponent * alpha],
  };
  NSSize size = [self.title sizeWithAttributes:attributes];
  NSPoint origin = NSMakePoint(floor(NSMidX(self.bounds) - size.width / 2),
                               floor(NSMidY(self.bounds) - size.height / 2));
  [self.title drawAtPoint:origin withAttributes:attributes];
}

- (void)drawFocusRingMask {
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds
                                   xRadius:kButtonRadius
                                   yRadius:kButtonRadius] fill];
}

- (NSRect)focusRingMaskBounds {
  return self.bounds;
}
@end

// A borderless text button in the accent text color, read as a link.
@interface ArktSheetLinkButton : NSButton
@end

@implementation ArktSheetLinkButton
- (instancetype)initWithTitle:(NSString*)title {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
              NSFontAttributeName : [NSFont systemFontOfSize:13],
              NSForegroundColorAttributeName : AccentTextColor(),
            }];
    self.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return self;
}

- (void)resetCursorRects {
  [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (NSAccessibilityRole)accessibilityRole {
  return NSAccessibilityLinkRole;
}
@end

// Escape and Cmd-. arrive here when no control handles them.
@interface ArktSheetWindow : NSWindow
@property(nonatomic, copy) void (^onEscape)(void);
@end

@implementation ArktSheetWindow
@synthesize onEscape = _onEscape;

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (void)cancelOperation:(id)sender {
  if (self.onEscape) {
    self.onEscape();
  }
}
@end

@interface ArktDialogSheet () <NSTextViewDelegate>
@end

@implementation ArktDialogSheet {
  ArktDialogSheetContent* _content;
  ArktSheetWindow* _window;
  ArktSheetButton* _primary;
  ArktSheetButton* _cancel;
  NSButton* _checkbox;
  __weak NSWindow* _parent;
  BOOL _answered;
  BOOL _closed;
  id _parentCloseObserver;
}

@synthesize onPrimary = _onPrimary;
@synthesize onCancel = _onCancel;
@synthesize onDismiss = _onDismiss;
@synthesize onLink = _onLink;
@synthesize onCheckbox = _onCheckbox;

- (instancetype)initWithContent:(ArktDialogSheetContent*)content {
  if ((self = [super init])) {
    _content = content;
    [self buildWindow];
  }
  return self;
}

- (void)dealloc {
  if (_parentCloseObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_parentCloseObserver];
  }
}

- (NSWindow*)window {
  return _window;
}

- (BOOL)checkboxChecked {
  return _checkbox && _checkbox.state == NSControlStateValueOn;
}

#pragma mark - Building

- (NSView*)headerView {
  NSStackView* text = [NSStackView stackViewWithViews:@[]];
  text.orientation = NSUserInterfaceLayoutOrientationVertical;
  text.alignment = NSLayoutAttributeLeading;
  text.spacing = 3;
  CGFloat text_width =
      kContentWidth - (_content.icon ? kIconSize + kIconGap : 0);
  NSTextField* title =
      Label(_content.title,
            [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
            PrimaryTextColor(), text_width);
  title.accessibilityRole = NSAccessibilityStaticTextRole;
  [text addArrangedSubview:title];
  if (_content.subtitle.length) {
    NSTextField* subtitle = Label(_content.subtitle,
                                  [NSFont systemFontOfSize:12],
                                  SecondaryTextColor(), text_width);
    if (_content.subtitleAccessibilityLabel.length) {
      subtitle.accessibilityLabel = _content.subtitleAccessibilityLabel;
    }
    [text addArrangedSubview:subtitle];
  }

  if (!_content.icon) {
    return text;
  }
  NSImageView* icon = [NSImageView imageViewWithImage:_content.icon];
  // Down-scale large icons, never up-scale or crop small ones.
  icon.imageScaling = NSImageScaleProportionallyDown;
  icon.translatesAutoresizingMaskIntoConstraints = NO;
  // The name is in the title; the icon is decoration for VoiceOver.
  icon.accessibilityElement = NO;
  icon.cell.accessibilityElement = NO;
  [NSLayoutConstraint activateConstraints:@[
    [icon.widthAnchor constraintEqualToConstant:kIconSize],
    [icon.heightAnchor constraintEqualToConstant:kIconSize],
  ]];
  NSStackView* row = [NSStackView stackViewWithViews:@[ icon, text ]];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeTop;
  row.spacing = kIconGap;
  return row;
}

- (NSView*)paragraphView:(ArktDialogSheetParagraph*)paragraph
                   index:(NSInteger)index {
  NSFont* font = [NSFont systemFontOfSize:13];
  NSColor* color =
      paragraph.secondary ? SecondaryTextColor() : PrimaryTextColor();
  if (paragraph.linkRange.location == NSNotFound ||
      NSMaxRange(paragraph.linkRange) > paragraph.text.length) {
    return Label(paragraph.text, font, color, kContentWidth);
  }

  // A text view, so the link inside the sentence is a real, focusable link.
  NSMutableAttributedString* text = [[NSMutableAttributedString alloc]
      initWithString:paragraph.text
          attributes:@{
            NSFontAttributeName : font,
            NSForegroundColorAttributeName : color,
          }];
  [text addAttribute:NSLinkAttributeName
               value:[NSString stringWithFormat:@"arkt-sheet-link:%ld",
                                                (long)index]
               range:paragraph.linkRange];
  NSTextView* view =
      [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kContentWidth, 10)];
  view.editable = NO;
  view.selectable = YES;
  view.drawsBackground = NO;
  view.textContainerInset = NSZeroSize;
  view.textContainer.lineFragmentPadding = 0;
  view.linkTextAttributes = @{
    NSForegroundColorAttributeName : AccentTextColor(),
    NSCursorAttributeName : NSCursor.pointingHandCursor,
  };
  view.delegate = self;
  [view.textStorage setAttributedString:text];
  [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
  CGFloat height = ceil(
      [view.layoutManager usedRectForTextContainer:view.textContainer]
          .size.height);
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [NSLayoutConstraint activateConstraints:@[
    [view.widthAnchor constraintEqualToConstant:kContentWidth],
    [view.heightAnchor constraintEqualToConstant:height],
  ]];
  return view;
}

- (BOOL)textView:(NSTextView*)textView
    clickedOnLink:(id)link
          atIndex:(NSUInteger)charIndex {
  NSString* value = [link isKindOfClass:[NSURL class]]
                        ? [(NSURL*)link absoluteString]
                        : [link description];
  NSString* prefix = @"arkt-sheet-link:";
  if (![value hasPrefix:prefix]) {
    return YES;  // Not ours; swallow it rather than opening anything.
  }
  NSInteger index = [[value substringFromIndex:prefix.length] integerValue];
  if (!_answered && !_closed && self.onLink) {
    self.onLink(index);
  }
  return YES;
}

- (NSView*)listView {
  NSStackView* list = [NSStackView stackViewWithViews:@[]];
  list.orientation = NSUserInterfaceLayoutOrientationVertical;
  list.alignment = NSLayoutAttributeLeading;
  list.spacing = 8;
  list.translatesAutoresizingMaskIntoConstraints = NO;
  NSFont* font = [NSFont systemFontOfSize:13];
  NSFont* detail_font = [NSFont systemFontOfSize:12];
  constexpr CGFloat kBulletWidth = 12;
  for (ArktDialogSheetItem* item in _content.listItems) {
    NSTextField* bullet =
        Label(@"•", font, SecondaryTextColor(), kBulletWidth);
    bullet.accessibilityElement = NO;
    bullet.cell.accessibilityElement = NO;
    NSStackView* body = [NSStackView stackViewWithViews:@[]];
    body.orientation = NSUserInterfaceLayoutOrientationVertical;
    body.alignment = NSLayoutAttributeLeading;
    body.spacing = 2;
    [body addArrangedSubview:Label(item.text, font, PrimaryTextColor(),
                                   kContentWidth - kBulletWidth - 4)];
    for (NSString* detail in item.details) {
      [body addArrangedSubview:Label(detail, detail_font, SecondaryTextColor(),
                                     kContentWidth - kBulletWidth - 4)];
    }
    NSStackView* row = [NSStackView stackViewWithViews:@[ bullet, body ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 4;
    [NSLayoutConstraint activateConstraints:@[
      [bullet.widthAnchor constraintEqualToConstant:kBulletWidth],
    ]];
    [list addArrangedSubview:row];
  }

  // Long lists scroll inside the sheet instead of growing it off screen.
  [list layoutSubtreeIfNeeded];
  CGFloat height = list.fittingSize.height;
  if (height <= kListMaxHeight) {
    return list;
  }
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.drawsBackground = NO;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  NSView* document = [[NSView alloc] initWithFrame:NSZeroRect];
  document.translatesAutoresizingMaskIntoConstraints = NO;
  [document addSubview:list];
  scroll.documentView = document;
  [NSLayoutConstraint activateConstraints:@[
    [scroll.widthAnchor constraintEqualToConstant:kContentWidth],
    [scroll.heightAnchor constraintEqualToConstant:kListMaxHeight],
    [document.leadingAnchor
        constraintEqualToAnchor:scroll.contentView.leadingAnchor],
    [document.trailingAnchor
        constraintEqualToAnchor:scroll.contentView.trailingAnchor],
    [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
    [list.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
    [list.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
    [list.topAnchor constraintEqualToAnchor:document.topAnchor],
    [list.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
  ]];
  return scroll;
}

- (NSView*)footerView {
  NSStackView* footer = [NSStackView stackViewWithViews:@[]];
  footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  footer.alignment = NSLayoutAttributeCenterY;
  footer.spacing = 8;
  footer.translatesAutoresizingMaskIntoConstraints = NO;

  if (_content.footerLinkTitle.length) {
    ArktSheetLinkButton* link =
        [[ArktSheetLinkButton alloc] initWithTitle:_content.footerLinkTitle];
    link.target = self;
    link.action = @selector(footerLinkPressed:);
    [footer addView:link inGravity:NSStackViewGravityLeading];
  }

  NSString* primary_title = _content.primaryTitle;
  if (_content.cancelTitle.length) {
    _cancel = [[ArktSheetButton alloc] initWithTitle:_content.cancelTitle
                                              accent:NO];
    _cancel.target = self;
    _cancel.action = @selector(cancelPressed:);
    [footer addView:_cancel inGravity:NSStackViewGravityTrailing];
  }
  if (primary_title.length) {
    _primary = [[ArktSheetButton alloc] initWithTitle:primary_title accent:YES];
    _primary.target = self;
    _primary.action = @selector(primaryPressed:);
    [footer addView:_primary inGravity:NSStackViewGravityTrailing];
  }

  // Return presses the default button only; Escape goes through
  // -cancelOperation: of the window.
  if (_content.defaultButton == ArktDialogSheetDefaultPrimary && _primary) {
    _primary.keyEquivalent = @"\r";
  } else if (_content.defaultButton == ArktDialogSheetDefaultCancel &&
             _cancel) {
    _cancel.keyEquivalent = @"\r";
  }
  [NSLayoutConstraint activateConstraints:@[
    [footer.widthAnchor constraintEqualToConstant:kContentWidth],
  ]];
  return footer;
}

- (void)buildWindow {
  NSStackView* stack = [NSStackView stackViewWithViews:@[]];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 14;
  stack.edgeInsets = NSEdgeInsetsMake(kInset, kInset, kInset, kInset);
  stack.translatesAutoresizingMaskIntoConstraints = NO;

  [stack addArrangedSubview:[self headerView]];

  NSInteger index = 0;
  for (ArktDialogSheetParagraph* paragraph in _content.paragraphs) {
    [stack addArrangedSubview:[self paragraphView:paragraph index:index++]];
  }

  if (_content.listItems.count) {
    NSBox* divider = [[NSBox alloc] initWithFrame:NSZeroRect];
    divider.boxType = NSBoxCustom;
    divider.borderWidth = 0;
    divider.fillColor = DividerColor();
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.accessibilityElement = NO;
    [NSLayoutConstraint activateConstraints:@[
      [divider.heightAnchor constraintEqualToConstant:1],
      [divider.widthAnchor constraintEqualToConstant:kContentWidth],
    ]];
    [stack addArrangedSubview:divider];
    if (_content.listHeading.length) {
      [stack addArrangedSubview:Label(_content.listHeading,
                                      [NSFont systemFontOfSize:13
                                                        weight:
                                                            NSFontWeightMedium],
                                      PrimaryTextColor(), kContentWidth)];
      [stack setCustomSpacing:8 afterView:stack.arrangedSubviews.lastObject];
    }
    [stack addArrangedSubview:[self listView]];
  }

  if (_content.checkboxTitle.length) {
    _checkbox = [NSButton checkboxWithTitle:_content.checkboxTitle
                                     target:self
                                     action:@selector(checkboxChanged:)];
    _checkbox.font = [NSFont systemFontOfSize:13];
    _checkbox.state = _content.checkboxChecked ? NSControlStateValueOn
                                               : NSControlStateValueOff;
    [stack addArrangedSubview:_checkbox];
  }

  NSView* footer = [self footerView];
  [stack addArrangedSubview:footer];
  [stack setCustomSpacing:20 afterView:stack.arrangedSubviews[
                                           stack.arrangedSubviews.count - 2]];

  NSView* content = [[NSView alloc] initWithFrame:NSZeroRect];
  [content addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    [stack.widthAnchor constraintEqualToConstant:kSheetWidth],
  ]];
  [content layoutSubtreeIfNeeded];
  NSSize size = stack.fittingSize;

  _window = [[ArktSheetWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, kSheetWidth, size.height)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:YES];
  _window.releasedWhenClosed = NO;
  _window.title = _content.title ?: @"";
  _window.backgroundColor = SurfaceColor();
  _window.contentView = content;
  // VoiceOver announces the sheet by the dialog title.
  _window.accessibilityLabel = _content.title;
  __weak ArktDialogSheet* weak_self = self;
  _window.onEscape = ^{
    [weak_self escapePressed];
  };
  // Keyboard focus starts on the button Return presses, so the focus ring
  // and Return never point at different buttons.
  _window.initialFirstResponder =
      _content.defaultButton == ArktDialogSheetDefaultPrimary && _primary
          ? _primary
          : (_cancel ?: _primary);
}

#pragma mark - Showing

- (void)beginOnWindow:(NSWindow*)parent {
  if (_closed || !parent) {
    return;
  }
  _parent = parent;
  _window.appearance = parent.appearance;
  __weak ArktDialogSheet* weak_self = self;
  _parentCloseObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:NSWindowWillCloseNotification
                  object:parent
                   queue:nil
              usingBlock:^(NSNotification* note) {
                [weak_self parentWillClose];
              }];
  if (_primary && _content.primaryEnableDelay > 0) {
    _primary.enabled = NO;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(_content.primaryEnableDelay * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          ArktDialogSheet* strong_self = weak_self;
          if (strong_self && !strong_self->_closed) {
            strong_self->_primary.enabled = YES;
          }
        });
  }
  [parent beginSheet:_window completionHandler:nil];
}

- (void)close {
  if (_closed) {
    return;
  }
  _closed = YES;
  if (_parentCloseObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_parentCloseObserver];
    _parentCloseObserver = nil;
  }
  NSWindow* parent = _parent;
  if (_window.sheetParent) {
    [_window.sheetParent endSheet:_window];
  } else if (parent) {
    // Still queued behind another sheet: drop it from the queue.
    [parent endSheet:_window];
  }
  [_window orderOut:nil];
}

- (void)setPrimaryTitle:(NSString*)title enabled:(BOOL)enabled {
  if (!_primary) {
    return;
  }
  if (title.length) {
    _primary.title = title;
  }
  _primary.enabled = enabled;
}

- (void)setCancelTitle:(NSString*)title enabled:(BOOL)enabled {
  if (!_cancel) {
    return;
  }
  if (title.length) {
    _cancel.title = title;
  }
  _cancel.enabled = enabled;
}

- (void)rearm {
  if (!_closed) {
    _answered = NO;
  }
}

#pragma mark - Actions

- (BOOL)takeAnswer {
  if (_answered || _closed) {
    return NO;
  }
  _answered = YES;
  return YES;
}

- (void)primaryPressed:(id)sender {
  if (!_primary.enabled || ![self takeAnswer]) {
    return;
  }
  if (self.onPrimary) {
    self.onPrimary();
  }
}

- (void)cancelPressed:(id)sender {
  if (![self takeAnswer]) {
    return;
  }
  if (self.onCancel) {
    self.onCancel();
  }
}

- (void)escapePressed {
  if (_cancel) {
    [self cancelPressed:nil];
    return;
  }
  if (![self takeAnswer]) {
    return;
  }
  if (self.onDismiss) {
    self.onDismiss();
  }
}

- (void)parentWillClose {
  if (![self takeAnswer]) {
    return;
  }
  if (self.onDismiss) {
    self.onDismiss();
  }
}

- (void)footerLinkPressed:(id)sender {
  if (!_answered && !_closed && self.onLink) {
    self.onLink(-1);
  }
}

- (void)checkboxChanged:(id)sender {
  if (!_answered && !_closed && self.onCheckbox) {
    self.onCheckbox(self.checkboxChecked);
  }
}
@end
