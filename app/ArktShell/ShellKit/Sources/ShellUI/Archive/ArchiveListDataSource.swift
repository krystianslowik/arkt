import Foundation

// MARK: - Query

/// The Space filter of the Archive window (BH-088): one Space, or Little Arkt. Nil in `ArchiveQuery` is "Everywhere".
public enum ArchiveSpaceFilter: Hashable, Sendable {
  case space(UUID)
  case littleArkt
}

/// The close-type filter (BH-088). Nil in `ArchiveQuery` is "Closed and Auto Archived".
public enum ArchiveCloseType: Hashable, Sendable, CaseIterable {
  case closed
  case autoArchived

  public var title: String {
    switch self {
    case .closed: "Closed"
    case .autoArchived: "Auto Archived"
    }
  }
}

/// What the Archive window asks for: search text and the two filters, combined (AND). ShellUI's own spelling of the
/// store's `ArchiveFilter`, which CoreBridge maps it to.
public struct ArchiveQuery: Hashable, Sendable {
  public var text: String
  public var space: ArchiveSpaceFilter?
  public var closeType: ArchiveCloseType?

  public init(text: String = "", space: ArchiveSpaceFilter? = nil, closeType: ArchiveCloseType? = nil) {
    self.text = text
    self.space = space
    self.closeType = closeType
  }

  /// Search text with something in it besides whitespace.
  public var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  /// A Space or close-type filter is on (the chip strip shows).
  public var hasFilters: Bool { space != nil || closeType != nil }
}

/// One Space in the filter menu and its chip: the Space's title and theme color (nil: the default theme, drawn in
/// `sidebarForeground`).
public struct ArchiveSpaceOption: Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var color: RGBA?

  public init(id: UUID, title: String, color: RGBA?) {
    self.id = id
    self.title = title
    self.color = color
  }
}

// MARK: - Rows

/// What an archived item is: a tab (its URL, for the letter tile), a folder (with the number of tabs inside), or a
/// Split View.
public enum ArchiveRowKind: Equatable, Sendable {
  case tab(URL?)
  case folder(tabCount: Int)
  case split
}

/// Where an item was archived from, as the row's trailing mark: a Space's color dot (nil color: the default theme),
/// Little Arkt's window glyph, or nothing (Favorites, an unknown Space).
public enum ArchiveRowPlace: Equatable, Sendable {
  case none
  case space(color: RGBA?)
  case littleArkt
}

/// A tab inside a folder or split that matched the search while the folder itself did not (design section 4): shown
/// indented under the opened folder, not selectable on its own.
public struct ArchiveChildRow: Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var url: URL?

  public init(id: UUID, title: String, url: URL?) {
    self.id = id
    self.title = title
    self.url = url
  }
}

/// One row of the Archive window, already worded for display (ShellUI knows no archive types).
public struct ArchiveRow: Equatable, Sendable {
  /// The archived root node's id.
  public var id: UUID
  public var title: String
  /// Host (or "Folder" / "Split View"), Space and relative date: read by VoiceOver and the tooltip, not printed.
  public var detail: String
  /// "Closed" or "Auto archived".
  public var reason: String
  public var kind: ArchiveRowKind
  public var place: ArchiveRowPlace
  /// The compact relative time printed at the trailing edge ("12m", "3h", "Yesterday", "Mon", "22 Sep").
  public var time: String
  /// Tabs inside that matched the search when the item itself did not; the row shows open with them under it.
  public var matchedChildren: [ArchiveChildRow]

  public init(
    id: UUID, title: String, detail: String, reason: String, kind: ArchiveRowKind = .tab(nil),
    place: ArchiveRowPlace = .none, time: String = "", matchedChildren: [ArchiveChildRow] = []
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.reason = reason
    self.kind = kind
    self.place = place
    self.time = time
    self.matchedChildren = matchedChildren
  }
}

/// Everything the Archive window shows after a load.
public struct ArchiveListPage: Equatable, Sendable {
  /// Every row loaded so far, newest first.
  public var rows: [ArchiveRow]
  /// Stored items that could not be read back; counted, never shown (BH-087).
  public var unreadable: Int
  /// More items may exist beyond `rows`; the window loads the next page as the list nears its end.
  public var mayHaveMore: Bool
  /// The last load failed; `rows` are what was loaded before it.
  public var failed: Bool
  /// Every archived item, unfiltered (the footer's "42 items"); nil when unknown.
  public var total: Int?
  /// The items matching the query, every page included ("3 results", "3 of 42 items"); nil when unknown.
  public var matching: Int?

  public init(rows: [ArchiveRow], unreadable: Int, mayHaveMore: Bool, failed: Bool = false, total: Int? = nil,
              matching: Int? = nil) {
    self.rows = rows
    self.unreadable = unreadable
    self.mayHaveMore = mayHaveMore
    self.failed = failed
    self.total = total
    self.matching = matching
  }
}

/// The one-time auto-archive education banner (BH-089): a headline and a secondary line.
public struct ArchiveBanner: Equatable, Sendable {
  public var headline: String
  public var detail: String

  public init(headline: String, detail: String) {
    self.headline = headline
    self.detail = detail
  }
}

// MARK: - Data source

/// What the Archive window reads and restores through. The app's implementation is CoreBridge's `ArchiveListModel`.
/// Loads may overlap; the window applies every page it gets back, so a load that returns after a newer one started
/// must report the newer state, never its own older rows.
@MainActor
public protocol ArchiveListDataSource: AnyObject {
  /// Called when the list or `canRestore` may have changed outside the window (an entry archived, its archive write
  /// landed, or the Space list changed); the window sets it and refreshes while on screen.
  var onChange: (@MainActor () -> Void)? { get set }
  /// False while there is no Space to restore into.
  var canRestore: Bool { get }
  /// The first page, starting over.
  func loadPage() async -> ArchiveListPage
  /// The loaded rows plus the next page.
  func loadMore() async -> ArchiveListPage
  /// The rows again, as many as are loaded (at least the first page).
  func refresh() async -> ArchiveListPage
  /// Restores the row's item. True when it was restored and the row is gone from the list.
  func restore(_ id: UUID) -> Bool

  /// The search text and filters later loads apply (#111); the window follows with `loadPage()`.
  func setQuery(_ query: ArchiveQuery)
  /// The Spaces the filter menu lists, in sidebar order.
  var spaceOptions: [ArchiveSpaceOption] { get }
  /// Clear Archive (BH-087): empties the whole archive, filters notwithstanding. True when it was emptied.
  func clearArchive() async -> Bool
  /// The education banner when it is due (BH-089): an auto-archived item exists and it was never dismissed.
  func educationBanner() async -> ArchiveBanner?
  /// Got It or Open Settings: the banner is never shown again.
  func dismissEducationBanner()
  /// Stored favicon images (PNG or similar data) of the given archived node ids; missing ones are left out.
  func favicons(for ids: Set<UUID>) async -> [UUID: Data]
}

extension ArchiveListDataSource {
  public func setQuery(_ query: ArchiveQuery) {}
  public var spaceOptions: [ArchiveSpaceOption] { [] }
  public func clearArchive() async -> Bool { false }
  public func educationBanner() async -> ArchiveBanner? { nil }
  public func dismissEducationBanner() {}
  public func favicons(for ids: Set<UUID>) async -> [UUID: Data] { [:] }
}
