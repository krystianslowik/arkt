import AppKit

// MARK: - Sidebar drag and drop (#104)

/// The window side of sidebar drag and drop: every drop on a Space page becomes source writes here, through the
/// same paths the menus use, so a drag can never do what a menu would refuse.
///
/// - A move goes through `move(_:to:at:)` (one write for the set): a node arriving in Today takes its page's live
///   URL and restarts its idle clock (`didEnterToday`), so neither a stale pinned URL nor an old clock survives.
/// - Panes reach a split only through `addToSplit` and `movePane`, and leave it through `moveNodes`, which shrinks
///   the split: no drag ever leaves a one-pane split.
/// - The shown tab moved to another Space stays shown (the window follows it), so no automatic pass takes it for a
///   hidden, idle tab.
extension ShellWindowController {
  func wireSidebarDrop() {
    sidebarController.onSidebarDropRequest = { [weak self] request in self?.performSidebarDrop(request) ?? false }
    sidebarController.onSidebarTextDrop = { [weak self] url, title, placement in
      self?.openDroppedLink(url, title: title, at: placement) ?? false
    }
    sidebarController.onSidebarDragOut = { [weak self] node, point in self?.onDragOutToNewWindow?(node, point) }
  }

  /// Performs `request`; false when it was refused (the failure reports through `onError`).
  @discardableResult
  func performSidebarDrop(_ request: SidebarDropRequest) -> Bool {
    let nodes = Self.moveTargets(request.nodes, in: sidebar)
    guard !nodes.isEmpty else { return false }
    switch request.target {
    case .split(let target, let before, _):
      guard !request.duplicate, nodes.count == 1, case .tab? = sidebar.node(nodes[0]) else { return false }
      let isSplit = if case .split? = sidebar.node(target) { true } else { false }
      return joinSplit(nodes[0], target: target, at: before ? 0 : (isSplit ? Int.max : 1))
    case .folder(let folder, _):
      let placement = folderDropPlacement(folder)
      return place(nodes, request, in: placement.location,
                   at: placement.index ?? sidebar.children(of: placement.location).count)
    case .insert(let location, let index, _, _):
      if case .split(let split) = location {
        guard !request.duplicate, nodes.count == 1, case .tab? = sidebar.node(nodes[0]) else { return false }
        return joinSplit(nodes[0], target: split, at: index)
      }
      return place(nodes, request, in: location, at: index)
    }
  }

  /// Moves (or, for an Opt-drag, copies) `nodes` to `location` at `index`, then keeps the right tab on screen.
  private func place(_ nodes: [NodeID], _ request: SidebarDropRequest, in location: SidebarLocation, at index: Int)
    -> Bool {
    let current = currentNode
    let movedCurrent = current.map { current in nodes.contains { tabs(in: $0).contains(current) } } ?? false
    if request.duplicate {
      return placeCopies(of: nodes, in: location, at: index)
    }
    guard move(nodes, to: location, at: index) else { return false }
    if request.fromOtherWindow, let first = nodes.first {
      activate(node: first)                        // this window takes the page over (#300)
    } else if movedCurrent, let current {
      activate(node: current)                      // the window follows the shown tab to its new place
    }
    return true
  }

  /// GS-014: a copy of each node lands at the target; the originals stay. The index is re-read after copying,
  /// because each copy first lands right after its original.
  private func placeCopies(of nodes: [NodeID], in location: SidebarLocation, at index: Int) -> Bool {
    let before = sidebar.children(of: location)
    let anchor = index < before.count ? before[max(index, 0)] : nil
    var copies: [NodeID] = []
    for node in nodes {
      do { copies.append(try sidebar.duplicateNode(node)) } catch {
        onError?(.moveNode, error)
        return false
      }
    }
    let after = sidebar.children(of: location)
    let target = anchor.flatMap { after.firstIndex(of: $0) } ?? after.count
    return move(copies, to: location, at: target)
  }

  /// GS-010, BH-118: `node` joins `target`'s split, or makes one with the tab `target`; it is shown with its split.
  /// A pane dropped among its own split's panes reorders them.
  private func joinSplit(_ node: NodeID, target: NodeID, at index: Int) -> Bool {
    if case .split(let split)? = sidebar.parent(of: node), split == target {
      do { try sidebar.movePane(node, to: index) } catch {
        onError?(.editSplit, error)
        return false
      }
      activate(node: node)
      return true
    }
    let joined = enteringToday([node]) {             // a pin joining a Today split becomes a Today tab
      do {
        try sidebar.addToSplit(.existing(node), target: target, at: index, orientation: .horizontal)
        return true
      } catch {
        onError?(.addPane, error)
        return false
      }
    }
    guard joined else { return false }
    activate(node: node)
    return true
  }

  /// GS-015: a new tab for dropped text or a link where the indicator stood, shown at once.
  private func openDroppedLink(_ url: URL, title: String, at placement: SidebarDropPlacement) -> Bool {
    do {
      let node = try sidebar.addTab(url: url, title: title, in: placement.location, at: placement.index)
      activate(node: node)
      announceCreation(.tab)                       // BH-006
      return true
    } catch {
      onError?(.addTab, error)
      return false
    }
  }
}
