#ifndef ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_
#define ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_

#import <AppKit/AppKit.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

#import "arkt/browser/arkt_window_host.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/sessions/core/session_id.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
#include "ui/color/color_provider_source.h"
#include "ui/gfx/geometry/rect.h"
#include "url/gurl.h"

class ExtensionsContainer;

namespace new_tab_footer {
class NewTabFooterController;
}  // namespace new_tab_footer

namespace arkt {

class ArktExclusiveAccessContext;
class ArktExtensionsContainer;
class ArktModalDialogHost;
class ArktSidePanelUI;
class ArktStubLocationBar;

// Chromium's BrowserWindow for a TYPE_NORMAL Browser, implemented on a plain
// NSWindow owned by an ArktWindowHost (variant P, week-2 plan Decision 1).
// There is no views::Widget and no BrowserView: lookups that expect one return
// nullptr, and BrowserWindow::FromBrowser falls back to Browser::GetWindow().
class ArktBrowserWindow : public BrowserWindow,
                          public ui::ColorProviderSource,
                          public TabStripModelObserver {
 public:
  ArktBrowserWindow(BrowserWindowInterface* browser, id<ArktWindowHost> host);
  ArktBrowserWindow(const ArktBrowserWindow&) = delete;
  ArktBrowserWindow& operator=(const ArktBrowserWindow&) = delete;
  ~ArktBrowserWindow() override;

  // The ArktBrowserWindow of `browser`, or nullptr if its window is not one.
  // Chromium is built without RTTI, so this looks the browser up in the set of
  // live ArktBrowserWindows instead of casting.
  static ArktBrowserWindow* FromBrowser(const BrowserWindowInterface* browser);

  BrowserWindowInterface* browser() const { return browser_; }
  base::WeakPtr<ArktBrowserWindow> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }
  id<ArktWindowHost> host() const { return host_; }
  // True when the host is an embedder's (ShellUI, the self-test embedder),
  // false for the placeholder host. Embedder hosts mount tab views
  // themselves (week-3 plan, Decision 6); the placeholder host gets the
  // active tab mounted in its card and the tab list events.
  bool host_mode() const { return host_mode_; }
  // Moves the window to `host` (a window held before the embedder was ready,
  // whose host is asked for at replay). The old host's window is ordered out
  // and released.
  void ReplaceHost(id<ArktWindowHost> host);
  // Registered as the browser's ExtensionsContainer for the window's life.
  ArktExtensionsContainer* extensions_container() const {
    return extensions_container_.get();
  }

  // ui::BaseWindow:
  bool IsActive() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  void Show() override;
  void Hide() override;
  bool IsVisible() const override;
  void ShowInactive() override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  void SetBounds(const gfx::Rect& bounds) override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;

