import CoreGraphics
import EngineAPI
import Foundation

/// A Peek that closed (the user, a new Peek, its source's close or Tab Handoff), as Cmd-Shift-T and Cmd-Z bring it
/// back (BH-150, KB-079). A tab or Space switch only hides a Peek (#348).
public struct ClosedPeek: Equatable, Sendable {
  /// An unloaded copy of the Peek's tab, made at the close, that holds its back and forward history; nil when the
  /// engine could not copy it or the copy closed since (the Peek then reopens its URL without history).
  public var parked: TabID?
  /// The sidebar row of the tab the Peek covered; nil when that tab had none.
  public var sourceNode: NodeID?
  public var url: URL
  /// The clicked link from the card's center, so a later close of the reopened Peek returns towards it.
  public var linkOffset: CGVector

  public init(parked: TabID?, sourceNode: NodeID?, url: URL, linkOffset: CGVector) {
    self.parked = parked
    self.sourceNode = sourceNode
    self.url = url
    self.linkOffset = linkOffset
  }
}

/// A sidebar row the user closed (Cmd-W, the row's X, a bulk archive; BH-074, KB-010): a Today tab or split that
/// went to the Archive, or a pinned tab or Favorite whose page closed while the row stayed.
public struct ClosedNode: Equatable, Sendable {
  public var node: NodeID
  /// The row went to the Archive (Today); it comes back through the archive record.
  public var isArchived: Bool
  /// Where the row sat when it closed, so it comes back at its place: a Today row at its index, a pane into its split
  /// (when that split still exists) at its index with `splitShare` (#403).
  public var location: SidebarLocation?
  public var index: Int?
  /// A pane's share of its split when it closed; nil for any other row.
  public var splitShare: Double?
  /// Unloaded copies of the row's pages (a split: one per pane), keyed by the tab node they belong to.
  public var parked: [NodeID: TabID]
  /// The Peek that was open over it and closed with it; both reopen together.
  public var peek: ClosedPeek?

  public init(node: NodeID, isArchived: Bool, location: SidebarLocation?, index: Int?, splitShare: Double? = nil,
              parked: [NodeID: TabID], peek: ClosedPeek? = nil) {
    self.node = node
    self.isArchived = isArchived
    self.location = location
    self.index = index
    self.splitShare = splitShare
    self.parked = parked
    self.peek = peek
  }
}

/// Several rows closed by one action (Clear, Archive Below, a multi-selection Cmd-W, an auto-archive pass): one
/// Undo and one Cmd-Z bring them all back (alerts design, decision 3). `id` names the batch for its undo toast.
public struct ClosedBatch: Equatable, Sendable {
  public var id: UUID
  /// In closing order.
  public var nodes: [ClosedNode]

  public init(id: UUID, nodes: [ClosedNode]) {
    self.id = id
    self.nodes = nodes
  }
}

/// One entry of the reopen stack.
public enum ClosedItem: Equatable, Sendable {
  case node(ClosedNode)
  case peek(ClosedPeek)
  case batch(ClosedBatch)

  /// The parked copies this item holds.
  public var parkedTabs: [TabID] {
    switch self {
    case .node(let node): node.parkedTabs
    case .peek(let peek): peek.parked.map { [$0] } ?? []
    case .batch(let batch): batch.nodes.flatMap(\.parkedTabs)
    }
  }
}

extension ClosedNode {
  /// The parked copies of its pages and of the Peek that closed with it.
  var parkedTabs: [TabID] { Array(parked.values) + (peek?.parked.map { [$0] } ?? []) }
}

/// The window's single reopen stack for closed tabs and closed Peeks (#346, #110), most recent last. Pure: the
/// window makes and closes the parked copies; the stack only says which ones it holds and which it let go.
///
/// History survives a close in a parked copy (`EngineClient.duplicateTab`) made just before the page closes, not in
/// the page kept alive: a page kept alive behind the scenes keeps playing its audio, a copy that is never shown does
/// not load (Chromium loads a cloned tab when it is first shown). Decision recorded on #346.
public struct ReopenStack: Sendable {
  /// How many closes the stack remembers. Older ones stay in the Archive. [I]
  public static let defaultCapacity = 20

  public let capacity: Int
  public private(set) var items: [ClosedItem] = []

  public init(capacity: Int = ReopenStack.defaultCapacity) {
    self.capacity = max(1, capacity)
  }

  public var isEmpty: Bool { items.isEmpty }

  /// Every parked copy, oldest item first.
  public var parkedTabs: [TabID] { items.flatMap(\.parkedTabs) }

  public func isParked(_ tab: TabID) -> Bool { items.contains { $0.parkedTabs.contains(tab) } }

