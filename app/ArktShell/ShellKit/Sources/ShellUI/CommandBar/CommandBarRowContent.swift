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
    case .reload: "arrow.clockwise"
    case .open: "globe"
    case .folder: "folder"
    case .extensionAction: "puzzlepiece.extension"
    }
  }

  /// The text after the title: host and path (tabs, history, Paste and Go), "<n> tabs" (folders), the description
  /// (extensions). Go, Search for and suggestion rows have none.
  public var secondaryText: String {
    switch kind {
    case .switchTo, .history, .pasteAndGo, .reload, .folder, .extensionAction: subtitle
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
    case .reload: CommandBarResults.reloadTitle
    case .suggestion: "Search"
    case .search: nil
    }
  }

  /// What a screen reader says for a command bar row (design, Accessibility): "<title>, <secondary text>, <kind>,
  /// <k> of <n>" (k from 1).
  public func commandBarLabel(position: Int, of count: Int) -> String {
    [displayTitle, secondaryText, accessibilityKind, "\(position) of \(count)"].filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  /// What a screen reader says for a row of Little Arkt's quick lookup, worded as before #993: "<title>, <host or
  /// address>, <kind>, <k> of <n>", the search row read as its query ("search suggestion"), an address as "address".
  public func accessibilityLabel(position: Int, of count: Int) -> String {
    let (secondary, kindWord): (String, String) = switch kind {
    case .switchTo: (subtitle, "open tab")
    case .open: (CommandBarTitleMatch.displayURL(subtitle), "address")
    case .pasteAndGo: (CommandBarTitleMatch.displayURL(subtitle), "clipboard")
    case .reload: (subtitle, "reload")
    case .search, .suggestion: ("", "search suggestion")
    case .history: (subtitle, "history")
    case .folder: (subtitle, "folder")
    case .extensionAction: (subtitle, "extension")
    }
    return [title, secondary, kindWord, "\(position) of \(count)"].filter { !$0.isEmpty }.joined(separator: ", ")
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
    case .reload: "reload"
    }
  }
}

/// Where a title matches the query, so the match can be drawn in semibold, and how a URL reads on a row.
public enum CommandBarTitleMatch {

  /// Where each word of `query` starts a word of `title` (the first such place per word), ignoring case and
  /// diacritics, as the matching does: the parts drawn in semibold.
  public static func wordStartRanges(of query: String, in title: String) -> [Range<String.Index>] {
    query.split(whereSeparator: \.isWhitespace).compactMap { word in
      var from = title.startIndex
      while let found = title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: from..<title.endIndex) {
        if found.lowerBound == title.startIndex || startsWord(at: found.lowerBound, in: title) { return found }
        from = title.index(after: found.lowerBound)
      }
      return nil
    }
  }

  private static func startsWord(at index: String.Index, in title: String) -> Bool {
    let before = title[title.index(before: index)]
    if !(before.isLetter || before.isNumber) { return true }
    return isUnspaced(before) || isUnspaced(title[index])
  }

  /// Scripts written without spaces between words: CJK ideographs, kana, Hangul.
  private static func isUnspaced(_ character: Character) -> Bool {
    guard let value = character.unicodeScalars.first?.value else { return false }
    switch value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF66...0xFF9F: return true
    default: return false
    }
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
