import Foundation

/// The sidebar's multi-selection (BH-028, GS-031): Cmd-click toggles one row, Shift-click selects the contiguous
/// range from the anchor row. The current row seeds an empty selection, so Cmd-clicking a second row selects both
/// (as the current row reads as selected already) [I]. A plain click, a Space switch or a selected row leaving the
/// outline ends it (design section 6). Rows are node ids; the outline decides which rows may be selected.
public struct SidebarSelection: Equatable, Sendable {
  /// Selected rows, in the order they joined.
  public private(set) var nodes: [NodeID] = []
  /// Where the next Shift-click range starts: the last Cmd-clicked row, or the seed of the first range.
  public private(set) var anchor: NodeID?

  public init() {}

  public var isEmpty: Bool { nodes.isEmpty }
  public var count: Int { nodes.count }
  public func contains(_ id: NodeID) -> Bool { nodes.contains(id) }

  /// Cmd-click on `id`. An empty selection first takes `seed` (the current row), unless the click is on it.
  public mutating func toggle(_ id: NodeID, seed: NodeID?) {
    if nodes.isEmpty, let seed, seed != id { nodes = [seed] }
    if let index = nodes.firstIndex(of: id) {
      nodes.remove(at: index)
    } else {
      nodes.append(id)
    }
    anchor = id
  }

  /// Shift-click on `id`: the rows of `order` from the anchor (else `seed`, else `id`) to `id`, inclusive, replace
  /// the selection. The anchor stays, so a second Shift-click moves only the far end.
  public mutating func extend(to id: NodeID, seed: NodeID?, order: [NodeID]) {
    let start = anchor ?? seed ?? id
    anchor = start
    guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: id) else {
      nodes = [id]
      return
    }
    nodes = Array(order[min(from, to)...max(from, to)])
  }

  public mutating func clear() {
    nodes = []
    anchor = nil
  }

  /// Keeps only rows for which `isKept` holds (the others left the outline); a removed anchor is forgotten.
  public mutating func retain(where isKept: (NodeID) -> Bool) {
    nodes.removeAll { !isKept($0) }
    if let anchor, !isKept(anchor) { self.anchor = nil }
  }

  /// The selected rows sorted by `order` (display order); rows missing from it go last.
  public func ordered(by order: [NodeID]) -> [NodeID] {
    let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return nodes.sorted { (position[$0] ?? .max) < (position[$1] ?? .max) }
  }

  /// The nodes a bulk action runs on: a pane stands for its whole split (so no bulk action ever tears a Split View
  /// apart), folders and unknown ids are dropped, and repeats collapse to their first place.
  @MainActor
  public static func bulkTargets(_ ids: [NodeID], in source: any SidebarSource) -> [NodeID] {
    var seen: Set<NodeID> = []
    var result: [NodeID] = []
    for id in ids {
      let target: NodeID
      switch (source.node(id), source.parent(of: id)) {
      case (.tab?, .split(let split)?): target = split
      case (.tab?, _), (.split?, _): target = id
      case (.folder?, _), (nil, _): continue
      }
      if seen.insert(target).inserted { result.append(target) }
    }
    return result
  }
}
