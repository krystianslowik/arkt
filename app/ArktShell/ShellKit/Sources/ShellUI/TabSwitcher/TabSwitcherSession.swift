import Foundation

/// The open switcher: its rows (newest first) and the highlighted one (BH-008 to BH-010). Pure state; the view and
/// the window controller follow it.
public struct TabSwitcherSession: Equatable, Sendable {
  public enum Direction: Equatable, Sendable {
    case forward, backward
  }

  /// The five most recently viewed tabs (BH-008). PARITY(NEEDS-RUNTIME-CHECK): whether Arc ever lists more.
  public static let maximumRows = 5

  public private(set) var rows: [NodeID]
  public private(set) var highlight: Int

  /// Nil without rows (fewer than two viewed tabs: Ctrl-Tab does nothing). Opening forward highlights the first row
  /// (the previous tab, BH-007); backward, one step back from the current tab, the last.
  public init?(rows: [NodeID], direction: Direction) {
    let rows = Array(rows.prefix(Self.maximumRows))
    guard !rows.isEmpty else { return nil }
    self.rows = rows
    highlight = direction == .forward ? 0 : rows.count - 1
  }

  public var highlighted: NodeID { rows[highlight] }

  /// Tab, Shift-Tab or Ctrl-`: one row down or up, wrapping at both ends (BH-008, BH-009).
  public mutating func move(_ direction: Direction) {
    let step = direction == .forward ? 1 : -1
    highlight = ((highlight + step) % rows.count + rows.count) % rows.count
  }

  /// Drops `node`'s row (closed with W, or removed elsewhere). The highlight stays on its tab, or, when that row
  /// went, on the row that took its place (the next most recent), else the new last row. Returns true when no row is
  /// left; an unknown tab changes nothing.
  @discardableResult
  public mutating func remove(_ node: NodeID) -> Bool {
    guard let index = rows.firstIndex(of: node) else { return rows.isEmpty }
    rows.remove(at: index)
    guard !rows.isEmpty else {
      highlight = 0
      return true
    }
    if index < highlight { highlight -= 1 }
    highlight = min(highlight, rows.count - 1)
    return false
  }
}
