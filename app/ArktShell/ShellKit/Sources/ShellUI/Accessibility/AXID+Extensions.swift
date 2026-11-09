extension AXID {
  /// The Extensions panel (#595, design/extensions direction C), opened by `AXID.Sidebar.extensions`.
  public enum Extensions {
    /// The panel's content. The panel window is a dialog labelled "Extensions".
    public static let panel = "extensions.panel"
    /// The list of rows (a list labelled "Extensions").
    public static let list = "extensions.list"
    /// One extension. Label: its name. Actions: Move Up and Move Down when pinned, Show Menu.
    public static let row = "extensions.row"
    /// Runs the extension's action. Label: "<name>, <status>". Value: the action's id.
    public static let rowRun = "extensions.row.run"
    /// The pin toggle. Label: "Pin <name>". Value: pinned.
    public static let rowPin = "extensions.row.pin"
    /// Opens the extension's context menu. Label: "More for <name>".
    public static let rowMore = "extensions.row.more"
    /// The hint shown under Pinned while nothing is pinned.
    public static let hint = "extensions.hint"
    /// The empty state ("No extensions yet") and its Browse the Web Store button.
    public static let empty = "extensions.empty"
    public static let browseWebStore = "extensions.browseWebStore"
    /// Manage Extensions... in the footer.
    public static let manage = "extensions.manage"
  }
}
