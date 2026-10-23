#include "arkt/browser/arkt_browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <string>
#include <utility>

#import "arkt/browser/arkt_window_controller.h"
#include "base/check.h"
#include "base/containers/flat_set.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/observer_list.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/custom_theme_supplier.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/fullscreen/browser_window_fullscreen_controller.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "chrome/browser/ui/views/new_tab_footer/footer_controller.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/search/ntp_features.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/color/color_provider_utils.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/gfx/range/range.h"
#include "ui/native_theme/native_theme.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace {

constexpr CGFloat kSidebarWidth = 190;
constexpr CGFloat kCardInset = 10;
constexpr CGFloat kCardRadius = 10;

// Logs `ARKT: stub <scope>::<method>` the first time a stubbed method runs.
void LogStubOnce(const char* scope, const char* method) {
  static base::NoDestructor<base::flat_set<std::string>> logged;
  std::string name = std::string(scope) + "::" + method;
  if (logged->insert(name).second) {
    LOG(WARNING) << "ARKT: stub " << name;
  }
}

#define ARKT_STUB(scope) LogStubOnce(scope, __func__)

// The windows constructed and not yet destroyed. Chromium has no RTTI, so this
// set is how a BrowserWindow is recognised as ours.
base::flat_set<arkt::ArktBrowserWindow*>& LiveWindows() {
  static base::NoDestructor<base::flat_set<arkt::ArktBrowserWindow*>> windows;
  return *windows;
}

int TabId(content::WebContents* contents) {
  return contents ? sessions::SessionTabHelper::IdForTab(contents).id() : -1;
}

NSDictionary<NSString*, id>* TabEvent(NSString* kind,
                                      content::WebContents* contents,
                                      int index) {
  return @{@"kind" : kind, @"tabId" : @(TabId(contents)), @"index" : @(index)};
}

}  // namespace

// -----------------------------------------------------------------------------
// ArktPlaceholderWindowHost

@interface ArktPlaceholderWindowHost () <NSWindowDelegate>
@end

@implementation ArktPlaceholderWindowHost {
  ArktWindow* __strong _window;
  NSView* __strong _card;
  NSButton* __strong _extensionsButton;
}

@synthesize closeRequested = _closeRequested;

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

    _extensionsButton = [NSButton buttonWithTitle:@"Extensions"
                                           target:nil
                                           action:nil];
    [_extensionsButton sizeToFit];
    _extensionsButton.frameOrigin = NSMakePoint(
        16, NSHeight(bounds) - 44 - NSHeight(_extensionsButton.frame));
    _extensionsButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [root addSubview:_extensionsButton];
  }
  return self;
}