  // BrowserWindow:
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents,
                                float ratio) override;
  bool DoBrowserControlsShrinkRendererSize(
      const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  PinnedToolbarActions* GetPinnedToolbarActions() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsLocationBarVisible() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble(
      std::vector<apps::IntentPickerAppInfo> app_info,
      bool show_stay_in_chrome,
      bool show_remember_selection,
      apps::IntentPickerBubbleType bubble_type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data,
                           const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost()
      override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void MaybeShowProfileSwitchIPH() override;
  void MaybeShowSupervisedUserProfileSignInIPH() override;
  void ShowHatsDialog(
      const std::string& site_id,
      const std::optional<std::string>& hats_histogram_name,
      const std::optional<uint64_t> hats_survey_ukm_id,
      base::OnceClosure success_callback,
      base::OnceClosure failure_callback,
      const SurveyBitsData& product_specific_bits_data,
      const SurveyStringData& product_specific_string_data) override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;

  // ui::ColorProviderSource (BrowserWindow declares GetColorProvider too):
  const ui::ColorProvider* GetColorProvider() const override;
  ui::ColorProviderKey GetColorProviderKey() const override;
  ui::RendererColorMap GetRendererColorMap(
      ui::ColorProviderKey::ColorMode color_mode,
      ui::ColorProviderKey::ForcedColors forced_colors) const override;

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;
  void OnTabChangedAt(tabs::TabInterface* tab,
                      TabChangeType change_type) override;

  // Makes the tab with session id `tab_id` the active tab of the model (a tab
  // picked in the host's tab list). Returns false if the window has no such
  // tab.
  bool ActivateTab(int32_t tab_id);

  // Called by the exclusive access context when the host window entered or
  // left native fullscreen.
  void OnFullscreenChanged();

  // While held, Show(), ShowInactive() and Activate() only record that the
  // window should be shown; ReleaseHeldShow() shows it then. Used for a window
  // Chromium creates before the embedder is ready (week-3 plan, Decision 2).
  // Minimize, Maximize, Restore and entering fullscreen are recorded while
  // held (the last one wins) and applied after the show, so the window cannot
  // become visible through them before; bounds set while held are applied to
  // the window again at release, after a host replacement (#255 review).
  void HoldShow();
  void ReleaseHeldShow();
  bool IsShowHeld() const { return show_held_; }
  // Entering fullscreen while the show is held (ArktExclusiveAccessContext).
  void DeferFullscreenWhileHeld();

  // True while the Browser is trying to close (unload processing of its tabs
  // runs or ran), until it closes or the close is cancelled.
  bool IsAttemptingToClose() const;

  // True when the current window close was asked for by chrome.windows.remove
  // (an extension's windows.remove call was in flight when Close() started
  // it). The facade reports the window's tabs with ArktCloseReasonExtension
  // instead of ArktCloseReasonWindowClosing (week-3 plan, Decision 12).
  bool IsClosedByExtension() const { return closed_by_extension_; }

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  // One tab in model order, as last reported to the host.
  struct TabEntry {
    SessionID id = SessionID::InvalidValue();
    std::u16string title;
    GURL url;
  };

  enum class PendingShow { kNone, kShow, kShowInactive };
  // A window state asked for while the show is held.
  enum class PendingState { kNone, kMaximized, kMinimized, kRestored,
                            kFullscreen };

  // Sets the engine's blocks on `host_` and observes its window and card;
  // UnbindHost undoes both, unmounts the placeholder's tab and orders the
  // window out.
  void BindHost();
  void UnbindHost();
  void Mount(content::WebContents* contents);
  void Unmount(content::WebContents* contents);
  void OnCardResized();
  // The view a tab-modal dialog of `contents` and the contents size follow:
  // in host mode the tab's container (ArktTabContainerView) when the embedder
  // has mounted it in this window, else the host's card (Decision 6).
  // nullptr means the active tab.
  NSView* DialogHostViewFor(content::WebContents* contents) const;
  // Builds an event for the tab at `index` that carries its title and URL, and
  // stores them in `entries_[index]`.
  ArktTabEvent* EntryEvent(ArktTabEventKind kind,
                           content::WebContents* contents,
                           int index,
                           int32_t previous_tab_id);
  // --arkt-trace-visibility: logs every tab's WebContents visibility.
  void TraceVisibility();

  const raw_ptr<BrowserWindowInterface> browser_;
  id<ArktWindowHost> __strong host_;
  bool host_mode_ = false;
  // NSNotificationCenter observer tokens for the host window and card.
  NSMutableArray* __strong notification_tokens_;
  // The WebContents whose view is mounted in the card, if any.
  raw_ptr<content::WebContents> mounted_ = nullptr;
  // The tab list as the host knows it. Kept apart from any host view: the
  // host gets events, never this list.
  std::vector<TabEntry> entries_;
  const bool trace_visibility_;

  std::unique_ptr<ArktExclusiveAccessContext> exclusive_access_context_;
  // The window's dialog host (the active tab's view or the card) and, in
  // host mode, one per tab (its view, the card as fallback).
  std::unique_ptr<ArktModalDialogHost> modal_dialog_host_;
  std::map<content::WebContents*, std::unique_ptr<ArktModalDialogHost>>
      tab_modal_dialog_hosts_;
  std::unique_ptr<ArktStubLocationBar> location_bar_;
  std::unique_ptr<ArktSidePanelUI> side_panel_ui_;
  std::unique_ptr<new_tab_footer::NewTabFooterController>
      new_tab_footer_controller_;
  std::unique_ptr<ArktExtensionsContainer> extensions_container_;
  std::unique_ptr<ui::ScopedUnownedUserData<ExtensionsContainer>>
      scoped_extensions_container_;
  // The window frame when native fullscreen began (GetRestoredBounds).
  gfx::Rect bounds_before_fullscreen_;
  bool show_held_ = false;
  PendingShow show_pending_ = PendingShow::kNone;
  PendingState state_pending_ = PendingState::kNone;
  // Bounds set while the show is held, applied again at release.
  gfx::Rect bounds_pending_;
  bool closed_by_extension_ = false;

  base::WeakPtrFactory<ArktBrowserWindow> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_
