import CoreGraphics
import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// The window's reopen stack (#346, #110: BH-074, BH-150, KB-010, KB-011): one list for closed tabs and closed Peeks,
/// most recent first, holding the parked copies that keep each page's history.
struct ReopenStackTests {
  private static let url = URL(string: "https://atlas.example/lisbon")!

  private static func node(_ id: NodeID = UUID(), parked: [NodeID: TabID] = [:], archived: Bool = true) -> ClosedNode {
    ClosedNode(node: id, isArchived: archived, location: .today(UUID()), index: 2, parked: parked)
  }

  private static func peek(parked: TabID? = TabID(), source: NodeID? = UUID()) -> ClosedPeek {
    ClosedPeek(parked: parked, sourceNode: source, url: url, linkOffset: CGVector(dx: 10, dy: -4))
  }

  @Test func `the most recent close comes back first and repeating walks back`() {
    var stack = ReopenStack()
    let first = Self.node()
    let second = Self.peek()
    #expect(stack.push(.node(first)).isEmpty)
    #expect(stack.push(.peek(second)).isEmpty)
    #expect(stack.pop() == .peek(second))
    #expect(stack.pop() == .node(first))
    #expect(stack.pop() == nil)
    #expect(stack.isEmpty)
  }

  @Test func `a full stack drops its oldest item and hands back that item's parked tabs`() {
    var stack = ReopenStack(capacity: 2)
    let oldTab = TabID()
    let oldPeekTab = TabID()
    var oldest = Self.node(parked: [UUID(): oldTab])
    oldest.peek = Self.peek(parked: oldPeekTab)
    _ = stack.push(.node(oldest))
    _ = stack.push(.peek(Self.peek()))
    let evicted = stack.push(.peek(Self.peek()))
    #expect(Set(evicted) == [oldTab, oldPeekTab])
    #expect(stack.items.count == 2)
    #expect(!stack.items.contains(.node(oldest)))
  }

  @Test func `every parked tab is listed and a closed one is forgotten`() {
    var stack = ReopenStack()
    let pane = UUID()
    let paneTab = TabID()
    let peekTab = TabID()
    _ = stack.push(.node(Self.node(parked: [pane: paneTab])))
    _ = stack.push(.peek(Self.peek(parked: peekTab)))
    #expect(stack.parkedTabs == [paneTab, peekTab])
    #expect(stack.isParked(peekTab))

    stack.forget(parked: peekTab)
    stack.forget(parked: paneTab)
    #expect(stack.parkedTabs.isEmpty)
    #expect(stack.items.count == 2, "the items stay: they reopen without history")
    guard case .peek(let peek)? = stack.items.last else { Issue.record("the Peek is still on top"); return }
    #expect(peek.parked == nil)
  }

  /// A close the user cancelled at a leave-site prompt never happened: its item goes, with its parked copies.
  @Test func `a cancelled close takes its item off the stack`() {
    var stack = ReopenStack()
    let kept = Self.node()
    let cancelledTab = TabID()
    let cancelled = Self.node(parked: [UUID(): cancelledTab])
    _ = stack.push(.node(kept))
    _ = stack.push(.node(cancelled))
    #expect(stack.remove(node: cancelled.node) == [cancelledTab])
    #expect(stack.items == [.node(kept)])
    #expect(stack.remove(node: UUID()).isEmpty)
  }

  /// Closing the source tab closes its Peek; both come back together.
  @Test func `a Peek closed with its source rides on the source's item`() {
    var stack = ReopenStack()
    let source = Self.node()
    _ = stack.push(.node(source))
    _ = stack.push(.node(Self.node()))
    let peek = Self.peek(source: source.node)
    let attached = stack.attach(peek, to: source.node)
    #expect(attached)
    #expect(stack.items.count == 2)
    guard case .node(let carrier)? = stack.items.first else { Issue.record("the source item stays in place"); return }
    #expect(carrier.peek == peek)
    let stray = stack.attach(peek, to: UUID())
    #expect(!stray, "no item for that row")
  }