- (void)dealloc {
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

- (void)tabListChanged:(NSArray<NSDictionary<NSString*, id>*>*)events {
  for (NSDictionary<NSString*, id>* event in events) {
    LOG(WARNING) << "ARKT: tab event "
                 << base::SysNSStringToUTF8(event[@"kind"]) << " tab "
                 << [event[@"tabId"] intValue] << " index "
                 << [event[@"index"] intValue];
  }
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

namespace arkt {

// -----------------------------------------------------------------------------
// Window-side objects

// Fullscreen through the host window's native fullscreen. There is no
// exclusive access bubble this week.
class ArktExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit ArktExclusiveAccessContext(ArktBrowserWindow* window)
      : window_(window) {}
  ArktExclusiveAccessContext(const ArktExclusiveAccessContext&) = delete;
  ArktExclusiveAccessContext& operator=(const ArktExclusiveAccessContext&) =
      delete;
  ~ArktExclusiveAccessContext() override = default;

  // ExclusiveAccessContext:
  Profile* GetProfile() override { return window_->browser()->GetProfile(); }
  bool IsFullscreen() const override { return window_->IsFullscreen(); }
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override {
    if (IsFullscreen()) {
      return;
    }
    LOG(WARNING) << "ARKT: enter fullscreen";
    [window_->host().window toggleFullScreen:nil];
  }
  void ExitFullscreen() override {
    if (BrowserWindowFullscreenController::From(window_->browser())
            ->IsForceFullscreen() ||
        !IsFullscreen()) {
      return;
    }
    LOG(WARNING) << "ARKT: exit fullscreen";
    [window_->host().window toggleFullScreen:nil];
  }
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override {
    ARKT_STUB("ExclusiveAccessContext");
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
  }
  bool IsExclusiveAccessBubbleDisplayed() const override { return false; }
  void OnExclusiveAccessUserInput() override {}
  content::WebContents* GetWebContentsForExclusiveAccess() override {
    return window_->browser()->GetTabStripModel()->GetActiveWebContents();
  }
  bool CanUserEnterFullscreen() const override { return true; }
  bool CanUserExitFullscreen() const override { return true; }

 private:
  const raw_ptr<ArktBrowserWindow> window_;
};

// Tab-modal dialogs are positioned against the card: top centre, at most the
// card's size.
class ArktModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  explicit ArktModalDialogHost(NSView* card) : card_(card) {}
  ArktModalDialogHost(const ArktModalDialogHost&) = delete;
  ArktModalDialogHost& operator=(const ArktModalDialogHost&) = delete;
  ~ArktModalDialogHost() override {
    for (auto& observer : observers_) {
      observer.OnHostDestroying();
    }
  }

  // web_modal::WebContentsModalDialogHost:
  gfx::NativeView GetHostView() const override {
    return gfx::NativeView(card_);
  }
  gfx::Point GetDialogPosition(const gfx::Size& size) override {
    return gfx::Point(
        std::max(0, (static_cast<int>(NSWidth(card_.bounds)) - size.width()) /
                        2),
        0);
  }
  gfx::Size GetMaximumDialogSize() override {
    return gfx::Size(static_cast<int>(NSWidth(card_.bounds)),
                     static_cast<int>(NSHeight(card_.bounds)));
  }
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.AddObserver(observer);
  }
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.RemoveObserver(observer);
  }
  void NotifyPositionRequiresUpdate() override {
    for (auto& observer : observers_) {
      observer.OnPositionRequiresUpdate();
    }
  }

 private:
  NSView* __weak card_;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

// Arkt has no omnibox. Non-null so the callers that dereference
// GetLocationBar() without a check stay safe; IsDrawn() is false, so anchored
// UI (permission chips, page action bubbles) takes its no-location-bar path.
class ArktStubLocationBar : public LocationBar {
 public:
  explicit ArktStubLocationBar(BrowserWindowInterface* browser)
      : LocationBar(chrome::BrowserCommandController::From(browser)),
        browser_(browser) {}
  ArktStubLocationBar(const ArktStubLocationBar&) = delete;
  ArktStubLocationBar& operator=(const ArktStubLocationBar&) = delete;
  ~ArktStubLocationBar() override = default;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override {
    ARKT_STUB("LocationBar");
  }
  void FocusSearch() override { ARKT_STUB("LocationBar"); }
  void UpdateFocusBehavior(bool toolbar_visible) override {}
  void UpdateContentSettingsIcons() override {}
  void SaveStateToContents(content::WebContents* contents) override {}
  void Revert() override {}
  OmniboxView* GetOmniboxView() override { return nullptr; }
  OmniboxPopupView* GetOmniboxPopupView() override { return nullptr; }
  OmniboxController* GetOmniboxController() override { return nullptr; }
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override {
    return false;
  }
  content::WebContents* GetWebContents() override {
    return browser_->GetTabStripModel()->GetActiveWebContents();
  }
  LocationBarModel* GetLocationBarModel() override { return nullptr; }
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override {
    return std::nullopt;
  }
  ChipController* GetChipController() override {
    ARKT_STUB("LocationBar");
    return nullptr;
  }
  void AnnounceAlert(const std::u16string& announcement) override {}
  void OnChanged() override {}
  void UpdateWithoutTabRestore() override {}
  ui::TrackedElement* GetAnchorOrNull() override { return nullptr; }
  BrowserWindowInterface* GetBrowser() override { return browser_; }
  Profile* GetProfile() override { return browser_->GetProfile(); }
  bool IsInitialized() const override { return true; }
  bool IsVisible() const override { return false; }
  bool IsDrawn() const override { return false; }
  bool IsFullscreen() const override { return false; }
  bool IsEditingOrEmpty() const override { return false; }
  bool IsMouseHovered() const override { return false; }
  bool IsFocusWithin() const override { return false; }
  void InvalidateLayout() override {}
  gfx::Rect Bounds() const override { return gfx::Rect(); }
  gfx::Rect BoundsInScreen() const override { return gfx::Rect(); }
  gfx::Size MinimumSize() const override { return gfx::Size(); }
  gfx::Size PreferredSize() const override { return gfx::Size(); }
  void Update(content::WebContents* contents) override {}
  void ResetTabState(content::WebContents* contents) override {}
  bool HasSecurityStateChanged() override { return false; }
  LocationBarTesting* GetLocationBarForTesting() override { return nullptr; }

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
};

