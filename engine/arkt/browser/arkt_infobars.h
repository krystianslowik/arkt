#ifndef ARKT_BROWSER_ARKT_INFOBARS_H_
#define ARKT_BROWSER_ARKT_INFOBARS_H_

#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/infobars/core/infobar_manager.h"

@class ArktInfobarStackView;
@class ArktInfobarView;

namespace content {
class WebContents;
}

namespace ui {
class ColorProvider;
}

namespace arkt {

// Draws the infobars of one tab in an Arkt window natively (Task W3-10).
//
// Chromium adds infobars to the tab's infobars::ContentInfoBarManager and
// expects BrowserView's InfoBarContainerView to show the active tab's ones;
// an Arkt window has no BrowserView, so without this they stay in the manager
// with nothing on screen. The presenter observes the manager and keeps one
// native row per ConfirmInfoBarDelegate infobar in `stack()`, which the window
// lays out at the top of the tab's container (or the placeholder's card),
// pushing the page down as Chrome's infobar container does. Buttons, links
// and the close button run the delegate exactly as ConfirmInfoBar and
// InfoBarView do. Infobars with their own Views (not a confirm delegate:
// tab sharing, the alternate-URL bar) are logged and not drawn.
class ArktInfobarPresenter : public infobars::InfoBarManager::Observer {
 public:
  // `layout_changed` runs when the stack's height changed. `color_provider`
  // gives the colors for the infobar icons (the window's provider).
  ArktInfobarPresenter(
      content::WebContents* contents,
      base::RepeatingCallback<const ui::ColorProvider*()> color_provider,
      base::RepeatingClosure layout_changed);
  ArktInfobarPresenter(const ArktInfobarPresenter&) = delete;
  ArktInfobarPresenter& operator=(const ArktInfobarPresenter&) = delete;
  ~ArktInfobarPresenter() override;

  ArktInfobarStackView* stack() const { return stack_; }
  bool empty() const { return rows_.empty(); }

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* infobar) override;
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool animate) override;
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                         infobars::InfoBar* new_infobar) override;
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override;

 private:
  enum class Action { kOk, kCancel, kLink, kMessageLink, kClose };

  void Add(infobars::InfoBar* infobar, size_t index);
  // Removes the row of `infobar`; returns its index, or -1.
  int Remove(infobars::InfoBar* infobar);
  void Act(infobars::InfoBar* infobar, Action action, size_t link_index);

  raw_ptr<infobars::InfoBarManager> manager_;
  base::RepeatingCallback<const ui::ColorProvider*()> color_provider_;
  base::RepeatingClosure layout_changed_;
  ArktInfobarStackView* __strong stack_;
  // Drawn infobars in the manager's order, top to bottom.
  std::vector<std::pair<raw_ptr<infobars::InfoBar>, ArktInfobarView*>> rows_;
  base::WeakPtrFactory<ArktInfobarPresenter> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_INFOBARS_H_
