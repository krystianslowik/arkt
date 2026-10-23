import Foundation

/// Placeholder suggestion provider: URL, matching open tabs, search. Real providers (Chromium autocomplete,
/// history, actions, Spaces) replace `make` later behind the same `Result` type.
public enum CommandBarResults {
  /// An open tab the bar can switch to; `node` is its sidebar node.
  public struct OpenTab: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    public let url: URL
    public init(node: NodeID, title: String, url: URL) { self.node = node; self.title = title; self.url = url }
  }

  public enum Kind: Sendable, Equatable {
    case open(URL)
    case switchTo(NodeID)
    case search(URL)

    public var name: String {
      switch self {
      case .open: "open"
      case .switchTo: "switch"
      case .search: "search"
      }
    }
  }

  public struct Result: Sendable, Equatable {
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let trailingHint: String?
  }

  public static let maxSwitchResults = 6
  public static let switchHint = "Switch to Tab"

  public static func make(query raw: String, openTabs: [OpenTab]) -> [Result] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var results: [Result] = []

    if let url = URLInputParser.url(from: query) {
      results.append(Result(kind: .open(url), title: query, subtitle: url.absoluteString, trailingHint: nil))
    }

    let matching = query.isEmpty ? openTabs : openTabs.filter { tab in
      tab.title.localizedStandardContains(query) || (tab.url.host() ?? "").localizedStandardContains(query)
    }
    for tab in matching.prefix(maxSwitchResults) {
      results.append(Result(kind: .switchTo(tab.node), title: tab.title, subtitle: tab.url.host() ?? tab.url.absoluteString,
                            trailingHint: switchHint))
    }

    if !query.isEmpty {
      results.append(Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                            subtitle: "Search Google", trailingHint: nil))
    }
    return results
  }
}

extension CommandBarResults {
  /// Every open tab of a Space for "Switch to Tab": pinned, then Today, depth-first through folders.
  /// A split contributes its first pane (activating it shows the split).
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
          tabs.append(OpenTab(node: node, title: title, url: url))
        }
      }
    }
    for id in source.children(of: .pinned(space)) + source.children(of: .today(space)) { visit(id, depth: 0) }
    return tabs
  }
}
