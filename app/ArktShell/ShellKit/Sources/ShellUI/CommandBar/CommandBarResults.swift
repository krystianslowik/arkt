#if DEBUG
import Synchronization
#endif
import Foundation

/// The command bar's rows (design/command-bar/README.md, "Row order and what each group searches"): an optional
/// literal row (Paste and Go, or Go to a typed address), then up to five groups in a fixed order, Tabs, Folders,
/// History, Extensions and Search, at most three rows each. Filled synchronously from in-memory lists on every
/// keystroke; search suggestions are the only part that arrives later, and they go at the bottom.
///
/// Little Arkt's quick lookup reuses the row type with its own plain list (`make(query:openTabs:)`).
public enum CommandBarResults {
  /// An open tab the bar can switch to; `node` is its sidebar node. `isSplitPane`: it is a pane of a split, so
  /// Little Arkt's lookup says "Switch to Split View" (BH-104).
  public struct OpenTab: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    public let url: URL
    public let isSplitPane: Bool
    /// When the tab was last shown in this window; nil when it has not been since the app started. Ranks the Tabs
    /// group and picks the empty field's recent tabs.
    public let lastViewed: Date?
    /// The Space the tab is open in.
    public let spaceTitle: String?
    /// What the bar matches besides the title, worked out once: the window keeps its open tabs between keystrokes,
    /// so a keystroke over 2,000 tabs does no string work per tab beyond the search itself (#606).
    let matchText: MatchText
    public init(node: NodeID, title: String, url: URL, isSplitPane: Bool = false, lastViewed: Date? = nil,
                spaceTitle: String? = nil) {
      self.node = node; self.title = title; self.url = url; self.isSplitPane = isSplitPane
      self.lastViewed = lastViewed
      self.spaceTitle = spaceTitle
      matchText = MatchText(title: title, url: url)
    }
  }

  /// A page's title and address as the matching reads them, folded once: the title and the address as stored
  /// (without the scheme; an internationalized host in its `xn--` form) with case and diacritics folded, and the host as
  /// the rows show it (`HostDisplay`, #732) with case folded only, when it reads differently.
  struct MatchText: Sendable, Equatable {
    let title: WordStartMatch.Text
    let address: WordStartMatch.Text
    let shownHost: WordStartMatch.Text?
    init(title: String, url: URL) {
      self.title = WordStartMatch.Text(title)
      address = WordStartMatch.Text(CommandBarTitleMatch.displayURL(url.absoluteString))
      let raw = url.host()
      let shown = raw.flatMap { $0.range(of: "xn--", options: .caseInsensitive) != nil ? HostDisplay.host(of: url) : nil }
      shownHost = shown == raw ? nil : shown.map { WordStartMatch.Text($0, foldsDiacritics: false) }
    }
  }

  /// A folder in the Pinned section of the window (nested ones included), for the Folders group (BH-104).
  public struct Folder: Sendable, Equatable {
    public let node: NodeID
    public let title: String
    /// The tabs inside it, nested folders included: "<n> tabs".
    public let tabCount: Int
    /// When a tab in the folder was last shown in this window.
    public let lastViewed: Date?
    public init(node: NodeID, title: String, tabCount: Int, lastViewed: Date? = nil) {
      self.node = node; self.title = title; self.tabCount = tabCount; self.lastViewed = lastViewed
    }
  }

  /// An enabled extension with a toolbar action, for the Extensions group (BH-104). `id` is the action's id.
  public struct Extension: Sendable, Equatable {
    public let id: String
    public let name: String
    /// The manifest's short description; empty when it has none.
    public let description: String
    /// The extension's icon, PNG; nil draws the puzzle piece.
    public let iconPNG: Data?
    public init(id: String, name: String, description: String, iconPNG: Data? = nil) {
      self.id = id; self.name = name; self.description = description; self.iconPNG = iconPNG
    }
  }

  /// A page the history provider remembers, in the provider's (frecency) order. There is no history store yet: the
  /// app passes none, and tests pass synthetic visits. `openTab` is set when that page is already an open tab, which
  /// keeps it out of the History group.
  public struct HistoryVisit: Sendable, Equatable {
    public let title: String
    public let url: URL
    public let visited: Date?
    public let openTab: NodeID?
    let matchText: MatchText
    public init(title: String, url: URL, visited: Date? = nil, openTab: NodeID? = nil) {
      self.title = title; self.url = url; self.visited = visited; self.openTab = openTab
      matchText = MatchText(title: title, url: url)
    }
  }

  /// The groups, in the order the list shows them. Each row of a group carries it; the literal row carries none.
  public enum Group: Sendable, Equatable, CaseIterable {
    case tabs, folders, history, extensions, search

    public var title: String {
      switch self {
      case .tabs: "Tabs"
      case .folders: "Folders"
      case .history: "History"
      case .extensions: "Extensions"
      case .search: "Search"
      }
    }
  }

  /// Everything the rows are made from besides the query text.
  public struct Input: Sendable, Equatable {
    public var openTabs: [OpenTab] = []
    /// The tab on screen: never offered under Tabs (Return on it would only close the bar).
    public var currentTab: NodeID?
    public var folders: [Folder] = []
    public var history: [HistoryVisit] = []
    public var extensions: [Extension] = []
    /// The search engine's suggestions for the query, as they arrived (`CommandBarController`).
    public var suggestions: [String] = []
    /// "Include search engine suggestions" (#562): off shows no suggestions. The Search for row stays.
    public var searchSuggestionsEnabled = true
    /// BH-108: an address read from the clipboard when the bar opened; nil adds no Paste and Go.
    public var clipboardURL: URL?
    /// Cmd-L's untouched page (KB-004): the empty field leads with a Reload row for it. Nil adds none.
    public var reloadURL: URL?
    /// BH-109: removal ids hidden this session (Cmd-Opt-Delete on a history row).
    public var excluded: Set<String> = []
    /// The clock for "Yesterday"; injected so results are deterministic.
    public var now = Date()
    public init() {}
  }

  public enum Kind: Sendable, Equatable {
    /// Go: the text parses as an address (KB-001). Also Little Arkt's address row.
    case open(URL)
    case switchTo(NodeID)
    /// Search for "<text>": the exact text with the user's engine.
    case search(URL)
    /// A search engine suggestion, searched for as it reads.
    case suggestion(URL)
    /// BH-108: open the clipboard address (GS-035 names it "Paste and Go").
    case pasteAndGo(URL)
    /// KB-004: reload the page Cmd-L opened on.
    case reload(URL)
    /// A history visit (#372). Return opens it.
    case history(URL)
    /// BH-104: show this folder in the sidebar.
    case folder(NodeID)
    /// BH-104: open this extension action's popup, as a toolbar click would.
    case extensionAction(String)

    public var name: String {
      switch self {
      case .open: "open"
      case .switchTo: "switch"
      case .search: "search"
      case .suggestion: "suggestion"
      case .pasteAndGo: "pasteAndGo"
      case .reload: "reload"
      case .history: "history"
      case .folder: "folder"
      case .extensionAction: "extension"
      }
    }
  }

  public struct Result: Sendable, Equatable {
    public let kind: Kind
    public let title: String
    /// The secondary text: host and path, "<n> tabs", an extension's description. Little Arkt shows it as is.
    public let subtitle: String
    /// Little Arkt's caption on a tab row ("Switch to Tab", "Switch to Split View"); nil elsewhere.
    public let trailingHint: String?
    /// BH-109: identifies a removable row ("history:<url>"); nil for every other row.
    public let removalID: String?
    /// The group the row belongs to; nil for the literal row and for Little Arkt's rows.
    public var group: Group?
    /// "Yesterday": when a history page was visited. Unselected history rows show it.
    public var timeText: String?
    /// An extension's own icon, PNG.
    public var iconPNG: Data?

    public init(kind: Kind, title: String, subtitle: String, trailingHint: String?, removalID: String?) {
      self.kind = kind; self.title = title; self.subtitle = subtitle; self.trailingHint = trailingHint
      self.removalID = removalID
    }

    /// Accessibility value of `commandBar.row`: what Return does.
    public var accessibilityCaption: String {
      switch kind {
      case .open: "Open"
      case .switchTo: trailingHint ?? CommandBarResults.switchHint
      case .search, .suggestion: "Search"
      case .pasteAndGo: CommandBarResults.pasteAndGoTitle
      case .reload: CommandBarResults.reloadTitle
      case .history: "Open"
      case .folder: "Show Folder"
      case .extensionAction: "Open Extension"
      }
    }
  }

  public static let maxRowsPerGroup = 3
  /// Little Arkt's lookup: at most six open tabs.
  public static let maxSwitchResults = 6
  public static let switchHint = "Switch to Tab"
  /// The caption of an open tab that is a split pane (BH-104, [S] string), in Little Arkt's lookup.
  public static let switchToSplitHint = "Switch to Split View"
  public static let pasteAndGoTitle = "Paste and Go"
  public static let reloadTitle = "Reload"

  /// The header text over each row that starts a group; keyed by row index.
  public static func groupHeaders(of results: [Result]) -> [Int: String] {
    var headers: [Int: String] = [:]
    var previous: Group?
    for (index, result) in results.enumerated() {
      if let group = result.group, group != previous { headers[index] = group.title }
      previous = result.group
    }
    return headers
  }

  /// Said once typing settles (design, Accessibility): "<n> results", or the Search row alone.
  public static func countAnnouncement(for results: [Result]) -> String {
    if results.count == 1, case .search = results[0].kind { return "No matches. Return searches the web." }
    return results.count == 1 ? "1 result" : "\(results.count) results"
  }

  // MARK: The command bar

  /// The rows for `query`. An empty (or blank) query is the empty field: Paste and Go, recent tabs, recent history.
  public static func grouped(query raw: String, input: Input) -> [Result] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? emptyField(input) : typed(query: query, input: input)
  }

  private static func emptyField(_ input: Input) -> [Result] {
    var rows: [Result] = []
    if let url = input.reloadURL {
      rows.append(Result(kind: .reload(url), title: reloadTitle, subtitle: HostDisplay.hostOrAddress(url),
                         trailingHint: nil, removalID: nil))
    }
    if let url = input.clipboardURL {
      rows.append(Result(kind: .pasteAndGo(url), title: pasteAndGoTitle, subtitle: shownURL(url),
                         trailingHint: nil, removalID: nil))
    }
    let candidates = input.openTabs.enumerated().filter { $0.element.node != input.currentTab }
    let recent = topThree(candidates) { a, b in
      isMoreRecent(a.element.lastViewed, b.element.lastViewed, orIndex: a.offset < b.offset)
    }
    for entry in recent { rows.append(tabRow(entry.element)) }
    let openURLs = input.history.isEmpty ? [] : Set(input.openTabs.map(\.url))
    let visits = input.history.enumerated()
      .filter { isKeptVisit($0.element, openURLs: openURLs, excluded: input.excluded) }
    for entry in topThree(visits, by: { a, b in
      isMoreRecent(a.element.visited, b.element.visited, orIndex: a.offset < b.offset)
    }) {
      rows.append(historyRow(entry.element, now: input.now))
    }
    return rows
  }

  private static func typed(query: String, input: Input) -> [Result] {
    var rows: [Result] = []
    if let url = URLInputParser.url(from: query) {
      rows.append(Result(kind: .open(url), title: query, subtitle: "", trailingHint: nil, removalID: nil))
    }
    let match = WordStartMatch(query)

    // Tabs: match quality, then most recently viewed. Only the best three are kept, by index, and rows are built for
    // those alone (#606, #839).
    var best: [(quality: Int, index: Int)] = []
    let tabs = input.openTabs
    for index in tabs.indices {
      guard let quality = match.quality(tabs[index].matchText), tabs[index].node != input.currentTab else { continue }
      if best.count == maxRowsPerGroup, let last = best.last,
         !ranksTab((quality, index), before: last, in: tabs) { continue }
      let at = best.firstIndex { ranksTab((quality, index), before: $0, in: tabs) } ?? best.count
      best.insert((quality, index), at: at)
      if best.count > maxRowsPerGroup { best.removeLast() }
    }
    for entry in best { rows.append(tabRow(tabs[entry.index])) }

    // Folders: the name only; match quality, then the most recently viewed tab inside.
    var folders: [(quality: Int, index: Int, folder: Folder)] = []
    for (index, folder) in input.folders.enumerated() {
      if let quality = match.quality(title: folder.title, detail: nil) { folders.append((quality, index, folder)) }
    }
    for entry in topThree(folders, by: { a, b in
      a.quality != b.quality ? a.quality < b.quality
        : isMoreRecent(a.folder.lastViewed, b.folder.lastViewed, orIndex: a.index < b.index)
    }) {
      var row = Result(kind: .folder(entry.folder.node), title: entry.folder.title,
                       subtitle: tabCountText(entry.folder.tabCount), trailingHint: nil, removalID: nil)
      row.group = .folders
      rows.append(row)
    }

    // History: the provider's order (frecency), pages that are open tabs left out.
    let openURLs = input.history.isEmpty ? [] : Set(input.openTabs.map(\.url))
    var history = 0
    for visit in input.history where history < maxRowsPerGroup {
      guard isKeptVisit(visit, openURLs: openURLs, excluded: input.excluded),
            match.quality(visit.matchText) != nil
      else { continue }
      rows.append(historyRow(visit, now: input.now))
      history += 1
    }

    // Extensions: name and description; match quality, then name.
    var extensions: [(quality: Int, index: Int, item: Extension)] = []
    for (index, item) in input.extensions.enumerated() {
      if let quality = match.quality(title: item.name, detail: item.description) {
        extensions.append((quality, index, item))
      }
    }
    for entry in topThree(extensions, by: { a, b in
      a.quality != b.quality ? a.quality < b.quality
        : a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
    }) {
      var row = Result(kind: .extensionAction(entry.item.id), title: entry.item.name, subtitle: entry.item.description,
                       trailingHint: nil, removalID: nil)
      row.group = .extensions
      row.iconPNG = entry.item.iconPNG
      rows.append(row)
    }

    // Search: the exact text, then up to two suggestions below it.
    var search = Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                        subtitle: "Search \(CommandBarSettings.searchEngineName)", trailingHint: nil, removalID: nil)
    search.group = .search
    rows.append(search)
    if input.searchSuggestionsEnabled {
      var seen: Set<String> = [query.lowercased()]
      for text in input.suggestions where seen.count < maxRowsPerGroup {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
        var row = Result(kind: .suggestion(URLInputParser.searchURL(for: trimmed)), title: trimmed, subtitle: "",
                         trailingHint: nil, removalID: nil)
        row.group = .search
        rows.append(row)
      }
    }
    return rows
  }

  /// Match quality first, then the most recently viewed, then the original order.
  private static func ranksTab(_ a: (quality: Int, index: Int), before b: (quality: Int, index: Int),
                               in tabs: [OpenTab]) -> Bool {
    if a.quality != b.quality { return a.quality < b.quality }
    return isMoreRecent(tabs[a.index].lastViewed, tabs[b.index].lastViewed, orIndex: a.index < b.index)
  }

  /// The first three of `items` by `order`, without sorting them all.
  private static func topThree<T>(_ items: [T], by order: (T, T) -> Bool) -> [T] {
    var top: [T] = []
    for item in items {
      let at = top.firstIndex { order(item, $0) } ?? top.count
      if at < maxRowsPerGroup {
        top.insert(item, at: at)
        if top.count > maxRowsPerGroup { top.removeLast() }
      }
    }
    return top
  }

  /// Newer first; a date beats none; otherwise `orIndex` (the original order).
  private static func isMoreRecent(_ a: Date?, _ b: Date?, orIndex: Bool) -> Bool {
    switch (a, b) {
    case let (a?, b?) where a != b: a > b
    case (_?, nil): true
    case (nil, _?): false
    default: orIndex
    }
  }

  private static func isKeptVisit(_ visit: HistoryVisit, openURLs: Set<URL>, excluded: Set<String>) -> Bool {
    visit.openTab == nil && !openURLs.contains(visit.url) && !excluded.contains(historyRemovalID(visit.url))
  }

  private static func historyRemovalID(_ url: URL) -> String { "history:\(url.absoluteString)" }

  /// "1 tab", "6 tabs".
  static func tabCountText(_ count: Int) -> String { count == 1 ? "1 tab" : "\(count) tabs" }

  /// Host and path as a row shows them, without the scheme (`HostDisplay` writes the host).
  static func shownURL(_ url: URL) -> String { CommandBarTitleMatch.displayURL(HostDisplay.address(url)) }

  private static func tabRow(_ tab: OpenTab) -> Result {
    #if DEBUG
    tabRowCounter?.count()
    #endif
    var row = Result(kind: .switchTo(tab.node), title: HostDisplay.title(tab.title, for: tab.url),
                     subtitle: shownURL(tab.url), trailingHint: switchHint, removalID: nil)
    row.group = .tabs
    return row
  }

  private static func historyRow(_ visit: HistoryVisit, now: Date) -> Result {
    var row = Result(kind: .history(visit.url), title: HostDisplay.title(visit.title, for: visit.url),
                     subtitle: shownURL(visit.url), trailingHint: nil, removalID: historyRemovalID(visit.url))
    row.group = .history
    row.timeText = visit.visited.map { CommandBarRelativeTime.text(from: $0, to: now) }
    return row
  }

  // MARK: Little Arkt's lookup

  /// Little Arkt's quick lookup (#354): an empty query lists up to six open tabs; text lists the typed address, the
  /// open tabs whose title or host holds it (up to six) and a search row, which an address with its scheme drops (#96).
  public static func make(query raw: String, openTabs: [OpenTab]) -> [Result] {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty { return openTabs.prefix(maxSwitchResults).map(lookupTabRow) }
    var results: [Result] = []
    let url = URLInputParser.url(from: query)
    if let url {
      // The subtitle shows what the input expands to; when the input is that URL already, it adds nothing.
      let subtitle = url.absoluteString == query ? "" : HostDisplay.address(url)
      results.append(Result(kind: .open(url), title: query, subtitle: subtitle, trailingHint: nil, removalID: nil))
    }
    let match = StandardMatch(query)
    let matching = openTabs.filter { tab in
      match.found(in: tab.title) || match.found(in: tab.url.host() ?? "") // not shown
        || shownHost(of: tab.url, contains: query)
    }
    results += matching.prefix(maxSwitchResults).map(lookupTabRow)
    if !(url != nil && URLInputParser.hasExplicitScheme(query)) {
      results.append(Result(kind: .search(URLInputParser.searchURL(for: query)), title: query,
                            subtitle: "Search \(CommandBarSettings.searchEngineName)", trailingHint: nil,
                            removalID: nil))
    }
    return results
  }

  private static func lookupTabRow(_ tab: OpenTab) -> Result {
    Result(kind: .switchTo(tab.node), title: HostDisplay.title(tab.title, for: tab.url),
           subtitle: HostDisplay.hostOrAddress(tab.url), trailingHint: tab.isSplitPane ? switchToSplitHint : switchHint,
           removalID: nil)
  }

  /// `localizedStandardContains` with the current locale fetched once per pass (#606): case- and
  /// diacritic-insensitive and nonliteral, in the current locale. Little Arkt's lookup matching.
  struct StandardMatch {
    private let query: CFString
    private let locale = CFLocaleCopyCurrent()
    init(_ query: String) { self.query = query as CFString }
    func found(in text: String) -> Bool {
      let text = text as CFString
      return CFStringFindWithOptionsAndLocale(text, query, CFRange(location: 0, length: CFStringGetLength(text)),
                                              [.compareCaseInsensitive, .compareDiacriticInsensitive, .compareNonliteral],
                                              locale, nil)
    }
  }

  /// Whether the host the rows show for `url` (`HostDisplay`, #732) holds `query`, so a host typed in Unicode finds it
  /// as well as the encoded form. Case is folded, diacritics are not. Little Arkt's lookup matching.
  static func shownHost(of url: URL, contains query: String) -> Bool {
    guard let raw = url.host(), raw.range(of: "xn--", options: .caseInsensitive) != nil,
          let shown = HostDisplay.host(of: url), shown != raw else { return false }
    return shown.range(of: query, options: .caseInsensitive) != nil
  }
}

