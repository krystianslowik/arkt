import Foundation

/// A shell command the command bar's action search lists and runs (BH-106, KB-081). The window supplies the
/// list and the handler; this type only names and filters them.
public struct CommandBarAction: Sendable, Equatable {
  /// Stable id handed to the window's handler ("newSpace").
  public let id: String
  /// Display title ("New Space").
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public enum CommandBarActions {
  /// Case- and diacritic-insensitive "contains" filter; an empty query keeps every action, in order.
  public static func filter(_ actions: [CommandBarAction], query raw: String) -> [CommandBarAction] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return actions }
    return actions.filter { $0.title.localizedStandardContains(query) }
  }
}
