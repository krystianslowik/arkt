import AppKit
import EngineAPI

// The crashed tab view in a Little Arkt window (#683, follow-up to #578; design/extensions `surf-crashed`): the main
// window's view, over this window's page. Reload reloads the page; Close Tab closes the window, as Cmd-W does here.
// The engine's snapshot is the source of truth, read again at every refresh.

extension LittleArktWindowController {
  func makeCrashedTabPresenter() -> CrashedTabPresenter {
    let presenter = CrashedTabPresenter()
    presenter.onReload = { [weak self] tab in self?.reloadCrashedTab(tab) }
    presenter.onClose = { [weak self] _ in self?.closeTab(nil) }
    return presenter
  }

  /// Puts the view on the card while the shown tab is crashed and takes it off otherwise. `crashed`: the crash was
  /// just reported, so the view plays its entrance. A new view takes the focus on Reload when the window's focus was
  /// on the page (or nowhere).
  func refreshCrashedTab(crashed: TabID? = nil) {
    var placements: [CrashedTabPresenter.Placement] = []
    if let tab = shownTab, card.contentView != nil, card.contentView === engine.contentView(for: tab),
       let snapshot = engine.snapshot(of: tab), snapshot.crash != nil {
      placements.append(.init(card: card, tab: tab, host: snapshot.url.flatMap(HostDisplay.host(of:))))
    }
    let made = crashedTabs.apply(cards: [card], placements: placements, crashedNow: crashed)
    guard let view = crashedTabs.view(on: card) else { return }
    view.isDefault = true                                     // one page per window: Return is its Reload
    guard made.contains(where: { $0 === view }), CrashedTabView.focusIsOnPage(of: card, in: window) else { return }
    window.makeFirstResponder(view.reloadButton)              // with Full Keyboard Access; else Return presses it
  }

  /// Reload on the view: the engine reloads the page; `.tabRecovered` takes the view down, and the page gets the focus
  /// when it was on the card.
  private func reloadCrashedTab(_ tab: TabID) {
    let focusOnPage = CrashedTabView.focusIsOnPage(of: card, in: window)
    engine.reload(tab)
    if focusOnPage, tab == shownTab, let page = engine.contentView(for: tab), page.window === window {
      window.makeFirstResponder(page)
    }
  }
}
