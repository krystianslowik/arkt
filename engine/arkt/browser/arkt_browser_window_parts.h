#ifndef ARKT_BROWSER_ARKT_BROWSER_WINDOW_PARTS_H_
#define ARKT_BROWSER_ARKT_BROWSER_WINDOW_PARTS_H_

#import <AppKit/AppKit.h>

#include <optional>
#include <string>

#include "base/callback_list.h"
#include "base/memory/raw_ptr.h"
#include "base/observer_list.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class BrowserWindowInterface;

// The window-side objects ArktBrowserWindow hands to Chromium: things a
// BrowserView or Webium window would provide and callers expect to be there.

namespace arkt {

class ArktBrowserWindow;

// Logs `ARKT: stub <scope>::<method>` the first time a stubbed method runs.
void LogStubOnce(const char* scope, const char* method);

#define ARKT_STUB(scope) ::arkt::LogStubOnce(scope, __func__)

// Fullscreen through the host window's native fullscreen. There is no
// exclusive access bubble this week.
class ArktExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit ArktExclusiveAccessContext(ArktBrowserWindow* window);
  ArktExclusiveAccessContext(const ArktExclusiveAccessContext&) = delete;
  ArktExclusiveAccessContext& operator=(const ArktExclusiveAccessContext&) =
      delete;
  ~ArktExclusiveAccessContext() override;

  // ExclusiveAccessContext:
  Profile* GetProfile() override;
  bool IsFullscreen() const override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;

 private:
  const raw_ptr<ArktBrowserWindow> window_;
};

// Tab-modal dialogs are positioned against the card: top centre, at most the
// card's size.
class ArktModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  // `view` is asked for the host view on every call: the tab's view, or the
  // host's card as fallback, can change while a dialog is up (week-3 plan,
  // Decision 6).
  explicit ArktModalDialogHost(NSView* (^view)(void));
  ArktModalDialogHost(const ArktModalDialogHost&) = delete;
  ArktModalDialogHost& operator=(const ArktModalDialogHost&) = delete;
  ~ArktModalDialogHost() override;

  // web_modal::WebContentsModalDialogHost:
  gfx::NativeView GetHostView() const override;
  gfx::Point GetDialogPosition(const gfx::Size& size) override;
  gfx::Size GetMaximumDialogSize() override;
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override;
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override;
  void NotifyPositionRequiresUpdate() override;

 private:
  NSView* (^view_)(void);
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

// Arkt has no omnibox. Non-null so the callers that dereference
// GetLocationBar() without a check stay safe; IsDrawn() is false, so anchored
// UI (permission chips, page action bubbles) takes its no-location-bar path.
class ArktStubLocationBar : public LocationBar {
 public:
  explicit ArktStubLocationBar(BrowserWindowInterface* browser);
  ArktStubLocationBar(const ArktStubLocationBar&) = delete;
  ArktStubLocationBar& operator=(const ArktStubLocationBar&) = delete;
  ~ArktStubLocationBar() override;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override;
  ChipController* GetChipController() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  BrowserWindowInterface* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
};

// Find in page without UI this week: the controller always gets a bar, so
// FindBarController never dereferences nullptr (find_bar_controller.cc).
class ArktFindBar : public FindBar {
 public:
  ArktFindBar();
  ArktFindBar(const ArktFindBar&) = delete;
  ArktFindBar& operator=(const ArktFindBar&) = delete;
  ~ArktFindBar() override;

  // FindBar:
  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController* controller) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults(
      const find_in_page::FindNotificationDetails& results) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange(const std::u16string& find_text,
                                   const gfx::Range& selected_range) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult(
      const find_in_page::FindNotificationDetails& result,
      const std::u16string& find_text) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;

 private:
  raw_ptr<FindBarController> controller_ = nullptr;
  std::u16string find_text_;
  bool visible_ = false;
};

// Arkt has no Views side panel. SidePanelUI::From() must still be non-null:
// tab features such as ReadAnythingSidePanelController treat a missing
// SidePanelUI outside tests as a bug (CHECK_IS_TEST) when the active tab
// detaches, which every tab, window and app close does. Nothing is ever
// shown, so every query answers "closed".
class ArktSidePanelUI : public SidePanelUI {
 public:
  explicit ArktSidePanelUI(BrowserWindowInterface* browser);
  ArktSidePanelUI(const ArktSidePanelUI&) = delete;
  ArktSidePanelUI& operator=(const ArktSidePanelUI&) = delete;
  ~ArktSidePanelUI() override;

  // SidePanelUI:
  void Show(SidePanelEntryId entry_id,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void Show(SidePanelEntryKey entry_key,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void ShowFrom(SidePanelEntryKey entry_key,
                gfx::Rect starting_bounds_in_browser_coordinates) override;
  void Close(SidePanelEntryHideReason hide_reason,
             bool suppress_animations) override;
  void Toggle(SidePanelEntryKey key,
              SidePanelOpenTrigger open_trigger) override;
  std::optional<SidePanelEntryId> GetCurrentEntryId() const override;
  int GetCurrentEntryDefaultContentWidth() const override;
  bool IsSidePanelShowing() const override;
  bool IsSidePanelEntryShowing(
      const SidePanelEntryKey& entry_key) const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey& entry_key,
                               bool for_tab) const override;
  base::CallbackListSubscription RegisterSidePanelShown(
      ShownCallback callback) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          bool tab_removed_for_deletion) override;
  content::WebContents* GetWebContentsForTest(SidePanelEntryId id) override;
  void DisableAnimationsForTesting() override;
  void SetNoDelaysForTesting(bool no_delays_for_testing) override;

 private:
  base::RepeatingCallbackList<void()> shown_callbacks_;
  ui::ScopedUnownedUserData<SidePanelUI> scoped_user_data_;
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_WINDOW_PARTS_H_
