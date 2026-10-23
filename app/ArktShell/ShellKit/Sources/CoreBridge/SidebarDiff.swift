import Foundation
import ShellUI
import SidebarModel

/// The `SidebarChange`s that turn one `Sidebar` value into another, in delivery order: `.spaces`, then changed
/// sections, then changed containers by ascending depth, then nodes whose drawn presentation changed. Ties sort by
/// case rank and UUID string, so the order is deterministic.
enum SidebarDiff {
  static func changes(from old: SidebarModel.Sidebar, to new: SidebarModel.Sidebar) -> [SidebarChange] {
    var result: [SidebarChange] = []
    if old.spaceOrder != new.spaceOrder || old.spaces != new.spaces { result.append(.spaces) }

    var sections: [SidebarModel.Location] = []
    var containers: [(depth: Int, location: SidebarModel.Location)] = []
    for location in Set(old.childOrder.keys).union(new.childOrder.keys)
    where old.childOrder[location] != new.childOrder[location] {
      if let container = location.containerNode {
        guard new.nodes[container] != nil else { continue }  // removed with its parent: rows already gone
        containers.append((depth(of: container, in: new), location))
      } else {
        // A section of a removed Space: `.spaces` already drops its page, so a structure change has no rows to hit.
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
