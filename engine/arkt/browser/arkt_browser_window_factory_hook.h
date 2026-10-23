#ifndef ARKT_BROWSER_ARKT_BROWSER_WINDOW_FACTORY_HOOK_H_
#define ARKT_BROWSER_ARKT_BROWSER_WINDOW_FACTORY_HOOK_H_

#include <memory>

#include "chrome/browser/ui/browser_window_deleter.h"

class BrowserWindow;
class BrowserWindowInterface;

namespace arkt {

// Lets //arkt/browser create the window of a Browser without
// //chrome/browser/ui/views/frame:browser_window_factory depending on it (that
// would be a GN cycle: //arkt/browser is a dependency of
// //chrome/browser:core). Called from BrowserWindow::CreateBrowserWindow
// (patch 0004).
//
// Deliberately narrower than BrowserWindow::CreateBrowserWindow(browser,
// user_gesture, in_tab_dragging): both extra arguments are only consumed on
// Aura (user_gesture sets aura::client::kCreatedByUserGesture; in_tab_dragging
// marks a window created by dragging a tab out of a Views tab strip), never on
// Mac, and an Arkt window has no Views tab strip to drag from.
//
// Returns nullptr for browsers Arkt does not take; Chromium then creates its
// own window.
using CreateBrowserWindowFn =
    std::unique_ptr<BrowserWindow, BrowserWindowDeleter> (*)(
        BrowserWindowInterface* browser);

// Set once at startup, before the first Browser exists. nullptr means "always
// use Chromium's window".
void SetCreateBrowserWindowOverride(CreateBrowserWindowFn fn);
CreateBrowserWindowFn GetCreateBrowserWindowOverride();

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_WINDOW_FACTORY_HOOK_H_
