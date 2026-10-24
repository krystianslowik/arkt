#include "arkt/browser/arkt_extensions_bridge.h"

#import <AppKit/AppKit.h>

#include <cstdint>
#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "components/javascript_dialogs/app_modal_dialog_queue.h"
#include "components/web_modal/web_modal_utils.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/extension.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"

namespace arkt {

namespace {

class PopoverExtensionView;
void ClosePopup(PopoverExtensionView* popup, const char* reason);

// An extension popup hosted in an NSPopover instead of Chrome's Views bubble.
// It closes when the page calls window.close(), its extension unloads or
// another window of the app becomes key, as Chrome's ExtensionPopup does
// (the active-tab close is the window's: ArktBrowserWindow).
class PopoverExtensionView : public extensions::ExtensionView,
                             public extensions::ExtensionRegistryObserver {
 public:
  PopoverExtensionView(std::unique_ptr<extensions::ExtensionViewHost> host,
                       NSView* anchor,
                       const void* owner,
                       ShowPopupCallback on_loaded)
      : host_(std::move(host)),
        anchor_(anchor),
        owner_(reinterpret_cast<uintptr_t>(owner)),
        on_loaded_(std::move(on_loaded)) {
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
    // The host calls this from inside its own WebContents callbacks, so the
    // close (which destroys the host) runs from a posted task.
    host_->SetCloseHandler(base::BindOnce(
        [](base::WeakPtr<PopoverExtensionView> popup,
           extensions::ExtensionHost*) {
          base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
              FROM_HERE, base::BindOnce(
                             [](base::WeakPtr<PopoverExtensionView> popup) {
                               if (popup) {
                                 ClosePopup(popup.get(), "window.close");
                               }
                             },
                             popup));
        },
        weak_factory_.GetWeakPtr()));
    registry_observation_.Observe(
        extensions::ExtensionRegistry::Get(host_->browser_context()));
    host_->CreateRendererSoon();
  }

  ~PopoverExtensionView() override {
    if (key_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:key_observer_];
    }
    [popover_ close];
    host_->set_view(nullptr);
    // The popup never showed: report the failure, as Chrome's popup does.
    if (on_loaded_) {
      std::move(on_loaded_).Run(nullptr);
    }
  }

  const extensions::ExtensionId& extension_id() const {
    return host_->extension_id();
  }
  bool IsOwnedBy(const void* owner) const {
    return owner_ == reinterpret_cast<uintptr_t>(owner);
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

  // extensions::ExtensionRegistryObserver:
  void OnExtensionUnloaded(content::BrowserContext* browser_context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override {
    if (extension->id() != host_->extension_id()) {
      return;
    }
    // Unload notifications are sent from inside the registry; close later.
    registry_observation_.Reset();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<PopoverExtensionView> popup) {
                         if (popup) {
                           ClosePopup(popup.get(), "extension unloaded");
                         }
                       },
                       weak_factory_.GetWeakPtr()));
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
    // As Chrome's popup: the page gets focus when it is shown, so the popover
    // is the key window and activating any other window closes it.
    NSWindow* popover_window = popover_.contentViewController.view.window;
    [popover_window makeKeyWindow];
    host_->host_contents()->Focus();
    LOG(WARNING) << "ARKT: popup key " << popover_window.isKeyWindow;
    ObserveKeyWindow();
    if (on_loaded_) {
      std::move(on_loaded_).Run(host_.get());
    }
  }

 private:
  // Chrome closes the popup when another widget of the anchor window's tree
  // is activated (ExtensionPopup::OnWidgetTreeActivated), not when the app
  // loses focus. Here: any other window of the app becoming key, which also
  // covers a click back into the anchor window.
  void ObserveKeyWindow() {
    if (key_observer_) {
      return;
    }
    base::WeakPtr<PopoverExtensionView> weak = weak_factory_.GetWeakPtr();
    key_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidBecomeKeyNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification* notification) {
                  if (weak) {
                    weak->OnWindowBecameKey(notification.object);
                  }
                }];
  }

  void OnWindowBecameKey(NSWindow* window) {
    NSWindow* popover_window = popover_.contentViewController.view.window;
    for (NSWindow* w = window; w; w = w.parentWindow) {
      if (w == popover_window) {
        return;
      }
    }
    // Chrome's exceptions (CloseUnlessBlockedByInspectionOrJSDialog): an app
    // modal JavaScript dialog (on Arkt an unparented window, often the
    // popup's own alert) or a web modal dialog of the popup keeps it open.
    // The DevTools-inspection exception needs //chrome/browser/devtools,
    // which //arkt/browser cannot depend on; not applied.
    if (javascript_dialogs::AppModalDialogQueue::GetInstance()
            ->HasActiveDialog() ||
        web_modal::WebContentsHasActiveWebModal(host_->host_contents())) {
      return;
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<PopoverExtensionView> popup) {
                         if (popup) {
                           ClosePopup(popup.get(), "another window key");
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }

  std::unique_ptr<extensions::ExtensionViewHost> host_;
  NSView* __weak anchor_;
  // The owner's address, compared only, never dereferenced.
  const uintptr_t owner_;
  NSPopover* __strong popover_;
  ShowPopupCallback on_loaded_;
  id __strong key_observer_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  base::WeakPtrFactory<PopoverExtensionView> weak_factory_{this};
};

std::unique_ptr<PopoverExtensionView>& CurrentPopup() {
  static base::NoDestructor<std::unique_ptr<PopoverExtensionView>> popup;
  return *popup;
}

void ClosePopup(PopoverExtensionView* popup, const char* reason) {
  if (CurrentPopup().get() != popup) {
    return;
  }
  LOG(WARNING) << "ARKT: popup closed (" << reason << ") "
               << popup->extension_id();
  CurrentPopup().reset();
}

PopoverExtensionView* PopupFor(const extensions::ExtensionId& extension_id,
                               const void* owner) {
  PopoverExtensionView* popup = CurrentPopup().get();
  return popup && popup->extension_id() == extension_id &&
                 popup->IsOwnedBy(owner)
             ? popup
             : nullptr;
}

}  // namespace

void ShowPopover(std::unique_ptr<extensions::ExtensionViewHost> host,
                 NSView* anchor,
                 const void* owner,
                 ShowPopupCallback on_loaded) {
  CurrentPopup().reset();
  CurrentPopup() = std::make_unique<PopoverExtensionView>(
      std::move(host), anchor, owner, std::move(on_loaded));
}

bool IsShowingPopover(const extensions::ExtensionId& extension_id,
                      const void* owner) {
  return PopupFor(extension_id, owner) != nullptr;
}

bool IsShowingAnyPopover() {
  return CurrentPopup() != nullptr;
}

void HidePopover(const extensions::ExtensionId& extension_id,
                 const void* owner) {
  if (PopoverExtensionView* popup = PopupFor(extension_id, owner)) {
    ClosePopup(popup, "hidden");
  }
}

gfx::NativeView GetPopoverNativeView(
    const extensions::ExtensionId& extension_id,
    const void* owner) {
  PopoverExtensionView* popup = PopupFor(extension_id, owner);
  return popup ? popup->GetNativeView() : gfx::NativeView();
}

}  // namespace arkt
