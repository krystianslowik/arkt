import Foundation

/// The list of one open Folder Preview (BH-093): every tab under the folder in sidebar order (nested folders' tabs
/// and split panes included [I]), filtered by the search text. Typing highlights the first match; the arrows move
/// the highlight within the matches. Pure: the controller and the view read it.
struct FolderPreviewSession {
  struct Item: Equatable {
    var node: NodeID
    var title: String
    var url: URL
    /// The URL's host, matched by the search as well as the title.
    var host: String
  }

  let folder: NodeID
  let items: [Item]
  /// The search text; a new value highlights its first match.
  var query = "" {
    didSet {
      guard query != oldValue else { return }
      matches = Self.filter(items, by: query)
      highlighted = matches.isEmpty ? nil : 0
    }
  }
  private(set) var matches: [Item]
  /// Index into `matches`.
  private(set) var highlighted: Int?

  var highlightedNode: NodeID? { highlighted.map { matches[$0].node } }

  @MainActor
  init(folder: NodeID, in source: any SidebarSource) {
    self.folder = folder
    var tabs: [Item] = []
    Self.collectTabs(under: folder, in: source, into: &tabs, depth: 0)
    items = tabs
    matches = tabs
    highlighted = tabs.isEmpty ? nil : 0
  }

  /// Moves the highlight by `step` matches, stopping at either end.
  mutating func move(by step: Int) {
    guard let current = highlighted, !matches.isEmpty else { return }
    highlighted = min(max(current + step, 0), matches.count - 1)
  }

  /// Highlights match `index` (the pointer over a row).
  mutating func highlight(_ index: Int) {
    guard matches.indices.contains(index) else { return }
    highlighted = index
  }

  private static func filter(_ items: [Item], by query: String) -> [Item] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return items }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    return items.filter { $0.title.range(of: needle, options: options) != nil
      || $0.host.range(of: needle, options: options) != nil }
  }

  @MainActor
  private static func collectTabs(under container: NodeID, in source: any SidebarSource, into tabs: inout [Item],
                                  depth: Int) {
    guard depth < 64, let location = source.node(container)?.childLocation else { return }
    for child in source.children(of: location) {
      if case .tab(let id, let url, let title)? = source.node(child) {
        tabs.append(Item(node: id, title: title, url: url, host: url.host() ?? ""))
      } else {
        collectTabs(under: child, in: source, into: &tabs, depth: depth + 1)
      }
    }
  }
}
