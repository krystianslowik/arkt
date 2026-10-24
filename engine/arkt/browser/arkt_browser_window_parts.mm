#include "arkt/browser/arkt_browser_window_parts.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <set>
#include <utility>

#include "arkt/browser/arkt_browser_window.h"
#include "base/containers/flat_set.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/stringprintf.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/fullscreen/browser_window_fullscreen_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/range/range.h"
#include "ui/views/widget/widget_delegate.h"
#include "url/origin.h"

namespace arkt {

void LogStubOnce(const char* scope, const char* method) {
  static base::NoDestructor<base::flat_set<std::string>> logged;
  std::string name = std::string(scope) + "::" + method;
  if (logged->insert(name).second) {
    LOG(WARNING) << "ARKT: stub " << name;
  }
}

// ArktExclusiveAccessContext --------------------------------------------------

ArktExclusiveAccessContext::ArktExclusiveAccessContext(
    ArktBrowserWindow* window)
    : window_(window) {}

ArktExclusiveAccessContext::~ArktExclusiveAccessContext() = default;

Profile* ArktExclusiveAccessContext::GetProfile() {
  return window_->browser()->GetProfile();
}

bool ArktExclusiveAccessContext::IsFullscreen() const {
  return window_->IsFullscreen();
}

void ArktExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  if (IsFullscreen()) {
    return;
  }
  if (window_->IsShowHeld()) {
    window_->DeferFullscreenWhileHeld();
    return;
  }
  LOG(WARNING) << "ARKT: enter fullscreen";
  [window_->host().window toggleFullScreen:nil];
}

void ArktExclusiveAccessContext::ExitFullscreen() {
  if (BrowserWindowFullscreenController::From(window_->browser())
          ->IsForceFullscreen() ||
      !IsFullscreen()) {
    return;
  }
  LOG(WARNING) << "ARKT: exit fullscreen";
  [window_->host().window toggleFullScreen:nil];
}

void ArktExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  ARKT_STUB("ExclusiveAccessContext");
  if (first_hide_callback) {
    std::move(first_hide_callback)
        .Run(ExclusiveAccessBubbleHideReason::kNotShown);
  }
}

bool ArktExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return false;
}

void ArktExclusiveAccessContext::OnExclusiveAccessUserInput() {}

content::WebContents*
ArktExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return window_->browser()->GetTabStripModel()->GetActiveWebContents();
}

bool ArktExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool ArktExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

// ArktModalDialogHost ---------------------------------------------------------

namespace {

// Dialog widgets some ArktModalDialogHost tracks, so a dialog of one tab is
// never claimed by another tab's host.
std::set<views::Widget*>& ClaimedDialogs() {
  static base::NoDestructor<std::set<views::Widget*>> claimed;
  return *claimed;
}

std::string FrameString(NSRect frame) {
  return base::StringPrintf("%d,%d %dx%d", static_cast<int>(NSMinX(frame)),
                            static_cast<int>(NSMinY(frame)),
                            static_cast<int>(NSWidth(frame)),
                            static_cast<int>(NSHeight(frame)));
}

}  // namespace

ArktModalDialogHost::ArktModalDialogHost(NSView* (^view)(void))
    : view_([view copy]) {}

ArktModalDialogHost::~ArktModalDialogHost() {
  // Chromium closes the dialogs that observe this host synchronously.
  for (auto& observer : observers_) {
    observer.OnHostDestroying();
  }
  for (views::Widget* widget : dialogs_) {
    Detach(widget);
    widget->RemoveObserver(this);
    ClaimedDialogs().erase(widget);
  }
  dialogs_.clear();
}

gfx::NativeView ArktModalDialogHost::GetHostView() const {
  return gfx::NativeView(view_());
}

gfx::Point ArktModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  NSView* view = view_();
  return gfx::Point(
      std::max(0, (static_cast<int>(NSWidth(view.bounds)) - size.width()) / 2),
      0);
}

gfx::Size ArktModalDialogHost::GetMaximumDialogSize() {
  NSView* view = view_();
  return gfx::Size(static_cast<int>(NSWidth(view.bounds)),
                   static_cast<int>(NSHeight(view.bounds)));
}

