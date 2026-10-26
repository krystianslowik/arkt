// Little Arkt identifiers (#314). Kept beside `AXID.swift` while other open branches edit that file; no imports.
extension AXID {
  /// The Little Arkt window (`LittleArktWindowController`).
  public enum LittleArkt {
    public static let window = "littleArkt.window"
    public static let host = "littleArkt.host"
    public static let copyLink = "littleArkt.copyLink"
    public static let open = "littleArkt.open"
    public static let chooser = "littleArkt.chooser"
    public static let card = "littleArkt.card"
  }

  /// The quick lookup bar (#354, `LittleArktLookupController`): the "Little Arkt" tag, the input and the results.
  public enum LittleArktLookup {
    public static let root = "littleArkt.lookup"
    public static let tag = "littleArkt.lookup.tag"
    /// Label: "Little Arkt: Search or Enter URL"; value: open while the bar shows.
    public static let field = "littleArkt.lookup.field"
    public static let results = "littleArkt.lookup.results"
    public static let row = "littleArkt.lookup.row"
    /// Value of `root` while the bar shows and while it does not.
    public static let open = "open"
    public static let closed = "closed"
  }
}
