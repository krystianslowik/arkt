import Foundation

/// Facts a result carries so the preview column can be decided without the window (#372).
public struct CommandBarPreviewFacts: Sendable, Equatable {
  public var rowKind: CommandBarRowKind
  public var title: String
  public var host: String
  public var spaceTitle: String?
  /// Already worded for the meta line ("12 min ago", "Yesterday", "Now"). Nil omits the time.
  public var timeText: String?
  /// A history row whose page is already an open tab: Return switches to it.
  public var isAlsoOpen: Bool
  public var url: URL
  public var node: NodeID?

  public init(rowKind: CommandBarRowKind, title: String, host: String, spaceTitle: String?, timeText: String?,
              isAlsoOpen: Bool, url: URL, node: NodeID?) {
    self.rowKind = rowKind
    self.title = title
    self.host = host
    self.spaceTitle = spaceTitle
    self.timeText = timeText
    self.isAlsoOpen = isAlsoOpen
    self.url = url
    self.node = node
  }
}

/// What the preview column shows for one row. Nil means the bar stays narrow (#372).
public enum CommandBarPreview {
  public struct Content: Sendable, Equatable {
    public var title: String
    public var meta: String
    public var showsOpenDot: Bool
    public var primaryTitle: String
    public var splitTitle: String
    public var thumbnail: Thumbnail
    public var url: URL
    public var node: NodeID?
  }

  /// Where the thumbnail comes from. An open tab asks the live frame; history asks the cache (#370).
  public enum Thumbnail: Sendable, Equatable {
    case liveTab(NodeID)
    case cachedPage(URL)
  }

  public static let splitTitle = "Split View"
  public static let switchTitle = "Switch to Tab"
  public static let openTitle = "Open"

  /// The column for `facts`, or nil. An empty query never widens, even when a recent tab is selected.
  public static func content(for facts: CommandBarPreviewFacts?, queryIsEmpty: Bool) -> Content? {
    guard !queryIsEmpty, let facts else { return nil }
    switch facts.rowKind {
    case .openTab:
      return Content(title: facts.title,
                     meta: openMeta(host: facts.host, space: facts.spaceTitle, time: facts.timeText),
                     showsOpenDot: true, primaryTitle: switchTitle, splitTitle: splitTitle,
                     thumbnail: facts.node.map { .liveTab($0) } ?? .cachedPage(facts.url),
                     url: facts.url, node: facts.node)
    case .history:
      return Content(title: facts.title, meta: visitedMeta(host: facts.host, time: facts.timeText),
                     showsOpenDot: false, primaryTitle: facts.isAlsoOpen ? switchTitle : openTitle,
                     splitTitle: splitTitle, thumbnail: .cachedPage(facts.url),
                     url: facts.url, node: facts.isAlsoOpen ? facts.node : nil)
    case .searchSuggestion, .siteSearch, .action, .pasteAndGo, .archived, .address, .space, .noMatch:
      return nil
    }
  }

  private static func openMeta(host: String, space: String?, time: String?) -> String {
    var text = host + " · open"
    if let space, !space.isEmpty { text += " in \(space)" }
    if let time, !time.isEmpty { text += ", \(time)" }
    return text
  }

  private static func visitedMeta(host: String, time: String?) -> String {
    if let time, !time.isEmpty { return "\(host) · visited \(time)" }
    return "\(host) · visited"
  }
}

/// Drops a thumbnail that arrives after the selection has moved (#372). The column shows the well at once;
/// only a completion whose token is still current may replace it.
public struct CommandBarThumbnailGate: Equatable, Sendable {
  private var current = 0

  public init() {}

  public mutating func begin() -> Int {
    current += 1
    return current
  }

  public func accepts(_ token: Int) -> Bool { token == current && token != 0 }
}