/// The command bar's matching (design, "Row order"): every word of the query starts a word of the text, ignoring
/// case and diacritics. A word starts at the beginning, after a character that is not a letter or digit, or anywhere
/// in text written without spaces (Han, kana, Hangul). `quality` ranks a match: 0 when the title starts with the
/// query's first word, 1 when every word is found in the title, 2 when some are found only in the detail (host and
/// path, a description) or in a shown host, which folds case but not diacritics. Nil when a word is found in none.
///
/// Texts are folded to UTF-16 once (`Text`), so a keystroke over 2,000 open tabs only compares code units (#606).
struct WordStartMatch {
  /// A text folded for matching, as UTF-8.
  struct Text: Sendable, Equatable {
    let bytes: [UInt8]
    init(_ string: String, foldsDiacritics: Bool = true) {
      let options: String.CompareOptions = foldsDiacritics ? [.caseInsensitive, .diacriticInsensitive] : .caseInsensitive
      bytes = Array(string.folding(options: options, locale: nil).utf8)
    }
  }

  private let words: [[UInt8]]
  /// The words folded for case only, for a shown host.
  private let caseWords: [[UInt8]]

  init(_ query: String) {
    let split = query.split(whereSeparator: \.isWhitespace).map(String.init)
    words = split.map { Text($0).bytes }
    caseWords = split.map { Text($0, foldsDiacritics: false).bytes }
  }

