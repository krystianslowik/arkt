import AppKit

/// The window side of Favorites add and remove (BH-046, BH-047): "Move To > Favorites" and the sidebar drop.
/// Every add lands appended; a refusal reports `.moveNode` ("Favorites are full." on a full section).
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
  }

  /// Moves `node` to `location`, appended. False when the model refused; the failure reports `.moveNode`.
  @discardableResult
  func move(_ node: NodeID, to location: SidebarLocation) -> Bool {
    do {
      try sidebar.moveNode(node, to: location, at: sidebar.children(of: location).count)
      return true
    } catch {
      onError?(.moveNode, error)
      return false
    }
  }
}
