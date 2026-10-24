#include "arkt/browser/arkt_browser_window.h"

#import <AppKit/AppKit.h>

#include <string>
#include <utility>

#include "arkt/browser/arkt_browser_window_parts.h"
#include "arkt/browser/arkt_extensions_bridge.h"
#include "arkt/browser/arkt_extensions_container.h"
#import "arkt/browser/arkt_placeholder_window_host.h"
#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/containers/flat_set.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/custom_theme_supplier.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/new_tab_footer/footer_controller.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/generated_resources.h"
#include "components/bookmarks/common/bookmark_pref_names.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/prefs/pref_service.h"
#include "components/search/ntp_features.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/base/window_open_disposition.h"
#include "ui/color/color_provider_manager.h"
#include "ui/color/color_provider_utils.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace {

// The windows constructed and not yet destroyed. Chromium has no RTTI, so this
// set is how a BrowserWindow is recognised as ours.
base::flat_set<arkt::ArktBrowserWindow*>& LiveWindows() {
  static base::NoDestructor<base::flat_set<arkt::ArktBrowserWindow*>> windows;
  return *windows;
}

// Logs ARKT: visibility lines after every tab change (W5c verification).
constexpr char kTraceVisibilitySwitch[] = "arkt-trace-visibility";

int32_t TabId(content::WebContents* contents) {
  return contents ? sessions::SessionTabHelper::IdForTab(contents).id() : -1;
}

const char* VisibilityName(content::Visibility visibility) {
  switch (visibility) {
    case content::Visibility::VISIBLE:
      return "visible";
    case content::Visibility::HIDDEN:
      return "hidden";
    case content::Visibility::OCCLUDED:
      return "occluded";
  }
  return "unknown";
}

// Main menu validation, as BrowserNativeWidgetMac::ValidateUserInterfaceItem
// and BrowserWindowCommandHandler validateUserInterfaceItem:window: do for a
// Views browser window.

// AppController keyWindowIsModal: an app-modal session, or a sheet on the
// window (the file chooser; Arkt's tab-modal dialogs are not sheets yet).
bool KeyWindowIsModal(NSWindow* window) {
  return NSApp.modalWindow != nil || window.attachedSheet != nil;
}

// Commands that would put up their own dialog or be confusing to run while
// a modal dialog is up.
bool IsDisabledWhileModal(int command) {
  switch (command) {
    case IDC_BACK:
    case IDC_BOOKMARK_ALL_TABS:
    case IDC_BOOKMARK_THIS_TAB:
    case IDC_CREATE_NEW_TAB_GROUP:
    case IDC_DUPLICATE_TAB:
    case IDC_DUPLICATE_TARGET_TAB:
    case IDC_FOCUS_LOCATION:
    case IDC_FORWARD:
    case IDC_GROUP_TARGET_TAB:
    case IDC_HOME:
    case IDC_MANAGE_EXTENSIONS:
    case IDC_MOVE_TAB_TO_NEW_WINDOW:
    case IDC_MUTE_TARGET_SITE:
    case IDC_NAME_WINDOW:
    case IDC_NEW_TAB_TO_RIGHT:
    case IDC_NEW_TAB:
    case IDC_OPEN_FILE:
    case IDC_PIN_TARGET_TAB:
    case IDC_PRINT:
    case IDC_RELOAD:
    case IDC_SAVE_PAGE:
    case IDC_SELECT_NEXT_TAB:
    case IDC_SELECT_PREVIOUS_TAB:
    case IDC_CYCLE_TO_NEXT_TAB:
    case IDC_CYCLE_TO_PREV_TAB:
    case IDC_SHOW_BOOKMARK_MANAGER:
    case IDC_SHOW_DOWNLOADS:
    case IDC_STOP:
    case IDC_TAB_SEARCH:
    case IDC_WINDOW_CLOSE_OTHER_TABS:
    case IDC_WINDOW_CLOSE_TABS_TO_RIGHT:
    case IDC_WINDOW_GROUP_TAB:
    case IDC_WINDOW_MUTE_SITE:
    case IDC_WINDOW_PIN_TAB:
      return true;
    default:
      return false;
  }
}

// The enabled state every host gets through validateCommand.
bool IsCommandEnabledInWindow(BrowserWindowInterface* browser,
                              NSWindow* window,
                              int command) {
  return chrome::SupportsCommand(browser, command) &&
         chrome::IsCommandEnabled(browser, command) &&
         !(IsDisabledWhileModal(command) && KeyWindowIsModal(window));
}

