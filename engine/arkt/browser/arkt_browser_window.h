#ifndef ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_
#define ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_

#import <AppKit/AppKit.h>

#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "ui/color/color_provider_source.h"
#include "ui/gfx/geometry/rect.h"

namespace new_tab_footer {
class NewTabFooterController;
}  // namespace new_tab_footer

// The embedder seam of the engine window. ArktBrowserWindow never creates or
// lays out a window: it asks its host for the NSWindow and for the view tab
// content is mounted in, and reports tab changes back. This week's host is
// ArktPlaceholderWindowHost; in week 3 ShellUI hands over its own borderless
// window and card through the same protocol.
@protocol ArktWindowHost <NSObject>
@property(nonatomic, readonly) NSWindow* window;
// The view that holds the mounted tab content.
@property(nonatomic, readonly) NSView* cardView;
// Called by the host when the user asks to close the window (close button,
// Close Window menu item). The host must not close the window itself; the
// engine closes the Browser and then releases the host.
@property(nonatomic, copy) void (^closeRequested)(void);
// Plain tab events, one dictionary per change, in order. Keys: "kind"
// ("inserted", "removed", "moved", "activated"), "tabId", "index", and for
// "moved" also "fromIndex".
- (void)tabListChanged:(NSArray<NSDictionary<NSString*, id>*>*)events;
@end

// This week's host: an ArktWindow with the 190 pt sidebar placeholder (with
// the Extensions button) and an inset, rounded card.
@interface ArktPlaceholderWindowHost : NSObject <ArktWindowHost>
@property(nonatomic, readonly) NSButton* extensionsButton;
@end

namespace arkt {

class ArktExclusiveAccessContext;
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
  id<ArktWindowHost> host() const { return host_; }

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
  void OnTabStripModelChanged(TabStripModel* tab_strip_model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override;

  // Called by the exclusive access context when the host window entered or
  // left native fullscreen.
  void OnFullscreenChanged();

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  void Mount(content::WebContents* contents);
  void Unmount(content::WebContents* contents);
  void OnCardResized();

  const raw_ptr<BrowserWindowInterface> browser_;
  id<ArktWindowHost> __strong host_;
  // NSNotificationCenter observer tokens for the host window and card.
  NSMutableArray* __strong notification_tokens_;
  // The WebContents whose view is mounted in the card, if any.
  raw_ptr<content::WebContents> mounted_ = nullptr;

  std::unique_ptr<ArktExclusiveAccessContext> exclusive_access_context_;
  std::unique_ptr<ArktModalDialogHost> modal_dialog_host_;
  std::unique_ptr<ArktStubLocationBar> location_bar_;
  std::unique_ptr<ArktSidePanelUI> side_panel_ui_;
  std::unique_ptr<new_tab_footer::NewTabFooterController>
      new_tab_footer_controller_;
  // The window frame when native fullscreen began (GetRestoredBounds).
  gfx::Rect bounds_before_fullscreen_;

  base::WeakPtrFactory<ArktBrowserWindow> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_WINDOW_H_
