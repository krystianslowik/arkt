import AppKit

/// The window side of Favorites add and remove (BH-046, BH-047): "Move To > Favorites", the sidebar drop, and
/// the BH-049 unload. Every add lands appended; a refusal reports `.moveNode` ("Favorites are full." on a full
/// section).
extension ShellWindowController {
  /// Wires the sidebar's Favorites entry points.
  func wireFavorites() {
    sidebarController.onMoveToFavorites = { [weak self] node in
      guard let self else { return }
      self.move(node, to: .favorites(profile: self.sidebarController.profile))
    }
    sidebarController.onSidebarDrop = { [weak self] node, location in   // the band: the whole dragged set (#105)
      guard let self else { return false }
      let dragged = self.sidebarController.dragNodes
      let nodes = dragged.contains(node) ? Self.moveTargets(dragged, in: self.sidebar) : [node]
      return self.move(nodes, to: location, at: self.sidebar.children(of: location).count)
    }
    sidebarController.onFavoriteUnload = { [weak self] node in self?.close(node: node) }
  }

  // MARK: Command bar (BH-047, #340)

  static let favoriteTabActionID = "favoriteTab"
  static let moveToFavoritesActionID = "moveToFavorites"

  /// The command bar's "Favorite Tab" and "Move To Favorites" (BH-047): listed only while the current tab can be
  /// favorited.
  func favoriteCommandBarActions() -> [CommandBarAction] {
    guard favoritableCurrentNode() != nil else { return [] }
    return [
      CommandBarAction(id: Self.favoriteTabActionID, title: "Favorite Tab"),
      CommandBarAction(id: Self.moveToFavoritesActionID, title: "Move To Favorites"),
    ]
  }

  /// Both command bar actions: appends the current tab to Favorites, as "Move To > Favorites" on its row does. A
  /// refusal reports `.moveNode` ("Favorites are full." on a full section).
  func favoriteCurrentTab() {
    guard let node = favoritableCurrentNode() else { return }
    move(node, to: .favorites(profile: sidebarController.profile))
  }

  /// What favoriting the current tab moves: the tab, or its whole split for a pane (a pane never leaves its split
  /// this way, as its row has no Move To). Nil without a current tab or when it already is a Favorite.
  private func favoritableCurrentNode() -> NodeID? {
    guard let node = currentNode else { return nil }
    if case .favorites? = sidebar.section(containing: node) { return nil }
    if case .split(let split)? = sidebar.parent(of: node) { return split }
    return node
  }

  /// Moves `node` to `location` at `index` (nil appends). False when the model refused; the failure reports
  /// `.moveNode`. A node arriving in Today from another section (an unpin, a Favorite dragged down) becomes an
  /// ordinary Today item: see `didEnterToday(_:)`.
  @discardableResult
  func move(_ node: NodeID, to location: SidebarLocation, at index: Int? = nil) -> Bool {
    let enteringToday = Self.isToday(location) && !Self.isToday(sidebar.section(containing: node))
    do {
      try sidebar.moveNode(node, to: location, at: index ?? sidebar.children(of: location).count)
    } catch {
      onError?(.moveNode, error)
      return false
    }
    if enteringToday { didEnterToday(node) }
    return true
  }

  /// Moves a dragged set (#104) as one source write: `nodes` land together at `index` (measured before removal).
  /// Every node arriving in Today from another section goes through `didEnterToday(_:)`, as one moved alone does.
  @discardableResult
  func move(_ nodes: [NodeID], to location: SidebarLocation, at index: Int) -> Bool {
    enteringToday(nodes) {
      do {
        try sidebar.moveNodes(nodes, to: location, at: index)
        return true
      } catch {
        onError?(.moveNode, error)
        return false
      }
    }
  }

  /// Runs `write`, then sends each of `nodes` that it brought into Today from another section, directly or inside a
  /// folder or a split, through `didEnterToday(_:)`. Returns what `write` returns.
  func enteringToday(_ nodes: [NodeID], _ write: () -> Bool) -> Bool {
    let outside = nodes.filter { !Self.isToday(sidebar.section(containing: $0)) }
    guard write() else { return false }
    for node in outside where Self.isToday(sidebar.section(containing: node)) { didEnterToday(node) }
    return true
  }

  /// A pinned or Favorite node never ages (BH-054, BH-048) and keeps its pinned URL on navigation (BH-057), so
  /// once in Today it could be archived on the next idle pass, or come back at the pinned URL after a relaunch.
  /// For every tab it holds (a split's panes), the node takes the loaded page's URL and its idle clock restarts,
  /// through the same stamp a tab leaving the content area gets (decision 10).
  private func didEnterToday(_ node: NodeID) {
    for tab in tabs(in: node) {
      if case .tab(_, let stored, _)? = sidebar.node(tab),
         let live = tabsByNode[tab].flatMap({ engine.snapshot(of: $0)?.url }), live != stored {
        sidebar.updateTab(tab, url: live, title: nil)
      }
      onTabHidden?(tab)
    }
  }

  /// `node` itself when it is a tab, else every tab below it (a split's panes, a folder's tabs).
  func tabs(in node: NodeID) -> [NodeID] {
    switch sidebar.node(node) {
    case .tab?:
      return [node]
    case let container?:
      guard let inner = container.childLocation else { return [] }
      return sidebar.children(of: inner).flatMap { tabs(in: $0) }
    case nil:
      return []
    }
  }

  private static func isToday(_ location: SidebarLocation?) -> Bool {
    if case .today? = location { true } else { false }
  }
}
