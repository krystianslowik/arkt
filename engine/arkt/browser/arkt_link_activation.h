#ifndef ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_
#define ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_

#include "base/functional/callback.h"

namespace content {
class NavigationHandle;
class NavigationThrottleRegistry;
}  // namespace content

namespace arkt {

// Answers a user link activation before Chromium navigates (#313): true
// cancels the navigation, and the embedder opens the link itself (a Peek, a
// new tab). Runs inside NavigationThrottle::WillStartRequest; it must not
// start or close a navigation, a tab or a window before it returns.
using LinkActivationDecider =
    base::RepeatingCallback<bool(content::NavigationHandle&)>;

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

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_LINK_ACTIVATION_H_
