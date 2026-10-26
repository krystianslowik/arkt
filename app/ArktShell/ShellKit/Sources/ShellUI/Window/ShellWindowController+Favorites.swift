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
    sidebarController.onSidebarDrop = { [weak self] node, location in
      self?.move(node, to: location) ?? false
    }
    sidebarController.onFavoriteUnload = { [weak self] node in self?.close(node: node) }
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

  /// A pinned or Favorite node never ages (BH-054, BH-048), so its `lastActiveAt` can be days old: once in Today
  /// the idle timer would archive it on its next pass. Leaving its section restarts the clock of every tab it holds
  /// (a split's panes), through the same stamp a tab leaving the content area gets (decision 10).
  private func didEnterToday(_ node: NodeID) {
    for tab in tabs(in: node) { onTabHidden?(tab) }
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
