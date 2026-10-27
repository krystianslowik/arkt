import Foundation

/// A key cap glyph or label as the bar draws it.
public enum CommandBarKeyCaps {
  public static let `return` = "\u{21A9}"
  public static let command = "\u{2318}"
  public static let shift = "\u{21E7}"
  public static let option = "\u{2325}"
  public static let control = "\u{2303}"
  public static let tab = "tab"
  public static let escape = "esc"
  public static let up = "\u{2191}"
  public static let down = "\u{2193}"
}

/// One item of a row's trailing group, right-aligned: a caption or a key cap.
public enum CommandBarTrailing: Equatable, Sendable {
  case text(String)
  case keyCap(String)
}

/// The kinds of row the bar shows (design/command-bar/README.md, Row anatomy).
public enum CommandBarRowKind: Equatable, Sendable {
  case openTab, searchSuggestion, history, siteSearch, action, pasteAndGo, archived, address, space
}

extension CommandBarResults.Result {
  public var rowKind: CommandBarRowKind {
    switch kind {
    case .switchTo: .openTab
    case .search: .searchSuggestion
    case .siteSearch: .siteSearch
    case .action: .action
    case .pasteAndGo: .pasteAndGo
    case .restore: .archived
    case .open: .address
    case .switchSpace: .space
    }
  }

  /// The SF Symbol in the row's slot. An open tab's slot carries a generic symbol until favicons reach the bar.
  public var symbolName: String {
    switch rowKind {
    case .openTab: "square.on.square"
    case .searchSuggestion, .siteSearch: "magnifyingglass"
    case .history: "clock"
    case .action: "bolt"
    case .pasteAndGo: "doc.on.clipboard"
    case .archived: "archivebox"
    case .address: "globe"
    case .space: "square.grid.2x2"
    }
  }

  /// The URL or detail after the title. Search suggestions, site search, actions and Spaces have none: what they are
  /// is said by the trailing caption and the symbol.
  public var secondaryText: String {
    switch rowKind {
    case .openTab, .history, .archived, .pasteAndGo, .address: subtitle
    case .searchSuggestion, .siteSearch, .action, .space: ""
    }
  }

  /// The right-aligned group. A caption is always shown; Return shows on the selected row, since it runs it.
  public func trailing(isSelected: Bool) -> [CommandBarTrailing] {
    let returnCap = CommandBarTrailing.keyCap(CommandBarKeyCaps.return)
    switch rowKind {
    case .openTab, .address, .archived, .space, .history:
      let caption = trailingHint ?? accessibilityCaption
      return isSelected && rowKind != .archived && rowKind != .space ? [.text(caption), returnCap] : [.text(caption)]
    case .searchSuggestion:
      return isSelected ? [.text("Search"), returnCap] : [.text("Search")]
    case .siteSearch, .pasteAndGo:
      return isSelected ? [returnCap] : []
    case .action:
      if !keyCaps.isEmpty { return keyCaps.map { .keyCap($0) } }
      return isSelected ? [returnCap] : []
    }
  }

  /// What a screen reader says for the row: "<title>, <host>, <kind>, <k> of <n>" (k from 1).
  public func accessibilityLabel(position: Int, of count: Int) -> String {
    [title, secondaryText, accessibilityKind, "\(position) of \(count)"].filter { !$0.isEmpty }.joined(separator: ", ")
  }

  private var accessibilityKind: String {
    switch rowKind {
    case .openTab: "open tab"
    case .searchSuggestion: "search suggestion"
    case .history: "history"
    case .siteSearch: "site search"
    case .action: "action"
    case .pasteAndGo: "clipboard"
    case .archived: "archived"
    case .address: "address"
    case .space: "space"
    }
  }
}

/// Where a title matches the query, so the match can be drawn in semibold.
public enum CommandBarTitleMatch {
  public static func range(of query: String, in title: String) -> Range<String.Index>? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive])
  }
}
