import AppKit
import EngineAPI

// The crashed tab view in the shell window (#578, part of #122; design/extensions `surf-crashed`). Chromium's own sad
// tab never shows in an Arkt window (patch 0005), so a tab whose page process went away gets this view over its page
// area: on the single card, on the pane card of a split that shows it, or on an open Peek's card (#683). Little Arkt
// windows place the same view on their card (`LittleArktWindowController`). The engine's snapshot is the source of
// truth (`TabSnapshot.crash`), read again at every refresh, so a tab switch, a Space switch, a split and a crash in the
// background all come out of the same placement. The view goes with `.tabRecovered` (a reload or a new navigation) or
// when its page leaves the card.

/// A card that can cover its page with the crashed tab view: a content card (the window's, a split pane's, a Little
/// Arkt window's) or a Peek's card.
@MainActor
protocol CrashedTabHost: NSView {
  var pageOverlayView: NSView? { get }
  func setPageOverlay(_ view: NSView?)
}

extension ContentCardView: CrashedTabHost {}
extension PeekCardView: CrashedTabHost {}

/// Places one `CrashedTabView` on each card that shows a crashed tab and takes it off the others. The controller says
/// which card shows which crashed tab; this owns the views, their entrance and the spoken alert.
@MainActor
final class CrashedTabPresenter {
  /// A card that shows a crashed tab, and the page's host for the body line.
  struct Placement {
    let card: any CrashedTabHost
    let tab: TabID
    let host: String?
  }

  /// Reduce Motion, read at each entrance. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Speaks the alert when a view appears. Tests replace it to count what was said.
  var announce: @MainActor (String, NSView) -> Void = { text, view in
    NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
      .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }
  var onReload: (@MainActor (TabID) -> Void)?
  var onClose: (@MainActor (TabID) -> Void)?

  /// The view on `card`, if it shows one.
  func view(on card: any CrashedTabHost) -> CrashedTabView? { card.pageOverlayView as? CrashedTabView }

  /// Puts the views in place on `cards`: a card in `placements` keeps its view for the same tab or gets a new one; any
  /// other card loses its view. A new view for `crashedNow` (the crash happened on screen) plays its entrance; one that
  /// came with a tab switch shows at once. Every new view is announced. Returns the new views.
  @discardableResult
  func apply(cards: [any CrashedTabHost], placements: [Placement], crashedNow: TabID? = nil) -> [CrashedTabView] {
    var made: [CrashedTabView] = []
    for card in cards {
      guard let placement = placements.first(where: { $0.card === card }) else {
        if view(on: card) != nil { card.setPageOverlay(nil) }
        continue
      }
      if let existing = view(on: card), existing.tab == placement.tab {
        existing.update(host: placement.host)
        continue
      }
      let view = CrashedTabView(tab: placement.tab, host: placement.host)
      let tab = placement.tab
      view.onReload = { [weak self] in self?.onReload?(tab) }
      view.onClose = { [weak self] in self?.onClose?(tab) }
      card.setPageOverlay(view)
      if tab == crashedNow { view.playEntrance(reduceMotion: reduceMotion()) }
      announce(CrashedTabView.title + ". " + view.bodyLabel.stringValue, view)
      made.append(view)
    }
    return made
  }
}

extension ShellWindowController {
  func makeCrashedTabPresenter() -> CrashedTabPresenter {
    let presenter = CrashedTabPresenter()
    presenter.onReload = { [weak self] tab in self?.reloadCrashedTab(tab) }
    presenter.onClose = { [weak self] tab in self?.closeCrashedTab(tab) }
    return presenter
  }

  /// The cards that can show a page in this window: the single card and the split's panes.
  private var pageCards: [ContentCardView] { [rootView.card] + rootView.split.paneCards }

