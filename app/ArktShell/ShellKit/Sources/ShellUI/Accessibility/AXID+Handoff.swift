// Tab Handoff identifiers (#300, BH-066). Kept beside `AXID.swift` while other open branches edit that file.
extension AXID {
  /// The placeholder a window shows where a page it showed moved to another window (`HandoffPlaceholderView`).
  public enum Handoff {
    public static let placeholder = "handoff.placeholder"
    public static let moveHere = "handoff.moveHere"
  }
}