void SetToggleState(id item, bool on) {
  NSControlStateValue state = on ? NSControlStateValueOn : NSControlStateValueOff;
  if (NSMenuItem* menu_item = base::apple::ObjCCast<NSMenuItem>(item)) {
    if (menu_item.state != state) {
      menu_item.state = state;
    }
  } else if (NSButton* button = base::apple::ObjCCast<NSButton>(item)) {
    if (button.state != state) {
      button.state = state;
    }
  }
}

// The item-level part (toggle state, hidden state, dynamic title, key
// equivalent rule). The facade's validateCommand block only carries the
// command id, so only the placeholder host gets this part.
BOOL ValidateCommandItem(BrowserWindowInterface* browser,
                         NSWindow* window,
                         id<NSValidatedUserInterfaceItem> item) {
  const int command = static_cast<int>(item.tag);
  if (!chrome::SupportsCommand(browser, command)) {
    return NO;
  }
  bool enable = IsCommandEnabledInWindow(browser, window, command);
  NSMenuItem* menu_item = base::apple::ObjCCast<NSMenuItem>(item);
  PrefService* prefs = browser->GetProfile()->GetPrefs();
  TabStripModel* model = browser->GetTabStripModel();
  const bool has_active_tab =
      !model->empty() && model->active_index() != TabStripModel::kNoTab;
  switch (command) {
    case IDC_CLOSE_TAB:
      // disable_if_has_no_key_equivalent: AppController decides through the
      // item's key equivalent whether the window is tabbed.
      if (menu_item) {
        enable &= menu_item.keyEquivalent.length > 0;
      }
      break;
    case IDC_FULLSCREEN:
      if (menu_item) {
        NSString* title = base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
            browser->GetWindow()->IsFullscreen() ? IDS_EXIT_FULLSCREEN_MAC
                                                 : IDS_ENTER_FULLSCREEN_MAC));
        if (![menu_item.title isEqualToString:title]) {
          menu_item.title = title;
        }
      }
      break;
    case IDC_SHOW_AS_TAB:
      if (menu_item) {
        menu_item.hidden =
            browser->GetType() == BrowserWindowInterface::TYPE_NORMAL ||
            browser->GetType() == BrowserWindowInterface::TYPE_DEVTOOLS;
      }
      break;
    case IDC_SHOW_BOOKMARK_BAR:
      SetToggleState(item, prefs->GetBoolean(bookmarks::prefs::kShowBookmarkBar));
      break;
    case IDC_TOGGLE_FULLSCREEN_TOOLBAR:
      // Arkt windows are never app windows (no AppBrowserController).
      SetToggleState(item, prefs->GetBoolean(prefs::kShowFullscreenToolbar));
      break;
    case IDC_TOGGLE_JAVASCRIPT_APPLE_EVENTS:
      SetToggleState(item,
                     prefs->GetBoolean(prefs::kAllowJavascriptAppleEvents));
      break;
    case IDC_WINDOW_MUTE_SITE:
      SetToggleState(item, has_active_tab && !model->WillContextMenuMuteSites(
                                                 model->active_index()));
      break;
    case IDC_WINDOW_PIN_TAB:
      SetToggleState(item, has_active_tab &&
                               !model->WillContextMenuPin(model->active_index()));
      break;
    case IDC_WINDOW_GROUP_TAB:
      SetToggleState(item, has_active_tab && !model->WillContextMenuGroup(
                                                 model->active_index()));
      break;
    default:
      break;
  }
  return enable;
}

}  // namespace

