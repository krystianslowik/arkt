#ifndef ARKT_BROWSER_ARKT_EXTENSION_CALLS_H_
#define ARKT_BROWSER_ARKT_EXTENSION_CALLS_H_

#include <string_view>

namespace content {
class BrowserContext;
}

namespace arkt {

// Whether an enabled extension of `context` has a call to the extension API
// function `function` (for example "tabs.remove") in flight: the call's
// keepalive (Activity::API_FUNCTION) is held from before the function runs
// until it responds. Read from ProcessManager's keepalive records, so it
// sees calls from service workers and lazy background pages, but not calls
// from extension pages that hold no keepalive (popups, options pages,
// persistent background pages).
//
// This is how a close the facade did not start is told apart: in 156 both
// chrome.tabs.remove (TabsRemoveFunction, WebContents::Close) and
// window.close() reach Browser through WebContentsDelegate::CloseContents
// (week-3 plan, Decision 12).
bool IsExtensionApiCallInFlight(content::BrowserContext* context,
                                std::string_view function);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_EXTENSION_CALLS_H_
