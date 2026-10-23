import Archive
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
        let v2 = ArktDatabase(writer: queue)
        _ = try await ArchiveStore(database: v2).add([item], onConflict: .replace)
        try v2.close()
      }
      let state = try await ArktLaunch.openAndLoad(location, now: Self.date)
      #expect(state.outcome == .opened)
      #expect(try await state.database.writer.read { try ArktDatabase.migrator.completedMigrations($0) }
        == ["v1-sidebar", "v2-archive", "v3-settings"])
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
}