namespace arkt {

// -----------------------------------------------------------------------------
// ArktBrowserWindow

ArktBrowserWindow::ArktBrowserWindow(BrowserWindowInterface* browser,
                                     id<ArktWindowHost> host)
    : browser_(browser),
      host_(host),
      notification_tokens_([[NSMutableArray alloc] init]),
      trace_visibility_(base::CommandLine::ForCurrentProcess()->HasSwitch(
          kTraceVisibilitySwitch)) {
  CHECK(host_.window);
  CHECK(host_.cardView);
  LiveWindows().insert(this);

  // Everything BrowserWindowFeatures::InitPostWindowConstruction asks the
  // window for must exist when the constructor returns (it builds
  // ExclusiveAccessManager from GetExclusiveAccessContext()).
  exclusive_access_context_ =
      std::make_unique<ArktExclusiveAccessContext>(this);
  modal_dialog_host_ = std::make_unique<ArktModalDialogHost>(host_.cardView);
  location_bar_ = std::make_unique<ArktStubLocationBar>(browser_);
  side_panel_ui_ = std::make_unique<ArktSidePanelUI>(browser_);
  // BrowserWindowFeatures creates the NTP footer controller for BrowserView
  // windows only, and the NTP handler CHECKs that it exists. With no contents
  // container views it tracks nothing and reports the footer hidden.
  if (base::FeatureList::IsEnabled(ntp_features::kNtpFooter)) {
    new_tab_footer_controller_ =
        std::make_unique<new_tab_footer::NewTabFooterController>(
            browser_->GetProfile(),
            std::vector<raw_ptr<ContentsContainerView, DanglingUntriaged>>(),
            browser_->GetUnownedUserDataHost());
  }

  // chrome.action.openPopup and other non-UI callers find the window's
  // extension actions through ExtensionsContainer::From, as with Webium
  // (webui_browser_window.cc:194).
  extensions_container_ = std::make_unique<ArktExtensionsContainer>(browser_);
  scoped_extensions_container_ =
      std::make_unique<ui::ScopedUnownedUserData<ExtensionsContainer>>(
          browser_->GetUnownedUserDataHost(), *extensions_container_);

  browser_->GetTabStripModel()->AddObserver(this);

  // `this` outlives the tokens: the destructor removes them first.
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  NSWindow* window = host_.window;
  [notification_tokens_
      addObject:[center addObserverForName:NSWindowDidBecomeKeyNotification
                                    object:window
                                     queue:nil
                                usingBlock:^(NSNotification*) {
                                  BrowserActiveStateManager::From(browser_)
                                      ->DidBecomeActive();
                                }]];
  [notification_tokens_
      addObject:[center addObserverForName:NSWindowDidResignKeyNotification
                                    object:window
                                     queue:nil
                                usingBlock:^(NSNotification*) {
                                  BrowserActiveStateManager::From(browser_)
                                      ->DidBecomeInactive();
                                }]];
  [notification_tokens_
      addObject:[center
                    addObserverForName:NSWindowWillEnterFullScreenNotification
                                object:window
                                 queue:nil
                            usingBlock:^(NSNotification*) {
                              bounds_before_fullscreen_ = GetBounds();
                            }]];
  for (NSNotificationName name in @[
         NSWindowDidEnterFullScreenNotification,
         NSWindowDidExitFullScreenNotification
       ]) {
    [notification_tokens_
        addObject:[center addObserverForName:name
                                      object:window
                                       queue:nil
                                  usingBlock:^(NSNotification*) {
                                    OnFullscreenChanged();
                                  }]];
  }
  [notification_tokens_
      addObject:[center addObserverForName:NSViewFrameDidChangeNotification
                                    object:host_.cardView
                                     queue:nil
                                usingBlock:^(NSNotification*) {
                                  OnCardResized();
                                }]];

  base::WeakPtr<ArktBrowserWindow> weak = weak_factory_.GetWeakPtr();
  host_.closeRequested = ^{
    if (weak) {
      weak->Close();
    }
  };
  host_.validateCommand = ^BOOL(NSInteger command) {
    return weak &&
           IsCommandEnabledInWindow(weak->browser_, weak->host_.window,
                                    static_cast<int>(command));
  };
  if ([host_ isKindOfClass:[ArktPlaceholderWindowHost class]]) {
    static_cast<ArktPlaceholderWindowHost*>(host_).validateItem =
        ^BOOL(id<NSValidatedUserInterfaceItem> item) {
          return weak && ValidateCommandItem(weak->browser_,
                                             weak->host_.window, item);
        };
  }
  host_.executeCommand = ^(NSInteger command, NSInteger disposition) {
    if (weak) {
      chrome::ExecuteCommandWithDisposition(
          weak->browser_, static_cast<int>(command),
          static_cast<WindowOpenDisposition>(disposition));
    }
  };
  host_.activateTab = ^(int32_t tab_id) {
    if (weak) {
      weak->ActivateTab(tab_id);
    }
  };
  LOG(WARNING) << "ARKT: native window created";
  LOG(WARNING) << "ARKT: native window session id "
               << browser_->GetSessionID().id();
}

ArktBrowserWindow::~ArktBrowserWindow() {
  // As WebUIBrowserWindow does: features that reach into the window go first.
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();

  for (id token in notification_tokens_) {
    [NSNotificationCenter.defaultCenter removeObserver:token];
  }
  [notification_tokens_ removeAllObjects];
  browser_->GetTabStripModel()->RemoveObserver(this);
  if (mounted_) {
    Unmount(mounted_);
  }
  host_.closeRequested = nil;
  host_.validateCommand = nil;
  if ([host_ isKindOfClass:[ArktPlaceholderWindowHost class]]) {
    static_cast<ArktPlaceholderWindowHost*>(host_).validateItem = nil;
  }
  host_.executeCommand = nil;
  host_.activateTab = nil;
  [host_.window orderOut:nil];

  if (new_tab_footer_controller_) {
    new_tab_footer_controller_->TearDown();
    new_tab_footer_controller_.reset();
  }
  scoped_extensions_container_.reset();
  extensions_container_.reset();
  side_panel_ui_.reset();
  location_bar_.reset();
  modal_dialog_host_.reset();
  exclusive_access_context_.reset();
  LiveWindows().erase(this);
  host_ = nil;
  LOG(WARNING) << "ARKT: native window destroyed";
}

// static
ArktBrowserWindow* ArktBrowserWindow::FromBrowser(
    const BrowserWindowInterface* browser) {
  if (!browser) {
    return nullptr;
  }
  for (ArktBrowserWindow* window : LiveWindows()) {
    if (window->browser_ == browser) {
      return window;
    }
  }
  return nullptr;
}

void ArktBrowserWindow::DeleteBrowserWindow() {
  delete this;
}

void ArktBrowserWindow::Mount(content::WebContents* contents) {
  if (!contents || contents == mounted_) {
    return;
  }
  if (mounted_) {
    Unmount(mounted_);
  }
  NSView* card = host_.cardView;
  NSView* view = contents->GetNativeView().GetNativeNSView();
  view.frame = card.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  view.hidden = NO;
  [card addSubview:view];
  mounted_ = contents;
  if (host_.window.isKeyWindow) {
    contents->Focus();
  }
  LOG(WARNING) << "ARKT: native window mounted tab " << TabId(contents);
}

void ArktBrowserWindow::Unmount(content::WebContents* contents) {
  if (!contents || contents != mounted_) {
    return;
  }
  // Out of the view hierarchy means hidden to Chromium
  // (WebContentsViewCocoa updateWebContentsVisibility).
  [contents->GetNativeView().GetNativeNSView() removeFromSuperview];
  mounted_ = nullptr;
}

void ArktBrowserWindow::OnCardResized() {
  modal_dialog_host_->NotifyPositionRequiresUpdate();
}

void ArktBrowserWindow::OnFullscreenChanged() {
  if (auto* manager = ExclusiveAccessManager::From(browser_)) {
    manager->fullscreen_controller()->WindowFullscreenStateChanged();
  }
}

// ui::BaseWindow --------------------------------------------------------------

bool ArktBrowserWindow::IsActive() const {
  return host_.window.isKeyWindow;
}

bool ArktBrowserWindow::IsMaximized() const {
  // As NativeWidgetMac::IsMaximized: zoomed is Mac's maximized.
  return host_.window.isZoomed && !IsFullscreen();
}

bool ArktBrowserWindow::IsMinimized() const {
  return host_.window.isMiniaturized;
}

bool ArktBrowserWindow::IsFullscreen() const {
  return (host_.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

gfx::NativeWindow ArktBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(host_.window);
}

gfx::Rect ArktBrowserWindow::GetRestoredBounds() const {
  // A minimized NSWindow keeps its frame; in fullscreen the frame is the
  // screen, so report the frame from before entering it (as
  // NativeWidgetMacNSWindowHost does).
  if (IsFullscreen() && !bounds_before_fullscreen_.IsEmpty()) {
    return bounds_before_fullscreen_;
  }
  return GetBounds();
}

ui::mojom::WindowShowState ArktBrowserWindow::GetRestoredState() const {
  return ui::mojom::WindowShowState::kDefault;
}

gfx::Rect ArktBrowserWindow::GetBounds() const {
  return gfx::ScreenRectFromNSRect(host_.window.frame);
}

void ArktBrowserWindow::Show() {
  // Activation is asynchronous on Mac; the Browser must be the last active one
  // as soon as Show() returns (as BrowserView and WebUIBrowserWindow do).
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  NSWindow* window = host_.window;
  if (window.isVisible) {
    [window makeKeyAndOrderFront:nil];
    return;
  }
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];
  if (mounted_) {
    mounted_->Focus();
  }
  // Scripts take the window number for window-only screenshots from here.
  LOG(WARNING) << "ARKT: window number " << window.windowNumber;
}

void ArktBrowserWindow::Hide() {
  [host_.window orderOut:nil];
}

bool ArktBrowserWindow::IsVisible() const {
  return host_.window.isVisible;
}

void ArktBrowserWindow::ShowInactive() {
  [host_.window orderFront:nil];
}

void ArktBrowserWindow::Close() {
  // Close() is called again by Browser::TabStripEmpty() while the first call
  // is still closing tabs; run each request from the run loop, as a Widget
  // close would, so that call never re-enters UnloadController.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ArktBrowserWindow> window) {
                       if (!window) {
                         return;
                       }
                       UnloadController* unload =
                           UnloadController::From(window->browser_);
                       // beforeunload handlers, the user or policy may cancel.
                       if (!unload->HandleBeforeClose()) {
                         return;
                       }
                       if (!window->browser_->GetTabStripModel()->empty()) {
                         // Looks closed at once; tabs close, then
                         // TabStripEmpty() calls Close() again.
                         [window->host_.window orderOut:nil];
                       }
                       unload->OnWindowClosing();
                     },
                     weak_factory_.GetWeakPtr()));
}

