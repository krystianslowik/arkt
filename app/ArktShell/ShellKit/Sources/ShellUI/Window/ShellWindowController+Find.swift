import AppKit
import EngineAPI

// Find in page in the shell window (#134, design/find-in-page direction A). One bar per tab, drawn over the top trailing
// corner of the page while that tab is current. In a Split View the bar belongs to the focused pane (#493): it anchors
// to that pane, and an open query stays and is searched there when focus moves. The commands are the shell's
// (`claim`), so Chromium's own find bar, which `CreateFindBar` must never show in an Arkt window, is never asked for.
//
// Cut from this change: Jump to Selection.
extension ShellWindowController {
  /// The presenter, the bar over the card and their wiring to the window: focus, the page's keyboard on close, the
  /// field's nudge and the spoken count.
  func makeFindBar() -> FindBarPresenter {
    let presenter = FindBarPresenter(engine: engine)
    let view = FindBarView(presenter: presenter)
    rootView.card.findBarView = view
    presenter.onChange = { [weak view] in view?.refresh() }
    presenter.onFocusRequested = { [weak view] in view?.focusField() }
    presenter.onNoMatches = { [weak view] in view?.nudgeField() }
    presenter.onAnnouncement = { [weak view] in view?.announce($0) }
    presenter.onClosed = { [weak self] in self?.returnFocusToPage() }
    return presenter
  }

  /// The tab Find acts on: the focused pane's page while a split shows, otherwise the current page. Nil when a split
  /// has no focused pane, or that pane has no page.
  private var findTarget: TabID? {
    if splitState.split != nil {
      guard let focus = splitState.focus else { return nil }
      return engineTab(of: focus)
    }
    return currentTab
  }

  /// A page is showing and the first run is not covering the window. A split with no focused pane cannot find.
  private var canFind: Bool { findTarget != nil && onboarding == nil }

  /// True when `tab` is a pane of the split on screen.
  private func isShownPane(_ tab: TabID) -> Bool {
    guard let node = nodeByTab[tab] else { return false }
    return splitState.panes.contains(node)
  }

  /// The card the bar is drawn on: the focused pane, or the single card when no split is showing.
  private var findAnchorCard: ContentCardView {
    if splitState.split != nil, let focus = splitState.focus, let index = splitState.panes.firstIndex(of: focus),
       rootView.split.paneCards.indices.contains(index) {
      return rootView.split.paneCards[index]
    }
    return rootView.card
  }

  /// The one find bar, whether the single card or a pane card is hosting it.
  private var installedFindBar: FindBarView? {
    if let bar = rootView.card.findBarView { return bar }
    for view in rootView.split.subviews {
      if let card = view as? ContentCardView, let bar = card.findBarView { return bar }
    }
    return nil
  }

  /// Hosts the bar on `card`. Moving it inside the window does not replay the entrance; the card lays it out.
  private func anchorFindBar(to card: ContentCardView) {
    guard let bar = installedFindBar else { return }
    if bar.superview !== card {
      let host = bar.superview as? ContentCardView
      card.addSubview(bar, positioned: .above, relativeTo: card.closeButton ?? card.clipView)
      if host?.findBarView === bar { host?.findBarView = nil }
      if card.findBarView !== bar { card.findBarView = bar }
    }
    card.layoutSubtreeIfNeeded()
  }

  func claimFind(_ command: EngineCommand) -> CommandClaim {
    switch command {
    case .find: CommandClaim(isEnabled: canFind)
    default: CommandClaim(isEnabled: canFind && findBar.canFindAgain)    // Find Next, Find Previous
    }
  }

  func performFind(_ command: EngineCommand) -> Bool {
    // Claimed but disabled (no focused pane, the first run): handled, so nothing falls through to the engine's own find.
    guard claimFind(command).isEnabled else { return true }
    switch command {
    case .find: findBar.open()
    case .findNext: findBar.step(forward: true)
    default: findBar.step(forward: false)
    }
    return true
  }

  /// The content area changed. The bar follows the current tab, or the focused pane while a split shows. Moving
  /// between panes of that split keeps an open query and searches it in the pane that gained focus.
  func refreshFindBar() {
    let target = findTarget
    if splitState.split != nil, let target, let previous = findBar.visibleTab, previous != target,
       isShownPane(previous), isShownPane(target) {
      findBar.moveOpenSearch(to: target)
    } else {
      findBar.shownTabChanged(target)
    }
    anchorFindBar(to: findAnchorCard)
  }
}
