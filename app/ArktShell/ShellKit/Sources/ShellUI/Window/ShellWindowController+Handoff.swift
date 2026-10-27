import AppKit
import EngineAPI

/// What another window of the set holds for a row (Tab Handoff, #300).
public enum LiveTabHandoff: Equatable, Sendable {
  /// No other window has a page for the row.
  case notLive
  /// Another window let go of the row's page; the caller moves it.
  /// A pending JavaScript dialog of the page travels with it (`dialog`).
  case released(TabID, dialog: JavaScriptDialog? = nil)
  /// Another window has the page and keeps it (its close is held behind a leave-site prompt).
  case held
}

// MARK: - Tab Handoff (#300, BH-066)

/// Two windows show the same Space, and a tab's page is loaded in one window at a time. Selecting a row whose page is
/// live in another window moves that page here with the engine's no-reload move (`moveTab`, #314), with its history
/// and state; the window it left shows `HandoffPlaceholderView` where it showed the page, and selecting the row there
/// moves it back. PARITY(BH-066): the move is Arc's Tab Handoff; the placeholder's wording and look are [I].
extension ShellWindowController {
  /// Maps `tab`, which another window just let go of for `node`, and moves it into this window's engine window. The
  /// caller shows it.
  func adoptHandedOffTab(_ tab: TabID, for node: NodeID, dialog: JavaScriptDialog? = nil) -> TabID {
    let target = ensureEngineWindow()
    keepsWindowWithoutEngine = false
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    // Before the move, so an end the engine reports for the move itself (a confirm or prompt of a tab that stops
    // being active, as Chromium answers a hidden tab's) finds the dialog. Its panel shows once the page is shown.
    if let dialog { javaScriptDialogs.adopt(dialog) }
    let shown = currentTab
    engineActiveTab = tab                          // the move's own activation is this window's request
    engine.moveTab(tab, to: target)
    if let shown { activateEngineTab(shown) }      // what is active here stays the shell's choice
    if let snapshot = engine.snapshot(of: tab) { replay(snapshot, into: node) }
    return tab
  }

  /// Lets go of `node`'s page for another window, which moves it next: the mappings go first, so the tab's later
  /// events reach that window only. The row stays (not loaded here); a shown page leaves the placeholder, a shown pane
  /// closes as when its page closed. The engine's next pick of an active tab here is not followed. `.notLive` for a
  /// row without a page here, `.held` for one whose close is held behind a prompt (it stays).
  func releaseLiveTab(of node: NodeID) -> LiveTabHandoff {
    guard let tab = tabsByNode[node] else { return .notLive }
    guard let snapshot = engine.snapshot(of: tab), !snapshot.isClosing else { return .held }
    tabsByNode[node] = nil
    nodeByTab[tab] = nil
    peek.sourceWillLeave(tab)                      // its hidden Peek closes here (#348)
    let dialog = javaScriptDialogs.release(tab)    // its panel goes with it; the new window shows it (#464)
    let wasCurrent = currentTab == tab
    let wasShown = visibleNodes.contains(node)
    if wasCurrent { currentTab = nil }
    if tab == engineActiveTab {
      engineActiveTab = nil
      if !tabsByNode.isEmpty { expectEngineReactivation() }
    }
    // The engine closes a window whose last tab moved out; this window stays open without one (as after New Window).
    if tabsByNode.isEmpty { keepsWindowWithoutEngine = true }
    sidebarController.deactivate(node: node)
    if wasShown { setShown(shownNodes.filter { $0 != node }) }
    if splitState.panes.contains(node) {
      paneDidClose(node, wasFocused: wasCurrent)
    } else {
      hiddenPaneDidClose(node)
    }
    if wasShown, currentTab == nil { showHandoffPlaceholder(for: node) }
    return .released(tab, dialog: dialog)
  }

  /// The card shows the placeholder for `node` until another tab is shown.
  private func showHandoffPlaceholder(for node: NodeID) {
    let placeholder = handoffPlaceholder ?? HandoffPlaceholderView(frame: .zero)
    if handoffPlaceholder == nil {
      placeholder.onMoveHere = { [weak self] node in self?.activate(node: node) }
      handoffPlaceholder = placeholder
    }
    placeholder.node = node
    hideSplit()
    rootView.card.setContent(placeholder)
    refreshAddress()
  }
}
