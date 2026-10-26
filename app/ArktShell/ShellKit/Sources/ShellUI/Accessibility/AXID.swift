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

  /// The shared dialog (`DialogSheetView`): Delete Space, Clear Archive, the launch alerts.
  public enum Dialog {
    /// Label: the title; help: the body.
    public static let root = "dialog"
    public static let primary = "dialog.primary"
    public static let secondary = "dialog.secondary"
    public static let cancel = "dialog.cancel"
    public static let footerLink = "dialog.footerLink"
    /// The prompt's text field (a page's `prompt()`); value: the text.
    public static let input = "dialog.input"
  }

  /// The toast over the bottom of the content card (`ToastView`); absent while no toast shows.
  public enum Toast {
    /// Label: the toast text. Value: `persistent` or `timed`.
    public static let root = "toast"
    /// The action button; present only while the toast has an action.
    public static let action = "toast.action"
    /// The dismiss button of a persistent toast.
    public static let dismiss = "toast.dismiss"
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
    /// The Space header's Collapse / Expand Pinned caret (BH-065); present only while the Space has pinned tabs.
    public static let spaceCollapsePinned = "sidebar.spaceCollapsePinned"
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
    /// A row's audio button (#364): mutes or unmutes the page.
    public static let rowAudio = "sidebar.row.audio"
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

  /// Archive window, table, rows, search, filters, buttons and footer (group U4c, #111).
  public enum Archive {
    public static let window = "archive.window"
    public static let table = "archive.table"
    /// Label: archived item title.
    public static let row = "archive.row"
    public static let restore = "archive.restore"
    /// Value: footer text.
    public static let footer = "archive.footer"
    /// The search field (#111). Label "Search Archive".
    public static let search = "archive.search"
    /// The filter button. Value: "N filters active" while any filter is on.
    public static let filter = "archive.filter"
    /// A filter chip: `archive.chip.<name>` (`chip(_:)`), a group with a "Remove filter" button.
    public static let chipPrefix = "archive.chip."
    public static func chip(_ name: String) -> String { chipPrefix + name }
    /// The "Clear Filters" link of the chip strip.
    public static let clearFilters = "archive.clearFilters"
    /// The one-time auto-archive education banner (BH-089).
    public static let banner = "archive.banner"
    /// The Clear Archive link in the footer.
    public static let clear = "archive.clear"
    /// The confirmation sheet's Clear Archive button.
    public static let clearConfirm = "archive.clearConfirm"
  }

  /// Split View container, pane cards, dividers and closed-pane reopen button (group U4c).
  public enum Split {
    public static let container = "split.container"
    /// Selected: focused pane.
    public static let pane = "split.pane"
    /// Value: pane share factor (`NSNumber`).
    public static let divider = "split.divider"
    public static let reopen = "split.reopen"
    /// Label "Close Pane": the X at the top of a pane with a page (#388).
    public static let close = "split.close"
  }

  /// The first run over the whole window (`OnboardingView`, onboarding spec sections 6 and 11); absent once it ends.
  public enum Onboarding {
    /// Label "Welcome to Arkt". Value: "Step {n} of {total}" (empty on Welcome).
    public static let root = "onboarding"
    /// The current step's container: `step` + "." + the step identifier ("welcome", "import", "theme", "default",
    /// "extensions", "tour-1" ... "tour-5", "done").
    public static let step = "onboarding.step"
    public static func step(_ identifier: String) -> String { "\(step).\(identifier)" }
    /// The step title. Label: the title text.
    public static let title = "onboarding.title"
    public static let lede = "onboarding.lede"
    public static let eyebrow = "onboarding.eyebrow"
    /// The footer's "{n} of {total}".
    public static let progress = "onboarding.progress"
    public static let back = "onboarding.back"
    public static let skipSetup = "onboarding.skipSetup"
    // Buttons by action.
    public static let getStarted = "onboarding.getStarted"
    public static let importData = "onboarding.import"
    public static let startFresh = "onboarding.startFresh"
    public static let tryAgain = "onboarding.tryAgain"
    public static let continueButton = "onboarding.continue"
    public static let skip = "onboarding.skip"
    public static let notNow = "onboarding.notNow"
    public static let makeDefault = "onboarding.makeDefault"
    public static let next = "onboarding.next"
    public static let skipTour = "onboarding.skipTour"
    public static let startBrowsing = "onboarding.startBrowsing"
    /// Import: one static text per count. Label: "37 pinned tabs", "Pinned tabs, counting", "37 pinned tabs, imported".
    public static let countPinnedTabs = "onboarding.count.pinnedTabs"
    public static let countSpaces = "onboarding.count.spaces"
    public static let countFavorites = "onboarding.count.favorites"
    public static let countFolders = "onboarding.count.folders"
    /// Make it yours: the Space name field (label "Name").
    public static let name = "onboarding.name"
    /// The swatch radio group; each swatch is a radio button labelled with its theme name ("Dune", "Imported").
    public static let swatches = "onboarding.swatches"
    public static let swatch = "onboarding.swatch"
    /// The Light / Dark radio group and its two radio buttons.
    public static let appearance = "onboarding.appearance"
    public static let appearanceLight = "onboarding.appearance.light"
    public static let appearanceDark = "onboarding.appearance.dark"
    /// Extensions: the Chrome Web Store checkbox.
    public static let webStore = "onboarding.webStore"
    /// The stage image of Welcome, Done and tips 1 and 2.
    public static let stage = "onboarding.stage"
  }

  /// The Ctrl-Tab switcher and the sidebar overflow pill (#103).
  public enum TabSwitcher {
    /// The floating panel (a dialog group labelled "Recent tabs"); absent while closed.
    public static let panel = "tabSwitcher"
    /// Label: "title, Space, k of n". Selected: the highlighted row.
    public static let row = "tabSwitcher.row"
    /// "3 more above" / "2 more below" after a keyboard reveal; absent otherwise.
    public static let overflowPill = "sidebar.overflowPill"
  }

  /// The Settings window (#307, docs/design/settings.md, section 7).
  public enum Settings {
    public static let window = "settings.window"
    /// A pane item: a radio button in the "Settings" tab group, labelled with the pane's short name.
    public static func tab(_ pane: String) -> String { "settings.tab.\(pane)" }
    /// A row's control: `settings.<pane>.<setting>`, labelled with the row's label, its caption as help.
    public static func control(_ pane: String, _ setting: String) -> String { "settings.\(pane).\(setting)" }
    /// Settings > Shortcuts: the search field.
    public static let shortcutsSearch = "settings.shortcuts.search"
    /// Settings > Spaces and Profiles: a Space's row, by the Space's id.
    public static func spaceRow(_ id: String) -> String { "settings.spaces.space.\(id)" }
  }
}
