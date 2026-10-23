import Foundation

/// One row of the Archive window, already worded for display (ShellUI knows no archive types).
public struct ArchiveRow: Equatable, Sendable {
  /// The archived root node's id.
  public var id: UUID
  public var title: String
  /// Host (or "Folder" / "Split View"), Space and relative date.
  public var detail: String
  /// "Closed" or "Auto archived".
  public var reason: String

  public init(id: UUID, title: String, detail: String, reason: String) {
    self.id = id
    self.title = title
    self.detail = detail
    self.reason = reason
  }
}

/// Everything the Archive window shows after a load.
public struct ArchiveListPage: Equatable, Sendable {
  /// Every row loaded so far, newest first.
  public var rows: [ArchiveRow]
  /// Stored items that could not be read back; counted, never shown (BH-087).
  public var unreadable: Int
  /// More items may exist beyond `rows`; "Load More" is offered only then.
  public var mayHaveMore: Bool
  /// The last load failed; `rows` are what was loaded before it.
  public var failed: Bool

  public init(rows: [ArchiveRow], unreadable: Int, mayHaveMore: Bool, failed: Bool = false) {
    self.rows = rows
    self.unreadable = unreadable
    self.mayHaveMore = mayHaveMore
    self.failed = failed
  }
}

/// What the Archive window reads and restores through. The app's implementation is CoreBridge's `ArchiveListModel`.
/// Loads may overlap; the window applies every page it gets back, so a load that returns after a newer one started
/// must report the newer state, never its own older rows.
@MainActor
public protocol ArchiveListDataSource: AnyObject {
  /// Called when the list may have changed outside the window (an entry archived, or its archive write landed); the
  /// window sets it and refreshes while on screen.
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
}
