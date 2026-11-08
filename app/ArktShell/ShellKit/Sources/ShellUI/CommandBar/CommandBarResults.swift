import Foundation
import EngineAPI

/// Builds command-bar results from caller-supplied sources. Folder and extension-action inputs are provider-only
/// until their production data and activation handlers are connected (#562).
public enum CommandBarResults {
  /// An open tab the bar can switch to; `node` is its sidebar node. `isSplitPane`: it is a pane of a split, so its
  /// result says "Switch to Split View" (BH-104).
  public struct OpenTab: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    public let url: URL
    public let isSplitPane: Bool
    /// When the tab was last shown in this window; nil when it has not been since the app started. The empty state's
    /// Recent tabs rows say "12 min" from it. The preview column says "12 min ago".
    public let lastViewed: Date?
    /// The Space the tab is open in. The preview's meta line names it.
    public let spaceTitle: String?
    public init(node: NodeID, title: String, url: URL, isSplitPane: Bool = false, lastViewed: Date? = nil,
                spaceTitle: String? = nil) {
      self.node = node; self.title = title; self.url = url; self.isSplitPane = isSplitPane
      self.lastViewed = lastViewed
      self.spaceTitle = spaceTitle
    }
  }

  /// A page the history provider remembers. There is no history store yet: the app passes none, and tests pass
  /// synthetic visits. `openTab` is set when that page is already an open tab, so Return switches to it.
  public struct HistoryVisit: Sendable, Equatable {
    public let title: String
    public let url: URL
    public let visited: Date?
    public let openTab: NodeID?
    public init(title: String, url: URL, visited: Date? = nil, openTab: NodeID? = nil) {
      self.title = title; self.url = url; self.visited = visited; self.openTab = openTab
    }
  }

  /// An archived item matching the query (#111, BH-087, BH-104), already worded: its title and "host, Space,
  /// archived <when>". `id` is the archived root node; Enter restores it.
  public struct ArchivedMatch: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public init(id: UUID, title: String, subtitle: String) {
      self.id = id; self.title = title; self.subtitle = subtitle
    }
  }

  /// Sidebar folder identity and title for provider matching.
  public struct Folder: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    public init(node: NodeID, title: String) { self.node = node; self.title = title }
  }

  /// A Space the bar can switch to (BH-104).
  public struct Space: Sendable, Equatable {
    public let id: SpaceID
    public let title: String
    public init(id: SpaceID, title: String) {
      self.id = id; self.title = title
    }
  }

  /// The groups of the empty state, each under a small header (design/command-bar/README.md, Empty state).
  public enum Group: Sendable, Equatable {
    case clipboard, recentTabs, actions

    public var title: String {
      switch self {
      case .clipboard: "Clipboard"
      case .recentTabs: "Recent tabs"
      case .actions: "Actions"
      }
    }
  }

  /// Which surface `make` fills (BH-106, BH-107); the controller owns the transitions (Tab scopes, Backspace on
  /// an empty field unscopes [I]).
  public enum Scope: Sendable, Equatable {
    case normal
    /// BH-106: Tab on the empty bar just opened with Cmd-T (KB-081).
    case actions
    /// BH-107: an alias typed and Tab pressed (KB-082).
    case siteSearch(SiteSearchEngine)
  }

  /// Everything `make` needs beyond the query text.
  public struct Input: Sendable, Equatable {
    public var openTabs: [OpenTab] = []
    public var spaces: [Space] = []
    public var folders: [Folder] = []
    /// Actions supplied by the engine, not a catalog of installed extensions.
    public var extensionActions: [ExtensionAction] = []
    public var actions: [CommandBarAction] = []
    /// BH-108: a URL read from the clipboard when the bar opened; nil adds no "Paste and Go".
    public var clipboardURL: URL?
    /// BH-109: removal ids hidden this session.
    public var excluded: Set<String> = []
    /// BH-113 (`searchSuggestEnabled`): off means no "Search <engine>" row and no engine round trip.
    public var searchSuggestionsEnabled = true
    public var searchEngine: SearchEngine = .google
    public var scope: Scope = .normal
    /// Matches the archive store found for the query, newest first; listed after open tabs (switching to an open
    /// tab beats restoring a closed one) and before the search row (which restoring beats).
    public var archived: [ArchivedMatch] = []
    /// The tabs of the empty state's Recent tabs, most recently viewed first. Empty: the open tabs stand in.
    public var recentTabs: [OpenTab] = []
    /// The engines a typed alias or site name offers a Tab-scoped row for (BH-107).
    public var siteSearchEngines: [SiteSearchEngine] = []
    /// The clock for "12 min"; injected so results are deterministic.
    public var now = Date()
    /// History visits matching is the caller's job only in the sense that the provider already filtered; `make`
    /// still matches `query` and caps the rows. Empty until a history store exists.
    public var history: [HistoryVisit] = []
    /// An empty query lists the open tabs plainly, without the empty state's groups (Little Arkt's lookup, which has
    /// no clipboard, recent tabs or actions).
    public var listsOpenTabsForAnEmptyQuery = false
    public init() {}
  }

  public enum Kind: Sendable, Equatable {
    case open(URL)
    case switchTo(NodeID)
    case search(URL)
    /// An archived item; Enter restores it (BH-086) instead of opening a duplicate.
    case restore(UUID)
    /// BH-108: open the clipboard URL (GS-035 names it "Paste and Go").
    case pasteAndGo(URL)
    /// BH-107: the scoped engine's search URL.
    case siteSearch(URL)
    /// BH-106: run the shell action with this id.
    case action(String)
    /// BH-104: switch to this Space.
    case switchSpace(SpaceID)
    /// A history visit (#372). Return opens it, or switches when `previewFacts` says it is already open.
    case history(URL)
    /// A filter that matches nothing: one row that says so (design/command-bar/README.md, Filters). Not actionable.
    case noMatch
    /// Provider-only identities; activation is not implemented.
    case folder(NodeID)
    case extensionAction(String)

    public var name: String {
      switch self {
      case .open: "open"
      case .switchTo: "switch"
      case .search: "search"
      case .restore: "restore"
      case .pasteAndGo: "pasteAndGo"
      case .siteSearch: "siteSearch"
      case .action: "action"
      case .switchSpace: "switchSpace"
      case .history: "history"
      case .noMatch: "noMatch"
      case .folder: "folder"
      case .extensionAction: "extensionAction"
      }
    }
  }

  public struct Result: Sendable, Equatable {
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let trailingHint: String?
    /// BH-109: identifies a removable suggestion ("tab:<node>", "search:<query>"); nil for the user's own input
    /// (the typed URL, Paste and Go) and for verbs (actions, Spaces), which removal makes no sense for.
    public let removalID: String?
    /// Key caps drawn on an action's row: its shortcut ("command", "shift", "N").
    public var keyCaps: [String] = []
    /// The empty state's group; nil for every row of a typed query.
    public var group: Group?
    /// The engine a normal-scope site-search row scopes to on Tab: the row shows a Tab key cap (the smart Tab rule).
    public var siteSearchEngine: SiteSearchEngine?
    /// "12 min": when a recent tab was last shown. The caption stays the Switch to Tab hint for accessibility.
    public var timeText: String?
    /// Preview facts for an open tab or a history row. Nil for every other kind. The column still stays hidden
    /// on an empty query (`CommandBarPreview.content`).
    public var previewFacts: CommandBarPreviewFacts?

    /// Accessibility value for `commandBar.row` ("Switch to Tab", "Switch to Split View", "Open", "Search").
    public var accessibilityCaption: String {
      switch kind {
      case .open: "Open"
      case .switchTo: trailingHint ?? CommandBarResults.switchHint
      case .restore: CommandBarResults.restoreHint
      case .search, .siteSearch: "Search"
      case .pasteAndGo: "Paste and Go"
      case .action: "Action"
      case .switchSpace: "Switch to Space"
      case .history: previewFacts?.isAlsoOpen == true ? CommandBarResults.switchHint : "Open"
      case .noMatch: title
      case .folder: "Folder"
      case .extensionAction: "Extension action"
      }
    }

    /// Whether Return does anything on the row.
    public var isActionable: Bool {
      switch kind {
      case .noMatch, .folder, .extensionAction: false
      default: true
      }
    }
  }

  /// The empty state's caps: four recent tabs and two actions, so Clipboard, Recent tabs and Actions fit the bar.
  public static let maxRecentTabs = 4
  public static let maxEmptyStateActions = 2
  /// Actions a typed query also lists, so the Actions pill has something to count.
  public static let maxMatchingActions = 3

  /// The header text over each row that starts a group; keyed by row index.
  public static func groupHeaders(of results: [Result]) -> [Int: String] {
    var headers: [Int: String] = [:]
    var previous: Group?
    for (index, result) in results.enumerated() {
      if let group = result.group, group != previous { headers[index] = group.title }
      previous = result.group
    }
    return headers
  }

  public static let maxSwitchResults = 6
  public static let maxHistoryResults = 6
  public static let maxSpaceResults = 3
  public static let switchHint = "Switch to Tab"
  /// The caption of an open tab that is a split pane (BH-104, [S] string).
  public static let switchToSplitHint = "Switch to Split View"
  /// The caption of an archived match (#111).
  public static let restoreHint = "Restore from Archive"
  /// Archived matches shown at most (#111, design section 7).
  public static let maxArchivedResults = 3

  public static let switchToSpaceHint = "Switch to Space"
  public static let pasteAndGoTitle = "Paste and Go"

  public static func make(query raw: String, input: Input) -> [Result] {
    makeWithCounts(query: raw, input: input).results
  }

  /// The pills' counts: every match for `query`, not just the rows the list shows (its caps lifted). Hidden for an
  /// empty query, so zeros there.
  public static func counts(query: String, input: Input) -> [CommandBarFilter: Int] {
    makeWithCounts(query: query, input: input).counts
  }

  /// The rows and the pills' counts from one matching pass (#606). A row is built only for a match the list shows;
  /// the rest are counted. With 2,000 open tabs a second pass that built a row for every match cost 27 ms a keystroke.
  public static func makeWithCounts(query raw: String,
                                    input: Input) -> (results: [Result], counts: [CommandBarFilter: Int]) {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let rows: [Result]
    switch input.scope {
    case .actions:
      // BH-106: action search lists the shell's actions only.
      rows = CommandBarActions.filter(input.actions, query: query).map { actionRow($0, group: nil) }
    case .siteSearch(let engine):
      // BH-107: one row per query, to the scoped engine.
      if !query.isEmpty, let url = engine.url(for: query) {
        rows = [Result(kind: .siteSearch(url), title: "Search \(engine.name) for \(query)",
                       subtitle: "Search \(engine.name)", trailingHint: nil,
                       removalID: "sitesearch:\(url.absoluteString)")]
      } else {
        rows = []
      }
    case .normal:
      if query.isEmpty { return (emptyState(input), CommandBarFilter.counts(of: [])) }
      return typed(query: query, searchQuery: raw, input: input)
    }
    return (rows, CommandBarFilter.showsCounts(forQuery: query) ? CommandBarFilter.counts(of: rows)
                                                                 : CommandBarFilter.counts(of: []))
  }

  /// A typed query in the normal scope: the rows, capped per kind, and the count of every match of each kind.
  private static func typed(query: String, searchQuery: String, input: Input) -> (results: [Result], counts: [CommandBarFilter: Int]) {
    let isKept = { (removalID: String?) in removalID.map { !input.excluded.contains($0) } ?? true }
    var results: [Result] = []

    let url = URLInputParser.url(from: query)
    if let url {
      // The subtitle shows what the input expands to; when the input is that URL already (Cmd-L), it adds nothing.
      let subtitle = url.absoluteString == query ? "" : HostDisplay.address(url)
      results.append(Result(kind: .open(url), title: query, subtitle: subtitle, trailingHint: nil, removalID: nil))
    }

    let match = StandardMatch(query)
    let matching = input.openTabs.filter { tab in
      match.found(in: tab.title) || match.found(in: tab.url.host() ?? "") // not shown
        || shownHost(of: tab.url, contains: query)
    }
    for tab in matching.prefix(maxSwitchResults) {
      results.append(tabRow(tab, group: nil, now: input.now))
    }

    let history = input.history.filter { visit in
      match.found(in: visit.title) || match.found(in: visit.url.absoluteString)
        || shownHost(of: visit.url, contains: query)
    }
    for visit in history.prefix(maxHistoryResults) {
      results.append(historyRow(visit, now: input.now))
    }

    // Spaces (BH-104): after the tabs, capped.
    let spaces = input.spaces.filter { match.found(in: $0.title) }
    for space in spaces.prefix(maxSpaceResults) {
      results.append(Result(kind: .switchSpace(space.id), title: space.title, subtitle: "Space",
                            trailingHint: switchToSpaceHint, removalID: nil))
    }

    for match in input.archived.prefix(maxArchivedResults) {
      results.append(Result(kind: .restore(match.id), title: match.title, subtitle: match.subtitle,
                            trailingHint: restoreHint, removalID: nil))
    }

    // Rows that are never capped and count under All only: the address, the search row and a site alias.
    var uncappedRows = url == nil ? 0 : 1

    // #96: an explicit http(s) scheme makes the input a URL for certain (Cmd-L prefills one), so a search row
    // would only repeat it. Chromium keeps a demoted search-what-you-typed row there; Arc unverified [I] (RT-08).
    // Schemeless input such as `example.com` stays ambiguous and keeps both rows.
    // BH-113: `searchSuggestEnabled` off drops the row and the engine round trip it stands for.
    let isExplicitURL = url != nil && URLInputParser.hasExplicitScheme(query)
    if !isExplicitURL, input.searchSuggestionsEnabled {
      let removalID = "search:\(query)"
      results.append(Result(kind: .search(URLInputParser.searchURL(for: searchQuery, engine: input.searchEngine)), title: query,
                            subtitle: "Search \(input.searchEngine.rawValue)", trailingHint: nil,
                            removalID: removalID))
      if isKept(removalID) { uncappedRows += 1 }
    }

    // BH-107: a typed alias or site name offers a row for that site, with a Tab key cap: Tab scopes to it.
    if let engine = SiteSearchEngines.engine(matching: query, in: input.siteSearchEngines),
       let searchURL = engine.url(for: query) {
      let exact = engine.alias.caseInsensitiveCompare(query) == .orderedSame
      var row = Result(kind: .siteSearch(searchURL), title: exact ? "Search \(engine.name)" : "Search \(engine.name) for \(query)",
                       subtitle: "Search \(engine.name)", trailingHint: nil, removalID: nil)
      row.siteSearchEngine = engine
      // An alias typed whole is the shortcut: its row leads, so Tab scopes at once (#322) and Return, with nothing yet
      // to search for, scopes too (`CommandBarController.commit`).
      results.insert(row, at: exact ? 0 : results.count)
      uncappedRows += 1
    }

    // Actions whose title matches the query, so the Actions pill counts them.
    let actions = CommandBarActions.filter(input.actions, query: query)
    for action in actions.prefix(maxMatchingActions) {
      results.append(actionRow(action, group: nil))
    }
    // Provisional provider-only placement; this does not establish a ranking policy.
    let folders = input.folders.filter { match.found(in: $0.title) }
    let extensionActions = input.extensionActions.filter { $0.isEnabled && match.found(in: $0.name) }
    for folder in folders {
      results.append(Result(kind: .folder(folder.node), title: folder.title, subtitle: "Folder",
                            trailingHint: nil, removalID: nil))
    }
    for action in extensionActions {
      results.append(Result(kind: .extensionAction(action.id), title: action.name, subtitle: "Extension action",
                            trailingHint: nil, removalID: nil))
    }

    // Counted without building rows: the removal ids are formed only when something was removed.
    let tabCount = input.excluded.isEmpty ? matching.count
      : matching.count { isKept("tab:\($0.node.uuidString)") }
    let historyCount = input.excluded.isEmpty ? history.count
      : history.count { isKept("history:\($0.url.absoluteString)") }
    var counts: [CommandBarFilter: Int] = [:]
    counts[.tabs] = tabCount + input.archived.count
    counts[.history] = historyCount
    counts[.actions] = actions.count
    counts[.all] = uncappedRows + tabCount + historyCount + spaces.count + input.archived.count + actions.count
      + folders.count + extensionActions.count
    return (results.filter { isKept($0.removalID) }, counts)
  }

  /// Match using the current locale fetched once per pass (#606).
  struct StandardMatch {
    private let query: CFString
    private let locale = CFLocaleCopyCurrent()
    init(_ query: String) { self.query = query as CFString }
    func found(in text: String) -> Bool {
      let text = text as CFString
      return CFStringFindWithOptionsAndLocale(text, query, CFRange(location: 0, length: CFStringGetLength(text)),
                                              [.compareCaseInsensitive, .compareDiacriticInsensitive, .compareNonliteral],
                                              locale, nil)
    }
  }

  /// Whether the host the rows show for `url` (`HostDisplay`, #732) holds `query`, so a host typed in Unicode finds it
  /// as well as the encoded form the URL itself is matched by. Case is folded, diacritics are not: "paypal" must not
  /// find "pàypal-login.net" through its shown host. Only a host with an `xn--` label can read differently, so every
  /// other one costs a substring check; `HostDisplay` keeps the answer per host, so each is decoded once however many
  /// rows and keystrokes ask. A title saved as the raw host (`HostDisplay.savedTitle(for:)`) is matched as saved.
  static func shownHost(of url: URL, contains query: String) -> Bool {
    guard let raw = url.host(), raw.range(of: "xn--", options: .caseInsensitive) != nil, // not shown
          let shown = HostDisplay.host(of: url), shown != raw else { return false }
    return shown.range(of: query, options: .caseInsensitive) != nil
  }

  private static func actionRow(_ action: CommandBarAction, group: Group?) -> Result {
    var row = Result(kind: .action(action.id), title: action.title, subtitle: "Action", trailingHint: nil,
                     removalID: nil)
    row.keyCaps = action.keyCaps
    row.group = group
    return row
  }

  private static func tabRow(_ tab: OpenTab, group: Group?, now: Date) -> Result {
    let title = HostDisplay.title(tab.title, for: tab.url)
    var row = Result(kind: .switchTo(tab.node), title: title,
                     subtitle: HostDisplay.hostOrAddress(tab.url),
                     trailingHint: tab.isSplitPane ? switchToSplitHint : switchHint,
                     removalID: "tab:\(tab.node.uuidString)")
    row.group = group
    if group == .recentTabs, let viewed = tab.lastViewed {
      row.timeText = CommandBarRelativeTime.text(from: viewed, to: now)
    }
    row.previewFacts = CommandBarPreviewFacts(
      rowKind: .openTab, title: title, host: HostDisplay.hostOrAddress(tab.url),
      spaceTitle: tab.spaceTitle,
      timeText: tab.lastViewed.map { CommandBarRelativeTime.preview(from: $0, to: now) },
      isAlsoOpen: false, url: tab.url, node: tab.node)
    return row
  }

  private static func historyRow(_ visit: HistoryVisit, now: Date) -> Result {
    let host = HostDisplay.hostOrAddress(visit.url)
    let title = HostDisplay.title(visit.title, for: visit.url)
    var row = Result(kind: .history(visit.url), title: title,
                     subtitle: CommandBarTitleMatch.displayURL(HostDisplay.address(visit.url)),
                     trailingHint: nil, removalID: "history:\(visit.url.absoluteString)")
    if let visited = visit.visited {
      row.timeText = CommandBarRelativeTime.text(from: visited, to: now)
    }
    row.previewFacts = CommandBarPreviewFacts(
      rowKind: .history, title: title, host: host, spaceTitle: nil,
      timeText: visit.visited.map { CommandBarRelativeTime.preview(from: $0, to: now) },
      isAlsoOpen: visit.openTab != nil, url: visit.url, node: visit.openTab)
    return row
  }

  /// The empty query: Clipboard (Paste and Go, only when the clipboard holds a URL), Recent tabs (up to four) and a
  /// short list of Actions (design/command-bar/README.md, Empty state).
  private static func emptyState(_ input: Input) -> [Result] {
    if input.listsOpenTabsForAnEmptyQuery {
      return input.openTabs.prefix(maxSwitchResults).map { tabRow($0, group: nil, now: input.now) }
        .filter { result in result.removalID.map { !input.excluded.contains($0) } ?? true }
    }
    var results: [Result] = []
    // BH-108 / GS-035.
    if let url = input.clipboardURL {
      var row = Result(kind: .pasteAndGo(url), title: pasteAndGoTitle, subtitle: HostDisplay.address(url),
                       trailingHint: nil, removalID: nil)
      row.group = .clipboard
      results.append(row)
    }
    let recents = input.recentTabs.isEmpty ? input.openTabs : input.recentTabs
    for tab in recents.prefix(maxRecentTabs) { results.append(tabRow(tab, group: .recentTabs, now: input.now)) }
    for action in input.actions.prefix(maxEmptyStateActions) { results.append(actionRow(action, group: .actions)) }
    return results.filter { result in
      result.removalID.map { !input.excluded.contains($0) } ?? true
    }
  }

  /// The pre-#112 convenience: a plain query over open tabs (no clipboard, Spaces, actions or exclusions) with optional archived matches (#111).
  public static func make(query raw: String, openTabs: [OpenTab], archived: [ArchivedMatch] = []) -> [Result] {
    var input = Input()
    input.openTabs = openTabs
    input.archived = archived
    input.listsOpenTabsForAnEmptyQuery = true
    return make(query: raw, input: input)
  }
}

