import Archive
import Foundation
import ShellUI
import SidebarModel

/// The Archive window's data (E5c, #111): pages of archived items from the store, worded as rows, filtered by the
/// window's search and filters (`setQuery`), restore through the `ArchiveCoordinator`, Clear Archive, and the one-time
/// education banner (BH-089).
///
/// `ArchiveStoring` exposes only a limit, so paging re-queries with a growing one (200, 400, 600 ...); fine at Arc's
/// ~1200 entries, a cursor is a later optimization. The store reads off the main actor; this model only awaits.
///
/// Entries still in the coordinator's outbox (a slow or failing archive write) are listed with every page (#88):
/// merged with the store's items newest first, one row per id (the newer entry wins), restorable like any row.
/// The model sets the coordinator's `onPendingItemsChange` and passes it on as `onChange`, so the window refreshes
/// when an entry is archived or its write lands. Space events (`.spaceAdded` and the others) are passed on too (#89):
/// they decide `canRestore` and the Space titles in the rows.
///
/// The search runs in the store (`ArchiveFilter.text`, the folded `search_text` column) off the main actor; which tabs
/// inside a folder matched is worked out off the main actor too, so a keystroke never blocks a frame.
@MainActor
public final class ArchiveListModel: ArchiveListDataSource {
  nonisolated public static let pageSize = 200

  public var onChange: (@MainActor () -> Void)?

  /// The Space a restore falls back to when the item's own Space is gone (BH-157 routing is a later track).
  public var currentSpaceProvider: @MainActor () -> UUID? = { nil }
  /// After a restore: what came back and the toast text (BH-086).
  public var onRestored: (@MainActor (RestoredItem, String) -> Void)?
  /// A restore the sidebar model refused (a `SidebarError`): the toast text (#91).
  public var onRestoreFailed: (@MainActor (String) -> Void)?
  /// Stored favicons of archived node ids (the app reads its favicon folder); none when unset.
  public var faviconLoader: (@MainActor (Set<UUID>) async -> [UUID: Data])?

  /// The rows loaded so far, newest first.
  public private(set) var rows: [ArchiveRow] = []

  private let source: ModelSidebarSource
  private let store: any ArchiveStoring
  private let coordinator: ArchiveCoordinator
  private let banner: (any ArchiveBannerStoring)?
  private let archiveState: (any ArchiveStateStoring)?
  private let now: @MainActor () -> Date
  private let calendar: Calendar
  private let locale: Locale
  private let formatter: RelativeDateTimeFormatter
  private var query = ArchiveQuery()
  /// Dismissed in this session; the stored flag may still be on its way.
  private var bannerDismissed = false
  private var limit = 0
  private var items: [UUID: ArchivedItem] = [:]
  /// The store's items from the last read that succeeded; a failed read lists them again with the outbox.
  private var storedItems: [ArchivedItem] = []
  private var unreadable = 0
  private var mayHaveMore = false
  /// Entries restored here (id and archive date): hidden from later pages, where the store may still hold them until
  /// the remove the coordinator queued lands. A later archive of the same id has a newer date and shows.
  private var restored: [UUID: Date] = [:]
  /// Bumped by every load, so a slower, older load never overwrites the state a newer one set.
  private var generation = 0
  private var spaceObservation: SidebarObservation?