// Find in page without UI this week: the controller always gets a bar, so
// FindBarController never dereferences nullptr (find_bar_controller.cc).
class ArktFindBar : public FindBar {
 public:
  ArktFindBar() = default;
  ArktFindBar(const ArktFindBar&) = delete;
  ArktFindBar& operator=(const ArktFindBar&) = delete;
  ~ArktFindBar() override = default;

  // FindBar:
  FindBarController* GetFindBarController() const override {
    return controller_;
  }
  void SetFindBarController(FindBarController* controller) override {
    controller_ = controller;
  }
  void Show(bool animate, bool focus) override {
    ARKT_STUB("FindBar");
    visible_ = true;
  }
  void Hide(bool animate) override { visible_ = false; }
  void SetFocusAndSelection() override {}
  void ClearResults(
      const find_in_page::FindNotificationDetails& results) override {}
  void StopAnimation() override {}
  void MoveWindowIfNecessary() override {}
  void SetFindTextAndSelectedRange(const std::u16string& find_text,
                                   const gfx::Range& selected_range) override {
    find_text_ = find_text;
  }
  std::u16string_view GetFindText() const override { return find_text_; }
  gfx::Range GetSelectedRange() const override { return gfx::Range(); }
  void UpdateUIForFindResult(
      const find_in_page::FindNotificationDetails& result,
      const std::u16string& find_text) override {}
  void AudibleAlert() override {}
  bool IsFindBarVisible() const override { return visible_; }
  void RestoreSavedFocus() override {}
  bool HasGlobalFindPasteboard() const override { return false; }
  void UpdateFindBarForChangedWebContents() override {}
  bool CanPopulateFromSelectedText() override { return false; }
  const FindBarTesting* GetFindBarTesting() const override { return nullptr; }
  bool HasFocus() const override { return false; }
  void CloseOverlappingBubbles() override {}
  views::Widget* GetHostWidget() override { return nullptr; }

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
  explicit ArktSidePanelUI(BrowserWindowInterface* browser)
      : scoped_user_data_(browser->GetUnownedUserDataHost(), *this) {}
  ArktSidePanelUI(const ArktSidePanelUI&) = delete;
  ArktSidePanelUI& operator=(const ArktSidePanelUI&) = delete;
  ~ArktSidePanelUI() override = default;

