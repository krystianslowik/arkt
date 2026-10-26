import AppKit
import EngineAPI

// MARK: - Little Arkt (#314)

/// The main window's side of Little Arkt's Open in: a tab from a Little Arkt window becomes a Today tab here, with
/// its page, history and state (no reload, BH-136).
extension ShellWindowController {
  /// `tab`, now in a Little Arkt window, becomes the first Today tab of `space` (the current Space when nil, a new
  /// first Space on a first run), selected, and the window comes forward with the page focused. The row and its
  /// mapping exist before the engine moves the tab, so the tab's first event here already has its row. False when
  /// the sidebar refuses the row; the tab then stays where it is.
  func receiveMovedTab(_ tab: TabID, in space: SpaceID?) -> Bool {
    guard let snapshot = engine.snapshot(of: tab) else { return false }
    let url = snapshot.url ?? Self.blankPage
    let title = snapshot.title.isEmpty ? (url.host() ?? url.absoluteString) : snapshot.title
    guard let target = space ?? currentSpace ?? createSpace() else { return false }
    let node: NodeID
    do {
      node = try sidebar.addTab(url: url, title: title, in: .today(target), at: 0)    // BH-079: the top of Today
    } catch {
      onError?(.addTab, error)
      return false
    }
    let engineWindow = ensureEngineWindow()
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    replay(snapshot, into: node)
    engine.moveTab(tab, to: engineWindow)
    if target != currentSpace { sidebarController.showSpace(target) }
    activate(node: node)
    window?.makeKeyAndOrderFront(nil)
    engine.focusPage(of: tab)
    return true
  }

  /// The Space "Open in" names: this window's current Space.
  var littleArktTargetSpace: SidebarSpaceInfo? {
    currentSpace.flatMap { sidebar.space($0) }
  }
}
