import Foundation

/// Placeholder suggestion provider: URL, matching open tabs and Spaces, Paste and Go, search. Real providers
/// (Chromium autocomplete, history, archived tabs, extensions) replace parts of `make` later behind the same
/// `Result` type; the BH-104 sources with no store yet (archived tabs, history, extensions, folders) are
/// deferred in #112.
public enum CommandBarResults {
  /// An open tab the bar can switch to; `node` is its sidebar node. `isSplitPane`: it is a pane of a split, so its
  /// result says "Switch to Split View" (BH-104).
  public struct OpenTab: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    public let url: URL
    public let isSplitPane: Bool
    /// When the tab was last shown in this window; nil when it has not been since the app started. The empty state's
    /// Recent tabs rows say "12 min" from it.
    public let lastViewed: Date?
    public init(node: NodeID, title: String, url: URL, isSplitPane: Bool = false, lastViewed: Date? = nil) {
      self.node = node; self.title = title; self.url = url; self.isSplitPane = isSplitPane
      self.lastViewed = lastViewed
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
    public var actions: [CommandBarAction] = []
    /// BH-108: a URL read from the clipboard when the bar opened; nil adds no "Paste and Go".
    public var clipboardURL: URL?
    /// BH-109: removal ids hidden this session.
    public var excluded: Set<String> = []
    /// BH-113 (`searchSuggestEnabled`): off means no "Search <engine>" row and no engine round trip.
    public var searchSuggestionsEnabled = true
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
    /// An empty query lists the open tabs plainly, without the empty state's groups (Little Arkt's lookup, which has
    /// no clipboard, recent tabs or actions).
    public var listsOpenTabsForAnEmptyQuery = false
    /// Counting every match for the pills lifts the caps on the rows shown.
    public var isCountingAllMatches = false
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
    /// A filter that matches nothing: one row that says so (design/command-bar/README.md, Filters). Not actionable.
    case noMatch

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
      case .noMatch: "noMatch"
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
      case .noMatch: title
      }
    }

    /// Whether Return does anything on the row; the empty row is the only one that does not.
    public var isActionable: Bool {
      if case .noMatch = kind { return false }
      return true
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
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch input.scope {
    case .actions:
      // BH-106: action search lists the shell's actions only.
      return CommandBarActions.filter(input.actions, query: query).map { actionRow($0, group: nil) }
    case .siteSearch(let engine):
      // BH-107: one row per query, to the scoped engine.
      guard !query.isEmpty, let url = engine.url(for: query) else { return [] }
      return [Result(kind: .siteSearch(url), title: "Search \(engine.name) for \(query)", subtitle: "Search \(engine.name)",
                     trailingHint: nil,
                     removalID: "sitesearch:\(url.absoluteString)")]
    case .normal:
      break
    }

    if query.isEmpty { return emptyState(input) }

    var results: [Result] = []

    let url = URLInputParser.url(from: query)
    if let url {
      // The subtitle shows what the input expands to; when the input is that URL already (Cmd-L), it adds nothing.
      let subtitle = url.absoluteString == query ? "" : url.absoluteString
      results.append(Result(kind: .open(url), title: query, subtitle: subtitle, trailingHint: nil, removalID: nil))
    }

    let matching = openTabsAll(input).filter { tab in
      tab.title.localizedStandardContains(query) || (tab.url.host() ?? "").localizedStandardContains(query)
    }
    for tab in matching.prefix(input.isCountingAllMatches ? .max : maxSwitchResults) {
      results.append(tabRow(tab, group: nil, now: input.now))
    }

    // Spaces (BH-104): after the tabs, capped.
    for space in input.spaces.filter({ $0.title.localizedStandardContains(query) })
      .prefix(input.isCountingAllMatches ? .max : maxSpaceResults) {
      results.append(Result(kind: .switchSpace(space.id), title: space.title, subtitle: "Space",
                            trailingHint: switchToSpaceHint, removalID: nil))
    }

    for match in input.archived.prefix(input.isCountingAllMatches ? .max : maxArchivedResults) {
      results.append(Result(kind: .restore(match.id), title: match.title, subtitle: match.subtitle,
                            trailingHint: restoreHint, removalID: nil))
    }

    // #96: an explicit http(s) scheme makes the input a URL for certain (Cmd-L prefills one), so a search row
    // would only repeat it. Chromium keeps a demoted search-what-you-typed row there; Arc unverified [I] (RT-08).
    // Schemeless input such as `example.com` stays ambiguous and keeps both rows.
    // BH-113: `searchSuggestEnabled` off drops the row and the engine round trip it stands for.
    let isExplicitURL = url != nil && URLInputParser.hasExplicitScheme(query)
    if !isExplicitURL, input.searchSuggestionsEnabled {
      results.append(Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                            subtitle: "Search \(CommandBarSettings.searchEngineName)", trailingHint: nil,
                            removalID: "search:\(query)"))
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
    }

    // Actions whose title matches the query, so the Actions pill counts them.
    for action in CommandBarActions.filter(input.actions, query: query)
      .prefix(input.isCountingAllMatches ? .max : maxMatchingActions) {
      results.append(actionRow(action, group: nil))
    }
    return results.filter { result in
      result.removalID.map { !input.excluded.contains($0) } ?? true
    }
  }

  /// The pills' counts: every match for `query`, not just the rows the list shows (its caps lifted). Hidden for an
  /// empty query, so zeros there.
  public static func counts(query: String, input: Input) -> [CommandBarFilter: Int] {
    guard CommandBarFilter.showsCounts(forQuery: query) else { return CommandBarFilter.counts(of: []) }
    var all = input
    all.isCountingAllMatches = true
    return CommandBarFilter.counts(of: make(query: query, input: all))
  }

  private static func openTabsAll(_ input: Input) -> [OpenTab] { input.openTabs }

  private static func actionRow(_ action: CommandBarAction, group: Group?) -> Result {
    var row = Result(kind: .action(action.id), title: action.title, subtitle: "Action", trailingHint: nil,
                     removalID: nil)
    row.keyCaps = action.keyCaps
    row.group = group
    return row
  }

  private static func tabRow(_ tab: OpenTab, group: Group?, now: Date) -> Result {
    var row = Result(kind: .switchTo(tab.node), title: tab.title,
                     subtitle: tab.url.host() ?? tab.url.absoluteString,
                     trailingHint: tab.isSplitPane ? switchToSplitHint : switchHint,
                     removalID: "tab:\(tab.node.uuidString)")
    row.group = group
    if group == .recentTabs, let viewed = tab.lastViewed {
      row.timeText = CommandBarRelativeTime.text(from: viewed, to: now)
    }
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
      var row = Result(kind: .pasteAndGo(url), title: pasteAndGoTitle, subtitle: url.absoluteString,
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
  /// Every open tab of a Space for "Switch to Tab": pinned, then Today, depth-first through folders.
  /// A split contributes its first pane, marked as a split pane (activating it shows the split).
  @MainActor
  public static func openTabs(in source: any SidebarSource, space: SpaceID) -> [OpenTab] {
    var tabs: [OpenTab] = []
    func visit(_ id: NodeID, depth: Int) {
      guard depth < 64, let info = source.node(id) else { return }   // depth guard against a malformed source
      switch info {
      case .tab(let node, let url, let title):
        tabs.append(OpenTab(node: node, title: title, url: url))
      case .folder(let folder, _):
        for child in source.children(of: .folder(folder)) { visit(child, depth: depth + 1) }
      case .split:
        if let first = source.firstTab(at: id), case .tab(let node, let url, let title)? = source.node(first) {
          tabs.append(OpenTab(node: node, title: title, url: url, isSplitPane: true))
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
