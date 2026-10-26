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
}