  /// A folder name, or an extension's name and description.
  func quality(title: String, detail: String?) -> Int? {
    quality(title: Text(title), detail: detail.map { Text($0) }, shownHost: nil)
  }

  /// A tab or a history visit.
  func quality(_ text: CommandBarResults.MatchText) -> Int? {
    quality(title: text.title, detail: text.address, shownHost: text.shownHost)
  }

  private func quality(title: Text, detail: Text?, shownHost: Text?) -> Int? {
    guard !words.isEmpty else { return nil }
    var inTitle = true
    for index in words.indices {
      if Self.startsWord(words[index], in: title.bytes) { continue }
      if let detail, Self.startsWord(words[index], in: detail.bytes) {
        inTitle = false
      } else if let shownHost, Self.startsWord(caseWords[index], in: shownHost.bytes) {
        inTitle = false
      } else {
        return nil
      }
    }
    guard inTitle else { return 2 }
    return Self.hasPrefix(words[0], title.bytes) ? 0 : 1
  }

  private static func hasPrefix(_ word: [UInt8], _ text: [UInt8]) -> Bool {
    guard word.count <= text.count else { return false }
    return text.withUnsafeBytes { text in
      word.withUnsafeBytes { word in
        guard let base = text.baseAddress, let needle = word.baseAddress else { return word.isEmpty }
        return memcmp(base, needle, word.count) == 0
      }
    }
  }

