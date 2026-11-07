#ifndef ARKT_BROWSER_ARKT_INFOBARS_H_
#define ARKT_BROWSER_ARKT_INFOBARS_H_

#include <cstdint>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/infobars/core/infobar_manager.h"

@class ArktInfobarContent;
@class ArktInfobarStackView;
@class ArktInfobarView;

namespace content {
class WebContents;
}

namespace ui {
class ColorProvider;
}

namespace arkt {

// What an infobar is about, for the few the shell tells apart (issue #400).
enum class InfobarKind { kOther, kDebugger, kAutomation, kReload };

// What the shell does on an infobar, as the click would.
enum class InfobarAction { kOk, kCancel, kLink, kMessageLink, kClose };

// One drawn infobar as plain values, for the embedder that presents it.
struct PresentedInfobar {
  // Unique among the infobars of the run; a replaced infobar is a new one.
  uint64_t id = 0;
  InfobarKind kind = InfobarKind::kOther;
  // The row's content: message, links, buttons, icon, close label.
  ArktInfobarContent* __strong content;
};

class ArktInfobarPresenter;

// Hands the tab's infobars to the shell (issue #400) and returns true, or
// returns false to keep the engine-drawn rows (no facade yet, or the tab's
// window has no embedder host that presents them). Called after every change
// of the tab's list. Set by the facade.
using InfobarSink = base::RepeatingCallback<bool(
    content::WebContents*,
    base::WeakPtr<ArktInfobarPresenter>)>;
void SetInfobarSink(InfobarSink sink);

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
//
// When the window's embedder host presents infobars (issue #400, the sink says
// so) the rows stay in the presenter, hidden: the stack keeps its height so the
// page still sits below the strip the shell draws, and the shell acts through
// Perform().
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

  // The drawn infobars in the manager's order, as plain values.
  std::vector<PresentedInfobar> Presented() const;
  // The shell's action on the infobar `id`, as the click would run it. False,
  // and nothing happens, when the infobar is already gone. The delegate decides
  // whether the infobar goes; the list the sink gets next says so.
  bool Perform(uint64_t id, InfobarAction action, size_t link_index);

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* infobar) override;
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool animate) override;
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                         infobars::InfoBar* new_infobar) override;
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override;

 private:
  using Action = InfobarAction;

  struct Row {
    raw_ptr<infobars::InfoBar> infobar;
    ArktInfobarView* __strong view;
    uint64_t id;
    InfobarKind kind;
    ArktInfobarContent* __strong content;
  };

  void Add(infobars::InfoBar* infobar, size_t index);
  // Removes the row of `infobar`; returns its index, or -1.
  int Remove(infobars::InfoBar* infobar);
  void Act(infobars::InfoBar* infobar, Action action, size_t link_index);
  // Tells the sink about the tab's list and hides the rows while it presents.
  void Publish();

  raw_ptr<infobars::InfoBarManager> manager_;
  base::WeakPtr<content::WebContents> contents_;
  // The sink took the tab's infobars: the rows are hidden, only their height
  // is kept.
  bool presented_ = false;
  base::RepeatingCallback<const ui::ColorProvider*()> color_provider_;
  base::RepeatingClosure layout_changed_;
  ArktInfobarStackView* __strong stack_;
  // Drawn infobars in the manager's order, top to bottom.
  std::vector<Row> rows_;
  base::WeakPtrFactory<ArktInfobarPresenter> weak_factory_{this};
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_INFOBARS_H_
