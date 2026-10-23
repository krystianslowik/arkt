#ifndef ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_
#define ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_

#include <memory>

#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "extensions/common/extension_id.h"
#include "ui/gfx/native_ui_types.h"

@class NSView;

namespace extensions {
class ExtensionViewHost;
}

namespace arkt {

// Hosts an extension popup in an NSPopover anchored to `anchor` instead of
// Chrome's Views bubble. There is at most one popup at a time; showing a new
// one closes the previous one. `owner` identifies who showed it (one Arkt
// window's extensions menu); the queries below only see popups of their
// owner, so one window never closes another window's popup. `on_loaded` (may
// be null) runs with the host once the popup page has loaded and the popover
// is shown.
void ShowPopover(std::unique_ptr<extensions::ExtensionViewHost> host,
                 NSView* anchor,
                 const void* owner,
                 ShowPopupCallback on_loaded);

// Whether the current popup belongs to `extension_id` and `owner`.
bool IsShowingPopover(const extensions::ExtensionId& extension_id,
                      const void* owner);

// Whether any popup is showing (or loading).
bool IsShowingAnyPopover();

// Closes the current popup if it belongs to `extension_id` and `owner`.
void HidePopover(const extensions::ExtensionId& extension_id,
                 const void* owner);

// The current popup's native view if it belongs to `extension_id` and
// `owner`.
gfx::NativeView GetPopoverNativeView(
    const extensions::ExtensionId& extension_id,
    const void* owner);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_
