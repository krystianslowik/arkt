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

// MARK: - Cycling, keys and the empty row

extension CommandBarFilter {
  /// Tab: the next pill, wrapping from Actions to All.
  public var next: CommandBarFilter {
    Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .all
  }

  /// Shift-Tab: the previous pill, wrapping from All to Actions.
  public var previous: CommandBarFilter {
    Self(rawValue: (rawValue + Self.allCases.count - 1) % Self.allCases.count) ?? .all
  }

  /// Cmd-1 to Cmd-4 select the pills in order.
  public init?(commandDigit digit: Int) {
    guard (1...Self.allCases.count).contains(digit) else { return nil }
    self = Self.allCases[digit - 1]
  }

  /// What the filter keeps; a filter that keeps nothing shows one row saying so. All never does.
  public func apply(to results: [CommandBarResults.Result], query: String) -> [CommandBarResults.Result] {
    guard self != .all else { return results }
    let kept = results.filter(includes)
    guard kept.isEmpty else { return kept }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmed.isEmpty ? "No \(self.title)" : "No \(self.title) match \(trimmed)"
    return [CommandBarResults.Result(kind: .noMatch, title: title, subtitle: "", trailingHint: nil, removalID: nil)]
  }
}