void ArktModalDialogHost::AddObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.AddObserver(observer);
  // A tab-modal dialog registers here right after its widget is created
  // (CreateWebModalDialogViews) and again when its manager gets this host
  // (ShowDialogWithManager), both before the widget is shown.
  ClaimNewDialogs();
}

void ArktModalDialogHost::RemoveObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.RemoveObserver(observer);
}

void ArktModalDialogHost::NotifyPositionRequiresUpdate() {
  for (auto& observer : observers_) {
    observer.OnPositionRequiresUpdate();
  }
  for (views::Widget* widget : dialogs_) {
    if (widget->IsVisible()) {
      Attach(widget);
    }
  }
}

void ArktModalDialogHost::OnWidgetVisibilityChanged(views::Widget* widget,
                                                    bool visible) {
  if (visible) {
    Attach(widget);
  } else {
    Detach(widget);
  }
}

void ArktModalDialogHost::OnWidgetBoundsChanged(views::Widget* widget,
                                                const gfx::Rect& new_bounds) {
  // Chromium only resizes the dialog (no host widget); keep it top-centred.
  if (widget->IsVisible()) {
    Attach(widget);
  }
}

void ArktModalDialogHost::OnWidgetDestroying(views::Widget* widget) {
  Detach(widget);
  widget->RemoveObserver(this);
  ClaimedDialogs().erase(widget);
  std::erase(dialogs_, widget);
}

void ArktModalDialogHost::ClaimNewDialogs() {
  NSView* view = view_();
  if (!view.window) {
    return;
  }
  for (NSWindow* window in NSApp.windows) {
    views::Widget* widget =
        views::Widget::GetWidgetForNativeWindow(gfx::NativeWindow(window));
    // A tab-modal dialog of an Arkt tab: child-modal, no parent widget (a
    // Views browser window's dialogs have one), not shown yet.
    if (!widget || widget->parent() || !widget->widget_delegate() ||
        widget->widget_delegate()->GetModalType() !=
            ui::mojom::ModalType::kChild ||
        window.isVisible || ClaimedDialogs().contains(widget)) {
      continue;
    }
    ClaimedDialogs().insert(widget);
    dialogs_.push_back(widget);
    widget->AddObserver(this);
    LOG(WARNING) << "ARKT: tab-modal dialog claimed window "
                 << window.windowNumber << " host window "
                 << view.window.windowNumber;
  }
}

void ArktModalDialogHost::Attach(views::Widget* widget) {
  NSWindow* dialog = widget->GetNativeWindow().GetNativeNSWindow();
  NSView* view = view_();
  NSWindow* parent = view.window;
  // Adding a child to a window that is hidden or on another Space would
  // switch Spaces (as NativeWidgetNSWindowBridge::OrderChildren).
  if (!dialog || !parent || !parent.visible || !parent.onActiveSpace) {
    return;
  }
  NSRect host = [parent convertRectToScreen:[view convertRect:view.bounds
                                                       toView:nil]];
  NSRect frame = dialog.frame;
  // Top centre on the view; inside it horizontally when it fits.
  CGFloat x = NSMidX(host) - NSWidth(frame) / 2;
  if (NSWidth(frame) <= NSWidth(host)) {
    x = std::clamp(x, NSMinX(host), NSMaxX(host) - NSWidth(frame));
  }
  NSPoint origin = NSMakePoint(std::round(x),
                               std::round(NSMaxY(host) - NSHeight(frame)));
  bool moved = !NSEqualPoints(origin, frame.origin);
  if (moved) {
    [dialog setFrameOrigin:origin];
  }
  bool attached = dialog.parentWindow == parent;
  if (!attached) {
    if (dialog.parentWindow) {
      [dialog.parentWindow removeChildWindow:dialog];
    }
    [parent addChildWindow:dialog ordered:NSWindowAbove];
  }
  if (moved || !attached) {
    LOG(WARNING) << "ARKT: tab-modal dialog attached window "
                 << dialog.windowNumber << " parent " << parent.windowNumber
                 << " frame " << FrameString(dialog.frame) << " host view "
                 << FrameString(host);
  }
}

