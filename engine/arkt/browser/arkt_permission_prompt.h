#ifndef ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_
#define ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_

#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"

namespace content {
class WebContents;
}

namespace arkt {

// What a permission request asks for, as the shell tells them apart.
enum class PermissionKind {
  kOther,
  kGeolocation,
  kNotifications,
  kCamera,
  kMicrophone,
};

// How the shell answers a request.
enum class PermissionChoice { kAllow, kAllowThisTime, kBlock, kDismiss };

// A site's permission request in a tab of an Arkt window, held for the shell to
// present (issue #400). Chromium's PermissionRequestManager decides when a
// prompt shows and ends (tab switching, navigation, a withdrawn request, the
// tab closing) and owns the prompt that owns this object; the shell only draws
// the values and answers once. Every string is Chromium's.
class ArktPermissionAsk {
 public:
  struct Values {
    std::u16string origin;
    // "example.com wants to".
    std::u16string title;
    // One phrase per kind ("Know your location").
    std::vector<std::u16string> items;
    std::vector<PermissionKind> kinds;
    std::u16string allow_title;
    // Unset when the request has no one-visit grant.
    std::optional<std::u16string> allow_this_time_title;
    std::u16string block_title;
  };
  // Hands a choice to the prompt, which calls the permission delegate.
  using AnswerCallback = base::RepeatingCallback<void(PermissionChoice)>;

  ArktPermissionAsk(Values values, AnswerCallback answer);
  ArktPermissionAsk(const ArktPermissionAsk&) = delete;
  ArktPermissionAsk& operator=(const ArktPermissionAsk&) = delete;
  ~ArktPermissionAsk();

  const Values& values() const { return values_; }
  base::WeakPtr<ArktPermissionAsk> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  // Runs once when the request is over, however it ended, before the object is
  // deleted.
  void SetEndedCallback(base::OnceClosure ended) { ended_ = std::move(ended); }

  // The shell's answer. False, and nothing happens, when the request is already
  // over or already answered. Allow this time counts as Allow when the request
  // has no one-visit grant. The answer may delete this object (the prompt goes
  // when the manager resolves the request), so nothing is touched after it.
  bool Respond(PermissionChoice choice);

  // The prompt goes away without the shell's answer (or after it): runs the
  // ended callback once.
  void End();

 private:
  const Values values_;
  AnswerCallback answer_;
  base::OnceClosure ended_;
  bool answered_ = false;
  bool over_ = false;
  base::WeakPtrFactory<ArktPermissionAsk> weak_factory_{this};
};

// Presents `ask` to the shell and returns true, or returns false to keep the
// engine-drawn panel (no facade yet, or the tab's window has no embedder host
// that presents it). Set by the facade.
using PermissionPresenter = base::RepeatingCallback<bool(
    content::WebContents*,
    base::WeakPtr<ArktPermissionAsk>)>;
void SetPermissionPresenter(PermissionPresenter presenter);

// Gives `contents` Arkt's permission prompt factory (issue #260). While the
// tab is in an Arkt window, a permission request (notifications, location,
// camera, microphone, ...) shows a native panel anchored to the tab's view
// instead of Chrome's Views bubble, which on a plain NSWindow opens as a
// separate window behind the Arkt window. Requests the panel does not cover
// (quiet UI, the permission element's secondary UI, pointer and keyboard
// lock), and tabs in any other window, keep Chrome's prompt. When the window's
// host presents permission requests (issue #400), the request goes to the
// presenter instead of the panel; the panel stays the fallback. Safe to call
// more than once; a no-op for contents without a permission request manager.
void UseArktPermissionPrompts(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_PERMISSION_PROMPT_H_
