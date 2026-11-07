#ifndef ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_
#define ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace content {
class NavigationHandle;
class NavigationThrottleRegistry;
class WebContents;
struct OpenURLParams;
}  // namespace content

namespace arkt {

// A user link activation the decider is asked about: the tab the link is in,
// where it goes, and where Chromium would open it (CURRENT_TAB for a plain
// click; NEW_WINDOW, NEW_FOREGROUND_TAB or NEW_BACKGROUND_TAB for a modified
// click, #345).
struct LinkActivation {
  raw_ptr<content::WebContents> source = nullptr;
  GURL url;
  WindowOpenDisposition disposition = WindowOpenDisposition::CURRENT_TAB;
};

// Answers a user link activation before Chromium navigates or opens anything
// (#313, #345): true drops it, and the embedder opens the link itself (a Peek,
// a new tab). Runs inside NavigationThrottle::WillStartRequest or
// WebContentsDelegate::OpenURLFromTab; it must not start or close a
// navigation, a tab or a window before it returns.
using LinkActivationDecider =
    base::RepeatingCallback<bool(const LinkActivation&)>;

// Set by the engine facade when it starts; a null callback lets every link
// navigate.
void SetLinkActivationDecider(LinkActivationDecider decider);

// True for a navigation the decider is asked about: the primary main frame,
// renderer-initiated with a user gesture, a link transition, a new document
// over HTTP(S). Script navigations, forms, reloads and history moves are
// never asked.
bool IsUserLinkActivation(content::NavigationHandle& navigation);

// Called from ChromeContentBrowserClient's throttle list (patch 0008): adds
// the link activation throttle to primary main-frame navigations. The
// throttle is the only place a renderer-initiated same-tab link navigation
// can be stopped before its request starts; NavigationHandle's own
// RegisterThrottleForTesting needs content's internal registry.
void MaybeAddLinkActivationThrottle(
    content::NavigationThrottleRegistry& registry);

// Called from BrowserWebContentsDelegate::OpenURLFromTab before it navigates
// (patch 0009, #345). Blink turns a Shift-, Command- or middle-click on a
// link into a NEW_WINDOW, NEW_FOREGROUND_TAB or NEW_BACKGROUND_TAB
// OpenURL, which never reaches the throttle above and, for NEW_WINDOW,
// creates the window before any navigation starts. True when the decider
// takes the link: OpenURLFromTab then opens nothing. Context-menu commands,
// forms, script and browser-initiated opens are never asked.
bool ShouldDropLinkOpenedFromTab(content::WebContents* source,
                                 const content::OpenURLParams& params);

// Receives WebContentsDelegate::UpdateTargetURL for a tab's contents (#114): the
// URL of the link under the pointer, or an empty URL when the pointer left it.
using TargetURLObserver =
    base::RepeatingCallback<void(content::WebContents*, const GURL&)>;

// Set by the engine facade when it starts; a null callback drops every report.
void SetTargetURLObserver(TargetURLObserver observer);

// Called from BrowserWebContentsDelegate::UpdateTargetURL (patch 0010, #114)
// before it looks for a status bubble. Arkt windows have none (their
// GetStatusBubbles is empty, and the Views bubble code casts every bubble to
// StatusBubbleViews), so this call is the only place the report is seen.
void NotifyTargetURLChanged(content::WebContents* source, const GURL& url);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_
