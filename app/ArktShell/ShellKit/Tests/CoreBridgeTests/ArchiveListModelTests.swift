import Archive
import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

@MainActor
struct ArchiveListModelTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private static let locale = Locale(identifier: "en_US")

  /// A source with one Space ("Work"), a paged store and a list model over them.
  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let store: PagedArchiveStore
    let coordinator: ArchiveCoordinator
    let model: ArchiveListModel
    let space: UUID?
    var restored: [(RestoredItem, String)] = []

    init(items: [ArchivedItem] = [], unreadable: Int = 0, withSpace: Bool = true, currentSpace: UUID? = nil) throws {
      let source = ModelSidebarSource(now: { ArchiveListModelTests.now })
      self.source = source
      space = withSpace ? try source.addSpace(title: "Work") : nil
      store = PagedArchiveStore(items: items, unreadable: unreadable)
      coordinator = ArchiveCoordinator(source: source, store: store, now: { ArchiveListModelTests.now })
      model = ArchiveListModel(
        source: source, store: store, coordinator: coordinator,
        now: { ArchiveListModelTests.now }, locale: ArchiveListModelTests.locale)
      model.currentSpaceProvider = { currentSpace }
      model.onRestored = { [unowned self] item, text in self.restored.append((item, text)) }
    }
  }

  private static func tab(
    _ title: String, url: String = "https://news.example.com/a", ago seconds: TimeInterval,
    source: ArchiveSource = .unknown, section: ArchivedSection? = .today, reason: ArchiveReason = .manual
  ) -> ArchivedItem {
    let tab = TabItem(url: URL(string: url)!, title: title)
    return ArchivedItem(
      reason: reason, archivedAt: now.addingTimeInterval(-seconds), source: source, section: section,
      snapshot: NodeSnapshot(kind: .tab(tab), createdAt: now))
  }

  /// `count` tabs, newest first, one second apart.
  private static func tabs(_ count: Int) -> [ArchivedItem] {
    (0..<count).map { tab("Item \($0)", ago: TimeInterval($0 + 1)) }
  }

  // MARK: - Paging

  @Test func firstPageAsksForTwoHundredNewestFirst() async throws {
    let harness = try Harness(items: Self.tabs(450).shuffled(), unreadable: 3)

    let page = await harness.model.loadPage()

    #expect(await harness.store.limits == [200])
    #expect(page.rows.count == 200)
    #expect(page.rows.first?.title == "Item 0")
    #expect(page.rows.last?.title == "Item 199")
    #expect(page.unreadable == 3)
    #expect(page.mayHaveMore)
    #expect(!page.failed)
  }

  @Test func loadMoreGrowsTheLimitUntilNothingIsLeft() async throws {
    let harness = try Harness(items: Self.tabs(450), unreadable: 3)
    _ = await harness.model.loadPage()

    let second = await harness.model.loadMore()
    #expect(second.rows.count == 400)
    #expect(second.mayHaveMore)

    let third = await harness.model.loadMore()
    #expect(await harness.store.limits == [200, 400, 600])
    #expect(third.rows.count == 450)
    #expect(!third.mayHaveMore)
    #expect(third.unreadable == 3)
  }

  @Test func loadPageStartsOverAtTwoHundred() async throws {
    let harness = try Harness(items: Self.tabs(450))
    _ = await harness.model.loadPage()
    _ = await harness.model.loadMore()

    let page = await harness.model.loadPage()

    #expect(await harness.store.limits == [200, 400, 200])
    #expect(page.rows.count == 200)
  }

  @Test func storeFailureKeepsTheRowsAndReportsIt() async throws {
    let harness = try Harness(items: Self.tabs(3))
    _ = await harness.model.loadPage()
    await harness.store.setFails(true)

    let page = await harness.model.loadMore()

    #expect(page.failed)
    #expect(page.rows.count == 3)
  }

  /// Overlapping loads: an older load that returns after a newer one leaves the model's rows and restorable items
  /// as the newer load set them, and reports that state too.
  @Test func anOlderLoadFinishingLastDoesNotOverwriteANewerOne() async throws {
    let harness = try Harness(items: Self.tabs(2))
    await harness.store.holdReads()
    let older = Task { await harness.model.loadPage() }
    await eventually { await harness.store.heldReadCount == 1 }
    await harness.store.seed([Self.tab("Newest", ago: 0.5)])
    let newer = Task { await harness.model.loadPage() }
    await eventually { await harness.store.heldReadCount == 2 }

    await harness.store.releaseLastRead()
    let newerPage = await newer.value
    await harness.store.releaseReads()
    let olderPage = await older.value

    let expected = ["Newest", "Item 0", "Item 1"]
    #expect(newerPage.rows.map(\.title) == expected)
    #expect(olderPage.rows.map(\.title) == expected)
    #expect(harness.model.rows.map(\.title) == expected)
    #expect(harness.model.restore(newerPage.rows[0].id))
  }

  // MARK: - Row text

  @Test func rowTextForTabsFoldersSplitsAndSources() async throws {
    let source = ModelSidebarSource(now: { Self.now })
    let work = try source.addSpace(title: "Work")
    let folder = ArchivedItem(
      reason: .auto, archivedAt: Self.now.addingTimeInterval(-7200), source: .space(work), section: .pinned,
      snapshot: NodeSnapshot(kind: .folder(FolderItem(title: "Reading")), createdAt: Self.now))
    let split = ArchivedItem(
      reason: .manual, archivedAt: Self.now.addingTimeInterval(-60), source: .littleArc, section: nil,
      snapshot: NodeSnapshot(
        kind: .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])), createdAt: Self.now,
        children: [
          NodeSnapshot(kind: .tab(TabItem(url: URL(string: "https://a.example")!, title: "A")), createdAt: Self.now),
          NodeSnapshot(kind: .tab(TabItem(url: URL(string: "https://b.example")!, title: "B")), createdAt: Self.now),
        ]))
    let store = PagedArchiveStore(items: [
      Self.tab("Weekend", ago: 30, source: .space(work)),
      folder,
      split,
      Self.tab("Lost", url: "https://lost.example/x", ago: 86_400 * 3, source: .space(UUID())),
      Self.tab("Fav", url: "https://mail.example", ago: 90, section: .favorites(profile: "default")),
      Self.tab("Old", url: "https://old.example", ago: 86_400 * 10, section: nil),
    ])
    let model = ArchiveListModel(
      source: source, store: store, coordinator: ArchiveCoordinator(source: source, store: store),
      now: { Self.now }, locale: Self.locale)

    let rows = await model.loadPage().rows
    let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })

    #expect(byTitle["Weekend"]?.detail == "news.example.com - Work - 30 seconds ago")
    #expect(byTitle["Weekend"]?.reason == "Closed")
    #expect(byTitle["Reading"]?.detail == "Folder - Work - 2 hours ago")
    #expect(byTitle["Reading"]?.reason == "Auto archived")
    #expect(byTitle["A | B"]?.detail == "Split View - Little Arc - 1 minute ago")
    #expect(byTitle["Lost"]?.detail == "lost.example - Unknown Space - 3 days ago")
    #expect(byTitle["Fav"]?.detail == "mail.example - Favorites - 1 minute ago")
    #expect(byTitle["Old"]?.detail == "old.example - Unknown Space - 1 week ago")
  }

  // MARK: - Restore

  @Test func restoreGoesThroughTheCoordinatorAndDropsTheRow() async throws {
    let harness = try Harness()
    let space = try #require(harness.space)
    let items = [
      Self.tab("First", ago: 10, source: .space(space)),
      Self.tab("Second", ago: 20, source: .space(space)),
    ]
    await harness.store.seed(items)
    _ = await harness.model.loadPage()
    #expect(harness.model.canRestore)

    harness.model.restore(items[1].id)

    #expect(harness.source.children(of: .today(space)) == [items[1].id])
    #expect(harness.model.rows.map(\.id) == [items[0].id])
    #expect(harness.restored.count == 1)
    #expect(harness.restored.first?.0.nodeID == items[1].id)
    #expect(harness.restored.first?.1 == "Tab restored to Work. Click to view.")
    await eventually { await harness.store.removed == [[items[1].id]] }
  }

  @Test func restoredRowStaysHiddenUntilTheStoreRemoveLands() async throws {
    let harness = try Harness()
    let space = try #require(harness.space)
    let items = [Self.tab("First", ago: 10, source: .space(space))]
    await harness.store.seed(items)
    await harness.store.holdRemoves()
    _ = await harness.model.loadPage()

    harness.model.restore(items[0].id)
    let page = await harness.model.loadPage()

    #expect(page.rows.isEmpty)
    await harness.store.releaseRemoves()
  }

  @Test func restoreUsesTheCurrentSpaceWhenTheSourceSpaceIsGone() async throws {
    let source = ModelSidebarSource(now: { Self.now })
    let first = try source.addSpace(title: "First")
    let current = try source.addSpace(title: "Current")
    let item = Self.tab("Orphan", ago: 10, source: .space(UUID()))
    let store = PagedArchiveStore(items: [item])
    let model = ArchiveListModel(
      source: source, store: store, coordinator: ArchiveCoordinator(source: source, store: store),
      now: { Self.now }, locale: Self.locale)
    model.currentSpaceProvider = { current }
    var texts: [String] = []
    model.onRestored = { _, text in texts.append(text) }
    _ = await model.loadPage()

    model.restore(item.id)

    #expect(source.children(of: .today(current)) == [item.id])
    #expect(source.children(of: .today(first)).isEmpty)
    #expect(texts == ["Tab restored to Current. Click to view."])
  }

  @Test func withoutASpaceNothingIsRestored() async throws {
    let harness = try Harness(items: [Self.tab("Lonely", ago: 10)], withSpace: false)
    _ = await harness.model.loadPage()

    #expect(!harness.model.canRestore)
    harness.model.restore(harness.model.rows[0].id)

    #expect(harness.restored.isEmpty)
    #expect(harness.model.rows.count == 1)
    #expect(harness.source.sidebar.nodes.isEmpty)
  }

  @Test func unknownRowIsIgnored() async throws {
    let harness = try Harness(items: [Self.tab("One", ago: 10)])
    _ = await harness.model.loadPage()

    harness.model.restore(UUID())

    #expect(harness.restored.isEmpty)
    #expect(harness.model.rows.count == 1)
  }
}