  /// Whether `word` occurs in `text` at the start of a word. Candidates are found with `memmem`; only a candidate's
  /// preceding character is looked at.
  static func startsWord(_ word: [UInt8], in text: [UInt8]) -> Bool {
    guard !word.isEmpty, word.count <= text.count else { return false }
    return text.withUnsafeBytes { text in
      word.withUnsafeBytes { word in
        guard let base = text.baseAddress, let needle = word.baseAddress else { return false }
        var offset = 0
        while offset + word.count <= text.count,
              let found = memmem(base + offset, text.count - offset, needle, word.count) {
          let at = base.distance(to: found)
          if at == 0 || isBoundary(in: text, at: at) { return true }
          offset = at + 1
        }
        return false
      }
    }
  }

  /// Whether a word may start at byte `at`: the character before it is not a letter or digit, or either of them is
  /// written without spaces between words.
  private static func isBoundary(in text: UnsafeRawBufferPointer, at: Int) -> Bool {
    let before = text[at - 1]
    if before < 0x80 {                                              // ASCII: a letter or digit continues the word
      let isWord = (0x30...0x39).contains(before) || (0x41...0x5A).contains(before) || (0x61...0x7A).contains(before)
      if !isWord { return true }
      guard text[at] >= 0x80, let first = scalar(in: text, at: at) else { return false }
      return isUnspaced(first)
    }
    var start = at - 1
    while start > 0, text[start] & 0xC0 == 0x80 { start -= 1 }     // back to the previous character's first byte
    guard let previous = scalar(in: text, at: start) else { return true }
    if isUnspaced(previous) { return true }
    if let first = scalar(in: text, at: at), isUnspaced(first) { return true }
    return !(previous.properties.isAlphabetic || previous.properties.numericType != nil)
  }

