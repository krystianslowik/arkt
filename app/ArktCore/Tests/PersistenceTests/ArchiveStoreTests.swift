import Archive
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct ArchiveStoreTests {
  static func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

  static func tab(
    _ title: String, url: String, source: ArchiveSource, reason: ArchiveReason = .manual,
    section: ArchivedSection? = nil, at seconds: Double, id: NodeID = NodeID()
  ) -> ArchivedItem {
    let snapshot = NodeSnapshot(
      id: id, kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: Self.at(0.25))
    return ArchivedItem(
      reason: reason, archivedAt: Self.at(seconds), source: source, section: section, snapshot: snapshot)
  }

  @Test func addThenFetchNewestFirst() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let old = Self.tab("Old", url: "https://example.com/o", source: .unknown, at: 1)
    let new = Self.tab("New", url: "https://example.com/n", source: .unknown, at: 2.5)
    #expect(try await store.add([old, new], onConflict: .replace) == 2)
    #expect(try await store.items().items == [new, old])
    #expect(try await store.count() == 2)
    #expect(try await store.items(limit: 1).items == [new])
  }

  /// `.keepExisting` (Arc re-import): a repeat is ignored and the stored entry is kept, also within one batch.
  @Test func keepExistingIgnoresRepeats() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let id = NodeID()
    let first = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1, id: id)
    let newer = Self.tab("B", url: "https://example.com/b", source: .littleArc, reason: .auto, at: 2, id: id)
    #expect(try await store.add([first], onConflict: .keepExisting) == 1)
    #expect(try await store.add([newer], onConflict: .keepExisting) == 0)
    #expect(try await store.add([newer, newer], onConflict: .keepExisting) == 0)
    #expect(try await store.items().items == [first])
    let other = Self.tab("C", url: "https://example.com/c", source: .unknown, at: 3)
    #expect(try await store.add([other, other, first], onConflict: .keepExisting) == 1)
    #expect(try await store.count() == 2)
  }

  /// `.replace` (the default, app archive events): the newest write of an id wins, every column included.
  @Test func replaceOverwritesTheStoredEntry() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let id = NodeID()
    let first = Self.tab("A", url: "https://example.com/a", source: .space(SpaceID()), section: .today, at: 1, id: id)
    let newer = Self.tab(
      "B", url: "https://example.com/b", source: .littleArc, reason: .auto, section: .favorites(profile: "p"), at: 2,
      id: id)
    #expect(try await store.add([first], onConflict: .replace) == 1)
    #expect(try await store.add([newer], onConflict: .replace) == 1)
    #expect(try await store.items().items == [newer])
    #expect(try await store.items(matching: ArchiveFilter(text: "example.com/b")).items == [newer])
    #expect(try await store.items(matching: ArchiveFilter(text: "example.com/a")).items.isEmpty)
    #expect(try await store.count() == 1)
  }

  /// D4a F1: the section an item was archived from survives the store, for every kind and for nil (unknown).
  @Test(arguments: [nil, .pinned, .today, .favorites(profile: "Work profile")] as [ArchivedSection?])
  func sectionRoundTrips(_ section: ArchivedSection?) async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let source: ArchiveSource = section == nil ? .unknown : .space(SpaceID())
    let item = Self.tab("A", url: "https://example.com/a", source: source, section: section, at: 1)
    _ = try await store.add([item], onConflict: .replace)
    let stored = try await store.items().items
    #expect(stored == [item])
    #expect(stored.first?.section == section)
  }

  /// The table rejects section and source columns that disagree, so a damaged write cannot slip in.
  @Test func schemaRejectsInconsistentSectionAndSourceColumns() async throws {
    let database = try ArktDatabase.inMemory()
    let insert = { (sourceKind: String, spaceID: String?, sectionKind: String?, profile: String?) in
      try await database.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, source_space_id,
              section_kind, section_profile, title, url, snapshot)
            VALUES (?, 1, 'manual', 0, ?, ?, ?, ?, 't', NULL, x'7b7d')
            """,
          arguments: [UUID().uuidString, sourceKind, spaceID, sectionKind, profile])
      }
    }
    await #expect(throws: DatabaseError.self) { try await insert("unknown", nil, "favorites", nil) }
    await #expect(throws: DatabaseError.self) { try await insert("unknown", nil, "pinned", "p") }
    await #expect(throws: DatabaseError.self) { try await insert("unknown", nil, nil, "p") }
    await #expect(throws: DatabaseError.self) { try await insert("unknown", nil, "elsewhere", nil) }
    await #expect(throws: DatabaseError.self) { try await insert("space", nil, nil, nil) }
    await #expect(throws: DatabaseError.self) { try await insert("littleArc", UUID().uuidString, nil, nil) }
    await #expect(throws: Never.self) { try await insert("space", UUID().uuidString, "favorites", "p") }
  }

  @Test func archivedItemTableIsStrict() async throws {
    let database = try ArktDatabase.inMemory()
    let strict = try await database.writer.read { db in
      try Row.fetchOne(db, sql: "SELECT strict FROM pragma_table_list WHERE name = 'archived_item'")?["strict"]
        as Int?
    }
    #expect(strict == 1)
  }

  /// BH-088: filter by Space.
  @Test func filtersBySpace() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let (s1, s2) = (SpaceID(), SpaceID())
    let a = Self.tab("A", url: "https://example.com/a", source: .space(s1), at: 1)
    let b = Self.tab("B", url: "https://example.com/b", source: .space(s2), at: 2)
    _ = try await store.add([a, b], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(source: .space(s1))).items == [a])
  }

  /// BH-088, BH-138: filter by Little Arc.
  @Test func filtersByLittleArc() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let little = Self.tab("L", url: "https://example.com/l", source: .littleArc, at: 1)
    let other = Self.tab("U", url: "https://example.com/u", source: .unknown, at: 2)
    _ = try await store.add([little, other], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(source: .littleArc)).items == [little])
  }

  /// BH-088: filter by close type.
  @Test func filtersByReason() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let auto = Self.tab("Auto", url: "https://example.com/1", source: .unknown, reason: .auto, at: 1)
    let manual = Self.tab("Manual", url: "https://example.com/2", source: .unknown, at: 2)
    _ = try await store.add([auto, manual], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(reason: .auto)).items == [auto])
  }

  /// BH-087: search matches title or URL, case-insensitively; LIKE wildcards in the query are literal.
  @Test func textSearchMatchesTitleAndURL() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let byTitle = Self.tab("Quarterly Report", url: "https://example.com/1", source: .unknown, at: 1)
    let byURL = Self.tab("x", url: "https://docs.example.org/report", source: .unknown, at: 2)
    let percent = Self.tab("100% done", url: "https://example.com/3", source: .unknown, at: 3)
    let backslash = Self.tab("a\\b", url: "https://example.com/4", source: .unknown, at: 4)
    _ = try await store.add([byTitle, byURL, percent, backslash], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(text: "REPORT")).items == [byURL, byTitle])
    #expect(try await store.items(matching: ArchiveFilter(text: "0%")).items == [percent])
    #expect(try await store.items(matching: ArchiveFilter(text: "_")).items.isEmpty)
    #expect(try await store.items(matching: ArchiveFilter(text: "a\\b")).items == [backslash])
    #expect(try await store.items(matching: ArchiveFilter(text: "")).items.count == 4)
  }

  @Test func filtersCombine() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let space = SpaceID()
    let match = Self.tab("Report", url: "https://example.com/1", source: .space(space), reason: .auto, at: 1)
    _ = try await store.add([
      match,
      Self.tab("Report", url: "https://example.com/2", source: .space(space), at: 2),
      Self.tab("Report", url: "https://example.com/3", source: .littleArc, reason: .auto, at: 3),
      Self.tab("Other", url: "https://example.com/4", source: .space(space), reason: .auto, at: 4),
    ], onConflict: .replace)
    let filter = ArchiveFilter(source: .space(space), reason: .auto, text: "report")
    #expect(try await store.items(matching: filter).items == [match])
  }

  @Test func removeDeletesRestoredItems() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let a = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
    let b = Self.tab("B", url: "https://example.com/b", source: .unknown, at: 2)
    _ = try await store.add([a, b], onConflict: .replace)
    try await store.remove([])
    try await store.remove([a.id, NodeID()])
    #expect(try await store.items().items == [b])
  }

  /// BH-087: Clear Archive.
  @Test func removeAllClearsTheArchive() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    _ = try await store.add([Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)], onConflict: .replace)
    try await store.removeAll()
    #expect(try await store.count() == 0)
  }

  @Test func unreadableRowsAreSkipped() async throws {
    let database = try ArktDatabase.inMemory()
    let store = ArchiveStore(database: database)
    let good = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
    _ = try await store.add([good], onConflict: .replace)
    let mismatchedID = try SidebarStorageFormat.makeEncoder().encode(good.snapshot)
    let newer = Self.tab("N", url: "https://example.com/n", source: .unknown, at: 2)
    let newerBody = try SidebarStorageFormat.makeEncoder().encode(newer.snapshot)
    try await database.writer.write { db in
      // Undecodable snapshot, a newer format version, and a snapshot whose id is not the row's id.
      try db.execute(
        sql: """
          INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, title, snapshot)
          VALUES (?, 1, 'manual', 0, 'unknown', 't', x'00'),
                 (?, 99, 'manual', 0, 'unknown', 't', ?),
                 (?, 1, 'manual', 0, 'unknown', 't', ?)
          """,
        arguments: [
          UUID().uuidString, newer.id.uuidString, newerBody, UUID().uuidString, mismatchedID,
        ])
    }
    #expect(try await store.items() == ArchivePage(items: [good], unreadable: 3))
    #expect(try await store.count() == 4)
  }

  @Test func folderAndSplitSnapshotsRoundTrip() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    func tab(_ title: String) -> NodeSnapshot {
      NodeSnapshot(
        kind: .tab(TabItem(
          url: URL(string: "https://example.com/\(title)")!, title: title, customTitle: "Custom \(title)",
          lastActiveAt: Self.at(0.125))),
        createdAt: Self.at(0.5))
    }
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .horizontal, widthFactors: [0.3, 0.7])), createdAt: Self.at(0),
      children: [tab("L"), tab("R")])
    let folder = NodeSnapshot(
      kind: .folder(FolderItem(title: "F")), createdAt: Self.at(0), children: [tab("C"), split])
    let items = [
      ArchivedItem(reason: .manual, archivedAt: Self.at(1), source: .space(SpaceID()), section: .pinned,
                   snapshot: folder),
      ArchivedItem(reason: .auto, archivedAt: Self.at(2), source: .space(SpaceID()), section: .today,
                   snapshot: split.withFreshIDs()),
    ]
    _ = try await store.add(items, onConflict: .replace)
    #expect(try await store.items().items == items.reversed())
  }

  /// The snapshot column holds the canonical D1 encoding of the snapshot (sorted keys, deterministic bytes).
  @Test func snapshotColumnIsTheCanonicalNodeSnapshotEncoding() async throws {
    let database = try ArktDatabase.inMemory()
    let item = Self.tab("A", url: "https://example.com/a/b", source: .unknown, at: 1)
    _ = try await ArchiveStore(database: database).add([item], onConflict: .replace)
    let stored = try await database.writer.read { db in
      try Data.fetchOne(db, sql: "SELECT snapshot FROM archived_item")
    }
    #expect(stored == (try SidebarStorageFormat.makeEncoder().encode(item.snapshot)))
  }

  @MainActor
  @Test func callsFromTheMainActorRunOffTheMainThread() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    _ = try await store.add([Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)], onConflict: .replace)
    #expect(try await store.items().items.count == 1)
    #expect(try await store.count() == 1)
    try await store.removeAll()
  }

  /// #100 (maintainer decision): archive entries older than 30 days (`ArchiveStore.retentionInterval`) are pruned by
  /// `pruneExpired(now:)`; entries at or within the 30-day window stay.
  @Test func pruneExpiredRemovesEntriesOlderThanThirtyDays() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let thirtyDays = ArchiveStore.retentionInterval
    let expired = Self.tab("Expired", url: "https://example.com/old", source: .unknown, at: 100)
    let boundary = Self.tab("Boundary", url: "https://example.com/edge", source: .unknown, at: 101)
    let recent = Self.tab("Recent", url: "https://example.com/new", source: .unknown, at: 100 + thirtyDays)
    _ = try await store.add([expired, boundary, recent], onConflict: .replace)

    let pruned = try await store.pruneExpired(now: Self.at(101 + thirtyDays))
    #expect(pruned == 1)
    #expect(try await store.items().items == [recent, boundary])
  }

  /// An existing v1 file is backed up before `v2-archive` runs; a current file is not backed up again.
  @Test func openingAV1FileBacksItUpBeforeTheArchiveMigration() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let sidebar = TestSidebars.make("v1")
      do {
        let queue = try DatabaseQueue(path: location.databaseURL.path)
        try ArktDatabase.migrator.migrate(queue, upTo: "v1-sidebar")
        try queue.close()
        let v1 = try ArktDatabase(writer: DatabaseQueue(path: location.databaseURL.path))
        _ = try await SidebarStore(database: v1).save(sidebar, at: Self.at(1))
        try v1.close()
      }
      let first = try await ArktLaunch.openAndLoad(location, now: Self.at(5))
      #expect(first.outcome == .opened)
      #expect(first.sidebar == sidebar)
      #expect(try await first.database.writer.read { try ArktDatabase.migrator.completedMigrations($0) }
        == ["v1-sidebar", "v2-archive", "v3-settings"])
      try first.database.close()

      let made = try Backups.list(in: location.backupsDirectory)
      #expect(made.count == 1)
      var readOnly = Configuration()
      readOnly.readonly = true
      let backup = try DatabaseQueue(path: try #require(made.first).path, configuration: readOnly)
      #expect(try await backup.read { try $0.tableExists("archived_item") } == false)
      #expect(try await backup.read { try ArktDatabase.migrator.completedMigrations($0) } == ["v1-sidebar"])
      try backup.close()

      let second = try await ArktLaunch.openAndLoad(location, now: Self.at(6))  // already current: no new backup
      try second.database.close()
      #expect(try Backups.list(in: location.backupsDirectory).count == 1)
    }
  }

  /// Archive rows are user data: a database holding only archived items is backed up, and the backup holds them.
  @Test func archiveOnlyDatabaseIsBackedUp() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      #expect(state.outcome == .created)
      _ = try await SidebarStore(database: state.database).save(Sidebar(), at: Self.at(1))
      let item = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
      _ = try await ArchiveStore(database: state.database).add([item], onConflict: .replace)
      let made = try #require(try await state.database.makeBackup(in: location, now: Self.at(2)))
      let backup = try ArktDatabase.open(at: made)
      defer { try? backup.close() }
      #expect(try await ArchiveStore(database: backup).items().items == [item])
    }
  }

  @Test func emptySidebarAndEmptyArchiveAreStillSkipped() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      #expect(try await state.database.makeBackup(in: location, now: Self.at(1)) == nil)  // no sidebar row
      _ = try await SidebarStore(database: state.database).save(Sidebar(), at: Self.at(2))
      #expect(try await state.database.makeBackup(in: location, now: Self.at(3)) == nil)  // empty sidebar row
      let item = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
      let store = ArchiveStore(database: state.database)
      _ = try await store.add([item], onConflict: .replace)
      try await store.remove([item.id])
      #expect(try await state.database.makeBackup(in: location, now: Self.at(4)) == nil)  // archive emptied again
      #expect(try Backups.list(in: location.backupsDirectory).isEmpty)
    }
  }

  /// An older schema without `archived_item` falls back to the sidebar check.
  @Test func v1SchemaWithoutArchiveTableFallsBackToTheSidebarCheck() async throws {
    let queue = try DatabaseQueue()
    try ArktDatabase.migrator.migrate(queue, upTo: "v1-sidebar")
    #expect(Backups.hasContent(queue) == false)
    _ = try await SidebarStore(database: ArktDatabase(writer: queue)).save(TestSidebars.make("a"), at: Self.at(1))
    #expect(Backups.hasContent(queue) == true)
  }

  /// Writes a row whose snapshot does not decode.
  static func insertUnreadable(_ database: ArktDatabase, at seconds: Double) async throws {
    let archivedAt = Self.at(seconds).timeIntervalSinceReferenceDate
    try await database.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, title, snapshot)
          VALUES (?, 1, 'manual', ?, 'unknown', 't', x'00')
          """,
        arguments: [UUID().uuidString, archivedAt])
    }
  }

  /// A limited page skips unreadable rows, keeps fetching until it has `limit` readable items, and reports the skips.
  @Test func limitedPageFillsPastUnreadableRows() async throws {
    let database = try ArktDatabase.inMemory()
    let store = ArchiveStore(database: database)
    let items = (1...4).map { Self.tab("T\($0)", url: "https://example.com/\($0)", source: .unknown, at: Double($0)) }
    _ = try await store.add(items, onConflict: .replace)
    try await Self.insertUnreadable(database, at: 2.5)
    let page = try await store.items(limit: 3)
    #expect(page.items == [items[3], items[2], items[1]])
    #expect(page.unreadable == 1)
    let all = try await store.items()
    #expect(all.items == items.reversed())
    #expect(all.unreadable == 1)
    let short = try await store.items(limit: 2)  // stops before reaching the unreadable row
    #expect(short.items == [items[3], items[2]])
    #expect(short.unreadable == 0)
    #expect(try await store.items(limit: 10).items.count == 4)
    #expect(try await store.items(limit: 0) == ArchivePage(items: [], unreadable: 0))
  }

  @Test func limitedPageWithManyUnreadableRowsInARow() async throws {
    let database = try ArktDatabase.inMemory()
    let store = ArchiveStore(database: database)
    let old = Self.tab("Old", url: "https://example.com/o", source: .unknown, at: 1)
    let new = Self.tab("New", url: "https://example.com/n", source: .unknown, at: 9)
    _ = try await store.add([old, new], onConflict: .replace)
    for second in 2...6 { try await Self.insertUnreadable(database, at: Double(second)) }
    try await Self.insertUnreadable(database, at: 9)  // same archived_at as `new`: the id breaks the tie
    let page = try await store.items(limit: 2)
    #expect(page.items == [new, old])
    #expect(page.unreadable == 6)
  }
}