void ArktModalDialogHost::Detach(views::Widget* widget) {
  NSWindow* dialog = widget->GetNativeWindow().GetNativeNSWindow();
  NSWindow* parent = dialog.parentWindow;
  if (!parent) {
    return;
  }
  [parent removeChildWindow:dialog];
  LOG(WARNING) << "ARKT: tab-modal dialog detached window "
               << dialog.windowNumber << " parent " << parent.windowNumber;
}

// ArktStubLocationBar ---------------------------------------------------------

ArktStubLocationBar::ArktStubLocationBar(BrowserWindowInterface* browser)
    : LocationBar(chrome::BrowserCommandController::From(browser)),
      browser_(browser) {}

ArktStubLocationBar::~ArktStubLocationBar() = default;

void ArktStubLocationBar::FocusLocation(bool is_user_initiated,
                                        bool clear_focus_if_failed) {
  ARKT_STUB("LocationBar");
}

void ArktStubLocationBar::FocusSearch() {
  ARKT_STUB("LocationBar");
}

void ArktStubLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void ArktStubLocationBar::UpdateContentSettingsIcons() {}

void ArktStubLocationBar::SaveStateToContents(content::WebContents* contents) {}

void ArktStubLocationBar::Revert() {}

OmniboxView* ArktStubLocationBar::GetOmniboxView() {
  return nullptr;
}

OmniboxPopupView* ArktStubLocationBar::GetOmniboxPopupView() {
  return nullptr;
}

OmniboxController* ArktStubLocationBar::GetOmniboxController() {
  return nullptr;
}

bool ArktStubLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}

content::WebContents* ArktStubLocationBar::GetWebContents() {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

LocationBarModel* ArktStubLocationBar::GetLocationBarModel() {
  return nullptr;
}

std::optional<bubble_anchor_util::AnchorConfiguration>
ArktStubLocationBar::GetChipAnchor() {
  return std::nullopt;
}

ChipController* ArktStubLocationBar::GetChipController() {
  ARKT_STUB("LocationBar");
  return nullptr;
}

void ArktStubLocationBar::AnnounceAlert(const std::u16string& announcement) {}

void ArktStubLocationBar::OnChanged() {}

void ArktStubLocationBar::UpdateWithoutTabRestore() {}

ui::TrackedElement* ArktStubLocationBar::GetAnchorOrNull() {
  return nullptr;
}

BrowserWindowInterface* ArktStubLocationBar::GetBrowser() {
  return browser_;
}

Profile* ArktStubLocationBar::GetProfile() {
  return browser_->GetProfile();
}

bool ArktStubLocationBar::IsInitialized() const {
  return true;
}

bool ArktStubLocationBar::IsVisible() const {
  return false;
}

bool ArktStubLocationBar::IsDrawn() const {
  return false;
}

bool ArktStubLocationBar::IsFullscreen() const {
  return false;
}

bool ArktStubLocationBar::IsEditingOrEmpty() const {
  return false;
}

bool ArktStubLocationBar::IsMouseHovered() const {
  return false;
}

bool ArktStubLocationBar::IsFocusWithin() const {
  return false;
}

void ArktStubLocationBar::InvalidateLayout() {}

gfx::Rect ArktStubLocationBar::Bounds() const {
  return gfx::Rect();
}

gfx::Rect ArktStubLocationBar::BoundsInScreen() const {
  return gfx::Rect();
}

gfx::Size ArktStubLocationBar::MinimumSize() const {
  return gfx::Size();
}

gfx::Size ArktStubLocationBar::PreferredSize() const {
  return gfx::Size();
}

void ArktStubLocationBar::Update(content::WebContents* contents) {}

void ArktStubLocationBar::ResetTabState(content::WebContents* contents) {}

bool ArktStubLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* ArktStubLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

// ArktFindBar -----------------------------------------------------------------

ArktFindBar::ArktFindBar() = default;

ArktFindBar::~ArktFindBar() = default;

FindBarController* ArktFindBar::GetFindBarController() const {
  return controller_;
}

void ArktFindBar::SetFindBarController(FindBarController* controller) {
  controller_ = controller;
}

void ArktFindBar::Show(bool animate, bool focus) {
  ARKT_STUB("FindBar");
  visible_ = true;
}

void ArktFindBar::Hide(bool animate) {
  visible_ = false;
}

void ArktFindBar::SetFocusAndSelection() {}

void ArktFindBar::ClearResults(
    const find_in_page::FindNotificationDetails& results) {}

void ArktFindBar::StopAnimation() {}

void ArktFindBar::MoveWindowIfNecessary() {}

void ArktFindBar::SetFindTextAndSelectedRange(
    const std::u16string& find_text,
    const gfx::Range& selected_range) {
  find_text_ = find_text;
}

std::u16string_view ArktFindBar::GetFindText() const {
  return find_text_;
}

gfx::Range ArktFindBar::GetSelectedRange() const {
  return gfx::Range();
}

void ArktFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& find_text) {}