void ArktBrowserWindow::Activate() {
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [NSApp activateIgnoringOtherApps:YES];
  [host_.window makeKeyAndOrderFront:nil];
}

void ArktBrowserWindow::Deactivate() {
  // NativeWidgetMac::Deactivate is NOTIMPLEMENTED too; ordering the window
  // back would do more than Chromium does on Mac.
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::Maximize() {
  if (!host_.window.isZoomed) {
    [host_.window zoom:nil];
  }
}

void ArktBrowserWindow::Minimize() {
  [host_.window miniaturize:nil];
}

void ArktBrowserWindow::Restore() {
  NSWindow* window = host_.window;
  if (window.isMiniaturized) {
    [window deminiaturize:nil];
  } else if (IsFullscreen()) {
    [window toggleFullScreen:nil];
  } else if (window.isZoomed) {
    [window zoom:nil];
  }
}

void ArktBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  [host_.window setFrame:gfx::ScreenRectToNSRect(bounds) display:YES];
}

void ArktBrowserWindow::FlashFrame(bool flash) {
  if (flash) {
    [NSApp requestUserAttention:NSInformationalRequest];
  }
}

ui::ZOrderLevel ArktBrowserWindow::GetZOrderLevel() const {
  return host_.window.level == NSNormalWindowLevel
             ? ui::ZOrderLevel::kNormal
             : ui::ZOrderLevel::kFloatingWindow;
}

void ArktBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {
  host_.window.level = order == ui::ZOrderLevel::kNormal
                           ? NSNormalWindowLevel
                           : NSFloatingWindowLevel;
}

// BrowserWindow: window state -------------------------------------------------

bool ArktBrowserWindow::IsOnCurrentWorkspace() const {
  return host_.window.isOnActiveSpace;
}

bool ArktBrowserWindow::IsVisibleOnScreen() const {
  NSWindow* window = host_.window;
  return window.isVisible && !window.isMiniaturized &&
         (window.occlusionState & NSWindowOcclusionStateVisible);
}

gfx::Size ArktBrowserWindow::GetContentsSize() const {
  NSRect bounds = host_.cardView.bounds;
  return gfx::Size(static_cast<int>(NSWidth(bounds)),
                   static_cast<int>(NSHeight(bounds)));
}

void ArktBrowserWindow::SetContentsSize(const gfx::Size& size) {
  gfx::Rect bounds = GetBounds();
  bounds.set_size(bounds.size() + size - GetContentsSize());
  SetBounds(bounds);
}

std::string ArktBrowserWindow::GetWorkspace() const {
  return std::string();
}

bool ArktBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return (host_.window.collectionBehavior &
          NSWindowCollectionBehaviorCanJoinAllSpaces) != 0;
}

bool ArktBrowserWindow::GetCanResize() {
  return (host_.window.styleMask & NSWindowStyleMaskResizable) != 0;
}

ui::mojom::WindowShowState ArktBrowserWindow::GetWindowShowState() const {
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kDefault;
}

