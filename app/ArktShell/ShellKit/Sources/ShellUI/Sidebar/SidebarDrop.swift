import AppKit

extension NSPasteboard.PasteboardType {
  /// Every node of a sidebar drag (#104), newline-separated UUID strings in display order. `.sidebarNode` still
  /// carries the row the drag started on, so the drop targets that take one tab keep reading it.
  static let sidebarNodes = NSPasteboard.PasteboardType("dev.arkt.sidebar-nodes")
}

/// One displayed outline row, as the drop resolver sees it: what it is and where it sits in the source.
public struct SidebarDropRow: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case tab
    /// `expanded`: its children are shown right below it.
    case folder(expanded: Bool)
    case split
    /// A tab inside the split `split`, drawn one level in.
    case pane(split: NodeID)
    /// The line between Pinned and Today.
    case divider
  }

  public var node: NodeID?
  public var kind: Kind
  /// The location holding the node (the divider: the Space's Today).
  public var location: SidebarLocation
  /// The node's index in `location` (the divider: 0).
  public var index: Int
  /// Outline level: 0 for section rows, one more per container.
  public var level: Int

  public init(node: NodeID?, kind: Kind, location: SidebarLocation, index: Int, level: Int) {
    self.node = node; self.kind = kind; self.location = location; self.index = index; self.level = level
  }
}

/// What a sidebar drop does (#104). The window performs it; the outline only previews it.
public enum SidebarDropTarget: Equatable, Sendable {
  /// The nodes land in `location` at `index` (measured before removal, the `moveNodes` convention). Above the
  /// divider pins (GS-007), below it unpins, a Favorite dropped on the page leaves Favorites (BH-047), another
  /// Space's page moves them there (GS-012), and a folder's children list takes them (GS-009). The preview opens a
  /// gap before display row `gapBeforeRow` (the row count: after the last row), with the indicator indented to
  /// `level`.
  case insert(location: SidebarLocation, index: Int, gapBeforeRow: Int, level: Int)
  /// Dropped on a folder row: the nodes join the folder, which keeps its open or closed state (GS-009, BH-091).
  /// Where in the folder is the window's folder seam (#109).
  case folder(NodeID, row: Int)
  /// One tab dropped on a tab or split row (GS-010, BH-118): a Split View with `target`; `before` puts the dropped
  /// tab first (the row's left half).
  case split(target: NodeID, before: Bool, row: Int)
}

/// The nodes a drag carries and what the resolver needs to know about them.
public struct SidebarDragPayload: Equatable, Sendable {
  /// The dragged nodes in display order; the row the drag started on is among them.
  public var nodes: [NodeID]
  /// True when the payload is exactly one tab (only a single tab makes or joins a Split View).
  public var isSingleTab: Bool

  public init(nodes: [NodeID], isSingleTab: Bool) {
    self.nodes = nodes; self.isSingleTab = isSingleTab
  }

  /// The pasteboard form: the ids as newline-separated UUID strings.
  public var pasteboardString: String { nodes.map(\.uuidString).joined(separator: "\n") }

  /// The ids of a `.sidebarNodes` string; nil when any line is not a UUID or there is none.
  public static func nodes(fromPasteboardString string: String) -> [NodeID]? {
    let ids = string.split(separator: "\n").map { UUID(uuidString: String($0)) }
    guard !ids.isEmpty, ids.allSatisfy({ $0 != nil }) else { return nil }
    return ids.compactMap { $0 }
  }
}

/// Where a drop at a point of the outline goes (#104). Pure: the outline describes its rows and the pointer.
///
/// A node row has three bands. The top quarter inserts before the row and the bottom quarter after it (into an open
/// folder: as its first child). The middle half acts on the row itself: a folder takes the nodes, a tab or split takes
/// one dragged tab into a Split View (left half: the dragged tab first), and any other drop there inserts at the
/// nearer edge. Panes have no middle band: a drop between panes reorders or joins that split. The divider's upper
/// half ends Pinned, its lower half starts Today; below the last row is the end of Today. Drops that would put a node
/// inside itself are refused (nil). PARITY(NEEDS-RUNTIME-CHECK [I]): Arc's exact band sizes are unmeasured.
public enum SidebarDropResolver {
  /// The share of a row's height at its top and at its bottom that inserts instead of acting on the row.
  public static let edgeBand: CGFloat = 0.25

