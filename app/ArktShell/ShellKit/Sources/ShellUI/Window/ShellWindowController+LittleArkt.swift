import AppKit
import EngineAPI

// MARK: - Little Arkt (#314, #352)

/// The main window's side of Little Arkt's Open in: a tab from a Little Arkt window becomes a Today tab here, with
/// its page, history and state (no reload, BH-136). Without the flight it happens at once (`receiveMovedTab`); with
/// it, the row comes first and the page at rest (`LittleArktFlightDestination`).
extension ShellWindowController: LittleArktFlightDestination {
  /// `tab`, now in a Little Arkt window, becomes the first Today tab of `space` (the current Space when nil, a new
  /// first Space on a first run), selected, and the window comes forward with the page focused. The row and its
  /// mapping exist before the engine moves the tab, so the tab's first event here already has its row. False when
  /// the sidebar refuses the row; the tab then stays where it is.
  func receiveMovedTab(_ tab: TabID, in space: SpaceID?) -> Bool {
    guard let node = beginReceiving(tab, in: space) else { return false }
    return finishReceiving(tab, node: node)
  }

  /// The row at the top of Today in `space`, mapped to `tab` (the page itself is still in the Little Arkt window),
  /// and that Space shown. Nil when the sidebar refuses the row.
  func beginReceiving(_ tab: TabID, in space: SpaceID?) -> NodeID? {
    guard let snapshot = engine.snapshot(of: tab) else { return nil }
    let url = snapshot.url ?? Self.blankPage
    let title = snapshot.title.isEmpty ? (url.host() ?? url.absoluteString) : snapshot.title
    guard let target = space ?? currentSpace ?? createSpace() else { return nil }
    let node: NodeID
    do {
      node = try sidebar.addTab(url: url, title: title, in: .today(target), at: 0)    // BH-079: the top of Today
    } catch {
      onError?(.addTab, error)
      return nil
    }
    _ = ensureEngineWindow()
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    replay(snapshot, into: node)
    if target != currentSpace { sidebarController.showSpace(target) }
    return node
  }

  /// The page moves into this window's engine window and its row is selected, mounting the page in the content card
  /// at its final size; the window becomes key with the page focused.
  func finishReceiving(_ tab: TabID, node: NodeID) -> Bool {
    guard tabsByNode[node] == tab else { return false }
    sidebarController.currentPage?.outlineController.endArrival()
    engine.moveTab(tab, to: ensureEngineWindow())
    activate(node: node)
    window?.makeKeyAndOrderFront(nil)
    engine.focusPage(of: tab)
    return true
  }

  func presentArrival(of node: NodeID, room: Double, appear: Double) {
    sidebarController.currentPage?.outlineController.presentArrival(of: node, room: room, appear: appear)
  }

  var flightWindow: NSWindow? { window }

  var flightCardFrame: CGRect? {
    rootView.layoutSubtreeIfNeeded()
    let card = rootView.card
    guard let window = card.window, !card.isHiddenOrHasHiddenAncestor else { return nil }
    return window.convertToScreen(card.convert(card.bounds, to: nil))
  }

  /// The Space "Open in" names: this window's current Space.
  var littleArktTargetSpace: SidebarSpaceInfo? {
    currentSpace.flatMap { sidebar.space($0) }
  }
}
