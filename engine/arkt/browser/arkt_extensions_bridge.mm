#include "arkt/browser/arkt_extensions_bridge.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "ui/gfx/native_ui_types.h"

namespace arkt {

namespace {

constexpr int kMaxAttempts = 120;
constexpr base::TimeDelta kRetryDelay = base::Milliseconds(500);

// An extension popup hosted in an NSPopover instead of Chrome's Views bubble.
class PopoverExtensionView : public extensions::ExtensionView {
 public:
  PopoverExtensionView(std::unique_ptr<extensions::ExtensionViewHost> host,
                       NSView* anchor)
      : host_(std::move(host)), anchor_(anchor) {
    host_->set_view(this);

    NSView* page = host_->host_contents()->GetNativeView().GetNativeNSView();
    page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSViewController* controller = [[NSViewController alloc] init];
    controller.view = page;
    popover_ = [[NSPopover alloc] init];
    popover_.contentViewController = controller;
    // Stays open until the next popup replaces it, so tests can drive it.
    popover_.behavior = NSPopoverBehaviorApplicationDefined;
    popover_.contentSize = NSMakeSize(extensions::kExtensionPopupMinSize.width(),
                                      extensions::kExtensionPopupMinSize.height());
    host_->CreateRendererSoon();
  }

  ~PopoverExtensionView() override {
    [popover_ close];
    host_->set_view(nullptr);
  }

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override {
    return host_->host_contents()->GetNativeView();
  }

  void ResizeDueToAutoResize(content::WebContents* web_contents,
                             const gfx::Size& new_size) override {
    LOG(WARNING) << "ARKT: popup auto-resize " << new_size.ToString();
    popover_.contentSize = NSMakeSize(new_size.width(), new_size.height());
  }

  void RenderFrameCreated(content::RenderFrameHost* frame_host) override {
    if (frame_host->GetView()) {
      frame_host->GetView()->EnableAutoResize(
          extensions::kExtensionPopupMinSize,
          extensions::kExtensionPopupMaxSize);
    }
  }

  bool HandleKeyboardEvent(
      content::WebContents* source,
      const input::NativeWebKeyboardEvent& event) override {
    return false;
  }

  void OnLoaded() override {
    LOG(WARNING) << "ARKT: popup loaded "
                 << host_->host_contents()->GetLastCommittedURL().spec();
    [popover_ showRelativeToRect:anchor_.bounds
                          ofView:anchor_
                   preferredEdge:NSRectEdgeMaxX];
  }

 private:
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  NSView* __weak anchor_;
  NSPopover* __strong popover_;
};

std::unique_ptr<PopoverExtensionView>& CurrentPopup() {
  static base::NoDestructor<std::unique_ptr<PopoverExtensionView>> popup;
  return *popup;
}

void LogActions(Profile* profile, ToolbarActionsModel* model) {
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile);
  LOG(WARNING) << "ARKT: toolbar actions " << model->action_ids().size();
  for (const auto& id : model->action_ids()) {
    const extensions::Extension* extension =
        registry->enabled_extensions().GetByID(id);
    LOG(WARNING) << "ARKT action " << id << " "
                 << (extension ? extension->name() : std::string("?"));
  }
}

void PollActions(base::WeakPtr<content::WebContents> tab,
                 BrowserWindowInterface* browser,
                 NSView* anchor,
                 std::string popup_extension_id,
                 size_t last_count,
                 int attempt) {
  if (!tab) {
    return;
  }
  Profile* profile = browser->GetProfile();
  ToolbarActionsModel* model = ToolbarActionsModel::Get(profile);
  bool ready = model && model->actions_initialized();
  if (ready && model->action_ids().size() != last_count) {
    LogActions(profile, model);
    last_count = model->action_ids().size();
  }
  if (ready && !popup_extension_id.empty() &&
      model->action_ids().contains(popup_extension_id)) {
    ShowExtensionPopup(browser, tab.get(), anchor, popup_extension_id);
    return;
  }
  if (attempt + 1 >= kMaxAttempts) {
    LOG(WARNING) << "ARKT: stopped waiting for extension actions";
    return;
  }
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&PollActions, tab, browser, anchor,
                     std::move(popup_extension_id), last_count, attempt + 1),
      kRetryDelay);
}

}  // namespace

void StartExtensionsDemo(BrowserWindowInterface* browser,
                         content::WebContents* tab,
                         NSView* anchor,
                         const std::string& popup_extension_id) {
  PollActions(tab->GetWeakPtr(), browser, anchor, popup_extension_id,
              static_cast<size_t>(-1), 0);
}

void ShowExtensionPopup(BrowserWindowInterface* browser,
                        content::WebContents* tab,
                        NSView* anchor,
                        const std::string& extension_id) {
  Profile* profile = browser->GetProfile();
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)
          ->enabled_extensions()
          .GetByID(extension_id);
  if (!extension) {
    LOG(ERROR) << "ARKT: extension not installed " << extension_id;
    return;
  }
  extensions::ExtensionActionRunner* runner =
      extensions::ExtensionActionRunner::GetForWebContents(tab);
  extensions::ExtensionAction::ShowAction show =
      runner ? runner->RunAction(extension, /*grant_tab_permissions=*/true)
             : extensions::ExtensionAction::ShowAction::kNone;
  if (show != extensions::ExtensionAction::ShowAction::kShowPopup) {
    LOG(WARNING) << "ARKT: action did not ask for a popup ("
                 << static_cast<int>(show) << ")";
    return;
  }
  extensions::ExtensionAction* action =
      extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(
          *extension);
  GURL url = action->GetPopupUrl(sessions::SessionTabHelper::IdForTab(tab).id());
  LOG(WARNING) << "ARKT: opening popup " << url.spec();
  CurrentPopup().reset();
  CurrentPopup() = std::make_unique<PopoverExtensionView>(
      extensions::ExtensionViewHostFactory::CreatePopupHost(*extension, url,
                                                            browser),
      anchor);
}

}  // namespace arkt
