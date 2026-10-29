import Archive
import ArcImport
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct SettingsStoreTests {
  static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test func missingGroupLoadsItsDefault() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    #expect(try await store.load(ArchiveSettings.self) == ArchiveSettings())
    #expect(try await store.load(ArchiveState.self) == ArchiveState())
  }

  @Test func saveThenLoad() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: "default", scope: .thisProfile)
    try await store.save(settings, at: Self.date)
    #expect(try await store.load(ArchiveSettings.self) == settings)
    settings.littleArcThreshold = .never
    try await store.save(settings, at: Self.date.addingTimeInterval(1))
    #expect(try await store.load(ArchiveSettings.self) == settings)
  }

  @Test func unreadableValueLoadsTheDefault() async throws {
    let database = try ArktDatabase.inMemory()
    try await database.writer.write { db in
      try db.execute(
        sql: "INSERT INTO setting (key, value, updated_at) VALUES (?, ?, 0)",
        arguments: [ArchiveSettings.storageKey, Data("not json".utf8)])
    }
    #expect(try await SettingsStore(database: database).load(ArchiveSettings.self) == ArchiveSettings())
  }

  @Test func groupsAreIndependent() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let state = ArchiveState(autoArchiveStartedAt: Self.date, educationBannerDismissed: true)
    try await store.save(state, at: Self.date)
    #expect(try await store.load(ArchiveSettings.self) == ArchiveSettings())
    #expect(try await store.load(ArchiveState.self) == state)
  }

  @Test func settingTableIsStrict() async throws {
    let database = try ArktDatabase.inMemory()
    let strict = try await database.writer.read { db in
      try Row.fetchOne(db, sql: "SELECT strict FROM pragma_table_list WHERE name = 'setting'")?["strict"] as Int?
    }
    #expect(strict == 1)
  }

  /// D4b review: `AutoArchiveInput.startedAt` comes from the persisted `ArchiveState.autoArchiveStartedAt`, set once.
  @Test func autoArchiveStartIsResolvedOnceAndPersisted() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    try await store.save(ArchiveState(educationBannerDismissed: true), at: Self.date)
    #expect(try await store.resolveAutoArchiveStart(now: Self.date) == Self.date)
    #expect(try await store.resolveAutoArchiveStart(now: Self.date.addingTimeInterval(60)) == Self.date)
    #expect(try await store.load(ArchiveState.self)
      == ArchiveState(autoArchiveStartedAt: Self.date, educationBannerDismissed: true))
  }

  @MainActor
  @Test func callsFromTheMainActorRunOffTheMainThread() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    try await store.save(ArchiveSettings(), at: Self.date)
    _ = try await store.load(ArchiveSettings.self)
    _ = try await store.resolveAutoArchiveStart(now: Self.date)
  }

  @Test func settingsSurviveReopen() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      var settings = ArchiveSettings()
      settings.littleArcThreshold = .twentyFourHours
      do {
        let database = try ArktDatabase.open(at: url)
        try await SettingsStore(database: database).save(settings, at: Self.date)
        try database.close()
      }
      let reopened = try ArktDatabase.open(at: url)
      defer { try? reopened.close() }
      #expect(try await SettingsStore(database: reopened).load(ArchiveSettings.self) == settings)
    }
  }

  /// An existing v2 file (here holding only archive rows) is backed up before `v3-settings` runs.
  @Test func openingAV2FileBacksItUpBeforeTheSettingsMigration() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let item = ArchivedItem(
        reason: .manual, archivedAt: Self.date, source: .unknown,
        snapshot: NodeSnapshot(
          kind: .tab(TabItem(url: URL(string: "https://example.com/a")!, title: "A")), createdAt: Self.date))
      do {
        let queue = try DatabaseQueue(path: location.databaseURL.path)
        try ArktDatabase.migrator.migrate(queue, upTo: "v2-archive")
        // The v2 columns only: today's `ArchiveStore.add` also writes the later `search_text` column.
        let body = try SidebarStorageFormat.makeEncoder().encode(item.snapshot)
        try await queue.write { db in
          try db.execute(
            sql: """
              INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, title, url, snapshot)
              VALUES (?, 1, 'manual', ?, 'unknown', 'A', 'https://example.com/a', ?)
              """,
            arguments: [item.id.uuidString, Self.date.timeIntervalSinceReferenceDate, body])
        }
        try queue.close()
      }
      let state = try await ArktLaunch.openAndLoad(location, now: Self.date)
      #expect(state.outcome == .opened)
      #expect(try await state.database.writer.read { try ArktDatabase.migrator.completedMigrations($0) }
        == ["v1-sidebar", "v2-archive", "v3-settings", "v4-archive-search"])
      #expect(try await ArchiveStore(database: state.database).items().items == [item])
      try state.database.close()

      let made = try Backups.list(in: location.backupsDirectory)
      #expect(made.count == 1)
      var readOnly = Configuration()
      readOnly.readonly = true
      let backup = try DatabaseQueue(path: try #require(made.first).path, configuration: readOnly)
      #expect(try await backup.read { try $0.tableExists("setting") } == false)
      #expect(try await backup.read { try ArktDatabase.migrator.completedMigrations($0) }
        == ["v1-sidebar", "v2-archive"])
      try backup.close()
    }
  }

  @Test func resetAutoArchiveStartOverwritesAndKeepsOtherFields() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try await store.resolveAutoArchiveStart(now: first)
    try await store.save(ArchiveState(autoArchiveStartedAt: first, educationBannerDismissed: true), at: first)
    let later = first.addingTimeInterval(3600)
    try await store.resetAutoArchiveStart(to: later)
    let state = try await store.load(ArchiveState.self)
    #expect(state.autoArchiveStartedAt == later)
    #expect(state.educationBannerDismissed)
    #expect(try await store.resolveAutoArchiveStart(now: later.addingTimeInterval(60)) == later)
  }

  @Test func resetAutoArchiveStartWithNothingStoredSetsIt() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    try await store.resetAutoArchiveStart(to: Self.date)
    #expect(try await store.load(ArchiveState.self).autoArchiveStartedAt == Self.date)
  }

  @Test func loadArchiveSettingsReadsTheStoredGroup() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    #expect(try await store.loadArchiveSettings() == ArchiveSettings())
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: "default", scope: .thisProfile)
    try await store.save(settings, at: Self.date)
    #expect(try await store.loadArchiveSettings() == settings)
  }

  @Test func storesConformToTheArchiveProtocols() throws {
    let database = try ArktDatabase.inMemory()
    let _: any ArchiveStoring = ArchiveStore(database: database)
    let _: any ArchiveStateStoring = SettingsStore(database: database)
  }

  // MARK: Arc import record

  @Test func arcImportRecordIsEmptyUntilSomethingIsRecorded() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let record = try await store.loadArcImportRecord()
    #expect(record == ArcImportRecord())
    #expect(record.isEmpty)
  }

  @Test func recordArcImportAddsToWhatIsStored() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    try await store.recordArcImport(ArcImportRecord(spaceIDs: ["s1"], favoriteItemIDs: ["f1"]), at: Self.date)
    try await store.recordArcImport(ArcImportRecord(spaceIDs: ["s2"], favoriteItemIDs: ["f1", "f2"]), at: Self.date)
    let record = try await store.loadArcImportRecord()
    #expect(record == ArcImportRecord(spaceIDs: ["s1", "s2"], favoriteItemIDs: ["f1", "f2"]))
    #expect(!record.isEmpty)
  }

  @Test func recordArcImportMergesVersionTwoFieldsAndKeepsTheLaterWatermark() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let early = Self.date
    let late = Self.date.addingTimeInterval(500)
    try await store.recordArcImport(ArcImportRecord(historyWatermark: late, cookieKeys: ["c1"]), at: Self.date)
    try await store.recordArcImport(
      ArcImportRecord(historyWatermark: early, bookmarkKeys: ["b1"], cookieKeys: ["c2"], extensionIDs: ["e1"]), at: Self.date)
    let record = try await store.loadArcImportRecord()
    #expect(record == ArcImportRecord(
      historyWatermark: late, bookmarkKeys: ["b1"], cookieKeys: ["c1", "c2"], extensionIDs: ["e1"]))
  }

  @Test func arcImportRecordIsStoredSortedAndSurvivesReopen() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let recorded = ArcImportRecord(spaceIDs: ["b", "a", "c"], favoriteItemIDs: ["z", "y"])
      do {
        let database = try ArktDatabase.open(at: url)
        try await SettingsStore(database: database).recordArcImport(recorded, at: Self.date)
        let key = ArcImportRecord.storageKey
        let raw = try await database.writer.read { db in
          try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
        }
        #expect(raw.map { String(decoding: $0, as: UTF8.self) }
          == #"{"favoriteItemIDs":["y","z"],"spaceIDs":["a","b","c"]}"#)
        try database.close()
      }
      let reopened = try ArktDatabase.open(at: url)
      defer { try? reopened.close() }
      #expect(try await SettingsStore(database: reopened).loadArcImportRecord() == recorded)
    }
  }

  @Test func settingsStoreIsAnArcImportRecordStore() throws {
    let _: any ArcImportRecordStoring = SettingsStore(database: try ArktDatabase.inMemory())
  }
}
