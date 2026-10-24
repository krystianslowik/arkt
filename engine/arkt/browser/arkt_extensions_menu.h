#ifndef ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_
#define ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/themes/theme_service_observer.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/common/extension_id.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/native_theme/native_theme.h"
#include "ui/native_theme/native_theme_observer.h"

@class ArktExtensionsMenuTarget;
@class NSMenu;
@class NSView;
class BrowserWindowInterface;
class ExtensionActionViewModel;
class ThemeService;

namespace content {
class WebContents;
}

namespace arkt {

// The sidebar Extensions menu of one Arkt window: one item per toolbar action
// of the window's profile, in ToolbarActionsModel order. Choosing an item runs
// the action through ExtensionActionViewModel, which opens the popup (through
// the Arkt delegate's TriggerPopup) or dispatches the click event.
class ArktExtensionsMenu : public ToolbarActionsModel::Observer,
                           public ThemeServiceObserver,
                           public ui::NativeThemeObserver {
 public:
  // `tab` is the WebContents Arkt shows; actions run against it. A null `tab`
  // means the browser's active tab (native window). `anchor` is
  // the sidebar Extensions button; popups and the menu attach to it.
  ArktExtensionsMenu(BrowserWindowInterface* browser,
                     content::WebContents* tab,
                     NSView* anchor);
  ArktExtensionsMenu(const ArktExtensionsMenu&) = delete;
  ArktExtensionsMenu& operator=(const ArktExtensionsMenu&) = delete;
  ~ArktExtensionsMenu() override;

  // With `dump`, logs the menu items on every model change and closes a shown
  // menu after 3 s (--arkt-extensions-menu-dump).
  void SetDump(bool dump);

  // Runs `extension_id`'s action as a toolbar click as soon as the model lists
  // it (--arkt-extensions-demo=<id>).
  void RunActionWhenAvailable(const extensions::ExtensionId& extension_id);

  // Shows the menu at the anchor. Returns after the menu has closed.
  void Show();

  // One toolbar action as plain values, for the engine facade (week-3 plan,
  // Decision 10): the shell draws the list, the popup stays engine-drawn.
  struct ActionInfo {
    ActionInfo();
    ActionInfo(const ActionInfo&);
    ~ActionInfo();
    extensions::ExtensionId id;
    std::u16string name;
    // The 16 pt icon for the active tab; may be null. Cached per action and
    // tab until the action or its icon changes, so the same image (same
    // backing) comes back from repeated calls.
    gfx::ImageSkia icon;
    bool enabled = false;
  };
  // Every action of the model, in model order.
  std::vector<ActionInfo> GetActions() const;
  // Popups (and the menu) attach to `anchor` from now on.
  void SetAnchor(NSView* anchor);
  // Runs `extension_id`'s action as a toolbar click. False when there is no
  // such action.
  bool RunAction(const extensions::ExtensionId& extension_id);
  // Called after every action list or action change (added, removed,
  // updated, model initialized, an action icon loaded).
  void SetOnChanged(base::RepeatingClosure on_changed);

  // Whether the menu is open (between Show's start and its return).
  bool IsShowing() const;
  // Cancels an open menu; Show then returns.
  void CloseIfOpen();
  // An action asked to close the menu (ExtensionActionViewModel's
  // CloseMenuTask). As Chrome's toolbar action views, this goes through the
  // window's ExtensionsContainer when this menu is that container's menu.
  void CloseForAction();

  // The view model of `extension_id`'s action, or nullptr.
  ExtensionActionViewModel* GetViewModel(
      const extensions::ExtensionId& extension_id) const;
  bool HasAnyActions() const;
  // Closes the popup of any of this menu's actions.
  void HideActivePopup();

  content::WebContents* active_web_contents() const;
  NSView* anchor() const;
  base::WeakPtr<ArktExtensionsMenu> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 private:
  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override {}
  void OnToolbarActionsModelShutdown() override;

  // ThemeServiceObserver, ui::NativeThemeObserver: icons are rasterized with
  // the tab's color provider, so a theme or color-scheme change drops them.
  void OnThemeChanged() override;
  void OnNativeThemeUpdated(ui::NativeTheme* observed_theme) override;
  void OnColorsChanged();

  // Creates and drops view models so they match the model's action list.
  void SyncViewModels();
  void LogActions() const;
  NSMenu* BuildMenu();
  void DumpMenu();
  void MaybeRunPendingAction();
  void NotifyChanged();
  // The rasterized icon of `id` for `web_contents`, from the cache when it
  // is still valid.
  gfx::ImageSkia CachedIcon(const extensions::ExtensionId& id,
                            ExtensionActionViewModel* view_model,
                            content::WebContents* web_contents) const;
  void OnActionIconUpdated(const extensions::ExtensionId& id);
  void ExecuteAction(const extensions::ExtensionId& extension_id,
                     ToolbarActionViewModel::InvocationSource source);
  void Shutdown();

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<ToolbarActionsModel> model_ = nullptr;
  base::WeakPtr<content::WebContents> tab_;
  NSView* __weak anchor_;
  ArktExtensionsMenuTarget* __strong target_;
  // The menu while Show tracks it.
  NSMenu* __strong shown_menu_;
  std::map<extensions::ExtensionId, std::unique_ptr<ExtensionActionViewModel>>
      view_models_;
  // One per view model: its icon finished loading (ExtensionActionIconFactory).
  std::map<extensions::ExtensionId, base::CallbackListSubscription>
      icon_subscriptions_;
  // Rasterized icons by action, for the tab they were made for (#258).
  struct IconCacheEntry {
    IconCacheEntry();
    IconCacheEntry(const IconCacheEntry&);
    ~IconCacheEntry();
    base::WeakPtr<content::WebContents> web_contents;
    gfx::ImageSkia icon;
  };
  mutable std::map<extensions::ExtensionId, IconCacheEntry> icon_cache_;
  bool dump_ = false;
  std::vector<std::string> last_dump_;
  extensions::ExtensionId pending_action_id_;
  base::RepeatingClosure on_changed_;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      observation_{this};
  base::ScopedObservation<ThemeService, ThemeServiceObserver>
      theme_observation_{this};
  base::ScopedObservation<ui::NativeTheme, ui::NativeThemeObserver>
      native_theme_observation_{this};
  base::CallbackListSubscription browser_did_close_;
  base::WeakPtrFactory<ArktExtensionsMenu> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_
