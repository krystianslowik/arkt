#include "arkt/browser/arkt_extensions_container.h"

#include <utility>

#include "arkt/browser/arkt_extensions_bridge.h"
#include "arkt/browser/arkt_extensions_menu.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/toolbar/toolbar_action_view_model.h"

namespace arkt {

ArktExtensionsContainer::ArktExtensionsContainer(
    BrowserWindowInterface* browser)
    : browser_(browser) {}

ArktExtensionsContainer::~ArktExtensionsContainer() = default;

void ArktExtensionsContainer::SetMenu(
    std::unique_ptr<ArktExtensionsMenu> menu) {
  menu_ = std::move(menu);
}

ToolbarActionViewModel* ArktExtensionsContainer::GetActionForId(
    const std::string& action_id) {
  return menu_ ? menu_->GetViewModel(action_id) : nullptr;
}

void ArktExtensionsContainer::HideActivePopup() {
  if (menu_) {
    menu_->HideActivePopup();
  }
}

void ArktExtensionsContainer::CloseExtensionsMenuIfOpen() {
  if (menu_) {
    LOG(WARNING) << "ARKT: extensions container close menu (showing="
                 << menu_->IsShowing() << ")";
    menu_->CloseIfOpen();
  }
}

bool ArktExtensionsContainer::ShowToolbarActionPopupForAPICall(
    const std::string& action_id,
    ShowPopupCallback callback) {
  // As Chrome's toolbar: never replace a showing popup, and only show in the
  // active window.
  if (IsShowingAnyPopover() || !browser_->GetWindow()->IsActive()) {
    LOG(WARNING) << "ARKT: openPopup refused for " << action_id;
    return false;
  }
  ToolbarActionViewModel* action = GetActionForId(action_id);
  if (!action) {
    LOG(WARNING) << "ARKT: openPopup has no action " << action_id;
    return false;
  }
  LOG(WARNING) << "ARKT: openPopup " << action_id;
  action->TriggerPopupForAPI(std::move(callback));
  return true;
}

void ArktExtensionsContainer::ToggleExtensionsMenu() {
  if (!menu_) {
    return;
  }
  LOG(WARNING) << "ARKT: extensions container toggle menu (showing="
               << menu_->IsShowing() << ")";
  if (menu_->IsShowing()) {
    menu_->CloseIfOpen();
    return;
  }
  // Showing the menu runs a nested event loop; never from inside the caller.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ArktExtensionsContainer> container) {
                       if (container && container->menu_) {
                         container->menu_->Show();
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

bool ArktExtensionsContainer::HasAnyExtensions() const {
  return menu_ && menu_->HasAnyActions();
}

content::WebContents* ArktExtensionsContainer::GetActiveWebContents() const {
  return menu_ ? menu_->active_web_contents() : nullptr;
}

}  // namespace arkt
