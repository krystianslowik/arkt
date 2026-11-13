#ifndef ARKT_BROWSER_ARKT_STUB_PROBE_H_
#define ARKT_BROWSER_ARKT_STUB_PROBE_H_

#include <string>

class GURL;

namespace content {
class WebContents;
}

namespace arkt {

// Self-test only (#589), for the facade's self-test commands: the no-crash
// checks of the Views stubs an Arkt window keeps, and the close of an
// incognito window with a download running. Each logs what it did with an
// "ARKT selftest" prefix.

// Calls every BrowserWindow stub of the tab's window and of its location bar,
// find bar, side panel and exclusive access context directly, with plain
// arguments, and logs one line per call.
void CallStubsForSelfTest(content::WebContents* contents);

// Runs the Chromium command `name` (focus-location, focus-search,
// focus-toolbar, focus-menu-bar, app-menu, bookmark, tab-search, avatar,
// caret, translate, find, chrome-labs, upgrade, reading-mode) on the tab's
// window when it is enabled, as a key or menu item would, and logs whether it
// was enabled.
void RunStubCommandForSelfTest(content::WebContents* contents,
                               const std::string& name);

// Opens an incognito window of the tab's profile with one tab at `url` (a
// download URL), and logs its window.
void OpenIncognitoForSelfTest(content::WebContents* contents, const GURL& url);

// Starts a download of `url` in the incognito profile of the tab's profile,
// saved to `file` without asking (a forced path), as an active incognito
// download.
void StartIncognitoDownloadForSelfTest(content::WebContents* contents,
                                       const GURL& url,
                                       const std::string& file);

// Closes the incognito window(s) of the tab's profile the way a close button
// does (BrowserWindow::Close), and logs each one's download count.
void CloseIncognitoForSelfTest(content::WebContents* contents);

// Logs every incognito window of the tab's profile that is still open, with
// its download count and whether its close is still under way.
void LogIncognitoForSelfTest(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_STUB_PROBE_H_