  /// Open `beginBatch()` calls; while any is open nothing falls off the bottom, so a batch never loses its first rows.
  private var openBatches = 0

  /// Adds `item` on top. Returns the parked copies of the items that fell off the bottom; the caller closes them.
  public mutating func push(_ item: ClosedItem) -> [TabID] {
    items.append(item)
    return openBatches > 0 ? [] : trim()
  }

  /// Starts collecting closes for a batch; returns the mark to pass to `collapse(since:into:)`.
  public mutating func beginBatch() -> Int {
    openBatches += 1
    return items.count
  }

  /// Ends a `beginBatch()`. Returns the parked copies of the items that fell off the bottom meanwhile.
  public mutating func endBatch() -> [TabID] {
    openBatches = max(0, openBatches - 1)
    return openBatches > 0 ? [] : trim()
  }

  private mutating func trim() -> [TabID] {
    guard items.count > capacity else { return [] }
    let dropped = items.prefix(items.count - capacity)
    items.removeFirst(dropped.count)
    return dropped.flatMap(\.parkedTabs)
  }

  /// Takes the most recent item off.
  public mutating func pop() -> ClosedItem? { items.popLast() }

  /// Takes off the most recent close of `node` (its close was cancelled), also from inside a batch; an emptied batch
  /// goes too. Returns its parked copies to close.
  public mutating func remove(node: NodeID) -> [TabID] {
    for index in items.indices.reversed() {
      switch items[index] {
      case .node(let closed) where closed.node == node:
        return items.remove(at: index).parkedTabs
      case .batch(var batch):
        guard let position = batch.nodes.lastIndex(where: { $0.node == node }) else { continue }
        let removed = batch.nodes.remove(at: position)
        if batch.nodes.isEmpty { items.remove(at: index) } else { items[index] = .batch(batch) }
        return removed.parkedTabs
      default:
        continue
      }
    }
    return []
  }

  /// Puts `peek` on the most recent close of `node`, the row whose close closed it. False when there is none.
  public mutating func attach(_ peek: ClosedPeek, to node: NodeID) -> Bool {
    for index in items.indices.reversed() {
      switch items[index] {
      case .node(var closed) where closed.node == node:
        closed.peek = peek
        items[index] = .node(closed)
        return true
      case .batch(var batch):
        guard let position = batch.nodes.lastIndex(where: { $0.node == node }) else { continue }
        batch.nodes[position].peek = peek
        items[index] = .batch(batch)
        return true
      default:
        continue
      }
    }
    return false
  }

  /// Folds the row closes pushed since the stack held `mark` items into one batch named `id`, so one pop brings them
  /// all back. Peeks pushed meanwhile stay on their own, below the batch. False (and nothing changes) when no row
  /// closed.
  @discardableResult
  public mutating func collapse(since mark: Int, into id: UUID) -> Bool {
    guard mark >= 0, mark <= items.count else { return false }
    let recent = items[mark...]
    let nodes = recent.compactMap { if case .node(let closed) = $0 { closed } else { nil } }
    guard !nodes.isEmpty else { return false }
    let others = recent.filter { if case .node = $0 { false } else { true } }
    items.removeSubrange(mark...)
    items.append(contentsOf: others)
    items.append(.batch(ClosedBatch(id: id, nodes: nodes)))
    return true
  }

  /// Takes batch `id` off wherever it is (its toast's Undo); nil when it is gone.
  public mutating func remove(batch id: UUID) -> ClosedBatch? {
    guard let index = items.lastIndex(where: { if case .batch(let batch) = $0 { batch.id == id } else { false } }),
          case .batch(let batch) = items.remove(at: index) else { return nil }
    return batch
  }

  public func contains(batch id: UUID) -> Bool {
    items.contains { if case .batch(let batch) = $0 { batch.id == id } else { false } }
  }

  /// A parked copy closed on its own (its window closed): its item stays and reopens without history.
  public mutating func forget(parked tab: TabID) {
    items = items.map { item in
      switch item {
      case .node(var closed):
        closed.parked = closed.parked.filter { $0.value != tab }
        if closed.peek?.parked == tab { closed.peek?.parked = nil }
        return .node(closed)
      case .peek(var peek):
        if peek.parked == tab { peek.parked = nil }
        return .peek(peek)
      case .batch(var batch):
        batch.nodes = batch.nodes.map { closed in
          var closed = closed
          closed.parked = closed.parked.filter { $0.value != tab }
          if closed.peek?.parked == tab { closed.peek?.parked = nil }
          return closed
        }
        return .batch(batch)
      }
    }
  }
}
