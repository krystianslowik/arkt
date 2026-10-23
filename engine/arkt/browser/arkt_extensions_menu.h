#ifndef ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_
#define ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/common/extension_id.h"

@class ArktExtensionsMenuTarget;
@class NSMenu;
@class NSView;
class BrowserWindowInterface;
class ExtensionActionViewModel;

namespace content {
class WebContents;
}

namespace arkt {

// The sidebar Extensions menu of one Arkt window: one item per toolbar action
// of the window's profile, in ToolbarActionsModel order. Choosing an item runs
// the action through ExtensionActionViewModel, which opens the popup (through
// the Arkt delegate's TriggerPopup) or dispatches the click event.
class ArktExtensionsMenu : public ToolbarActionsModel::Observer {
 public:
  // `tab` is the WebContents Arkt shows; actions run against it. `anchor` is
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

  content::WebContents* active_web_contents() const;
  NSView* anchor() const;

 private:
  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override {}
  void OnToolbarActionsModelShutdown() override;

  // Creates and drops view models so they match the model's action list.
  void SyncViewModels();
  void LogActions() const;
  NSMenu* BuildMenu();
  void DumpMenu();
  void MaybeRunPendingAction();
  void ExecuteAction(const extensions::ExtensionId& extension_id,
                     ToolbarActionViewModel::InvocationSource source);
  void Shutdown();

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<ToolbarActionsModel> model_ = nullptr;
  base::WeakPtr<content::WebContents> tab_;
  NSView* __weak anchor_;
  ArktExtensionsMenuTarget* __strong target_;
  std::map<extensions::ExtensionId, std::unique_ptr<ExtensionActionViewModel>>
      view_models_;
  bool dump_ = false;
  std::vector<std::string> last_dump_;
  extensions::ExtensionId pending_action_id_;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      observation_{this};
  base::CallbackListSubscription browser_did_close_;
  base::WeakPtrFactory<ArktExtensionsMenu> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSIONS_MENU_H_