bool ArktBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

// BrowserWindow: tabs ---------------------------------------------------------

void ArktBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                           content::WebContents* new_contents,
                                           int index,
                                           int reason) {
  // Tabs of a non-Views window have no Widget to take colours from.
  new_contents->SetColorProviderSource(this);
  Mount(new_contents);
}

void ArktBrowserWindow::OnTabDetached(content::WebContents* contents,
                                      bool was_active) {
  Unmount(contents);
}

ArktTabEvent* ArktBrowserWindow::EntryEvent(ArktTabEventKind kind,
                                            content::WebContents* contents,
                                            int index,
                                            int32_t previous_tab_id) {
  CHECK_GE(index, 0);
  CHECK_LT(static_cast<size_t>(index), entries_.size());
  TabEntry& entry = entries_[static_cast<size_t>(index)];
  entry.id = sessions::SessionTabHelper::IdForTab(contents);
  entry.title = contents->GetTitle();
  entry.url = contents->GetVisibleURL();
  return [[ArktTabEvent alloc]
       initWithKind:kind
              tabId:entry.id.id()
              index:index
          fromIndex:-1
      previousTabId:previous_tab_id
              title:base::SysUTF16ToNSString(entry.title)
                url:base::SysUTF8ToNSString(entry.url.spec())];
}

void ArktBrowserWindow::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  // `entries_` follows the model one change at a time, in the order the
  // change lists them (see TabStripModelChange::Insert and Remove).
  NSMutableArray<ArktTabEvent*>* events = [[NSMutableArray alloc] init];
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      for (const auto& inserted : change.GetInsert()->contents) {
        CHECK_GE(inserted.index, 0);
        CHECK_LE(static_cast<size_t>(inserted.index), entries_.size());
        entries_.insert(entries_.begin() + inserted.index, TabEntry());
        [events addObject:EntryEvent(ArktTabEventKindInserted,
                                     inserted.contents, inserted.index, -1)];
      }
      break;
    case TabStripModelChange::kRemoved:
      for (const auto& removed : change.GetRemove()->contents) {
        CHECK_GE(removed.index, 0);
        CHECK_LT(static_cast<size_t>(removed.index), entries_.size());
        entries_.erase(entries_.begin() + removed.index);
        [events
            addObject:[[ArktTabEvent alloc] initWithKind:ArktTabEventKindRemoved
                                                   tabId:TabId(removed.contents)
                                                   index:removed.index]];
      }
      break;
    case TabStripModelChange::kMoved: {
      const TabStripModelChange::Move* move = change.GetMove();
      CHECK_GE(move->from_index, 0);
      CHECK_LT(static_cast<size_t>(move->from_index), entries_.size());
      TabEntry entry = std::move(entries_[move->from_index]);
      entries_.erase(entries_.begin() + move->from_index);
      CHECK_GE(move->to_index, 0);
      CHECK_LE(static_cast<size_t>(move->to_index), entries_.size());
      entries_.insert(entries_.begin() + move->to_index, std::move(entry));
      [events addObject:[[ArktTabEvent alloc] initWithKind:ArktTabEventKindMoved
                                                     tabId:TabId(move->contents)
                                                     index:move->to_index
                                                 fromIndex:move->from_index
                                             previousTabId:-1
                                                     title:nil
                                                       url:nil]];
      break;
    }
    case TabStripModelChange::kReplaced: {
      // Same tab, new WebContents (and session id), e.g. a prerender
      // activation.
      const TabStripModelChange::Replace* replace = change.GetReplace();
      CHECK_GE(replace->index, 0);
      CHECK_LT(static_cast<size_t>(replace->index), entries_.size());
      [events
          addObject:EntryEvent(ArktTabEventKindUpdated, replace->new_contents,
                               replace->index, TabId(replace->old_contents))];
      break;
    }
    case TabStripModelChange::kSelectionOnly:
      break;
  }
  // As Chrome's ExtensionPopup: an extension popup belongs to the tab it was
  // opened on and closes when another tab becomes active. The popup itself
  // may have caused the change (chrome.tabs.create from its page), so it is
  // destroyed from a posted task, never under its own call.
  if (!tab_strip_model->empty() && selection.active_tab_changed()) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<ArktBrowserWindow> window) {
                         if (window && IsShowingAnyPopover()) {
                           LOG(WARNING) << "ARKT: popup hide (active tab "
                                           "changed)";
                           window->extensions_container_->HideActivePopup();
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }
  if (selection.active_tab_changed() && selection.new_contents) {
    [events addObject:[[ArktTabEvent alloc]
                          initWithKind:ArktTabEventKindActivated
                                 tabId:TabId(selection.new_contents)
                                 index:tab_strip_model->active_index()]];
  }
  if (events.count) {
    [host_ tabListChanged:events];
  }
  if (trace_visibility_ &&
      (change.type() != TabStripModelChange::kSelectionOnly ||
       selection.active_tab_changed())) {
    TraceVisibility();
  }
}

