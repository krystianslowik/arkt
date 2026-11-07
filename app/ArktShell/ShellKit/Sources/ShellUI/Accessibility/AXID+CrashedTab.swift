// Crashed tab identifiers (#578). Kept beside `AXID.swift` while other open branches edit that file.
extension AXID {
  /// The view over a page whose process went away (`CrashedTabView`).
  public enum CrashedTab {
    public static let root = "crashedTab.root"
    public static let reload = "crashedTab.reload"
    public static let closeTab = "crashedTab.closeTab"
  }
}