  private static func scalar(in text: UnsafeRawBufferPointer, at index: Int) -> Unicode.Scalar? {
    let lead = text[index]
    if lead < 0x80 { return Unicode.Scalar(lead) }
    let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2
    guard index + length <= text.count else { return nil }
    var value = UInt32(lead) & (length == 2 ? 0x1F : length == 3 ? 0x0F : 0x07)
    for offset in 1..<length { value = value << 6 | UInt32(text[index + offset] & 0x3F) }
    return Unicode.Scalar(value)
  }

  /// Scripts written without spaces between words: CJK ideographs, kana, Hangul.
  private static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF66...0xFF9F: true
    default: false
    }
  }
}

#if DEBUG
extension CommandBarResults {
  /// Counts the tab rows `grouped` builds, for tests that guard a keystroke's work by counting it instead of timing it
  /// (#839). Bound with `$tabRowCounter.withValue`, so it counts only the work of the code it wraps, on that task.
  /// Debug builds only.
  final class TabRowCounter: Sendable {
    private let built = Mutex(0)
    init() {}
    var value: Int { built.withLock { $0 } }
    func count() { built.withLock { $0 += 1 } }
  }

  @TaskLocal static var tabRowCounter: TabRowCounter?
}
#endif

extension CommandBarResults {
  /// Every open tab of a Space for "Switch to Tab": pinned, then Today, depth-first through folders.
  /// A split contributes its first pane, marked as a split pane (activating it shows the split).
  @MainActor
  public static func openTabs(in source: any SidebarSource, space: SpaceID) -> [OpenTab] {
    let spaceTitle = source.space(space)?.title
    var tabs: [OpenTab] = []
    func visit(_ id: NodeID, depth: Int) {
      guard depth < 64, let info = source.node(id) else { return }   // depth guard against a malformed source
      switch info {
      case .tab(let node, let url, let title):
        tabs.append(OpenTab(node: node, title: title, url: url, spaceTitle: spaceTitle))
      case .folder(let folder, _):
        for child in source.children(of: .folder(folder)) { visit(child, depth: depth + 1) }
      case .split:
        if let first = source.firstTab(at: id), case .tab(let node, let url, let title)? = source.node(first) {
          tabs.append(OpenTab(node: node, title: title, url: url, isSplitPane: true, spaceTitle: spaceTitle))
        }
      }
    }
    for id in source.children(of: .pinned(space)) + source.children(of: .today(space)) { visit(id, depth: 0) }
    return tabs
  }

