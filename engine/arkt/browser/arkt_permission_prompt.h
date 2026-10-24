#ifndef ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_
#define ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_

namespace content {
class WebContents;
}

namespace arkt {

// Gives `contents` Arkt's permission prompt factory (issue #260). While the
// tab is in an Arkt window, a permission request (notifications, location,
// camera, microphone, ...) shows a native panel anchored to the tab's view
// instead of Chrome's Views bubble, which on a plain NSWindow opens as a
// separate window behind the Arkt window. Requests the panel does not cover
// (quiet UI, the permission element's secondary UI, pointer and keyboard
// lock), and tabs in any other window, keep Chrome's prompt. Safe to call
// more than once; a no-op for contents without a permission request manager.
void UseArktPermissionPrompts(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_
