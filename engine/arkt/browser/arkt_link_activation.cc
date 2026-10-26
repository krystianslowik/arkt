#include "arkt/browser/arkt_link_activation.h"

#include <memory>
#include <utility>

#include "base/no_destructor.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace arkt {
namespace {

LinkActivationDecider& Decider() {
  static base::NoDestructor<LinkActivationDecider> decider;
  return *decider;
}

class LinkActivationThrottle : public content::NavigationThrottle {
 public:
  explicit LinkActivationThrottle(
      content::NavigationThrottleRegistry& registry)
      : content::NavigationThrottle(registry) {}
  LinkActivationThrottle(const LinkActivationThrottle&) = delete;
  LinkActivationThrottle& operator=(const LinkActivationThrottle&) = delete;
  ~LinkActivationThrottle() override = default;

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override {
    content::NavigationHandle& navigation = *navigation_handle();
    if (!IsUserLinkActivation(navigation) || Decider().is_null()) {
      return PROCEED;
    }
    // Copied: the decider may replace itself (a facade restart) while it runs.
    LinkActivationDecider decider = Decider();
    return decider.Run(navigation) ? CANCEL_AND_IGNORE : PROCEED;
  }

  const char* GetNameForLogging() override { return "ArktLinkActivation"; }
};

}  // namespace

void SetLinkActivationDecider(LinkActivationDecider decider) {
  Decider() = std::move(decider);
}

bool IsUserLinkActivation(content::NavigationHandle& navigation) {
  const ui::PageTransition transition = navigation.GetPageTransition();
  return navigation.IsInPrimaryMainFrame() &&
         navigation.IsRendererInitiated() && navigation.HasUserGesture() &&
         !navigation.IsSameDocument() &&
         ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_LINK) &&
         !(transition & ui::PAGE_TRANSITION_FORWARD_BACK) &&
         !navigation.IsPost() && navigation.GetURL().SchemeIsHTTPOrHTTPS();
}

void MaybeAddLinkActivationThrottle(
    content::NavigationThrottleRegistry& registry) {
  if (!registry.GetNavigationHandle().IsInPrimaryMainFrame()) {
    return;
  }
  registry.AddThrottle(std::make_unique<LinkActivationThrottle>(registry));
}

}  // namespace arkt
