#ifndef ARKT_BROWSER_ARKT_INFOBAR_VIEW_H_
#define ARKT_BROWSER_ARKT_INFOBAR_VIEW_H_

#import <AppKit/AppKit.h>

// Native infobars for Arkt windows (Task W3-10): one row per infobar, stacked
// at the top of the tab's container. Plain AppKit values only, as
// ArktDialogSheet: the Chromium side (arkt_infobars.mm) fills the content
// and runs the delegate, so a ShellUI presenter can take the same content
// later (week-3 Decision 10).

// One button of a row.
@interface ArktInfobarButton : NSObject
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* tooltip;
@property(nonatomic) BOOL enabled;
// Drawn with the accent fill (Chrome's prominent style).
@property(nonatomic) BOOL prominent;
@end

@interface ArktInfobarContent : NSObject
// What the row says. `messageLinkRanges` (NSValue ranges into `message`)
// mark inline links; clicking one calls onMessageLink with its index.
@property(nonatomic, copy) NSString* message;
@property(nonatomic, copy) NSArray<NSValue*>* messageLinkRanges;
// Shown at 20 pt (Chrome's infobar icon size). nil: none.
@property(nonatomic, strong) NSImage* icon;
// A link after the message, or at the trailing edge before the close button.
// nil: none.
@property(nonatomic, copy) NSString* linkTitle;
@property(nonatomic, copy) NSString* linkAccessibilityLabel;
@property(nonatomic) BOOL linkBeforeButtons;
// nil: no such button.
@property(nonatomic, strong) ArktInfobarButton* okButton;
@property(nonatomic, strong) ArktInfobarButton* cancelButton;
// nil: no close button (the infobar is not closeable).
@property(nonatomic, copy) NSString* closeAccessibilityLabel;
// Mirrors the row (right-to-left UI).
@property(nonatomic) BOOL rightToLeft;
// The infobar's identifier (InfoBarIdentifier name), for logs.
@property(nonatomic, copy) NSString* identifier;
@end

// One infobar. The callbacks report clicks only; the owner decides whether
// the row goes (as ConfirmInfoBar does with the delegate's return value).
@interface ArktInfobarView : NSView
@property(nonatomic, copy) void (^onOk)(void);
@property(nonatomic, copy) void (^onCancel)(void);
@property(nonatomic, copy) void (^onLink)(void);
@property(nonatomic, copy) void (^onMessageLink)(NSUInteger index);
@property(nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithContent:(ArktInfobarContent*)content;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
@end

// The rows of one tab, top to bottom. Its frame height is the sum of the
// rows' heights (0 without rows); the owner lays it out at the top of the
// tab's container and lays out again after a change.
@interface ArktInfobarStackView : NSView
- (void)insertRow:(ArktInfobarView*)row atIndex:(NSUInteger)index;
- (void)removeRow:(ArktInfobarView*)row;
@property(nonatomic, readonly) NSArray<ArktInfobarView*>* rows;
@end

// The height of one row.
extern const CGFloat kArktInfobarRowHeight;

#endif  // ARKT_BROWSER_ARKT_INFOBAR_VIEW_H_
