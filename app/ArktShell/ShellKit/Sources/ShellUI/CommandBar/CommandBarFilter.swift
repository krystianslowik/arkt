import Foundation

/// The filter pills right of the query field (design/command-bar/README.md, Filters). All is the default on every
/// open.
public enum CommandBarFilter: Int, CaseIterable, Sendable {
  case all, tabs, history, actions

  public var title: String {
    switch self {
    case .all: "All"
    case .tabs: "Tabs"
    case .history: "History"
    case .actions: "Actions"
    }
  }

  /// Archived results belong to All and Tabs; suggestions, site search, addresses and Paste and Go to All only.
  public func includes(_ result: CommandBarResults.Result) -> Bool {
    switch self {
    case .all: true
    case .tabs: result.rowKind == .openTab || result.rowKind == .archived
    case .history: result.rowKind == .history
    case .actions: result.rowKind == .action
    }
  }

  public static func counts(of results: [CommandBarResults.Result]) -> [CommandBarFilter: Int] {
    Dictionary(uniqueKeysWithValues: allCases.map { filter in (filter, results.filter(filter.includes).count) })
  }

  /// With an empty query the counts are hidden.
  public static func showsCounts(forQuery query: String) -> Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