void ArktFindBar::AudibleAlert() {}

bool ArktFindBar::IsFindBarVisible() const {
  return visible_;
}

void ArktFindBar::RestoreSavedFocus() {}

bool ArktFindBar::HasGlobalFindPasteboard() const {
  return false;
}

void ArktFindBar::UpdateFindBarForChangedWebContents() {}

bool ArktFindBar::CanPopulateFromSelectedText() {
  return false;
}

const FindBarTesting* ArktFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool ArktFindBar::HasFocus() const {
  return false;
}

void ArktFindBar::CloseOverlappingBubbles() {}

views::Widget* ArktFindBar::GetHostWidget() {
  return nullptr;
}

// ArktSidePanelUI -------------------------------------------------------------

ArktSidePanelUI::ArktSidePanelUI(BrowserWindowInterface* browser)
    : scoped_user_data_(browser->GetUnownedUserDataHost(), *this) {}

ArktSidePanelUI::~ArktSidePanelUI() = default;

void ArktSidePanelUI::Show(SidePanelEntryId entry_id,
                           std::optional<SidePanelOpenTrigger> open_trigger,
                           bool suppress_animations) {
  ARKT_STUB("SidePanelUI");
}

void ArktSidePanelUI::Show(SidePanelEntryKey entry_key,
                           std::optional<SidePanelOpenTrigger> open_trigger,
                           bool suppress_animations) {
  ARKT_STUB("SidePanelUI");
}

void ArktSidePanelUI::ShowFrom(
    SidePanelEntryKey entry_key,
    gfx::Rect starting_bounds_in_browser_coordinates) {
  ARKT_STUB("SidePanelUI");
}

void ArktSidePanelUI::Close(SidePanelEntryHideReason hide_reason,
                            bool suppress_animations) {}

void ArktSidePanelUI::Toggle(SidePanelEntryKey key,
                             SidePanelOpenTrigger open_trigger) {
  ARKT_STUB("SidePanelUI");
}

std::optional<SidePanelEntryId> ArktSidePanelUI::GetCurrentEntryId() const {
  return std::nullopt;
}

int ArktSidePanelUI::GetCurrentEntryDefaultContentWidth() const {
  return 0;
}

bool ArktSidePanelUI::IsSidePanelShowing() const {
  return false;
}

bool ArktSidePanelUI::IsSidePanelEntryShowing(
    const SidePanelEntryKey& entry_key) const {
  return false;
}

bool ArktSidePanelUI::IsSidePanelEntryShowing(
    const SidePanelEntryKey& entry_key,
    bool for_tab) const {
  return false;
}

base::CallbackListSubscription ArktSidePanelUI::RegisterSidePanelShown(
    ShownCallback callback) {
  return shown_callbacks_.Add(std::move(callback));
}

void ArktSidePanelUI::OnActiveTabChanged(content::WebContents* old_contents,
                                         content::WebContents* new_contents,
                                         bool tab_removed_for_deletion) {}

content::WebContents* ArktSidePanelUI::GetWebContentsForTest(
    SidePanelEntryId id) {
  return nullptr;
}

void ArktSidePanelUI::DisableAnimationsForTesting() {}

void ArktSidePanelUI::SetNoDelaysForTesting(bool no_delays_for_testing) {}

}  // namespace arkt
