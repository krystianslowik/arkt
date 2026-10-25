/// Accessibility identifiers of the shell, the only handles the UI test suite (`ArktShellUITests`) uses to find and
/// drive views. This file has no imports so the UI test target can compile the same file by path, and the
/// identifiers in the app and in the tests can never drift apart. Values that tests compare against
/// (`accessibilityValue`) live next to their identifiers.
///
/// Each area is its own nested enum; later groups add enums instead of editing these.
public enum AXID {
  /// The shell window (`ShellWindow`).
  public enum Shell {
    public static let window = "shell.window"
  }

  /// The inset card that hosts the page (`ContentCardView`).
  public enum Content {
    public static let card = "content.card"
  }

  /// First run: the panel in the content card while the profile has no Space (`EmptyStateView`).
  public enum EmptyState {
    public static let root = "emptyState"
    /// "Import from Arc"; absent from the accessibility tree while hidden (no Arc data).
    public static let importFromArc = "emptyState.import"
    public static let newSpace = "emptyState.newSpace"
  }

  /// The Toolbar at the top of the content card (`ContentToolbarView`); absent while the Toolbar is hidden.
  public enum Toolbar {
    public static let root = "toolbar"
    /// Enabled only while the shown tab can go back.
    public static let back = "toolbar.back"
    /// Enabled only while the shown tab can go forward.
    public static let forward = "toolbar.forward"
    public static let reload = "toolbar.reload"
    /// Value: the full address of the shown tab.
    public static let urlBar = "toolbar.urlBar"
  }

  /// The toast over the bottom of the content card (`ToastView`); absent while no toast shows.
  public enum Toast {
    /// Label: the toast text. Value: `persistent` or `timed`.
    public static let root = "toast"
    /// The action button; present only while the toast has an action.
    public static let action = "toast.action"
    /// Value of `root` for a toast that stays until dismissed (recovery notices).
    public static let persistent = "persistent"
    /// Value of `root` for a toast that hides after its duration.
    public static let timed = "timed"
  }

  /// Sidebar chrome, Space dock, Space pages and outline rows (group U4b).
  public enum Sidebar {
    /// Value: the displayed host of the shown tab.
    public static let urlBar = "sidebar.urlBar"
    public static let newTab = "sidebar.newTab"
    /// Shown only for an engine that runs extensions. Enabled: the window has extension actions.
    public static let extensions = "sidebar.extensions"
    public static let spaceDots = "sidebar.spaceDots"
    /// Label: Space title. Selected: current Space.
    public static let spaceDot = "sidebar.spaceDot"
    /// Label: Space title. Selected: current Space's page.
    public static let page = "sidebar.page"
    public static let spaceTitle = "sidebar.spaceTitle"
    /// The Space header's hover edit button (#106); present only while shown.
    public static let spaceRename = "sidebar.spaceRename"
    /// The Space header's hover "..." button (BH-038); present only while shown.
    public static let spaceOptions = "sidebar.spaceOptions"
    /// The menu that button opens: Icon, Theme, and a disabled Profile.
    public static let spaceMenu = "sidebar.spaceMenu"
    /// The current Space page's outline of pinned and Today rows (a proxy element, #269).
    public static let outline = "sidebar.outline"
    /// Label: row title. Selected: row state is `current`.
    public static let rowPinned = "sidebar.row.pinned"
    /// Label: row title. Selected: row state is `current`.
    public static let rowToday = "sidebar.row.today"
    /// Label: folder title.
    public static let rowFolder = "sidebar.row.folder"
    /// Label: joined pane titles. Selected: any pane of the split is `current`.
    public static let rowSplit = "sidebar.row.split"
    public static let divider = "sidebar.divider"
    /// Present only while the row's close button is shown. Label: tooltip.
    public static let rowClose = "sidebar.row.close"
  }

  /// Favorites grid and tiles at the top of the sidebar (group U4b).
  public enum Favorites {
    public static let grid = "favorites.grid"
    /// Label: title. Value: `loaded` or `unloaded`.
    public static let tile = "favorites.tile"
    /// Present only while a loaded tile is hovered.
    public static let tileClose = "favorites.tile.close"
    public static let loaded = "loaded"
    public static let unloaded = "unloaded"
  }

  /// Command bar panel, field, results table and result rows (group U4c).
  public enum CommandBar {
    /// On the panel's content view (`CommandBarView`). Value: `open` while shown, `closed` while hidden and inert.
    public static let root = "commandBar"
    public static let field = "commandBar.field"
    public static let results = "commandBar.results"
    /// Label: title. Selected: selection. Value: caption ("Switch to Tab", "Switch to Split View", "Open", "Search").
    public static let row = "commandBar.row"
    public static let open = "open"
    public static let closed = "closed"
  }

  /// Archive window, table, rows, buttons and footer (group U4c).
  public enum Archive {
    public static let window = "archive.window"
    public static let table = "archive.table"
    /// Label: archived item title.
    public static let row = "archive.row"
    public static let restore = "archive.restore"
    public static let loadMore = "archive.loadMore"
    /// Value: footer text.
    public static let footer = "archive.footer"
    /// Reserved for #111 (Archive search); unused until #111 lands.
    public static let search = "archive.search"
  }

  /// Split View container, pane cards, dividers and closed-pane reopen button (group U4c).
  public enum Split {
    public static let container = "split.container"
    /// Selected: focused pane.
    public static let pane = "split.pane"
    /// Value: pane share factor (`NSNumber`).
    public static let divider = "split.divider"
    public static let reopen = "split.reopen"
  }
}
