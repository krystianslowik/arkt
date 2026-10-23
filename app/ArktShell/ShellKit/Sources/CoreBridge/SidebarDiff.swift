import Foundation
import ShellUI
import SidebarModel

/// The `SidebarChange`s that turn one `Sidebar` value into another, in delivery order: Space events (removed in the
/// old order, then added, moved and changed in the new order), then changed sections, then changed containers by
/// ascending depth, then nodes whose drawn presentation changed. Ties sort by case rank and UUID string, so the
/// order is deterministic.
enum SidebarDiff {
  static func changes(from old: SidebarModel.Sidebar, to new: SidebarModel.Sidebar) -> [SidebarChange] {
    var result = spaceChanges(from: old, to: new)

    var sections: [SidebarModel.Location] = []
    var containers: [(depth: Int, location: SidebarModel.Location)] = []
    for location in Set(old.childOrder.keys).union(new.childOrder.keys)
    where old.childOrder[location] != new.childOrder[location] {
      if let container = location.containerNode {
        guard new.nodes[container] != nil else { continue }  // removed with its parent: rows already gone
        containers.append((depth(of: container, in: new), location))
      } else {
        // A section of a removed Space: `.spaceRemoved` already drops its page, so a structure change has no rows
        // to hit.
        if let space = location.sectionSpace, new.spaces[space] == nil { continue }
        sections.append(location)
      }
    }
    result += sections.sorted { key($0) < key($1) }.map { .structure(BridgeMapping.location($0)) }
    result += containers
      .map { container -> (order: (Int, Int, String), location: SidebarModel.Location) in
        let key = key(container.location)
        return ((container.depth, key.rank, key.id), container.location)
      }
      .sorted { $0.order < $1.order }
      .map { .structure(BridgeMapping.location($0.location)) }

    var nodeChanges: [UUID] = []
    for (id, node) in new.nodes {
      guard let before = old.nodes[id], before != node else { continue }
      if BridgeMapping.nodeInfo(before) != BridgeMapping.nodeInfo(node) { nodeChanges.append(id) }
    }
    result += nodeChanges.sorted { $0.uuidString < $1.uuidString }.map { .node($0) }
    return result
  }

  /// `.spaceMoved` goes to the Spaces outside a longest run that kept its relative order, so a drag reports the one
  /// dragged Space and an add or a removal alone (which only shifts indexes) reports none.
  private static func spaceChanges(from old: SidebarModel.Sidebar, to new: SidebarModel.Sidebar) -> [SidebarChange] {
    guard old.spaceOrder != new.spaceOrder || old.spaces != new.spaces else { return [] }
    let removed = old.spaceOrder.filter { new.spaces[$0] == nil }
    let added = new.spaceOrder.filter { old.spaces[$0] == nil }
    let oldIndex = Dictionary(uniqueKeysWithValues: old.spaceOrder.enumerated().map { ($1, $0) })
    let kept = new.spaceOrder.compactMap { id in oldIndex[id].map { (id: id, oldIndex: $0) } }
    let stayed = longestIncreasingRun(kept.map(\.oldIndex))
    let moved = kept.indices.filter { !stayed.contains($0) }.map { kept[$0].id }
    let changed = new.spaceOrder.filter { id in old.spaces[id].map { $0 != new.spaces[id] } ?? false }
    return removed.map { .spaceRemoved($0) } + added.map { .spaceAdded($0) } + moved.map { .spaceMoved($0) }
      + changed.map { .spaceChanged($0) }
  }

  /// Positions in `values` of one longest strictly increasing subsequence. O(n^2), for Space counts.
  private static func longestIncreasingRun(_ values: [Int]) -> Set<Int> {
    guard !values.isEmpty else { return [] }
    var length = [Int](repeating: 1, count: values.count)
    var previous = [Int?](repeating: nil, count: values.count)
    for i in values.indices {
      for j in 0..<i where values[j] < values[i] && length[j] + 1 > length[i] {
        length[i] = length[j] + 1
        previous[i] = j
      }
    }
    var result: Set<Int> = []
    var current = length.indices.max { length[$0] < length[$1] }
    while let index = current {
      result.insert(index)
      current = previous[index]
    }
    return result
  }

  /// Depth of a node: 1 directly in a section, one more per enclosing container.
  private static func depth(of id: UUID, in sidebar: SidebarModel.Sidebar) -> Int {
    var depth = 1
    var current = sidebar.nodes[id]?.parent.containerNode
    while let container = current, depth <= SidebarModel.Sidebar.maximumNestingDepth {
      depth += 1
      current = sidebar.nodes[container]?.parent.containerNode
    }
    return depth
  }

  /// Sort key: case rank (favorites, pinned, today, folder, split), then the profile or id string.
  private static func key(_ location: SidebarModel.Location) -> (rank: Int, id: String) {
    switch location {
    case .favorites(let profile): (0, profile)
    case .pinned(let id): (1, id.uuidString)
    case .today(let id): (2, id.uuidString)
    case .folder(let id): (3, id.uuidString)
    case .split(let id): (4, id.uuidString)
    }
  }
}

private extension SidebarModel.Location {
  /// The Space of a Pinned or Today section; nil for Favorites and containers.
  var sectionSpace: UUID? {
    switch self {
    case .pinned(let id), .today(let id): id
    case .favorites, .folder, .split: nil
    }
  }
}