void ArktBrowserWindow::OnTabChangedAt(tabs::TabInterface* tab,
                                       TabChangeType change_type) {
  int index = browser_->GetTabStripModel()->GetIndexOfTab(tab);
  if (index < 0 || static_cast<size_t>(index) >= entries_.size()) {
    return;
  }
  content::WebContents* contents = tab->GetContents();
  const TabEntry& entry = entries_[static_cast<size_t>(index)];
  if (entry.title == contents->GetTitle() &&
      entry.url == contents->GetVisibleURL()) {
    return;
  }
  [host_ tabListChanged:@[ EntryEvent(ArktTabEventKindUpdated, contents, index,
                                      -1) ]];
}

bool ArktBrowserWindow::ActivateTab(int32_t tab_id) {
  TabStripModel* model = browser_->GetTabStripModel();
  for (int i = 0; i < model->count(); ++i) {
    if (TabId(model->GetWebContentsAt(i)) == tab_id) {
      model->ActivateTabAt(
          i, TabStripUserGestureDetails(
                 TabStripUserGestureDetails::GestureType::kOther));
      return true;
    }
  }
  return false;
}

void ArktBrowserWindow::TraceVisibility() {
  // Visibility reaches WebContents through the view's window notifications;
  // read it once the current change has run to completion.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<ArktBrowserWindow> window) {
            if (!window) {
              return;
            }
            TabStripModel* model = window->browser_->GetTabStripModel();
            for (int i = 0; i < model->count(); ++i) {
              content::WebContents* contents = model->GetWebContentsAt(i);
              LOG(WARNING) << "ARKT: visibility " << TabId(contents) << " "
                           << VisibilityName(contents->GetVisibility());
            }
          },
          weak_factory_.GetWeakPtr()));
}

bool ArktBrowserWindow::IsTabStripEditable() const {
  // TabListBridge refuses every extension tab edit when this is false.
  return true;
}

void ArktBrowserWindow::DisableTabStripEditingForTesting() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}

void ArktBrowserWindow::UpdateTitleBar() {
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  host_.window.title =
      contents ? base::SysUTF16ToNSString(contents->GetTitle()) : @"Arkt";
}

void ArktBrowserWindow::UpdateLoadingAnimations(bool is_visible) {}

// BrowserWindow: theme and colours --------------------------------------------

ui::NativeTheme* ArktBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* ArktBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* ArktBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      GetColorProviderKey());
}

ui::ColorProviderKey ArktBrowserWindow::GetColorProviderKey() const {
  Profile* profile = browser_->GetProfile();
  ThemeService* theme_service = ThemeServiceFactory::GetForProfile(profile);
  scoped_refptr<ui::ColorProviderKey::ThemeInitializerSupplier> supplier;
  if (!profile->IsOffTheRecord() && !theme_service->UsingDeviceTheme()) {
    supplier = theme_service->GetThemeSupplier();
  }
  ui::ColorProviderKey key =
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(supplier);
  if (profile->IsIncognitoProfile()) {
    key.color_mode = ui::ColorProviderKey::ColorMode::kDark;
  }
  return key;
}

ui::RendererColorMap ArktBrowserWindow::GetRendererColorMap(
    ui::ColorProviderKey::ColorMode color_mode,
    ui::ColorProviderKey::ForcedColors forced_colors) const {
  ui::ColorProviderKey key = GetColorProviderKey();
  key.color_mode = color_mode;
  key.forced_colors = forced_colors;
  const ui::ColorProvider* provider =
      ui::ColorProviderManager::Get().GetColorProviderFor(key);
  CHECK(provider);
  return ui::CreateRendererColorMap(*provider);
}

// BrowserWindow: window-side objects ------------------------------------------

