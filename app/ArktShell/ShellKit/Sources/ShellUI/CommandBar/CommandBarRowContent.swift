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
  case openTab, searchSuggestion, history, siteSearch, action, pasteAndGo, archived, address, space, noMatch
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
    case .noMatch: .noMatch
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
    case .noMatch: ""
    }
  }

  /// The URL or detail after the title. Search suggestions, site search, actions and Spaces have none: what they are
  /// is said by the trailing caption and the symbol.
  public var secondaryText: String {
    switch rowKind {
    case .openTab, .history, .archived: subtitle
    case .pasteAndGo, .address: CommandBarTitleMatch.displayURL(subtitle)
    case .searchSuggestion, .siteSearch, .action, .space, .noMatch: ""
    }
  }

  /// The right-aligned group. A caption is always shown; Return shows on the selected row, since it runs it.
  public func trailing(isSelected: Bool) -> [CommandBarTrailing] {
    let returnCap = CommandBarTrailing.keyCap(CommandBarKeyCaps.return)
    switch rowKind {
    case .openTab, .address, .archived, .space, .history:
      let caption = timeText ?? trailingHint ?? accessibilityCaption
      return isSelected && rowKind != .archived && rowKind != .space ? [.text(caption), returnCap] : [.text(caption)]
    case .searchSuggestion:
      return isSelected ? [.text("Search"), returnCap] : [.text("Search")]
    case .siteSearch:
      // The Tab key cap says Tab scopes to the site (the smart Tab rule); Return runs the search.
      let tabCap = CommandBarTrailing.keyCap(CommandBarKeyCaps.tab)
      if showsTabKeyCap { return isSelected ? [tabCap, returnCap] : [tabCap] }
      return isSelected ? [returnCap] : []
    case .pasteAndGo:
      return isSelected ? [returnCap] : []
    case .noMatch:
      return []
    case .action:
      if !keyCaps.isEmpty { return keyCaps.map { .keyCap($0) } }
      return isSelected ? [returnCap] : []
    }
  }

  /// Whether the row shows a Tab key cap: a normal-scope site-search row, where Tab scopes to its site.
  public var showsTabKeyCap: Bool { rowKind == .siteSearch && siteSearchEngine != nil }

  /// What a screen reader says for the row: "<title>, <host>, <kind>, <k> of <n>" (k from 1). The empty row is its
  /// title alone.
  public func accessibilityLabel(position: Int, of count: Int) -> String {
    if rowKind == .noMatch { return title }
    return [title, secondaryText, accessibilityKind, "\(position) of \(count)"].filter { !$0.isEmpty }.joined(separator: ", ")
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
    case .noMatch: ""
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

extension CommandBarTitleMatch {
  /// A URL as a row shows it: without the scheme and a trailing slash ("arkt.dev/changelog").
  public static func displayURL(_ text: String) -> String {
    var shown = text
    for scheme in ["https://", "http://"] where shown.lowercased().hasPrefix(scheme) {
      shown.removeFirst(scheme.count)
      break
    }
    if shown.hasSuffix("/") { shown.removeLast() }
    return shown
  }
}
