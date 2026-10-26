import Archive
import Foundation
import ShellUI
import SidebarModel

/// Archived results in the command bar (#111, BH-087, BH-104): the store's Archive search (the same folded match as
/// the Archive window, folder children included), newest first, at most three, worded "host, Space, archived
/// <when>". Enter restores through the `ArchiveCoordinator`, as the Archive window does, with the restore toast.
/// The store reads off the main actor; this only awaits.
@MainActor
public final class ArchiveCommandBarSearch {
  /// The Space a restore falls back to when the item's own Space is gone.
  public var currentSpaceProvider: @MainActor () -> UUID? = { nil }
  /// After a restore: what came back and the toast text (BH-086).
  public var onRestored: (@MainActor (RestoredItem, String) -> Void)?
  /// A restore the sidebar model refused: the toast text (#91).
  public var onRestoreFailed: (@MainActor (String) -> Void)?

  private let source: ModelSidebarSource
  private let store: any ArchiveStoring
  private let coordinator: ArchiveCoordinator
  private let now: @MainActor () -> Date
  private let locale: Locale
  private let calendar: Calendar
  /// The items behind the matches last returned, by id: Enter restores from here.
  private var listed: [UUID: ArchivedItem] = [:]

  public init(
    source: ModelSidebarSource, store: any ArchiveStoring, coordinator: ArchiveCoordinator,
    now: @escaping @MainActor () -> Date = { Date() }, locale: Locale = .current, calendar: Calendar = .current
  ) {
    self.source = source
    self.store = store
    self.coordinator = coordinator
    self.now = now
    self.locale = locale
    var calendar = calendar
    calendar.locale = locale
    self.calendar = calendar
  }

  /// The archived items matching `query`, newest first, at most `CommandBarResults.maxArchivedResults`; entries
  /// still in the outbox count too. Empty for a blank query, an unreadable store, or a cancelled caller.
  public func matches(for query: String) async -> [CommandBarResults.ArchivedMatch] {
    guard ArchiveSearch.query(query) != nil else { return [] }
    let filter = ArchiveFilter(text: query)
    let limit = CommandBarResults.maxArchivedResults
    let pending = coordinator.pendingItems.filter(filter.matches)
    let stored = (try? await store.items(matching: filter, limit: limit).items) ?? []
    var seen: Set<UUID> = []
    let items = (pending + stored)
      .sorted { $0.archivedAt > $1.archivedAt }
      .filter { seen.insert($0.id).inserted && !coordinator.isRestored($0.id) }
      .prefix(limit)
    // A reply the bar dropped for a newer query (its task was cancelled) must not replace the items Enter restores.
    guard !Task.isCancelled else { return [] }
    listed = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return items.map { item in
      CommandBarResults.ArchivedMatch(id: item.id, title: item.title, subtitle: subtitle(for: item))
    }
  }

  /// Restores a listed match into its source Space (else the current one, else the first) and reports the toast.
  public func restore(_ id: UUID) {
    guard let item = listed.removeValue(forKey: id) else { return }
    let result: RestoredItem?
    do { result = try coordinator.restore(item, fallbackSpace: currentSpaceProvider()) } catch {
      onRestoreFailed?(ToastText.restoreFailed)
      return
    }
    guard let result else { return }
    let spaceTitle = result.space.map { source.sidebar.spaces[$0]?.title ?? "" }
    onRestored?(result, ToastText.restored(kind: ToastText.RestoredKind(item.snapshot.kind), spaceTitle: spaceTitle))
  }

  /// "sheets.example, Work, archived Jun 22" (folders and splits name their kind instead of a host).
  private func subtitle(for item: ArchivedItem) -> String {
    let what: String = switch item.snapshot.kind {
    case .tab(let tab): tab.url.host() ?? tab.url.absoluteString
    case .folder: "Folder"
    case .split: "Split View"
    }
    let place = ArchiveListModel.placeTitle(of: item, in: source.sidebar)
    let time = ArchiveListModel.compactTime(item.archivedAt, now: now(), calendar: calendar, locale: locale)
    let when: String = switch time {
    case "now": "just now"
    case "Yesterday": "yesterday"
    case _ where time.hasSuffix("m") || time.hasSuffix("h"): "\(time) ago"
    default: time
    }
    return "\(what), \(place), archived \(when)"
  }
}
