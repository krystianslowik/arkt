import Foundation
import SidebarModel

/// Archive search text (BH-087, #111): Unicode case-, diacritic- and width-insensitive, over the titles and URLs of
/// an archived node and every node inside it. `Persistence.ArchiveStore` stores `searchText(of:)` in its
/// `search_text` column and matches a folded query against it; CoreBridge uses `matches` and `matchingTabs` for the
/// rows it shows, so the store and the window always agree on what matched.
public enum ArchiveSearch {
  /// The fold applied to both sides of a match: lower case, no diacritics, no full-width forms.
  public static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
  }

  /// A typed query, trimmed and folded; nil when nothing is left to search for.
  public static func query(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return fold(trimmed)
  }

  /// Folded titles (custom and page titles) and URLs of `snapshot` and its whole subtree, one per line.
  public static func searchText(of snapshot: NodeSnapshot) -> String {
    var parts: [String] = []
    collect(snapshot, into: &parts)
    return parts.map(fold).joined(separator: "\n")
  }

  /// True when the folded `query` occurs in `snapshot`'s search text.
  public static func matches(_ snapshot: NodeSnapshot, query: String) -> Bool {
    searchText(of: snapshot).contains(query)
  }

  /// The tabs inside a folder or split that match `query`, depth first, when the root's own title and URL do not:
  /// the Archive shows such a folder open with these tabs under it. Empty for a tab, or a root that matches itself.
  public static func matchingTabs(in snapshot: NodeSnapshot, query: String) -> [NodeSnapshot] {
    guard !snapshot.children.isEmpty else { return [] }
    var own: [String] = []
    collectOwn(snapshot, into: &own)
    if own.contains(where: { fold($0).contains(query) }) { return [] }
    var found: [NodeSnapshot] = []
    func visit(_ node: NodeSnapshot) {
      if case .tab = node.kind, matches(node, query: query) { found.append(node) }
      node.children.forEach(visit)
    }
    snapshot.children.forEach(visit)
    return found
  }

  private static func collect(_ node: NodeSnapshot, into parts: inout [String]) {
    collectOwn(node, into: &parts)
    for child in node.children { collect(child, into: &parts) }
  }

  private static func collectOwn(_ node: NodeSnapshot, into parts: inout [String]) {
    switch node.kind {
    case .tab(let tab):
      if let custom = tab.customTitle { parts.append(custom) }
      parts.append(tab.title)
      parts.append(tab.url.absoluteString)
    case .folder(let folder):
      parts.append(folder.title)
    case .split:
      break
    }
  }
}
