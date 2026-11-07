// Find in page identifiers (#134). Kept beside `AXID.swift` like the other late groups; no imports, like it.
extension AXID {
  /// The find bar over the top trailing corner of the page (`FindBarView`); absent while no bar shows.
  public enum Find {
    /// Label: "Find in page"; role: group (search).
    public static let root = "find.root"
    public static let field = "find.field"
    /// Value: "3 of 12" or "No matches"; empty before a search.
    public static let count = "find.count"
    public static let previous = "find.previous"
    public static let next = "find.next"
    public static let close = "find.close"
  }
}
