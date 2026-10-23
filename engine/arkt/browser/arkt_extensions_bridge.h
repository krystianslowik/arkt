#ifndef ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_
#define ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_

#include <string>

@class NSView;
class BrowserWindowInterface;

namespace content {
class WebContents;
}

namespace arkt {

// Lists the profile's toolbar extension actions in the log once the toolbar
// model is ready, then, if `popup_extension_id` is non-empty and installed,
// runs that action (granting activeTab like a toolbar click) and shows its
// popup in an NSPopover anchored to `anchor`.
void StartExtensionsDemo(BrowserWindowInterface* browser,
                         content::WebContents* tab,
                         NSView* anchor,
                         const std::string& popup_extension_id);

// Runs the action and shows its popup now (used by the placeholder button).
void ShowExtensionPopup(BrowserWindowInterface* browser,
                        content::WebContents* tab,
                        NSView* anchor,
                        const std::string& extension_id);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSIONS_BRIDGE_H_
