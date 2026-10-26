import Foundation

/// Which of a Space's top-level Today rows Clear archives (BH-075, BH-078) and which stay because their page plays
/// media (BH-076) or is shown in a window (#429, maintainer decision over BH-075). Pure list rules so both the window and the tests can ask without a sidebar.
public enum TodayClearPolicy {
  /// The rows a Clear takes.
  public enum Scope: Equatable, Sendable {
    /// Clear Today Tabs (BH-075, KB-019): every row.
    case all
    /// Clear unselected Today tabs (BH-078): rows with nothing selected stay.
    case unselected
  }

  /// `rows` in their own order, without the rows that stay: a row playing media stays in every scope (BH-076), and
  /// so does a row shown in a window (#429: the tab this window shows, both panes of a Split View, and whatever another
  /// window shows); under `.unselected` a row holding a selected row stays too. `isSelected`, `playsMedia` and
  /// `isShown` answer for the row and everything inside it (a folder's tabs, a split's panes).
  public static func rows(_ rows: [NodeID], scope: Scope,
                          isSelected: (NodeID) -> Bool, playsMedia: (NodeID) -> Bool,
                          isShown: (NodeID) -> Bool = { _ in false }) -> [NodeID] {
    rows.filter { row in
      guard !playsMedia(row), !isShown(row) else { return false }
      return scope == .all || !isSelected(row)
    }
  }
}
