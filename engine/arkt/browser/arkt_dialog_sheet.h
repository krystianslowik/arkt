#ifndef ARKT_BROWSER_ARKT_DIALOG_SHEET_H_
#define ARKT_BROWSER_ARKT_DIALOG_SHEET_H_

#import <AppKit/AppKit.h>

// A native sheet for engine dialogs on Arkt windows (extension install,
// post-install and uninstall prompts, issue #244), or the same content as a
// non-modal panel anchored to a view (permission prompts, issue #260). Plain AppKit values only:
// nothing here knows Chromium types, so a ShellUI presenter can take the same
// content later (week-3 Decision 10 keeps these surfaces engine-drawn for
// now). The Chromium side is arkt_extension_dialogs.mm.

// One paragraph of body text. `linkRange` marks a link inside `text`
// (location NSNotFound: none); clicking it calls the sheet's onLink with the
// paragraph's index.
@interface ArktDialogSheetParagraph : NSObject
@property(nonatomic, copy) NSString* text;
@property(nonatomic) NSRange linkRange;
@property(nonatomic) BOOL secondary;
@end

// One entry of the list (a permission and its detail lines).
@interface ArktDialogSheetItem : NSObject
@property(nonatomic, copy) NSString* text;
@property(nonatomic, copy) NSArray<NSString*>* details;
@end

// Which button Return presses. Escape always cancels (or dismisses).
typedef NS_ENUM(NSInteger, ArktDialogSheetDefault) {
  ArktDialogSheetDefaultNone,
  ArktDialogSheetDefaultPrimary,
  ArktDialogSheetDefaultCancel,
};

@interface ArktDialogSheetContent : NSObject
@property(nonatomic, copy) NSString* title;
// Shown at up to 32x32 pt, never scaled up or cropped. nil: no icon.
@property(nonatomic, strong) NSImage* icon;
// A secondary line under the title (ratings and users for Web Store items).
@property(nonatomic, copy) NSString* subtitle;
// What VoiceOver reads for the subtitle; nil: the subtitle itself.
@property(nonatomic, copy) NSString* subtitleAccessibilityLabel;
@property(nonatomic, copy) NSArray<ArktDialogSheetParagraph*>* paragraphs;
@property(nonatomic, copy) NSString* listHeading;
@property(nonatomic, copy) NSArray<ArktDialogSheetItem*>* listItems;
// nil: no checkbox.
@property(nonatomic, copy) NSString* checkboxTitle;
@property(nonatomic) BOOL checkboxChecked;
// A link at the footer's leading edge (Open in Web Store). nil: none.
@property(nonatomic, copy) NSString* footerLinkTitle;
// nil: no such button. Give at least one of the two.
@property(nonatomic, copy) NSString* primaryTitle;
@property(nonatomic, copy) NSString* cancelTitle;
@property(nonatomic) ArktDialogSheetDefault defaultButton;
// The primary (and secondary) button stays disabled this long after the
// sheet appears.
@property(nonatomic) NSTimeInterval primaryEnableDelay;
// A third button between the primary and the cancel button. nil: none.
@property(nonatomic, copy) NSString* secondaryTitle;
// Width in points; 0: the default (420).
@property(nonatomic) CGFloat width;
// Buttons stacked at full width, primary first (for long labels).
@property(nonatomic) BOOL stackedButtons;
// The primary button drawn like the others, so no answer is nudged.
@property(nonatomic) BOOL neutralPrimary;
// Escape dismisses even when there is a Cancel button (Cancel is then a real
// answer, such as Block).
@property(nonatomic) BOOL escapeDismisses;
@end

@interface ArktDialogSheet : NSObject
// The callbacks run at most once in total between primary, cancel and
// dismiss; links and the checkbox may run any number of times before that.
// None of them ends the sheet: the owner calls -close.
@property(nonatomic, copy) void (^onPrimary)(void);
@property(nonatomic, copy) void (^onSecondary)(void);
// The Cancel button, or Escape when there is a Cancel button.
@property(nonatomic, copy) void (^onCancel)(void);
// Escape without a Cancel button (or with escapeDismisses), or the parent
// window closing.
@property(nonatomic, copy) void (^onDismiss)(void);
// Paragraph index, or -1 for the footer link.
@property(nonatomic, copy) void (^onLink)(NSInteger index);
@property(nonatomic, copy) void (^onCheckbox)(BOOL checked);

- (instancetype)initWithContent:(ArktDialogSheetContent*)content;
- (instancetype)init NS_UNAVAILABLE;

// Attaches the sheet to `parent` (queued by AppKit behind a sheet that is
// already up). Never runs a modal loop.
- (void)beginOnWindow:(NSWindow*)parent;
// Shows the content as a non-modal child window of `anchor`'s window, at the
// view's top-leading corner (top-trailing in right-to-left UI), following the
// view's frame and the window's size. Takes key focus only when the parent
// window is key. Never runs a modal loop.
- (void)beginPanelOnView:(NSView*)anchor rightToLeft:(BOOL)rightToLeft;
// Ends the sheet without calling any callback. Safe to call twice.
- (void)close;

// Lets the buttons answer again after an answer the owner did not act on
// (a ui::DialogModel button callback that keeps the dialog open).
- (void)rearm;

- (void)setPrimaryTitle:(NSString*)title enabled:(BOOL)enabled;
- (void)setCancelTitle:(NSString*)title enabled:(BOOL)enabled;

@property(nonatomic, readonly) NSWindow* window;
@property(nonatomic, readonly) BOOL checkboxChecked;
@end

#endif  // ARKT_BROWSER_ARKT_DIALOG_SHEET_H_
