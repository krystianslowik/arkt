import Foundation

/// A key cap glyph as the bar draws it.
public enum CommandBarKeyCaps {
  public static let `return` = "\u{21A9}"
}

/// What a row shows besides its title (design/command-bar/README.md, "Layout" and "Selected row").
extension CommandBarResults.Result {
  /// The title as drawn: the Search for row says what it searches for.
  public var displayTitle: String {
    if case .search = kind { return "Search for \u{201C}\(title)\u{201D}" }
    return title
  }

  /// The SF Symbol in the row's slot when there is no favicon or extension icon.
  public var symbolName: String {
    switch kind {
    case .switchTo: "square.on.square"
    case .search, .suggestion: "magnifyingglass"
    case .history: "clock"
    case .pasteAndGo: "doc.on.clipboard"
    case .open: "globe"
    case .folder: "folder"
    case .extensionAction: "puzzlepiece.extension"
    }
  }

  /// The text after the title: host and path (tabs, history, Paste and Go), "<n> tabs" (folders), the description
  /// (extensions). Go, Search for and suggestion rows have none.
  public var secondaryText: String {
    switch kind {
    case .switchTo, .history, .pasteAndGo, .folder, .extensionAction: subtitle
    case .open, .search, .suggestion: ""
    }
  }

  /// The verb the selected row shows next to the Return key cap. The Search for row has none: its title says it.
  public var verb: String? {
    switch kind {
    case .switchTo: "Switch to Tab"
    case .folder: "Show Folder"
    case .history: "Open"
    case .extensionAction: "Open Extension"
    case .open, .pasteAndGo: "Go"
    case .suggestion: "Search"
    case .search: nil
    }
  }

  /// What a screen reader says for the row: "<title>, <secondary text>, <kind>, <k> of <n>" (k from 1).
  public func accessibilityLabel(position: Int, of count: Int) -> String {
    [displayTitle, secondaryText, accessibilityKind, "\(position) of \(count)"].filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  private var accessibilityKind: String {
    switch kind {
    case .switchTo: "open tab"
    case .folder: "folder"
    case .history: "history"
    case .extensionAction: "extension"
    case .suggestion: "search suggestion"
    case .search: "search for what you typed"
    case .open: "go to address"
    case .pasteAndGo: "paste and go"
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
