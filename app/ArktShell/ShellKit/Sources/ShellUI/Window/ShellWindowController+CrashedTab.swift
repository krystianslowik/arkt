import AppKit
import EngineAPI

// The crashed tab view in the shell window (#578, part of #122; design/extensions `surf-crashed`). Chromium's own sad
// tab never shows in an Arkt window (patch 0005), so a tab whose page process went away gets this view over its page
// area: on the single card, or on the pane card of a split that shows it. The engine's snapshot is the source of truth
// (`TabSnapshot.crash`), read again at every refresh, so a tab switch, a Space switch, a split and a crash in the
// background all come out of the same placement. The view goes with `.tabRecovered` (a reload or a new navigation) or
// when its page leaves the card.

/// Places one `CrashedTabView` on each card that shows a crashed tab and takes it off the others. The controller says
/// which card shows which crashed tab; this owns the views, their entrance and the spoken alert.
@MainActor
final class CrashedTabPresenter {
  /// A card that shows a crashed tab, and the page's host for the body line.
  struct Placement {
    let card: ContentCardView
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
  func view(on card: ContentCardView) -> CrashedTabView? { card.pageOverlayView as? CrashedTabView }

  /// Puts the views in place on `cards`: a card in `placements` keeps its view for the same tab or gets a new one; any
  /// other card loses its view. A new view for `crashedNow` (the crash happened on screen) plays its entrance; one that
  /// came with a tab switch shows at once. Every new view is announced. Returns the new views.
  @discardableResult
  func apply(cards: [ContentCardView], placements: [Placement], crashedNow: TabID? = nil) -> [CrashedTabView] {
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

  /// Places the crashed tab view on every card whose page is a crashed tab and takes it off the rest. `crashed` is a
  /// tab whose crash was just reported: its view plays the entrance. A new view on the current tab's card takes focus
  /// on Reload, unless the user is typing somewhere else in the window.
  func refreshCrashedTabs(crashed: TabID? = nil) {
    let cards = pageCards
    let tabs = Array(tabsByNode.values) + (privateTab.map { [$0] } ?? [])
    var placements: [CrashedTabPresenter.Placement] = []
    for card in cards {
      guard let page = card.contentView,
            let tab = tabs.first(where: { engine.contentView(for: $0) === page }),
            let snapshot = engine.snapshot(of: tab), snapshot.crash != nil else { continue }
      placements.append(.init(card: card, tab: tab, host: snapshot.url?.host()))
    }
    let made = crashedTabs.apply(cards: cards, placements: placements, crashedNow: crashed)
    // Return is Reload on the current tab's view only (a split may show two), as the empty state's default button.
    for card in cards { crashedTabs.view(on: card)?.isDefault = crashedTabs.view(on: card)?.tab == currentTab }
    guard let window, let current = currentTab, let view = made.first(where: { $0.tab == current }),
          let card = view.superview?.superview as? ContentCardView, Self.userIsNotTypingElsewhere(of: card, in: window) else { return }
    window.makeFirstResponder(view.reloadButton)              // with Full Keyboard Access; else Return presses it
  }

  /// The user is not typing elsewhere in the window: the window's focus is not in text outside `card` (a row being
  /// renamed, a field of the Toolbar).
  private static func userIsNotTypingElsewhere(of card: ContentCardView, in window: NSWindow) -> Bool {
    guard let text = window.firstResponder as? NSText else { return true }
    return text.isDescendant(of: card)
  }

  /// Reload on the view: the engine reloads the page; `.tabRecovered` takes the view down, and the page gets the focus
  /// unless the user is typing elsewhere in the window.
  private func reloadCrashedTab(_ tab: TabID) {
    let card = pageCards.first { crashedTabs.view(on: $0)?.tab == tab }
    let focusOnPage = card.flatMap { card in window.map { Self.userIsNotTypingElsewhere(of: card, in: $0) } } ?? false
    engine.reload(tab)
    if focusOnPage, tab == currentTab, let window, let page = engine.contentView(for: tab), page.window === window {
      window.makeFirstResponder(page)
    }
  }

  /// Close Tab on the view: what the pane's X does in a split, Cmd-W otherwise.
  private func closeCrashedTab(_ tab: TabID) {
    guard let node = nodeByTab[tab] else {
      if tab == privateTab { window?.performClose(nil) }       // a blank or incognito window's one page (#487)
      return
    }
    if let index = splitState.panes.firstIndex(of: node), splitState.split != nil {
      closePane(at: index)
    } else {
      close(node: node)
    }
  }
}
