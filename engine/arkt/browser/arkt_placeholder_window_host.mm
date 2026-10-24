#import "arkt/browser/arkt_placeholder_window_host.h"

#import "arkt/browser/arkt_tab_list_view.h"
#import "arkt/browser/arkt_window_controller.h"
#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "ui/base/cocoa/cocoa_base_utils.h"
#include "ui/base/window_open_disposition.h"

namespace {

constexpr CGFloat kSidebarWidth = 190;
constexpr CGFloat kCardInset = 10;
constexpr CGFloat kCardRadius = 10;
constexpr CGFloat kSidebarPadding = 8;

}  // namespace

@interface ArktPlaceholderWindowHost () <NSWindowDelegate>
@end

@implementation ArktPlaceholderWindowHost {
  ArktWindow* __strong _window;
  NSView* __strong _card;
  NSButton* __strong _extensionsButton;
  ArktTabListView* __strong _tabList;
}

@synthesize closeRequested = _closeRequested;
@synthesize extensionsButtonAction = _extensionsButtonAction;
@synthesize validateCommand = _validateCommand;
@synthesize executeCommand = _executeCommand;
@synthesize activateTab = _activateTab;
@synthesize validateItem = _validateItem;

- (instancetype)init {
  if ((self = [super init])) {
    _window = [[ArktWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1400, 900)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable |
                            NSWindowStyleMaskResizable |
                            NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.titlebarAppearsTransparent = YES;
    _window.titleVisibility = NSWindowTitleHidden;
    _window.title = @"Arkt";
    _window.releasedWhenClosed = NO;
    _window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    _window.delegate = self;
    [_window center];

    // Frames and autoresizing masks, not constraints: the card must have its
    // final size before the first tab is mounted, so the page never lays out
    // in a zero-sized view.
    NSView* root = _window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    NSRect bounds = root.bounds;
    _card = [[NSView alloc]
        initWithFrame:NSMakeRect(kSidebarWidth, kCardInset,
                                 NSWidth(bounds) - kSidebarWidth - kCardInset,
                                 NSHeight(bounds) - 2 * kCardInset)];
    _card.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _card.wantsLayer = YES;
    _card.layer.cornerRadius = kCardRadius;
    _card.layer.masksToBounds = YES;
    _card.postsFrameChangedNotifications = YES;
    [root addSubview:_card];

    _extensionsButton =
        [NSButton buttonWithTitle:@"Extensions"
                           target:self
                           action:@selector(extensionsButtonClicked:)];
    [_extensionsButton sizeToFit];
    _extensionsButton.frameOrigin = NSMakePoint(
        16, NSHeight(bounds) - 44 - NSHeight(_extensionsButton.frame));
    _extensionsButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [root addSubview:_extensionsButton];

    // The tab list fills the sidebar below the button.
    CGFloat listTop = NSMinY(_extensionsButton.frame) - kSidebarPadding;
    _tabList = [[ArktTabListView alloc]
        initWithFrame:NSMakeRect(kSidebarPadding, kCardInset,
                                 kSidebarWidth - 2 * kSidebarPadding,
                                 listTop - kCardInset)];
    _tabList.autoresizingMask = NSViewMaxXMargin | NSViewHeightSizable;
    __weak ArktPlaceholderWindowHost* weakSelf = self;
    _tabList.tabSelected = ^(int32_t tabId) {
      ArktPlaceholderWindowHost* host = weakSelf;
      if (host && host->_activateTab) {
        host->_activateTab(tabId);
      }
    };
    [root addSubview:_tabList];
  }
  return self;
}

- (void)dealloc {
  _tabList.tabSelected = nil;
  _window.delegate = nil;
  [_window close];
}

- (NSWindow*)window {
  return _window;
}

- (NSView*)cardView {
  return _card;
}

- (NSButton*)extensionsButton {
  return _extensionsButton;
}

- (ArktTabListView*)tabList {
  return _tabList;
}

// Main menu commands. The window delegate is in the key window's responder
// chain, ahead of the app controller (which only handles window-less
// commands). Same contract as Chrome's BrowserWindowCommandHandler.

- (void)commandDispatch:(id)sender {
  if (_executeCommand) {
    _executeCommand([sender tag],
                    static_cast<NSInteger>(WindowOpenDisposition::CURRENT_TAB));
  }
}

- (void)commandDispatchUsingKeyModifiers:(id)sender {
  if (!_executeCommand || ([sender respondsToSelector:@selector(isEnabled)] &&
                           ![sender isEnabled])) {
    return;
  }
  NSInteger command = [sender tag];
  NSEvent* event = NSApp.currentEvent;
  NSUInteger flags = event.modifierFlags;
  // Shift- or Ctrl-reload skips the cache.
  if (command == IDC_RELOAD &&
      (flags & (NSEventModifierFlagShift | NSEventModifierFlagControl))) {
    command = IDC_RELOAD_BYPASSING_CACHE;
    flags &= ~(NSEventModifierFlagShift | NSEventModifierFlagControl);
  }
  // In a background window Cmd means "keep the window in the background".
  if ([sender respondsToSelector:@selector(window)] &&
      ![[sender window] isMainWindow]) {
    flags &= ~NSEventModifierFlagCommand;
  }
  _executeCommand(command, static_cast<NSInteger>(
                               ui::WindowOpenDispositionFromNSEventWithFlags(
                                   event, flags)));
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  SEL action = item.action;
  if (action == @selector(commandDispatch:) ||
      action == @selector(commandDispatchUsingKeyModifiers:)) {
    if (_validateItem) {
      return _validateItem(item);
    }
    return _validateCommand && _validateCommand(item.tag);
  }
  return [self respondsToSelector:action];
}

- (void)extensionsButtonClicked:(id)sender {
  if (_extensionsButtonAction) {
    _extensionsButtonAction();
  }
}

- (void)tabListChanged:(NSArray<ArktTabEvent*>*)events {
  for (ArktTabEvent* event in events) {
    LOG(WARNING) << "ARKT: tab event "
                 << base::SysNSStringToUTF8(event.kindName) << " tab "
                 << event.tabId << " index " << event.index;
  }
  [_tabList applyEvents:events];
  LOG(WARNING) << "ARKT: tab list rows " << _tabList.tableView.numberOfRows
               << " selected " << _tabList.tableView.selectedRow;
}

// NSWindowDelegate:

- (BOOL)windowShouldClose:(NSWindow*)sender {
  if (_closeRequested) {
    _closeRequested();
    return NO;
  }
  return YES;
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
  // Scripts check this line before sending synthetic input to the window.
  LOG(WARNING) << "ARKT: key window " << _window.windowNumber;
}

@end
