import Foundation
import Testing
@testable import ShellUI

/// The per-window list of recently viewed tabs behind the switcher (BH-007, BH-008) and Ctrl-Cmd-Right / Left
/// (BH-013, KB-026, KB-027).
struct RecentTabsTests {
  private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

  private func viewed(_ nodes: [UUID]) -> RecentTabs {
    var recent = RecentTabs()
    for node in nodes { recent.noteViewed(node) }
    return recent
  }

  @Test func `viewing a tab moves it to the front`() {
    var recent = viewed([a, b, c])
    #expect(recent.order == [c, b, a])
    recent.noteViewed(a)
    #expect(recent.order == [a, c, b])
  }

  @Test func `the previous tabs leave out the current one and stop at the limit`() {
    let recent = viewed([a, b, c, d])
    #expect(recent.previous(excluding: d, limit: 2) == [c, b])
    #expect(recent.previous(excluding: b, limit: 5) == [d, c, a])
    #expect(recent.previous(excluding: nil, limit: 5) == [d, c, b, a])
  }

  @Test func `one viewed tab has no previous tab`() {
    #expect(viewed([a]).previous(excluding: a, limit: 5).isEmpty)
  }

  @Test func `a removed or pruned tab leaves the list`() {
    var recent = viewed([a, b, c, d])
    recent.remove(b)
    #expect(recent.order == [d, c, a])
    recent.prune { $0 != c }
    #expect(recent.order == [d, a])
  }

  @Test func `the list keeps at most its capacity`() {
    var recent = RecentTabs()
    let nodes = (0..<(RecentTabs.capacity + 3)).map { _ in UUID() }
    for node in nodes { recent.noteViewed(node) }
    #expect(recent.order.count == RecentTabs.capacity)
    #expect(recent.order.first == nodes.last)
  }

  // MARK: Ctrl-Cmd-Right / Left (RT-01 assumed: the switcher's order, no overlay, wraps)

  @Test func `cycling forward walks back through earlier tabs and wraps`() {
    var recent = viewed([a, b, c])                 // c is current
    let first = recent.cycle(forward: true, current: c)
    #expect(first == b)
    recent.noteViewed(b)
    let second = recent.cycle(forward: true, current: b)
    #expect(second == a)
    recent.noteViewed(a)
    let third = recent.cycle(forward: true, current: a)
    #expect(third == c, "wraps to the tab the cycle started on")
  }

  @Test func `cycling backward from the start wraps to the oldest tab`() {
    var recent = viewed([a, b, c])
    let result = recent.cycle(forward: false, current: c)
    #expect(result == a)
  }

  @Test func `a cycle keeps its order while its own activations reorder the list`() {
    var recent = viewed([a, b, c])
    let target = recent.cycle(forward: true, current: c)
    #expect(target == b)
    recent.noteViewed(b)
    #expect(recent.order == [b, c, a])
    let result = recent.cycle(forward: false, current: b)
    #expect(result == c, "backward returns along the frozen order")
  }

  @Test func `viewing another tab ends the cycle`() {
    var recent = viewed([a, b, c])
    let result = recent.cycle(forward: true, current: c)
    #expect(result == b)
    recent.noteViewed(b)
    recent.noteViewed(d)                           // a click, not the cycle
    let next = recent.cycle(forward: true, current: d)
    #expect(next == b, "a new cycle starts from the new order")
  }

  @Test func `cycling with fewer than two tabs does nothing`() {
    var recent = viewed([a])
    let result = recent.cycle(forward: true, current: a)
    #expect(result == nil)
  }

  @Test func `a cycle skips tabs that left the list`() {
    var recent = viewed([a, b, c])
    let result = recent.cycle(forward: true, current: c)
    #expect(result == b)
    recent.noteViewed(b)
    recent.remove(a)
    let next = recent.cycle(forward: true, current: b)
    #expect(next == c)
  }
}
