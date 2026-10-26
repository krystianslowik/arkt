import CoreGraphics
import EngineAPI
import Foundation

/// A Peek that closed (the user, a tab or Space switch, its source's close), as Cmd-Shift-T and Cmd-Z bring it back
/// (BH-150, KB-079).
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
  /// Where the row sat when it closed, so it comes back at its place.
  public var location: SidebarLocation?
  public var index: Int?
  /// Unloaded copies of the row's pages (a split: one per pane), keyed by the tab node they belong to.
  public var parked: [NodeID: TabID]
  /// The Peek that was open over it and closed with it; both reopen together.
  public var peek: ClosedPeek?

  public init(node: NodeID, isArchived: Bool, location: SidebarLocation?, index: Int?, parked: [NodeID: TabID],
              peek: ClosedPeek? = nil) {
    self.node = node
    self.isArchived = isArchived
    self.location = location
    self.index = index
    self.parked = parked
    self.peek = peek
  }
}

/// One entry of the reopen stack.
public enum ClosedItem: Equatable, Sendable {
  case node(ClosedNode)
  case peek(ClosedPeek)

  /// The parked copies this item holds.
  public var parkedTabs: [TabID] {
    switch self {
    case .node(let node): Array(node.parked.values) + (node.peek?.parked.map { [$0] } ?? [])
    case .peek(let peek): peek.parked.map { [$0] } ?? []
    }
  }
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

  /// Adds `item` on top. Returns the parked copies of the items that fell off the bottom; the caller closes them.
  public mutating func push(_ item: ClosedItem) -> [TabID] {
    items.append(item)
    guard items.count > capacity else { return [] }
    let dropped = items.prefix(items.count - capacity)
    items.removeFirst(dropped.count)
    return dropped.flatMap(\.parkedTabs)
  }

  /// Takes the most recent item off.
  public mutating func pop() -> ClosedItem? { items.popLast() }

  /// Takes off the most recent item of `node` (its close was cancelled). Returns its parked copies to close.
  public mutating func remove(node: NodeID) -> [TabID] {
    guard let index = items.lastIndex(where: { if case .node(let closed) = $0 { closed.node == node } else { false } })
    else { return [] }
    return items.remove(at: index).parkedTabs
  }

  /// Puts `peek` on the most recent item of `node`, the row whose close closed it. False when there is none.
  public mutating func attach(_ peek: ClosedPeek, to node: NodeID) -> Bool {
    guard let index = items.lastIndex(where: { if case .node(let closed) = $0 { closed.node == node } else { false } }),
          case .node(var closed) = items[index] else { return false }
    closed.peek = peek
    items[index] = .node(closed)
    return true
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
      }
    }
  }
}