  /// The target of a drop over `row` (nil or out of range: below the last row) at `fractionY` (0 at the row's top) and
  /// `fractionX` (0 at the left edge), for `payload`, in the page of Space `space`.
  public static func target(rows: [SidebarDropRow], row: Int?, fractionY: CGFloat, fractionX: CGFloat,
                            payload: SidebarDragPayload, space: SpaceID, todayCount: Int) -> SidebarDropTarget? {
    guard let row, rows.indices.contains(row) else {
      return checked(.insert(location: .today(space), index: todayCount, gapBeforeRow: rows.count, level: 0),
                     rows: rows, payload: payload)
    }
    let info = rows[row]
    let upper = fractionY < 0.5
    let candidate: SidebarDropTarget
    switch info.kind {
    case .divider:
      candidate = upper
        ? .insert(location: .pinned(space), index: pinnedCount(rows: rows, before: row, space: space),
                  gapBeforeRow: row, level: 0)
        : .insert(location: .today(space), index: 0, gapBeforeRow: row + 1, level: 0)
    case .pane:
      candidate = edgeInsert(rows: rows, row: row, upper: upper)
    case .folder(let expanded):
      if fractionY < edgeBand {
        candidate = before(rows: rows, row: row)
      } else if fractionY > 1 - edgeBand {
        if expanded, let node = info.node {
          candidate = .insert(location: .folder(node), index: 0, gapBeforeRow: row + 1, level: info.level + 1)
        } else {
          candidate = after(rows: rows, row: row)
        }
      } else if let node = info.node {
        candidate = .folder(node, row: row)
      } else {
        candidate = edgeInsert(rows: rows, row: row, upper: upper)
      }
    case .tab, .split:
      if fractionY < edgeBand || fractionY > 1 - edgeBand || !payload.isSingleTab {
        candidate = edgeInsert(rows: rows, row: row, upper: upper)
      } else if let node = info.node, !payload.nodes.contains(node) {
        candidate = .split(target: node, before: fractionX < 0.5, row: row)
      } else {
        candidate = edgeInsert(rows: rows, row: row, upper: upper)
      }
    }
    return checked(candidate, rows: rows, payload: payload)
  }

  // MARK: Inserts

  private static func edgeInsert(rows: [SidebarDropRow], row: Int, upper: Bool) -> SidebarDropTarget {
    upper ? before(rows: rows, row: row) : after(rows: rows, row: row)
  }

  /// Before `row`, in its location.
  private static func before(rows: [SidebarDropRow], row: Int) -> SidebarDropTarget {
    let info = rows[row]
    return .insert(location: info.location, index: info.index, gapBeforeRow: row, level: info.level)
  }

  /// After `row` and everything shown under it, in its location. A split's panes stay with it: the gap opens below the
  /// last pane.
  private static func after(rows: [SidebarDropRow], row: Int) -> SidebarDropTarget {
    let info = rows[row]
    var end = row + 1
    while end < rows.count, rows[end].kind != .divider, rows[end].level > info.level { end += 1 }
    return .insert(location: info.location, index: info.index + 1, gapBeforeRow: end, level: info.level)
  }

  /// Rows of the Pinned section above the divider at `row` that sit directly in Pinned.
  private static func pinnedCount(rows: [SidebarDropRow], before row: Int, space: SpaceID) -> Int {
    rows[..<row].filter { $0.location == .pinned(space) && $0.kind != .divider }.count
  }

  // MARK: Refusals

  /// Nil when the drop would put a dragged node inside itself: onto itself, into its own folder, or between the
  /// children of a dragged container.
  private static func checked(_ target: SidebarDropTarget, rows: [SidebarDropRow],
                              payload: SidebarDragPayload) -> SidebarDropTarget? {
    let dragged = Set(payload.nodes)
    switch target {
    case .insert(let location, _, let gapRow, _):
      guard let container = location.containerNode else { return target }
      if dragged.contains(container) { return nil }
      guard let containerRow = rows[..<min(gapRow, rows.count)].lastIndex(where: { $0.node == container }) else {
        return target
      }
      return ancestors(ofRowAt: containerRow, rows: rows).isDisjoint(with: dragged) ? target : nil
    case .folder(let node, let row), .split(let node, _, let row):
      if dragged.contains(node) { return nil }
      return ancestors(ofRowAt: row, rows: rows).isDisjoint(with: dragged) ? target : nil
    }
  }

  /// The nodes of the rows that contain `row`, found upward by level.
  private static func ancestors(ofRowAt row: Int, rows: [SidebarDropRow]) -> Set<NodeID> {
    guard rows.indices.contains(row) else { return [] }
    var found: Set<NodeID> = []
    var current = rows[row].level
    var cursor = row - 1
    while current > 0, cursor >= 0 {
      if rows[cursor].level < current, rows[cursor].kind != .divider {
        if let node = rows[cursor].node { found.insert(node) }
        current = rows[cursor].level
      }
      cursor -= 1
    }
    return found
  }
}
