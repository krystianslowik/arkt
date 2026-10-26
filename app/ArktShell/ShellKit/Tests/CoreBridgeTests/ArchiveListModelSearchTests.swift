import Archive
import CoreBridge
import CoreTestSupport
import Foundation
import ShellUI
import SidebarModel
import Testing

/// #111: the Archive window's search, filters, counts, row presentation, Clear Archive and the education banner, as
/// `ArchiveListModel` provides them.
@MainActor
struct ArchiveListModelSearchTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)   // Monday 9 July 2029, 16:00 GMT
  private static let locale = Locale(identifier: "en_US")
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    calendar.locale = locale
    return calendar
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let store: PagedArchiveStore
    let state: FakeArchiveState
    let coordinator: ArchiveCoordinator
    let model: ArchiveListModel
    let work: UUID
    /// Never resumed: the coordinator's flush deadline cannot fire, so a flush waits for the write chain itself.
    let sleeper = ManualSleeper()

    init(items: [ArchivedItem] = [], work: UUID? = nil) throws {
      let source = ModelSidebarSource(now: { ArchiveListModelSearchTests.now })
      self.source = source
      self.work = try source.addSpace(title: "Work")
      store = PagedArchiveStore(items: items)
      state = FakeArchiveState()
      coordinator = ArchiveCoordinator(source: source, store: store, now: { ArchiveListModelSearchTests.now },
                                       sleep: sleeper.sleep)
      model = ArchiveListModel(
        source: source, store: store, coordinator: coordinator, banner: state, archiveState: state,
        now: { ArchiveListModelSearchTests.now }, locale: ArchiveListModelSearchTests.locale,
        calendar: ArchiveListModelSearchTests.calendar)
    }
  }

  private static func tab(
    _ title: String, url: String = "https://news.example.com/a", ago seconds: TimeInterval,
    source: ArchiveSource = .unknown, reason: ArchiveReason = .manual, id: UUID = UUID()
  ) -> ArchivedItem {
    ArchivedItem(
      reason: reason, archivedAt: now.addingTimeInterval(-seconds), source: source, section: .today,
      snapshot: NodeSnapshot(id: id, kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: now))
  }

  private static func folder(_ title: String, ago seconds: TimeInterval, source: ArchiveSource = .unknown,
                             children: [NodeSnapshot]) -> ArchivedItem {
    ArchivedItem(
      reason: .manual, archivedAt: now.addingTimeInterval(-seconds), source: source, section: .today,
      snapshot: NodeSnapshot(kind: .folder(FolderItem(title: title)), createdAt: now, children: children))
  }

  private static func child(_ title: String, _ url: String) -> NodeSnapshot {
    NodeSnapshot(kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: now)
  }

  // MARK: - Query and counts

  @Test func queryBecomesTheStoreFilter() async throws {
    let harness = try Harness()
    harness.model.setQuery(ArchiveQuery(text: "Report", space: .space(harness.work), closeType: .autoArchived))
    _ = await harness.model.loadPage()
    harness.model.setQuery(ArchiveQuery(space: .littleArkt, closeType: .closed))
    _ = await harness.model.loadPage()

    let filters = await harness.store.filters
    #expect(filters.first == ArchiveFilter(source: .space(harness.work), reason: .auto, text: "Report"))
    #expect(filters.last == ArchiveFilter(source: .littleArc, reason: .manual, text: nil))
  }

  @Test func pageCarriesTheTotalAndTheMatchingCount() async throws {
    let harness = try Harness(items: [
      Self.tab("Quarterly report", ago: 10), Self.tab("Expense report", ago: 20), Self.tab("Lichens", ago: 30),
    ])
    let all = await harness.model.loadPage()
    #expect(all.total == 3)
    #expect(all.matching == 3)

    harness.model.setQuery(ArchiveQuery(text: "REPORT"))
    let searched = await harness.model.loadPage()
    #expect(searched.rows.map(\.title) == ["Quarterly report", "Expense report"])
    #expect(searched.total == 3)
    #expect(searched.matching == 2)
  }

  /// Entries still in the outbox follow the query too, so a search never shows an unrelated pending entry.
  @Test func pendingEntriesFollowTheQuery() async throws {
    let harness = try Harness()
    let one = try harness.source.addTab(url: URL(string: "https://a.example")!, title: "Café notes",
                                        in: .today(harness.work))
    let two = try harness.source.addTab(url: URL(string: "https://b.example")!, title: "Budget",
                                        in: .today(harness.work))
    await harness.store.holdAdds()
    harness.coordinator.archive([one, two], reason: .manual)

    harness.model.setQuery(ArchiveQuery(text: "cafe"))
    let page = await harness.model.loadPage()

    #expect(page.rows.map(\.title) == ["Café notes"])
    await harness.store.releaseAdds()
  }

  /// A folder that matched only through tabs inside lists them, to be shown under the opened folder; a folder whose
  /// own title matches does not.
  @Test func folderMatchedThroughAChildListsTheMatchingTabs() async throws {
    let research = Self.folder("Research", ago: 100, children: [
      Self.child("Q3 report outline", "https://docs.example/q3"), Self.child("Budget", "https://sheets.example"),
    ])
    let reports = Self.folder("Reports", ago: 200, children: [Self.child("Old report", "https://x.example")])
    let harness = try Harness(items: [research, reports])

    harness.model.setQuery(ArchiveQuery(text: "report"))
    let rows = await harness.model.loadPage().rows

    #expect(rows.map(\.title) == ["Research", "Reports"])
    #expect(rows[0].matchedChildren.map(\.title) == ["Q3 report outline"])
    #expect(rows[0].matchedChildren.first?.url == URL(string: "https://docs.example/q3"))
    #expect(rows[1].matchedChildren.isEmpty)
    #expect(rows[0].kind == .folder(tabCount: 2))
  }

  // MARK: - Row presentation

  @Test func rowsCarryTheirPlaceAndKind() async throws {
    let harness = try Harness()
    let blue = SpaceThemeInfo(baseColors: [RGBA(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)], isDark: false)
    harness.source.setTheme(harness.work, to: blue)
    let plain = try harness.source.addSpace(title: "Plain")
    harness.source.setTheme(plain, to: nil)
    await harness.store.seed([
      Self.tab("In Work", ago: 10, source: .space(harness.work)),
      Self.tab("In Plain", ago: 20, source: .space(plain)),
      Self.tab("Little", url: "https://little.example", ago: 30, source: .littleArc),
      Self.tab("Lost", ago: 40, source: .unknown),
    ])

    let rows = await harness.model.loadPage().rows
    let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })

    let workColor = try #require(harness.model.spaceOptions.first { $0.id == harness.work }?.color)
    #expect(byTitle["In Work"]?.place == .space(color: workColor))
    #expect(byTitle["In Plain"]?.place == .space(color: nil))
    #expect(byTitle["Little"]?.place == .littleArkt)
    #expect(byTitle["Lost"]?.place == ArchiveRowPlace.none)
    #expect(byTitle["Little"]?.kind == .tab(URL(string: "https://little.example")))
    #expect(harness.model.spaceOptions.map(\.title) == ["Work", "Plain"])
    #expect(harness.model.spaceOptions.last?.color == nil)
  }

  @Test(arguments: [
    (30.0, "now"), (600, "10m"), (7200, "2h"), (50_000, "13h"), (129_600, "Yesterday"), (259_200, "Fri"),
    (864_000, "Jun 29"), (34_560_000, "Jun 4, 2028"),
  ])
  func compactRelativeTime(_ ago: TimeInterval, _ expected: String) {
    let date = Self.now.addingTimeInterval(-ago)
    #expect(ArchiveListModel.compactTime(date, now: Self.now, calendar: Self.calendar, locale: Self.locale)
      == expected)
  }

  @Test func rowsPrintTheCompactTime() async throws {
    let harness = try Harness(items: [Self.tab("Recent", ago: 600)])
    #expect(await harness.model.loadPage().rows.first?.time == "10m")
  }

  // MARK: - Clear Archive

  @Test func clearArchiveEmptiesTheStoreAndTheList() async throws {
    let harness = try Harness(items: [Self.tab("One", ago: 10), Self.tab("Two", ago: 20)])
    _ = await harness.model.loadPage()

    #expect(await harness.model.clearArchive())

    #expect(await harness.store.removeAllCount == 1)
    #expect(harness.model.rows.isEmpty)
    let page = await harness.model.loadPage()
    #expect(page.rows.isEmpty)
    #expect(page.total == 0)
  }

  /// An archive write still in the outbox lands before the clear, so it cannot reappear afterwards.
  @Test func clearArchiveWaitsForPendingWrites() async throws {
    let harness = try Harness()
    let tab = try harness.source.addTab(url: URL(string: "https://a.example")!, title: "Late",
                                        in: .today(harness.work))
    await harness.store.holdAdds()
    harness.coordinator.archive([tab], reason: .manual)
    await eventuallyTrue { await harness.store.heldAddCount == 1 }           // the write is in flight, not landed

    let clearing = Task { await harness.model.clearArchive() }
    await eventuallyTrue { harness.sleeper.parkedCount == 1 }                // the flush waits on that write
    #expect(await harness.store.removeAllCount == 0, "the clear has not run past the pending write")
    await harness.store.releaseAdds()
    #expect(await clearing.value)

    #expect(await harness.model.loadPage().rows.isEmpty)
    #expect(harness.coordinator.pendingItems.isEmpty)
    #expect(try harness.coordinator.restoreRecent(tab, fallbackSpace: nil) == nil, "no reopen of a cleared tab")
  }

  @Test func clearArchiveReportsAStoreFailure() async throws {
    let harness = try Harness(items: [Self.tab("One", ago: 10)])
    await harness.store.setFails(true)
    #expect(await harness.model.clearArchive() == false)
  }

  /// A clear also clears what was kept about the cleared pages, such as the command bar's thumbnails (#370).
  @Test func clearArchiveRunsTheClearedHookOnce() async throws {
    let harness = try Harness(items: [Self.tab("One", ago: 10)])
    var cleared = 0
    harness.model.onCleared = { cleared += 1 }
    #expect(await harness.model.clearArchive())
    #expect(cleared == 1)
  }

  @Test func failedClearSkipsTheClearedHook() async throws {
    let harness = try Harness(items: [Self.tab("One", ago: 10)])
    await harness.store.setFails(true)
    var cleared = 0
    harness.model.onCleared = { cleared += 1 }
    #expect(await harness.model.clearArchive() == false)
    #expect(cleared == 0)
  }

  // MARK: - Education banner (BH-089)

  @Test func bannerWaitsForAnAutoArchivedItem() async throws {
    let harness = try Harness(items: [Self.tab("Closed by hand", ago: 10)])
    #expect(await harness.model.educationBanner() == nil)

    await harness.store.seed([Self.tab("Idle", ago: 20, reason: .auto)])
    let banner = try #require(await harness.model.educationBanner())
    #expect(banner.headline == "Arkt archives Today tabs you haven\u{2019}t used in the past 12 hours.")
    #expect(banner.detail == "Restored tabs return to their Space. Change this in Settings > Spaces.")
  }

  @Test func bannerFollowsTheArchiveThreshold() async throws {
    let harness = try Harness(items: [Self.tab("Idle", ago: 20, reason: .auto)])
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: ArchiveSettings.defaultProfile, scope: .thisProfile)
    await harness.state.setSettings(settings)
    #expect(await harness.model.educationBanner()?.headline
      == "Arkt archives Today tabs you haven\u{2019}t used in the past 7 days.")
  }

  @Test func dismissedBannerNeverShowsAgain() async throws {
    let harness = try Harness(items: [Self.tab("Idle", ago: 20, reason: .auto)])
    #expect(await harness.model.educationBanner() != nil)

    harness.model.dismissEducationBanner()

    #expect(await harness.model.educationBanner() == nil, "at once, before the write lands")
    await eventuallyTrue { await harness.state.educationBannerDismissed }
  }

  @Test func bannerStaysHiddenWhenDismissedEarlier() async throws {
    let harness = try Harness(items: [Self.tab("Idle", ago: 20, reason: .auto)])
    try await harness.state.dismissEducationBanner(at: Self.now)
    #expect(await harness.model.educationBanner() == nil)
  }

  // MARK: - Favicons

  @Test func faviconsComeFromTheLoader() async throws {
    let harness = try Harness()
    let id = UUID()
    harness.model.faviconLoader = { ids in ids.contains(id) ? [id: Data([1, 2, 3])] : [:] }
    #expect(await harness.model.favicons(for: [id, UUID()]) == [id: Data([1, 2, 3])])
  }
}

/// Yields until `condition` holds; records an issue if it never does.
@MainActor
private func eventuallyTrue(
  _ condition: @MainActor () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<20_000 {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}