  @Test func `the default capacity is twenty`() {
    #expect(ReopenStack.defaultCapacity == 20)
  }

  // MARK: Batches (alerts design, decision 3: one Undo for a bulk archive)

  @Test func `closes pushed since a mark become one batch that comes back in one pop`() {
    var stack = ReopenStack()
    let before = Self.peek()
    _ = stack.push(.peek(before))
    let mark = stack.items.count
    let (a, b) = (Self.node(), Self.node())
    _ = stack.push(.node(a))
    _ = stack.push(.node(b))
    let id = UUID()
    let changed = stack.collapse(since: mark, into: id)
    #expect(changed)
    #expect(stack.items.count == 2)
    #expect(stack.pop() == .batch(ClosedBatch(id: id, nodes: [a, b])))
    #expect(stack.pop() == .peek(before))
  }

  @Test func `no close makes no batch, and one close makes a batch of one`() {
    var stack = ReopenStack()
    let peek = Self.peek()
    _ = stack.push(.peek(peek))
    let unchanged = stack.collapse(since: 1, into: UUID())
    #expect(!unchanged)
    #expect(stack.items == [.peek(peek)])
    let a = Self.node()
    _ = stack.push(.node(a))
    let id = UUID()
    let changed = stack.collapse(since: 1, into: id)
    #expect(changed)
    #expect(stack.items == [.peek(peek), .batch(ClosedBatch(id: id, nodes: [a]))])
  }

  @Test func `a batch is taken by its id even below a later close`() {
    var stack = ReopenStack()
    let (a, b, later) = (Self.node(), Self.node(), Self.node())
    _ = stack.push(.node(a))
    _ = stack.push(.node(b))
    let id = UUID()
    _ = stack.collapse(since: 0, into: id)
    _ = stack.push(.node(later))
    #expect(stack.remove(batch: id) == ClosedBatch(id: id, nodes: [a, b]))
    #expect(stack.items == [.node(later)])
    #expect(stack.remove(batch: id) == nil)
    #expect(stack.contains(batch: UUID()) == false)
  }

  @Test func `a cancelled close inside a batch leaves the rest of the batch`() {
    var stack = ReopenStack()
    let tab = TabID()
    let (a, b) = (Self.node(parked: [UUID(): tab]), Self.node())
    _ = stack.push(.node(a))
    _ = stack.push(.node(b))
    let id = UUID()
    _ = stack.collapse(since: 0, into: id)
    #expect(stack.remove(node: a.node) == [tab])
    #expect(stack.items == [.batch(ClosedBatch(id: id, nodes: [b]))])
    #expect(stack.remove(node: b.node).isEmpty)
    #expect(stack.isEmpty, "an emptied batch goes away")
  }

  @Test func `a peek attaches to its source inside a batch and parked tabs are seen there`() {
    var stack = ReopenStack()
    let tab = TabID()
    let (a, b) = (Self.node(parked: [UUID(): tab]), Self.node())
    _ = stack.push(.node(a))
    _ = stack.push(.node(b))
    _ = stack.collapse(since: 0, into: UUID())
    let peek = Self.peek(source: b.node)
    let changed = stack.attach(peek, to: b.node)
    #expect(changed)
    #expect(stack.isParked(tab))
    #expect(Set(stack.parkedTabs) == Set([tab, peek.parked!]))
    stack.forget(parked: tab)
    #expect(!stack.isParked(tab))
  }

  @Test func `nothing falls off the bottom while a batch is open`() {
    var stack = ReopenStack(capacity: 1)
    let oldTab = TabID()
    _ = stack.push(.node(Self.node(parked: [UUID(): oldTab])))
    let mark = stack.beginBatch()
    let batch = (0..<3).map { _ in Self.node() }
    for node in batch { #expect(stack.push(.node(node)).isEmpty) }
    let id = UUID()
    let changed = stack.collapse(since: mark, into: id)
    #expect(changed)
    #expect(stack.endBatch() == [oldTab])
    #expect(stack.items == [.batch(ClosedBatch(id: id, nodes: batch))])
  }
}
