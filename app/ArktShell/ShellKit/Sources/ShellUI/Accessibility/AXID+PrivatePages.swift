// The Pages list of a blank or incognito window (#668). Kept beside `AXID.swift` like the other late groups; no
// imports, like it.
extension AXID {
  public enum PrivatePages {
    /// The list "Pages" in the sidebar of a blank or incognito window (`PrivatePagesView`).
    public static let list = "sidebar.privatePages"
    /// A row of that list; its label is the page title.
    public static let row = "sidebar.privatePages.row"
  }
}
