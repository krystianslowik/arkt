import Foundation
import SidebarModel

/// Counts-only text describing an import, for the read-only `arkt-import-check` tool.
/// Never includes titles, URLs, ids, profile names or theme values: only numbers and enum case names.
public enum ImportCheckSummary {
  /// Favicon coverage computed by the caller, over the imported tabs.
  public struct FaviconCoverage: Hashable, Sendable {
    public var found: Int
    public var missing: Int

    public init(found: Int, missing: Int) {
      self.found = found
      self.missing = missing
    }
  }

  /// The enum case name of `value`, without any associated values: `unsupportedKind("x")` gives `unsupportedKind`.
  public static func caseName(_ value: some Any) -> String {
    let text = String(describing: value)
    return String(text.prefix { $0 != "(" })
  }

  public static func lines(sidebar: Sidebar, report: ImportReport, favicons: FaviconCoverage?) -> [String] {
    let favoriteRoots = Set(sidebar.nodes.values.compactMap { node -> Location? in
      if case .favorites = node.parent { return node.parent }
      return nil
    })
    let favorites = count(favoriteRoots, in: sidebar)
    let pinned = count(sidebar.spaceOrder.map { .pinned($0) }, in: sidebar)
    let today = count(sidebar.spaceOrder.map { .today($0) }, in: sidebar)

    var out = [
      "spaces: \(sidebar.spaceOrder.count) (report: \(report.spaces))",
      "favorites: \(favorites.text)",
      "pinned: \(pinned.text)",
      "today: \(today.text)",
      "imported totals (report): tabs \(report.tabs), folders \(report.folders), splits \(report.splits)",
      "skipped: \(report.skipped.count)",
    ]
    out += grouped(report.skipped.map { caseName($0.reason) })
    out.append("warnings: \(report.warnings.count)")
    out += grouped(report.warnings.map { caseName($0) })
    if let favicons {
      out.append("favicons (imported tabs): found \(favicons.found), missing \(favicons.missing)")
    }
    return out
  }

  struct Counts {
    var tabs = 0
    var folders = 0
    var splits = 0

    var text: String { "tabs \(tabs), folders \(folders), splits \(splits)" }
  }

  static func count(_ roots: some Sequence<Location>, in sidebar: Sidebar) -> Counts {
    var counts = Counts()
    var pending = Array(roots)
    while let location = pending.popLast() {
      for id in sidebar.children(of: location) {
        switch sidebar.nodes[id]?.kind {
        case .tab: counts.tabs += 1
        case .folder:
          counts.folders += 1
          pending.append(.folder(id))
        case .split:
          counts.splits += 1
          pending.append(.split(id))
        case nil: break
        }
      }
    }
    return counts
  }

  static func grouped(_ names: [String]) -> [String] {
    Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
      .sorted { $0.key < $1.key }
      .map { "  \($0.key): \($0.value)" }
  }
}