extension CommandBarResults {
  /// Collect each folder once, in caller Space and sidebar order, including closed nested folders.
  @MainActor
  public static func folders(in source: any SidebarSource, spaces: [SpaceID]) -> [Folder] {
    var folders: [Folder] = []
    var visited: Set<NodeID> = []
    func visit(_ id: NodeID, depth: Int) {
      guard depth < 64, visited.insert(id).inserted, let info = source.node(id) else { return }
      if case .folder(let node, let title) = info {
        folders.append(Folder(node: node, title: title))
        for child in source.children(of: .folder(node)) { visit(child, depth: depth + 1) }
      }
    }
    for space in spaces {
      for id in source.children(of: .pinned(space)) + source.children(of: .today(space)) {
        visit(id, depth: 0)
      }
    }
    return folders
  }

  /// Every open tab of a Space for "Switch to Tab": pinned, then Today, depth-first through folders.
  /// A split contributes its first pane, marked as a split pane (activating it shows the split).
  @MainActor
  public static func openTabs(in source: any SidebarSource, space: SpaceID) -> [OpenTab] {
    let spaceTitle = source.space(space)?.title
    var tabs: [OpenTab] = []
    func visit(_ id: NodeID, depth: Int) {
      guard depth < 64, let info = source.node(id) else { return }   // depth guard against a malformed source
      switch info {
      case .tab(let node, let url, let title):
        tabs.append(OpenTab(node: node, title: title, url: url, spaceTitle: spaceTitle))
      case .folder(let folder, _):
        for child in source.children(of: .folder(folder)) { visit(child, depth: depth + 1) }
      case .split:
        if let first = source.firstTab(at: id), case .tab(let node, let url, let title)? = source.node(first) {
          tabs.append(OpenTab(node: node, title: title, url: url, isSplitPane: true, spaceTitle: spaceTitle))
        }
      }
    }
    for id in source.children(of: .pinned(space)) + source.children(of: .today(space)) { visit(id, depth: 0) }
    return tabs
  }

  /// BH-104: open tabs of every Space, in the order the caller passes (the window puts the current Space first,
  /// so a Space switch refresh reorders, BH-111).
  @MainActor
  public static func openTabs(in source: any SidebarSource, spaces: [SpaceID]) -> [OpenTab] {
    spaces.flatMap { openTabs(in: source, space: $0) }
  }
}