  /// The open Peek's card and its tab, while its page is on the card (not while it closes or expands into a tab).
  private var peekCard: (card: PeekCardView, tab: TabID)? {
    guard let session = peek.session, session.phase != .closing, session.phase != .expanding,
          let card = peek.overlay?.card, card.page != nil else { return nil }
    return (card, session.tab)
  }

  /// Places the crashed tab view on every card whose page is a crashed tab and takes it off the rest. `crashed` is a
  /// tab whose crash was just reported: its view plays the entrance. A new view takes focus on Reload when the
  /// window's focus was on its card (or nowhere): the current tab's card while no Peek is open, the Peek's card while
  /// one is (#683).
  func refreshCrashedTabs(crashed: TabID? = nil) {
    let peekCard = self.peekCard
    let cards: [any CrashedTabHost] = pageCards + (peekCard.map { [$0.card] } ?? [])
    let tabs = Array(tabsByNode.values) + privateTabs
    var placements: [CrashedTabPresenter.Placement] = []
    for card in pageCards {
      guard let page = card.contentView,
            let tab = tabs.first(where: { engine.contentView(for: $0) === page }),
            let snapshot = engine.snapshot(of: tab), snapshot.crash != nil else { continue }
      placements.append(.init(card: card, tab: tab, host: snapshot.url.flatMap(HostDisplay.host(of:))))
    }
    if let (card, tab) = peekCard, let snapshot = engine.snapshot(of: tab), snapshot.crash != nil {
      placements.append(.init(card: card, tab: tab, host: snapshot.url.flatMap(HostDisplay.host(of:))))
    }
    let made = crashedTabs.apply(cards: cards, placements: placements, crashedNow: crashed)
    // Return is Reload on the current tab's view only (a split may show two), and never while a Peek is open: then
    // it is the Peek's view's.
    for card in pageCards {
      guard let view = crashedTabs.view(on: card) else { continue }
      view.isDefault = view.tab == currentTab
      view.keyboardIsElsewhere = { [weak self] in self?.peek.isOpen ?? true }
    }
    if let (card, _) = peekCard, let view = crashedTabs.view(on: card) {
      view.isDefault = true
      view.keyboardIsElsewhere = { false }
    }
    guard let window else { return }
    let focused = peek.isOpen ? peekCard?.tab : currentTab
    guard let focused, let view = made.first(where: { $0.tab == focused }),
          let card = view.superview?.superview, CrashedTabView.focusIsOnPage(of: card, in: window) else { return }
    window.makeFirstResponder(view.reloadButton)              // with Full Keyboard Access; else Return presses it
  }

  /// Reload on the view: the engine reloads the page; `.tabRecovered` takes the view down, and the page gets the focus
  /// when it was on the card.
  private func reloadCrashedTab(_ tab: TabID) {
    let cards: [any CrashedTabHost] = pageCards + (peekCard.map { [$0.card] } ?? [])
    let card = cards.first { crashedTabs.view(on: $0)?.tab == tab }
    let focusOnPage = card.flatMap { card in window.map { CrashedTabView.focusIsOnPage(of: card, in: $0) } } ?? false
    let shown = peek.isOpen ? peekCard?.tab : currentTab
    engine.reload(tab)
    if focusOnPage, tab == shown, let window, let page = engine.contentView(for: tab), page.window === window {
      window.makeFirstResponder(page)
    }
  }

  /// Close Tab on the view: what the pane's X does in a split, Cmd-W otherwise; on a Peek's card it closes the Peek, as
  /// its Close control does.
  private func closeCrashedTab(_ tab: TabID) {
    if tab == peek.session?.tab {
      peek.close(.control)
      return
    }
    guard let node = nodeByTab[tab] else {
      // A blank or incognito window's page (#487, #667): the window closes, as Cmd-W does there today.
      if privateTabs.contains(tab) { window?.performClose(nil) }
      return
    }
    if let index = splitState.panes.firstIndex(of: node), splitState.split != nil {
      closePane(at: index)
    } else {
      close(node: node)
    }
  }
}
