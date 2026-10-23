#ifndef ARKT_BROWSER_ARKT_EXTENSIONS_CONTAINER_H_
#define ARKT_BROWSER_ARKT_EXTENSIONS_CONTAINER_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/extensions/extensions_container.h"

class BrowserWindowInterface;

namespace arkt {

class ArktExtensionsMenu;

// The ExtensionsContainer of an Arkt window (week-2 W6): what non-UI code
// (chrome.action.openPopup, context menus, capture pickers) reaches through
// ExtensionsContainer::From(browser). It sits on the window's
// ArktExtensionsMenu, which holds the action view models and opens popups in
// the NSPopover at the sidebar Extensions button. Until the menu is attached
// the container reports no extensions.
class ArktExtensionsContainer final : public ExtensionsContainer {
 public:
  explicit ArktExtensionsContainer(BrowserWindowInterface* browser);
  ArktExtensionsContainer(const ArktExtensionsContainer&) = delete;
  ArktExtensionsContainer& operator=(const ArktExtensionsContainer&) = delete;
  ~ArktExtensionsContainer();

  // Takes the window's menu. The menu needs a fully constructed Browser, so it
  // arrives after the window.
  void SetMenu(std::unique_ptr<ArktExtensionsMenu> menu);
  ArktExtensionsMenu* menu() const { return menu_.get(); }

  // ExtensionsContainer:
  ToolbarActionViewModel* GetActionForId(const std::string& action_id) override;
  void HideActivePopup() override;
  void CloseExtensionsMenuIfOpen() override;
  bool ShowToolbarActionPopupForAPICall(const std::string& action_id,
                                        ShowPopupCallback callback) override;
  void ToggleExtensionsMenu() override;
  bool HasAnyExtensions() const override;
  content::WebContents* GetActiveWebContents() const override;

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
  std::unique_ptr<ArktExtensionsMenu> menu_;
  base::WeakPtrFactory<ArktExtensionsContainer> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSIONS_CONTAINER_H_