  /// BH-104: open tabs of every Space, in the order the caller passes (the window puts the current Space first,
  /// so a Space switch refresh reorders, BH-111).
  @MainActor
  public static func openTabs(in source: any SidebarSource, spaces: [SpaceID]) -> [OpenTab] {
    spaces.flatMap { openTabs(in: source, space: $0) }
  }

  /// BH-104: the folders of the Pinned section of each Space, nested ones included, depth first, with the tabs each
  /// holds (a nested folder's tabs count for every folder around it; a split counts as one tab, like the sidebar row).
  /// `lastViewed` answers when a tab was last shown in this window.
  @MainActor
  public static func folders(in source: any SidebarSource, spaces: [SpaceID],
                             lastViewed: (NodeID) -> Date? = { _ in nil }) -> [Folder] {
    var folders: [Folder] = []
    func walk(_ id: NodeID, depth: Int) -> (tabs: Int, viewed: Date?) {
      guard depth < 64, let info = source.node(id) else { return (0, nil) }   // depth guard against a malformed source
      switch info {
      case .tab(let node, _, _):
        return (1, lastViewed(node))
      case .split:
        return (1, source.firstTab(at: id).flatMap(lastViewed))
      case .folder(let folder, let title):
        let slot = folders.count
        folders.append(Folder(node: folder, title: title, tabCount: 0))
        var tabs = 0
        var viewed: Date?
        for child in source.children(of: .folder(folder)) {
          let inner = walk(child, depth: depth + 1)
          tabs += inner.tabs
          if let date = inner.viewed { viewed = max(viewed ?? date, date) }
        }
        folders[slot] = Folder(node: folder, title: title, tabCount: tabs, lastViewed: viewed)
        return (tabs, viewed)
      }
    }
    for space in spaces {
      for id in source.children(of: .pinned(space)) { _ = walk(id, depth: 0) }
    }
    return folders
  }
}
