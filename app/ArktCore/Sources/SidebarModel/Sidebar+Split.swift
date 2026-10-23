import Foundation

// MARK: - Split operations

/// Pure split operations. They keep a split's `widthFactors` matched to its panes (`count == panes`, `sum == 1`) and
/// cap a split at `maximumSplitPanes`. Every operation leaves the sidebar unchanged on throw. None of them recurses.
extension Sidebar {
  /// New split at the place of `tabs[0]` (same location and index; BH-119), holding `tabs` in order with equal
  /// shares.
  ///
  /// Takes 2...4 distinct tab ids. Tabs may come from anywhere, including another split, which shrinks or collapses
  /// as with `removePane`. When `tabs[0]` is itself a pane, it is first separated (`separatePane`), so the new split
  /// lands right after that pane's split [I].
  ///
  /// Throws `.unknownNode` for an unknown id and `.invalidSplit` for a wrong count, a repeated id (carrying it) or a
  /// node that is not a tab (carrying it); an empty list carries a fresh id that names no node. A pane that would sit
  /// deeper than `maximumNestingDepth` throws `.nestingTooDeep` from `move`.
  @discardableResult
  public mutating func createSplit(
    of tabs: [NodeID],
    orientation: Orientation = .horizontal,
    createdAt: Date = .now
  ) throws -> NodeID {
    guard let first = tabs.first else { throw SidebarError.invalidSplit(NodeID()) }
    for id in tabs {
      guard let node = nodes[id] else { throw SidebarError.unknownNode(id) }
      guard case .tab = node.kind else { throw SidebarError.invalidSplit(id) }
    }
    var seen = Set<NodeID>()
    for id in tabs where !seen.insert(id).inserted { throw SidebarError.invalidSplit(id) }
    guard (2...Self.maximumSplitPanes).contains(tabs.count) else { throw SidebarError.invalidSplit(first) }

    var copy = self
    if case .split? = copy.nodes[first]?.parent { try copy.separatePane(first) }
    guard let anchorParent = copy.nodes[first]?.parent else { throw SidebarError.unknownNode(first) }
    let position = copy.children(of: anchorParent).firstIndex(of: first) ?? 0
    let item = SplitItem(orientation: orientation, widthFactors: Self.equalShares(tabs.count))
    let split = try copy.insert(.split(item), in: anchorParent, createdAt: createdAt)
    try copy.move(split, to: anchorParent, at: position)
    for tab in tabs { try copy.takeTab(tab, into: split, at: copy.children(of: .split(split)).count) }
    self = copy
    return split
  }

  /// Moves an existing tab into `split` at `index` (nil appends; out-of-range indexes are clamped) and makes all
  /// shares equal [I] (RT-35). A tab that was a pane of another split leaves it as with `removePane`.
  ///
  /// Throws `.splitFull` when the split already holds `maximumSplitPanes` (BH-116), `.unknownNode` for unknown ids,
  /// and `.invalidSplit` when `split` is not a split (carrying it) or `tab` is not a tab or is already one of its
  /// panes (carrying the tab).
  public mutating func addPane(_ tab: NodeID, to split: NodeID, at index: Int? = nil) throws {
    var item = try splitItem(split)
    guard let node = nodes[tab] else { throw SidebarError.unknownNode(tab) }
    guard case .tab = node.kind, node.parent != .split(split) else { throw SidebarError.invalidSplit(tab) }
    let count = children(of: .split(split)).count
    guard count < Self.maximumSplitPanes else { throw SidebarError.splitFull(split) }

    var copy = self
    try copy.takeTab(tab, into: split, at: index ?? count)
    item.widthFactors = Self.equalShares(copy.children(of: .split(split)).count)
    copy.setSplitItem(split, item)
    self = copy
  }

  /// Ctrl-Shift-- (BH-122, CF-18): the pane leaves the split, keeps its id, and lands right after the split in the
  /// split's parent [I] (RT-21). The others rescale proportionally; one survivor replaces the split, and the pane
  /// lands right after it. Throws `.unknownNode`, or `.invalidSplit` when `pane` is not a split pane.
  public mutating func separatePane(_ pane: NodeID) throws {
    let (split, index) = try paneContext(pane)
    guard let splitParent = nodes[split]?.parent else { throw SidebarError.invalidSplit(pane) }
    var copy = self
    let position = copy.children(of: splitParent).firstIndex(of: split) ?? 0
    try copy.move(pane, to: splitParent, at: position + 1)
    copy.shrinkSplit(split, removedIndex: index)
    self = copy
  }

