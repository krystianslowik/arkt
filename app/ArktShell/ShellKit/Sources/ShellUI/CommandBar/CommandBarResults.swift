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
    public init(node: NodeID, title: String, url: URL, isSplitPane: Bool = false) {
      self.node = node; self.title = title; self.url = url; self.isSplitPane = isSplitPane
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
    public init() {}
  }

  public enum Kind: Sendable, Equatable {
    case open(URL)
    case switchTo(NodeID)
    case search(URL)
    /// BH-108: open the clipboard URL (GS-035 names it "Paste and Go").
    case pasteAndGo(URL)
    /// BH-107: the scoped engine's search URL.
    case siteSearch(URL)
    /// BH-106: run the shell action with this id.
    case action(String)
    /// BH-104: switch to this Space.
    case switchSpace(SpaceID)

    public var name: String {
      switch self {
      case .open: "open"
      case .switchTo: "switch"
      case .search: "search"
      case .pasteAndGo: "pasteAndGo"
      case .siteSearch: "siteSearch"
      case .action: "action"
      case .switchSpace: "switchSpace"
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

    /// Accessibility value for `commandBar.row` ("Switch to Tab", "Switch to Split View", "Open", "Search").
    public var accessibilityCaption: String {
      switch kind {
      case .open: "Open"
      case .switchTo: trailingHint ?? CommandBarResults.switchHint
      case .search, .siteSearch: "Search"
      case .pasteAndGo: "Paste and Go"
      case .action: "Action"
      case .switchSpace: "Switch to Space"
      }
    }
  }

  public static let maxSwitchResults = 6
  public static let maxSpaceResults = 3
  public static let switchHint = "Switch to Tab"
  /// The caption of an open tab that is a split pane (BH-104, [S] string).
  public static let switchToSplitHint = "Switch to Split View"
  public static let switchToSpaceHint = "Switch to Space"
  public static let pasteAndGoTitle = "Paste and Go"

  public static func make(query raw: String, input: Input) -> [Result] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch input.scope {
    case .actions:
      // BH-106: action search lists the shell's actions only.
      return CommandBarActions.filter(input.actions, query: query).map {
        Result(kind: .action($0.id), title: $0.title, subtitle: "Action", trailingHint: nil, removalID: nil)
      }
    case .siteSearch(let engine):
      // BH-107: one row per query, to the scoped engine.
      guard !query.isEmpty, let url = engine.url(for: query) else { return [] }
      return [Result(kind: .siteSearch(url), title: query, subtitle: "Search \(engine.name)", trailingHint: nil,
                     removalID: "sitesearch:\(url.absoluteString)")]
    case .normal:
      break
    }

    var results: [Result] = []

    // BH-108 / GS-035: a URL on the clipboard makes "Paste and Go" the top suggestion while the query is empty.
    if query.isEmpty, let url = input.clipboardURL {
      results.append(Result(kind: .pasteAndGo(url), title: pasteAndGoTitle, subtitle: url.absoluteString,
                            trailingHint: nil, removalID: nil))
    }

    let url = URLInputParser.url(from: query)
    if let url {
      // The subtitle shows what the input expands to; when the input is that URL already (Cmd-L), it adds nothing.
      let subtitle = url.absoluteString == query ? "" : url.absoluteString
      results.append(Result(kind: .open(url), title: query, subtitle: subtitle, trailingHint: nil, removalID: nil))
    }

    let matching = query.isEmpty ? openTabsAll(input) : openTabsAll(input).filter { tab in
      tab.title.localizedStandardContains(query) || (tab.url.host() ?? "").localizedStandardContains(query)
    }
    for tab in matching.prefix(maxSwitchResults) {
      results.append(Result(kind: .switchTo(tab.node), title: tab.title, subtitle: tab.url.host() ?? tab.url.absoluteString,
                            trailingHint: tab.isSplitPane ? switchToSplitHint : switchHint,
                            removalID: "tab:\(tab.node.uuidString)"))
    }

    // Spaces (BH-104): after the tabs, capped; an empty query lists no Spaces (the tabs are the empty surface).
    if !query.isEmpty {
      for space in input.spaces.filter({ $0.title.localizedStandardContains(query) }).prefix(maxSpaceResults) {
        results.append(Result(kind: .switchSpace(space.id), title: space.title, subtitle: "Space",
                              trailingHint: switchToSpaceHint, removalID: nil))
      }
    }

    // #96: an explicit http(s) scheme makes the input a URL for certain (Cmd-L prefills one), so a search row
    // would only repeat it. Chromium keeps a demoted search-what-you-typed row there; Arc unverified [I] (RT-08).
    // Schemeless input such as `example.com` stays ambiguous and keeps both rows.
    // BH-113: `searchSuggestEnabled` off drops the row and the engine round trip it stands for.
    let isExplicitURL = url != nil && URLInputParser.hasExplicitScheme(query)
    if !query.isEmpty, !isExplicitURL, input.searchSuggestionsEnabled {
      results.append(Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                            subtitle: "Search \(CommandBarSettings.searchEngineName)", trailingHint: nil,
                            removalID: "search:\(query)"))
    }
    return results.filter { result in
      result.removalID.map { !input.excluded.contains($0) } ?? true
    }
  }

  private static func openTabsAll(_ input: Input) -> [OpenTab] { input.openTabs }

  /// The pre-#112 convenience: a plain query over open tabs (no clipboard, Spaces, actions or exclusions).
  public static func make(query raw: String, openTabs: [OpenTab]) -> [Result] {
    var input = Input()
    input.openTabs = openTabs
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
