// Edit Pin popover identifiers (#363). Kept beside `AXID.swift` like the other feature files; no imports.
extension AXID {
  /// The Edit Pin popover (`EditPinView`).
  public enum EditPin {
    /// The popover. Role dialog, label "Edit Pinned Tab" or "Edit Favorite".
    public static let popover = "editPin.popover"
    /// The Name field.
    public static let name = "editPin.name"
    /// The Pinned URL field; its help is the invalid address line while it shows.
    public static let url = "editPin.url"
    /// Use Current Page, a button.
    public static let useCurrentPage = "editPin.useCurrentPage"
    public static let cancel = "editPin.cancel"
    /// Save, the primary (Return).
    public static let save = "editPin.save"
  }
}
