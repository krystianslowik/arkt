import Foundation

/// Placeholder suggestion provider: URL, matching open tabs, search. Real providers (Chromium autocomplete,
/// history, actions, Spaces) replace `make` later behind the same `Result` type.
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

  public enum Kind: Sendable, Equatable {
    case open(URL)
    case switchTo(NodeID)
    case search(URL)
    /// An archived item; Enter restores it (BH-086) instead of opening a duplicate.
    case restore(UUID)

    public var name: String {
      switch self {
      case .open: "open"
      case .switchTo: "switch"
      case .search: "search"
      case .restore: "restore"
      }
    }
  }

  public struct Result: Sendable, Equatable {
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let trailingHint: String?

    /// Accessibility value for `commandBar.row` ("Switch to Tab", "Switch to Split View", "Open", "Search").
    public var accessibilityCaption: String {
      switch kind {
      case .open: "Open"
      case .switchTo: trailingHint ?? CommandBarResults.switchHint
      case .search: "Search"
      case .restore: CommandBarResults.restoreHint
      }
    }
  }

  public static let maxSwitchResults = 6
  public static let switchHint = "Switch to Tab"
  /// The caption of an open tab that is a split pane (BH-104, [S] string).
  public static let switchToSplitHint = "Switch to Split View"
  /// The caption of an archived match (#111).
  public static let restoreHint = "Restore from Archive"
  /// Archived matches shown at most (#111, design section 7).
  public static let maxArchivedResults = 3

  /// `archived`: matches the archive store found for `raw`, newest first; listed after open tabs (switching to an
  /// open tab beats restoring a closed one) and before the search row (which restoring beats).
  public static func make(query raw: String, openTabs: [OpenTab], archived: [ArchivedMatch] = []) -> [Result] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var results: [Result] = []

    let url = URLInputParser.url(from: query)
    if let url {
      // The subtitle shows what the input expands to; when the input is that URL already (Cmd-L), it adds nothing.
      let subtitle = url.absoluteString == query ? "" : url.absoluteString
      results.append(Result(kind: .open(url), title: query, subtitle: subtitle, trailingHint: nil))
    }

    let matching = query.isEmpty ? openTabs : openTabs.filter { tab in
      tab.title.localizedStandardContains(query) || (tab.url.host() ?? "").localizedStandardContains(query)
    }
    for tab in matching.prefix(maxSwitchResults) {
      results.append(Result(kind: .switchTo(tab.node), title: tab.title, subtitle: tab.url.host() ?? tab.url.absoluteString,
                            trailingHint: tab.isSplitPane ? switchToSplitHint : switchHint))
    }

    if !query.isEmpty {
      for match in archived.prefix(maxArchivedResults) {
        results.append(Result(kind: .restore(match.id), title: match.title, subtitle: match.subtitle,
                              trailingHint: restoreHint))
      }
    }

    // #96: an explicit http(s) scheme makes the input a URL for certain (Cmd-L prefills one), so a search row
    // would only repeat it. Chromium keeps a demoted search-what-you-typed row there; Arc unverified [I] (RT-08).
    // Schemeless input such as `example.com` stays ambiguous and keeps both rows.
    let isExplicitURL = url != nil && URLInputParser.hasExplicitScheme(query)
    if !query.isEmpty, !isExplicitURL {
      results.append(Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                            subtitle: "Search Google", trailingHint: nil))
    }
    return results
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
}