  /// Separate All Tabs (BH-121, GS-033): the panes take the split's place, in order; the split is removed. Returns
  /// the panes in that order. Throws `.unknownNode`, or `.invalidSplit` when `split` is not a split.
  @discardableResult
  public mutating func separateSplit(_ split: NodeID) throws -> [NodeID] {
    _ = try splitItem(split)
    let panes = children(of: .split(split))
    try dissolve(split, order: panes)
    return panes
  }

  /// Expand Current Split (BH-124): `pane` stays where the split was, the others follow it in order; the split is
  /// removed. Throws `.unknownNode`, or `.invalidSplit` when `pane` is not a split pane.
  public mutating func expandPane(_ pane: NodeID) throws {
    let (split, _) = try paneContext(pane)
    try dissolve(split, order: [pane] + children(of: .split(split)).filter { $0 != pane })
  }

  /// Reorders `pane` inside its split; width factors follow their panes. `index` uses `move`'s before-removal
  /// convention and is clamped. Throws `.unknownNode`, or `.invalidSplit` when `pane` is not a split pane.
  public mutating func movePane(_ pane: NodeID, to index: Int) throws {
    let (split, oldIndex) = try paneContext(pane)
    var item = try splitItem(split)
    var copy = self
    try copy.move(pane, to: .split(split), at: index)
    if let newIndex = copy.children(of: .split(split)).firstIndex(of: pane),
      item.widthFactors.indices.contains(oldIndex)
    {
      let factor = item.widthFactors.remove(at: oldIndex)
      item.widthFactors.insert(factor, at: min(newIndex, item.widthFactors.count))
      copy.setSplitItem(split, item)
    }
    self = copy
  }

  /// Divider commit: one factor per pane, each finite and greater than 0; stored normalized to sum 1. Throws
  /// `.unknownNode`, or `.invalidSplit(split)` for a non-split or bad factors.
  public mutating func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws {
    var item = try splitItem(split)
    let total = factors.reduce(0, +)
    guard factors.count == children(of: .split(split)).count, factors.allSatisfy({ $0.isFinite && $0 > 0 }),
      total.isFinite
    else { throw SidebarError.invalidSplit(split) }
    item.widthFactors = factors.map { $0 / total }
    setSplitItem(split, item)
  }

  /// Convert to Horizontal / Vertical Split View (BH-120). Throws `.unknownNode`, or `.invalidSplit` for a
  /// non-split.
  public mutating func setSplitOrientation(_ split: NodeID, _ orientation: Orientation) throws {
    var item = try splitItem(split)
    item.orientation = orientation
    setSplitItem(split, item)
  }

  // MARK: - Helpers

  static func equalShares(_ count: Int) -> [Double] {
    Array(repeating: 1 / Double(count), count: count)
  }

  /// The payload of split `id`. Throws `.unknownNode`, or `.invalidSplit(id)` when `id` is not a split.
  private func splitItem(_ id: NodeID) throws -> SplitItem {
    guard let node = nodes[id] else { throw SidebarError.unknownNode(id) }
    guard case .split(let item) = node.kind else { throw SidebarError.invalidSplit(id) }
    return item
  }

  /// The split holding `pane` and the pane's index in it. Throws `.unknownNode`, or `.invalidSplit(pane)` when
  /// `pane` is not a pane of an existing split.
  private func paneContext(_ pane: NodeID) throws -> (split: NodeID, index: Int) {
    guard let node = nodes[pane] else { throw SidebarError.unknownNode(pane) }
    guard case .split(let split) = node.parent, case .split? = nodes[split]?.kind,
      let index = children(of: node.parent).firstIndex(of: pane)
    else { throw SidebarError.invalidSplit(pane) }
    return (split, index)
  }

  /// Moves `tab` into `split` at `index`; a tab leaving another split shrinks that split as `removePane` does.
  private mutating func takeTab(_ tab: NodeID, into split: NodeID, at index: Int) throws {
    var origin: (split: NodeID, index: Int?)?
    if case .split(let other)? = nodes[tab]?.parent, other != split {
      origin = (other, children(of: .split(other)).firstIndex(of: tab))
    }
    try move(tab, to: .split(split), at: index)
    if let origin { shrinkSplit(origin.split, removedIndex: origin.index) }
  }

  /// Moves the panes of `split` into the split's parent at its position, in `order`, then removes the split.
  private mutating func dissolve(_ split: NodeID, order: [NodeID]) throws {
    guard let parent = nodes[split]?.parent else { throw SidebarError.unknownNode(split) }
    var copy = self
    let position = copy.children(of: parent).firstIndex(of: split) ?? 0
    for (offset, pane) in order.enumerated() { try copy.move(pane, to: parent, at: position + offset) }
    copy.remove(split)
    self = copy
  }
}