std::vector<StatusBubble*> ArktBrowserWindow::GetStatusBubbles() {
  // Empty, as in WebUIBrowserWindow: BrowserWebContentsDelegate casts every
  // status bubble to StatusBubbleViews (ContentsMouseEvent, UpdateTargetURL),
  // so a non-Views bubble crashes on the first mouse-entered event.
  return {};
}

LocationBar* ArktBrowserWindow::GetLocationBar() const {
  return location_bar_.get();
}

ExclusiveAccessContext* ArktBrowserWindow::GetExclusiveAccessContext() {
  return exclusive_access_context_.get();
}

web_modal::WebContentsModalDialogHost*
ArktBrowserWindow::GetWebContentsModalDialogHost() {
  return modal_dialog_host_.get();
}

web_modal::WebContentsModalDialogHost*
ArktBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return modal_dialog_host_.get();
}

std::unique_ptr<FindBar> ArktBrowserWindow::CreateFindBar() {
  return std::make_unique<ArktFindBar>();
}

BrowserView* ArktBrowserWindow::AsBrowserView() {
  return nullptr;
}

// BrowserWindow: keyboard -----------------------------------------------------

content::KeyboardEventProcessingResult
ArktBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // The main menu sees Cmd key equivalents after the page did not handle them
  // (HandleKeyboardEvent), so nothing is reserved here.
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool ArktBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // Only real key downs the page did not handle: no synthesized char events,
  // no events the renderer asked to drop.
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar ||
      !event.os_event) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  if (ns_event.type != NSEventTypeKeyDown ||
      !(ns_event.modifierFlags & NSEventModifierFlagCommand)) {
    return false;
  }
  // Chrome's main menu dispatches the command to the browser of the key
  // window, which is found through GetNativeWindow().
  return [NSApp.mainMenu performKeyEquivalent:ns_event];
}

ui::AcceleratorProvider* ArktBrowserWindow::GetAcceleratorProvider() {
  ARKT_STUB("BrowserWindow");
  return nullptr;
}

// BrowserWindow: toolbar and location bar (Arkt has neither) ------------------

bool ArktBrowserWindow::IsToolbarVisible() const {
  // extension_action_api.cc only lets chrome.action.openPopup run when true.
  return true;
}

bool ArktBrowserWindow::IsToolbarShowing() const {
  return false;
}

bool ArktBrowserWindow::IsLocationBarVisible() const {
  return false;
}

void ArktBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool ArktBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

int ArktBrowserWindow::GetTopControlsHeight() const {
  return 0;
}

void ArktBrowserWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

void ArktBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {}

void ArktBrowserWindow::UpdateToolbar(content::WebContents* contents) {}

bool ArktBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}

void ArktBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                     bool animate) {}

void ArktBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}

void ArktBrowserWindow::FocusToolbar() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ToolbarSizeChanged(bool is_animating) {}

void ArktBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void ArktBrowserWindow::FocusAppMenu() {
  ARKT_STUB("BrowserWindow");
}

PinnedToolbarActions* ArktBrowserWindow::GetPinnedToolbarActions() {
  return nullptr;
}

autofill::AutofillBubbleHandler* ArktBrowserWindow::GetAutofillBubbleHandler() {
  // Week 3: a non-null no-op handler (six callers dereference it).
  ARKT_STUB("BrowserWindow");
  return nullptr;
}

// BrowserWindow: bubbles and dialogs Arkt does not show this week -------------

void ArktBrowserWindow::ShowUpdateChromeDialog() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                           bool already_bookmarked) {
  ARKT_STUB("BrowserWindow");
}

ShowTranslateBubbleResult ArktBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  ARKT_STUB("BrowserWindow");
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController* ArktBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

void ArktBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  // No dialog this week (known gap): the close waits, as in Webium.
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowAppMenu() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data,
                                            const gfx::PointF& point) {}

void ArktBrowserWindow::PreHandleDragExit() {}

void ArktBrowserWindow::HandleDragEnded() {}

void ArktBrowserWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::MaybeShowProfileSwitchIPH() {}

void ArktBrowserWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void ArktBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> ArktBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  ARKT_STUB("BrowserWindow");
  return nullptr;
}

void ArktBrowserWindow::ShowCaretBrowsingDialog() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::CreateTabSearchBubble() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::CloseTabSearchBubble() {}

void ArktBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  ARKT_STUB("BrowserWindow");
}

void ArktBrowserWindow::ShowChromeLabs() {
  ARKT_STUB("BrowserWindow");
}

}  // namespace arkt
