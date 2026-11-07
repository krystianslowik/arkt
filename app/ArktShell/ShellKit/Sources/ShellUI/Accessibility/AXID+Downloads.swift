extension AXID {
  /// Downloads (#132): the Library button's ring, its popover, the Library window and the dangerous-file sheet.
  public enum Downloads {
    /// The Library button in the sidebar's bottom bar. Label: "Library, downloading 13 percent". Value: the state.
    public static let libraryButton = "sidebar.library"
    /// The popover that lists the current downloads.
    public static let popover = "downloads.popover"
    /// Label: the row's summary ("Downloading <name>, 13 percent"). Value: the download's id.
    public static let row = "downloads.row"
    public static let cancel = "downloads.row.cancel"
    public static let open = "downloads.row.open"
    public static let showInFinder = "downloads.row.showInFinder"
    public static let retry = "downloads.row.retry"
    public static let remove = "downloads.row.remove"
    public static let review = "downloads.row.review"
    public static let keep = "downloads.row.keep"
    public static let discard = "downloads.row.discard"
    public static let progress = "downloads.row.progress"
    public static let popoverShowLibrary = "downloads.popover.showLibrary"
    public static let popoverClear = "downloads.popover.clear"

    public static let libraryWindow = "library.window"
    public static let libraryList = "library.list"
    public static let libraryRail = "library.rail"
    /// `library.rail.<section>` (`railItem(_:)`).
    public static let railPrefix = "library.rail."
    public static func railItem(_ section: String) -> String { railPrefix + section }
    public static let librarySearch = "library.search"
    public static let libraryFooter = "library.footer"
    public static let libraryChange = "library.change"
    public static let libraryClear = "library.clear"
    public static let libraryEmpty = "library.empty"
    public static let libraryOpenFolder = "library.openFolder"

    public static let dangerSheet = "downloads.danger"
    /// The settings pane's controls.
    public static let locationMode = "settings.downloads.mode"
    public static let locationFolder = "settings.downloads.folder"
    public static let locationChoose = "settings.downloads.choose"
    public static let openLibrary = "settings.downloads.openLibrary"
  }
}