  // SidePanelUI:
  void Show(SidePanelEntryId entry_id,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override {
    ARKT_STUB("SidePanelUI");
  }
  void Show(SidePanelEntryKey entry_key,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override {
    ARKT_STUB("SidePanelUI");
  }
  void ShowFrom(SidePanelEntryKey entry_key,
                gfx::Rect starting_bounds_in_browser_coordinates) override {
    ARKT_STUB("SidePanelUI");
  }
  void Close(SidePanelEntryHideReason hide_reason,
             bool suppress_animations) override {}
  void Toggle(SidePanelEntryKey key,
              SidePanelOpenTrigger open_trigger) override {
    ARKT_STUB("SidePanelUI");
  }
  std::optional<SidePanelEntryId> GetCurrentEntryId() const override {
    return std::nullopt;
  }
  int GetCurrentEntryDefaultContentWidth() const override { return 0; }
  bool IsSidePanelShowing() const override { return false; }
  bool IsSidePanelEntryShowing(
      const SidePanelEntryKey& entry_key) const override {
    return false;
  }
  bool IsSidePanelEntryShowing(const SidePanelEntryKey& entry_key,
                               bool for_tab) const override {
    return false;
  }
  base::CallbackListSubscription RegisterSidePanelShown(
      ShownCallback callback) override {
    return shown_callbacks_.Add(std::move(callback));
  }
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          bool tab_removed_for_deletion) override {}
  content::WebContents* GetWebContentsForTest(SidePanelEntryId id) override {
    return nullptr;
  }
  void DisableAnimationsForTesting() override {}
  void SetNoDelaysForTesting(bool no_delays_for_testing) override {}

 private:
  base::RepeatingCallbackList<void()> shown_callbacks_;
  ui::ScopedUnownedUserData<SidePanelUI> scoped_user_data_;
};

// -----------------------------------------------------------------------------
// ArktBrowserWindow

ArktBrowserWindow::ArktBrowserWindow(BrowserWindowInterface* browser,
                                     id<ArktWindowHost> host)
    : browser_(browser),
      host_(host),
      notification_tokens_([[NSMutableArray alloc] init]) {
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
  LOG(WARNING) << "ARKT: native window created";
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
  [host_.window orderOut:nil];

  if (new_tab_footer_controller_) {
    new_tab_footer_controller_->TearDown();
    new_tab_footer_controller_.reset();
  }
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

// ui::BaseWindow ---------------------------------------------------------------

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

// BrowserWindow: window state ---------------------------------------------------

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

// BrowserWindow: tabs ----------------------------------------------------------

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

void ArktBrowserWindow::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  NSMutableArray<NSDictionary<NSString*, id>*>* events =
      [[NSMutableArray alloc] init];
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      for (const auto& inserted : change.GetInsert()->contents) {
        [events addObject:TabEvent(@"inserted", inserted.contents,
                                   inserted.index)];
      }
      break;
    case TabStripModelChange::kRemoved:
      for (const auto& removed : change.GetRemove()->contents) {
        [events
            addObject:TabEvent(@"removed", removed.contents, removed.index)];
      }
      break;
    case TabStripModelChange::kMoved: {
      const TabStripModelChange::Move* move = change.GetMove();
      NSMutableDictionary<NSString*, id>* event =
          [TabEvent(@"moved", move->contents, move->to_index) mutableCopy];
      event[@"fromIndex"] = @(move->from_index);
      [events addObject:event];
      break;
    }
    case TabStripModelChange::kReplaced:
    case TabStripModelChange::kSelectionOnly:
      break;
  }
  if (selection.active_tab_changed() && selection.new_contents) {
    [events addObject:TabEvent(@"activated", selection.new_contents,
                               tab_strip_model->active_index())];
  }
  if (events.count) {
    [host_ tabListChanged:events];
  }
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

// BrowserWindow: theme and colours ---------------------------------------------

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

// BrowserWindow: window-side objects -------------------------------------------

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

// BrowserWindow: keyboard ------------------------------------------------------

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

// BrowserWindow: toolbar and location bar (Arkt has neither) --------------------

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

// BrowserWindow: bubbles and dialogs Arkt does not show this week ---------------

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
