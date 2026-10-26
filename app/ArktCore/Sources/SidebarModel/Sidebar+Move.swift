import Foundation

// MARK: - Moving a set (sidebar drag and drop, #104)

extension Sidebar {
  /// Moves `ids` into `location` as one step, in the order given, so that they land together at `index`.
  ///
  /// `index` is the proposed position measured BEFORE any of the nodes is removed, the `move(_:to:at:)` convention
  /// (an `NSOutlineView` drop's child index); it is clamped. Repeated ids move once, and a node whose ancestor is in
  /// the set moves with that ancestor. Nothing about a node changes but its place: a tab keeps its URL, titles and
  /// idle clock (`lastActiveAt`), a folder or a split keeps its children.
  ///
  /// A pane that leaves its split shrinks the split as `removePane` does: its width factor goes and the others keep
  /// their proportions, a split left with one pane is replaced by that tab (same id) at the split's place, and one
  /// left with none is removed, so no split ever keeps a single pane. A split is not a destination here (its panes
  /// go through `addPane` and `movePane`, which keep the width factors matched): `.split` throws `.invalidSplit`.
  ///
  /// Throws what `move(_:to:at:)` throws for the first node it refuses (`.unknownNode`, `.invalidDestination`,
  /// `.cycle`, `.nestingTooDeep`, `.favoritesFull` when the set does not fit). The sidebar is unchanged on throw.
  public mutating func moveNodes(_ ids: [NodeID], to location: Location, at index: Int) throws {
    if case .split(let split) = location { throw SidebarError.invalidSplit(split) }
    var seen = Set<NodeID>()
    var unique: [NodeID] = []
    for id in ids {
      guard nodes[id] != nil else { throw SidebarError.unknownNode(id) }
      if seen.insert(id).inserted { unique.append(id) }
    }
    let roots = unique.filter { !hasAncestor(of: $0, in: seen) }
    guard !roots.isEmpty else { return }
    let moving = Set(roots)
    let original = children(of: location)
    let anchor = original.prefix(min(max(index, 0), original.count)).filter { !moving.contains($0) }.count

    var copy = self
    for id in roots {
      var origin: (split: NodeID, index: Int?)?
      if case .split(let split)? = copy.nodes[id]?.parent {
        origin = (split, copy.children(of: .split(split)).firstIndex(of: id))
      }
      try copy.move(id, to: location, at: Int.max)
      if let origin { copy.shrinkSplit(origin.split, removedIndex: origin.index) }
    }
    var order = copy.children(of: location).filter { !moving.contains($0) }
    order.insert(contentsOf: roots, at: min(anchor, order.count))
    copy.reorderChildren(of: location, to: order)
    self = copy
  }

  /// Whether a container above `id` is in `set`.
  private func hasAncestor(of id: NodeID, in set: Set<NodeID>) -> Bool {
    var current = nodes[id]?.parent.containerNode
    for _ in 0...Self.maximumNestingDepth {
      guard let container = current else { return false }
      if set.contains(container) { return true }
      current = nodes[container]?.parent.containerNode
    }
    return false
  }
}