  /// `banner` and `archiveState` back the education banner (its flag and the "Archive tabs after" value); without
  /// them no banner is offered.
  public init(
    source: ModelSidebarSource, store: any ArchiveStoring, coordinator: ArchiveCoordinator,
    banner: (any ArchiveBannerStoring)? = nil, archiveState: (any ArchiveStateStoring)? = nil,
    now: @escaping @MainActor () -> Date = { Date() }, locale: Locale = .current, calendar: Calendar = .current
  ) {
    self.source = source
    self.store = store
    self.coordinator = coordinator
    self.banner = banner
    self.archiveState = archiveState
    self.now = now
    self.locale = locale
    var calendar = calendar
    calendar.locale = locale
    self.calendar = calendar
    formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .numeric
    coordinator.onPendingItemsChange = { [weak self] in self?.onChange?() }
    spaceObservation = source.observe { [weak self] change in
      switch change {
      case .spaceAdded, .spaceRemoved, .spaceMoved, .spaceChanged: self?.onChange?()
      case .structure, .node: break
      }
    }
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

  public func refresh() async -> ArchiveListPage {
    await load(limit: max(limit, Self.pageSize))
  }

  /// Restores the row's item (`ArchiveCoordinator.restore`: its source Space, else the current one, else the first),
  /// drops the row and reports the toast. False, and nothing changes, with no Space, an unknown row, or a restore the
  /// model refused; the refusal is reported through `onRestoreFailed`.
  @discardableResult
  public func restore(_ id: UUID) -> Bool {
    guard canRestore, let item = items[id] else { return false }
    let result: RestoredItem?
    do { result = try coordinator.restore(item, fallbackSpace: currentSpaceProvider()) } catch {
      onRestoreFailed?(ToastText.restoreFailed)
      return false
    }
    restored[id] = item.archivedAt
    items[id] = nil
    rows.removeAll { $0.id == id }
    total = total.map { max(0, $0 - 1) }
    matching = matching.map { max(0, $0 - 1) }
    if let result {
      // nil: back in Favorites. The Space was just restored into, so its title is there.
      let spaceTitle = result.space.map { source.sidebar.spaces[$0]?.title ?? "" }
      onRestored?(result, ToastText.restored(kind: ToastText.RestoredKind(item.snapshot.kind), spaceTitle: spaceTitle))
    }
    return true
  }

  public func setQuery(_ query: ArchiveQuery) {
    self.query = query
  }

  /// Every Space in sidebar order with its theme's first color (nil on the default theme).
  public var spaceOptions: [ArchiveSpaceOption] {
    source.sidebar.spaceOrder.compactMap { id in
      source.sidebar.spaces[id].map { ArchiveSpaceOption(id: id, title: $0.title, color: spaceColor(id)) }
    }
  }

  /// Clear Archive (BH-087): sends what the outbox still holds (so a pending entry cannot land after the clear), then
  /// empties the store. False when either step failed; the window says so.
  public func clearArchive() async -> Bool {
    generation += 1                                  // a load in flight must not list what is being cleared
    guard await coordinator.flush() else { return false }
    do { try await store.removeAll() } catch { return false }
    coordinator.forgetRecentlyArchived()            // a cleared tab does not come back with Cmd-Shift-T (#110)
    generation += 1
    rows = []
    items = [:]
    storedItems = []
    restored = [:]
    unreadable = 0
    mayHaveMore = false
    total = 0
    matching = 0
    return true
  }

  /// BH-089: due once an auto-archived item exists, until dismissed. Worded with the Default profile's "Archive tabs
  /// after" value.
  public func educationBanner() async -> ArchiveBanner? {
    guard let banner, !bannerDismissed else { return nil }
    guard let dismissed = try? await banner.isEducationBannerDismissed(), !dismissed, !bannerDismissed else {
      return nil
    }
    let pendingAuto = coordinator.pendingItems.contains { $0.reason == .auto }
    let storedAuto = ((try? await store.count(matching: ArchiveFilter(reason: .auto))) ?? 0) > 0
    guard pendingAuto || storedAuto, !bannerDismissed else { return nil }
    let settings = (try? await archiveState?.loadArchiveSettings()) ?? ArchiveSettings()
    guard let span = Self.span(settings.tabThreshold(forProfile: ArchiveSettings.defaultProfile)) else { return nil }
    return ArchiveBanner(
      headline: "Arkt archives Today tabs you haven\u{2019}t used in the past \(span).",
      detail: "Restored tabs return to their Space. Change this in Settings > Spaces.")
  }

  public func dismissEducationBanner() {
    guard !bannerDismissed else { return }
    bannerDismissed = true
    guard let banner else { return }
    let date = now()
    Task { try? await banner.dismissEducationBanner(at: date) }
  }

  public func favicons(for ids: Set<UUID>) async -> [UUID: Data] {
    await faviconLoader?(ids) ?? [:]
  }

  /// The banner's wording of a threshold; nil for `never` (nothing is auto-archived then).
  private static func span(_ threshold: AutoArchiveThreshold) -> String? {
    switch threshold {
    case .oneHour: "hour"
    case .sixHours: "6 hours"
    case .twelveHours: "12 hours"
    case .twentyFourHours: "24 hours"
    case .sevenDays: "7 days"
    case .thirtyDays: "30 days"
    case .never: nil
    }
  }

  // MARK: - Loading

  /// The store's filter for the current query.
  private var filter: ArchiveFilter {
    let source: ArchiveFilter.Source? = switch query.space {
    case .space(let id)?: .space(id)
    case .littleArkt?: .littleArc
    case nil: nil
    }
    let reason: ArchiveReason? = switch query.closeType {
    case .closed?: .manual
    case .autoArchived?: .auto
    case nil: nil
    }
    return ArchiveFilter(source: source, reason: reason, text: query.hasText ? query.text : nil)
  }

  private var page: ArchiveListPage {
    ArchiveListPage(rows: rows, unreadable: unreadable, mayHaveMore: mayHaveMore, total: total, matching: matching)
  }

  /// A load that a newer one overtook changes nothing and reports the current state (the newer load's, once it
  /// landed), so the window never shows older rows.
  private func load(limit wanted: Int) async -> ArchiveListPage {
    generation += 1
    let current = generation
    let filter = self.filter
    let folded = ArchiveSearch.query(filter.text)
    // Taken before the read: an entry whose write lands during it is then in the page, here, or both (never neither).
    let pending = coordinator.pendingItems.filter(filter.matches)
    let stored: ArchivePage
    let counts: (total: Int, matching: Int)?
    do {
      stored = try await store.items(matching: filter, limit: wanted)
      counts = await Self.counts(store, filter: filter)
    } catch {
      guard current == generation else { return page }
      list(storedItems, pending, children: [:])
      var failed = page
      failed.failed = true
      return failed
    }
    guard current == generation else { return page }
    let visible = Self.merged(stored.items, pending)
    let children = await Self.matchedChildren(of: visible, query: folded)
    guard current == generation else { return page }
    limit = wanted
    mayHaveMore = stored.items.count >= wanted       // fewer than asked: the store ran out
    unreadable = stored.unreadable
    storedItems = stored.items
    let unwritten = visible.count - stored.items.count    // outbox entries the store does not hold yet
    total = counts.map { $0.total + unwritten }
    matching = counts.map { $0.matching + unwritten }
    list(stored.items, pending, children: children)
    return page
  }

  private var total: Int?
  private var matching: Int?

  /// The archive's size and the query's match count (the footer's "3 of 42 items"); nil when the store cannot say.
  @concurrent
  private static func counts(_ store: any ArchiveStoring, filter: ArchiveFilter) async -> (total: Int, matching: Int)? {
    async let total = try? store.count(matching: ArchiveFilter())
    async let matching = try? store.count(matching: filter)
    guard let total = await total, let matching = await matching else { return nil }
    return (total, matching)
  }

  /// The tabs inside each folder or split that matched `query` when the item itself did not, by item id. Folding
  /// and walking every subtree runs off the main actor.
  @concurrent
  private static func matchedChildren(of items: [ArchivedItem], query: String?) async -> [UUID: [ArchiveChildRow]] {
    guard let query else { return [:] }
    var found: [UUID: [ArchiveChildRow]] = [:]
    for item in items where !item.snapshot.children.isEmpty {
      let tabs = ArchiveSearch.matchingTabs(in: item.snapshot, query: query).compactMap { node -> ArchiveChildRow? in
        guard case .tab(let tab) = node.kind else { return nil }
        return ArchiveChildRow(id: node.id, title: tab.customTitle ?? tab.title, url: tab.url)
      }
      if !tabs.isEmpty { found[item.id] = tabs }
    }
    return found
  }

  /// Sets the rows and restorable items: `stored` and `pending` merged, minus entries restored here.
  private func list(_ stored: [ArchivedItem], _ pending: [ArchivedItem], children: [UUID: [ArchiveChildRow]]) {
    let visible = Self.merged(stored, pending).filter { restored[$0.id] != $0.archivedAt }
    items = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    rows = visible.map { item in
      var row = row(for: item)
      row.matchedChildren = children[item.id] ?? []
      return row
    }
  }

  /// Store items and outbox entries, newest first, one per id: the newer entry wins (a re-archive the store still
  /// holds an older entry of), an outbox entry on equal dates. Equal dates keep the newest outbox entry first, then
  /// the store's order.
  private static func merged(_ stored: [ArchivedItem], _ pending: [ArchivedItem]) -> [ArchivedItem] {
    guard !pending.isEmpty else { return stored }
    var winners: [UUID: ArchivedItem] = [:]
    var order: [UUID] = []
    for item in pending.reversed() + stored {
      guard let kept = winners[item.id] else {
        winners[item.id] = item
        order.append(item.id)
        continue
      }
      if item.archivedAt > kept.archivedAt { winners[item.id] = item }
    }
    return order.enumerated()
      .compactMap { offset, id in winners[id].map { (offset, $0) } }
      .sorted { $0.1.archivedAt != $1.1.archivedAt ? $0.1.archivedAt > $1.1.archivedAt : $0.0 < $1.0 }
      .map(\.1)
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
    let kind: ArchiveRowKind = switch item.snapshot.kind {
    case .tab(let tab): .tab(tab.url)
    case .folder: .folder(tabCount: Self.tabCount(item.snapshot))
    case .split: .split
    }
    return ArchiveRow(id: item.id, title: item.title, detail: "\(what) - \(placeTitle(of: item)) - \(date)",
                      reason: reason, kind: kind, place: place(of: item),
                      time: Self.compactTime(item.archivedAt, now: now(), calendar: calendar, locale: locale))
  }

  /// The trailing mark: the Space's color dot, Little Arkt's glyph, or nothing for Favorites and unknown Spaces.
  private func place(of item: ArchivedItem) -> ArchiveRowPlace {
    if case .favorites? = item.section { return .none }
    switch item.source {
    case .space(let id): return source.sidebar.spaces[id] == nil ? .none : .space(color: spaceColor(id))
    case .littleArc: return .littleArkt
    case .unknown: return .none
    }
  }

  /// The Space theme's first stop (the tab switcher's Space chip color, BH-011); nil on the default theme.
  private func spaceColor(_ id: UUID) -> ShellUI.RGBA? {
    guard let space = source.sidebar.spaces[id], !BridgeMapping.usesDefaultTheme(space.theme) else { return nil }
    return BridgeMapping.theme(space.theme).baseColors.first
  }

  private static func tabCount(_ snapshot: NodeSnapshot) -> Int {
    snapshot.children.reduce(0) { count, child in
      if case .tab = child.kind { return count + 1 }
      return count + tabCount(child)
    }
  }

  /// The row's short time (design section 9): "now" under a minute, "12m" under an hour, "3h" earlier today,
  /// "Yesterday", the weekday within a week, else day and month, plus the year when it is not this year.
  public nonisolated static func compactTime(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
      return "Yesterday"
    }
    var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                 timeZone: calendar.timeZone)
    if seconds < 7 * 86_400 { return date.formatted(style.weekday(.abbreviated)) }
    style = style.month(.abbreviated).day()
    if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
    return date.formatted(style)
  }

  private func placeTitle(of item: ArchivedItem) -> String { Self.placeTitle(of: item, in: source.sidebar) }

  /// Where an item was archived from, for row details and the command bar: the Space's title, "Favorites",
  /// "Little Arkt" or "Unknown Space".
  static func placeTitle(of item: ArchivedItem, in sidebar: SidebarModel.Sidebar) -> String {
    if case .favorites? = item.section { return "Favorites" }   // [I] Favorites entries carry no Space
    switch item.source {
    case .space(let id): return sidebar.spaces[id]?.title ?? "Unknown Space"
    case .littleArc: return "Little Arkt"
    case .unknown: return "Unknown Space"
    }
  }
}