// MARK: - Helpers

/// An `ArchiveStoring` with a fixed list (sorted newest first on read), a fixed unreadable count, and a record of
/// every limit asked for.
actor PagedArchiveStore: ArchiveStoring {
  private var items: [ArchivedItem]
  private let unreadable: Int
  private var fails = false
  private var holdsRemoves = false
  private var heldRemoves: [CheckedContinuation<Void, Never>] = []
  private var holdsReads = false
  private var heldReads: [CheckedContinuation<Void, Never>] = []
  private(set) var limits: [Int?] = []
  private(set) var removed: [[NodeID]] = []

  init(items: [ArchivedItem] = [], unreadable: Int = 0) {
    self.items = items
    self.unreadable = unreadable
  }

  func seed(_ items: [ArchivedItem]) { self.items += items }
  func setFails(_ fails: Bool) { self.fails = fails }
  func holdRemoves() { holdsRemoves = true }

  func releaseRemoves() {
    holdsRemoves = false
    for held in heldRemoves { held.resume() }
    heldRemoves = []
  }

  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int {
    let ids = Set(items.map(\.id))
    self.items = self.items.filter { !ids.contains($0.id) } + items
    return items.count
  }

  /// Reads after this answer from the items at call time but wait to return until released.
  func holdReads() { holdsReads = true }
  var heldReadCount: Int { heldReads.count }
  /// Lets the read that started last return.
  func releaseLastRead() { heldReads.removeLast().resume() }

  func releaseReads() {
    holdsReads = false
    for held in heldReads { held.resume() }
    heldReads = []
  }

  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage {
    limits.append(limit)
    if fails { throw FakeStoreError() }
    let sorted = items.sorted { $0.archivedAt > $1.archivedAt }
    let page = ArchivePage(items: limit.map { Array(sorted.prefix($0)) } ?? sorted, unreadable: unreadable)
    if holdsReads { await withCheckedContinuation { heldReads.append($0) } }
    return page
  }

  func remove(_ ids: [NodeID]) async throws {
    if holdsRemoves { await withCheckedContinuation { heldRemoves.append($0) } }
    removed.append(ids)
    let gone = Set(ids)
    items.removeAll { gone.contains($0.id) }
  }
}

/// Yields until `condition` holds; records an issue if it never does.
@MainActor
private func eventually(
  _ condition: @MainActor () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<20_000 {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}
