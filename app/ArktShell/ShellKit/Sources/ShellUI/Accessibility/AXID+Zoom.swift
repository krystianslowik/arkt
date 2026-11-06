// Zoom pill identifiers (#579). Kept beside `AXID.swift` like the other late groups; no imports, like it.
extension AXID {
  /// The zoom pill over the top trailing corner of the page (`ZoomPillView`); absent while no pill shows.
  public enum Zoom {
    /// Label: "Zoom"; role: group.
    public static let root = "zoom.root"
    /// Value: "125%".
    public static let percent = "zoom.percent"
    public static let zoomOut = "zoom.out"
    public static let zoomIn = "zoom.in"
    public static let reset = "zoom.reset"
  }
}
