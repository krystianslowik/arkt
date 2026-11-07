// Incognito sidebar label (#487, BH-174). Kept beside `AXID.swift` like the other late groups; no imports, like it.
extension AXID {
  /// The window's kind, "Incognito" or "Blank" (#668), only in the footer of a blank or incognito window's sidebar
  /// (`SidebarContainerView.windowKindLabel`).
  public enum Incognito {
    public static let label = "sidebar.incognito"
  }
}
