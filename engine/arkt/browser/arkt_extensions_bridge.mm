#include "arkt/browser/arkt_extensions_bridge.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <utility>

#include "base/logging.h"
#include "base/no_destructor.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"

namespace arkt {

namespace {

// An extension popup hosted in an NSPopover instead of Chrome's Views bubble.
class PopoverExtensionView : public extensions::ExtensionView {
 public:
  PopoverExtensionView(std::unique_ptr<extensions::ExtensionViewHost> host,
                       NSView* anchor,
                       ShowPopupCallback on_loaded)
      : host_(std::move(host)),
        anchor_(anchor),
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
    host_->CreateRendererSoon();
  }

  ~PopoverExtensionView() override {
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
    if (on_loaded_) {
      std::move(on_loaded_).Run(host_.get());
    }
  }

 private:
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  NSView* __weak anchor_;
  NSPopover* __strong popover_;
  ShowPopupCallback on_loaded_;
};

std::unique_ptr<PopoverExtensionView>& CurrentPopup() {
  static base::NoDestructor<std::unique_ptr<PopoverExtensionView>> popup;
  return *popup;
}

PopoverExtensionView* PopupFor(const extensions::ExtensionId& extension_id) {
  PopoverExtensionView* popup = CurrentPopup().get();
  return popup && popup->extension_id() == extension_id ? popup : nullptr;
}

}  // namespace

void ShowPopover(std::unique_ptr<extensions::ExtensionViewHost> host,
                 NSView* anchor,
                 ShowPopupCallback on_loaded) {
  CurrentPopup().reset();
  CurrentPopup() = std::make_unique<PopoverExtensionView>(
      std::move(host), anchor, std::move(on_loaded));
}

bool IsShowingPopover(const extensions::ExtensionId& extension_id) {
  return PopupFor(extension_id) != nullptr;
}

void HidePopover(const extensions::ExtensionId& extension_id) {
  if (PopupFor(extension_id)) {
    CurrentPopup().reset();
  }
}

gfx::NativeView GetPopoverNativeView(
    const extensions::ExtensionId& extension_id) {
  PopoverExtensionView* popup = PopupFor(extension_id);
  return popup ? popup->GetNativeView() : gfx::NativeView();
}

}  // namespace arkt
