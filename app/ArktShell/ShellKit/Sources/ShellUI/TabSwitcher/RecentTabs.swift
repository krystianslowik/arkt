import Foundation

/// The tabs one window showed, most recently viewed first (BH-007, BH-008). The switcher, Ctrl-Cmd-Right / Left
/// (BH-013) and any later "recent" surface read this one list. It belongs to the window and is not persisted.
///
/// Scope: the tabs viewed in this window, across its Spaces; tabs last viewed in another window are not listed.
/// PARITY(NEEDS-RUNTIME-CHECK RT-12): Arc's window scope.
public struct RecentTabs: Equatable, Sendable {
  /// Enough for the switcher's five rows and a long Ctrl-Cmd-Right cycle; older entries fall off.
  public static let capacity = 64

  /// Newest first.
  public private(set) var order: [NodeID] = []
  /// A running Ctrl-Cmd-Right / Left cycle: the order frozen when it started and the position it reached.
  private var cycle: Cycle?

  private struct Cycle: Equatable, Sendable {
    var order: [NodeID]
    var index: Int
    /// The tab the last step asked for; viewing any other tab ends the cycle.
    var target: NodeID
  }

  public init() {}

  /// `node` became the shown tab: it moves to the front. A tab other than the one a cycle step asked for ends the
  /// cycle, so the next Ctrl-Cmd-Right starts from the new order.
  public mutating func noteViewed(_ node: NodeID) {
    if let cycle, cycle.target != node { self.cycle = nil }
    order.removeAll { $0 == node }
    order.insert(node, at: 0)
    if order.count > Self.capacity { order.removeLast(order.count - Self.capacity) }
  }

  /// `node` closed or left the sidebar.
  public mutating func remove(_ node: NodeID) {
    order.removeAll { $0 == node }
    cycle?.order.removeAll { $0 == node }
  }

  /// Keeps only the tabs `isAlive` accepts (after a sidebar change removed nodes).
  public mutating func prune(keeping isAlive: (NodeID) -> Bool) {
    order.removeAll { !isAlive($0) }
    cycle?.order.removeAll { !isAlive($0) }
  }

  /// The switcher's rows: the most recently viewed tabs other than `current`, newest first, at most `limit`.
  public func previous(excluding current: NodeID?, limit: Int) -> [NodeID] {
    Array(order.lazy.filter { $0 != current }.prefix(limit))
  }

  /// Ctrl-Cmd-Right (`forward`) or Ctrl-Cmd-Left: the tab to show next, or nil with fewer than two tabs. Forward goes
  /// back in time (to earlier viewed tabs), backward towards the newest; both wrap. The order is frozen at the first
  /// step, so the activations a cycle causes do not reorder it. PARITY(NEEDS-RUNTIME-CHECK RT-01): assumed to follow
  /// the switcher's order, without an overlay, wrapping.
  public mutating func cycle(forward: Bool, current: NodeID?) -> NodeID? {
    var state: Cycle
    if let running = cycle, running.order.count > 1, let index = running.order.firstIndex(of: running.target),
       running.target == current {
      state = running
      state.index = index
    } else {
      var frozen = order
      if let current {
        frozen.removeAll { $0 == current }
        frozen.insert(current, at: 0)
      }
      guard frozen.count > 1 else { return nil }
      state = Cycle(order: frozen, index: 0, target: frozen[0])
    }
    let count = state.order.count
    state.index = ((state.index + (forward ? 1 : -1)) % count + count) % count
    state.target = state.order[state.index]
    cycle = state
    return state.target
  }
}
