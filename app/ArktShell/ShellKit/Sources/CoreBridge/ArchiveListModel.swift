import Archive
import Foundation
import ShellUI
import SidebarModel

/// The Archive window's data (E5c): pages of archived items from the store, worded as rows, and restore through the
/// `ArchiveCoordinator`.
///
/// `ArchiveStoring` exposes only a limit, so paging re-queries with a growing one (200, 400, 600 ...); fine at Arc's
/// ~1200 entries, a cursor is a later optimization. The store reads off the main actor; this model only awaits.
@MainActor
public final class ArchiveListModel: ArchiveListDataSource {
  nonisolated public static let pageSize = 200

  /// The Space a restore falls back to when the item's own Space is gone (BH-157 routing is a later track).
  public var currentSpaceProvider: @MainActor () -> UUID? = { nil }
  /// After a restore: what came back and the toast text (BH-086).
  public var onRestored: (@MainActor (RestoredItem, String) -> Void)?

  /// The rows loaded so far, newest first.
  public private(set) var rows: [ArchiveRow] = []

  private let source: ModelSidebarSource
  private let store: any ArchiveStoring
  private let coordinator: ArchiveCoordinator
  private let now: @MainActor () -> Date
  private let formatter: RelativeDateTimeFormatter
  private var limit = 0
  private var items: [UUID: ArchivedItem] = [:]
  private var unreadable = 0
  private var mayHaveMore = false
  /// Entries restored here (id and archive date): hidden from later pages, where the store may still hold them until
  /// the remove the coordinator queued lands. A later archive of the same id has a newer date and shows.
  private var restored: [UUID: Date] = [:]

  public init(
    source: ModelSidebarSource, store: any ArchiveStoring, coordinator: ArchiveCoordinator,
    now: @escaping @MainActor () -> Date = { Date() }, locale: Locale = .current
  ) {
    self.source = source
    self.store = store
    self.coordinator = coordinator
    self.now = now
    formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .numeric
  }

  // MARK: - ArchiveListDataSource

  /// A restore needs a Space to land in.
  public var canRestore: Bool { !source.sidebar.spaceOrder.isEmpty }

  public func loadPage() async -> ArchiveListPage {
    await load(limit: Self.pageSize)
  }

  public func loadMore() async -> ArchiveListPage {
    await load(limit: limit + Self.pageSize)
  }

  /// Restores the row's item (`ArchiveCoordinator.restore`: its source Space, else the current one, else the first),
  /// drops the row and reports the toast. False, and nothing changes, with no Space, an unknown row, or a restore the
  /// model refused.
  @discardableResult
  public func restore(_ id: UUID) -> Bool {
    guard canRestore, let item = items[id] else { return false }
    let result: RestoredItem?
    do { result = try coordinator.restore(item, fallbackSpace: currentSpaceProvider()) } catch { return false }
    restored[id] = item.archivedAt
    items[id] = nil
    rows.removeAll { $0.id == id }
    if let result {
      // nil: back in Favorites. The Space was just restored into, so its title is there.
      let spaceTitle = result.space.map { source.sidebar.spaces[$0]?.title ?? "" }
      onRestored?(result, ToastText.restored(kind: ToastText.RestoredKind(item.snapshot.kind), spaceTitle: spaceTitle))
    }
    return true
  }

  // MARK: - Loading

  private func load(limit wanted: Int) async -> ArchiveListPage {
    let page: ArchivePage
    do { page = try await store.items(matching: ArchiveFilter(), limit: wanted) } catch {
      return ArchiveListPage(rows: rows, unreadable: unreadable, mayHaveMore: mayHaveMore, failed: true)
    }
    limit = wanted
    mayHaveMore = page.items.count >= wanted       // fewer than asked: the store ran out
    unreadable = page.unreadable
    let visible = page.items.filter { restored[$0.id] != $0.archivedAt }
    items = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    rows = visible.map(row(for:))
    return ArchiveListPage(rows: rows, unreadable: unreadable, mayHaveMore: mayHaveMore)
  }

  // MARK: - Row text

  /// Title; detail = host (or "Folder" / "Split View") - Space (or "Favorites", "Little Arc", "Unknown Space") -
  /// relative date; reason "Closed" (manual) or "Auto archived".
  func row(for item: ArchivedItem) -> ArchiveRow {
    let what: String = switch item.snapshot.kind {
    case .tab(let tab): tab.url.host() ?? tab.url.absoluteString
    case .folder: "Folder"
    case .split: "Split View"
    }
    let date = formatter.localizedString(for: item.archivedAt, relativeTo: now())
    let reason = switch item.reason {
    case .manual: "Closed"
    case .auto: "Auto archived"
    }
    return ArchiveRow(id: item.id, title: item.title, detail: "\(what) - \(placeTitle(of: item)) - \(date)",
                      reason: reason)
  }

  private func placeTitle(of item: ArchivedItem) -> String {
    if case .favorites? = item.section { return "Favorites" }   // [I] Favorites entries carry no Space
    switch item.source {
    case .space(let id): return source.sidebar.spaces[id]?.title ?? "Unknown Space"
    case .littleArc: return "Little Arc"
    case .unknown: return "Unknown Space"
    }
  }
}
