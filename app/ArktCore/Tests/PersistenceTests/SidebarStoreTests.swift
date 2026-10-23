import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct SidebarStoreTests {
  @Test func freshDatabaseHasNoSidebar() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    #expect(try await store.load() == nil)
  }

  @Test func saveThenLoadRoundTrips() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    let sidebar = TestSidebars.make("a")
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 10)) == .written)
    #expect(try await store.load() == sidebar)
  }

  @Test func secondSaveReplacesTheOnlyRow() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    let b = TestSidebars.make("b")
    _ = try await store.save(b, at: Date(timeIntervalSinceReferenceDate: 2))
    #expect(try await store.load() == b)
    let rows = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sidebar_snapshot") }
    #expect(rows == 1)
  }

  @Test func identicalSaveIsSkipped() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    let sidebar = TestSidebars.make("a")
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 1)) == .written)
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 2)) == .unchanged)
  }

  @Test func corruptedBodyFailsTheChecksum() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    try await database.writer.write { db in
      try db.execute(sql: "UPDATE sidebar_snapshot SET body = ?", arguments: [Data("garbage".utf8)])
    }
    await #expect(throws: SidebarStoreError.checksumMismatch) { try await store.load() }
  }

  @Test func validChecksumButUnsupportedVersionFailsToDecode() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    try await database.writer.write { db in
      let body = Data(#"{"favorites":[],"spaces":[],"version":99}"#.utf8)
      try db.execute(
        sql: "UPDATE sidebar_snapshot SET body = ?, sha256 = ?", arguments: [body, SidebarStore.sha256(body)])
    }
    await #expect(throws: SidebarDocumentError.unsupportedVersion(99)) { try await store.load() }
  }

  @Test func validChecksumButUndecodableBodyFailsToDecode() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    try await database.writer.write { db in
      let body = Data("not json".utf8)
      try db.execute(
        sql: "UPDATE sidebar_snapshot SET body = ?, sha256 = ?", arguments: [body, SidebarStore.sha256(body)])
    }
    await #expect(throws: DecodingError.self) { try await store.load() }
  }

  @Test func snapshotTableIsStrict() async throws {
    let database = try ArktDatabase.inMemory()
    let sql = try await database.writer.read {
      try String.fetchOne($0, sql: "SELECT sql FROM sqlite_master WHERE name = 'sidebar_snapshot'")
    }
    #expect(sql?.hasSuffix("STRICT") == true)
    await #expect(throws: DatabaseError.self) {
      try await database.writer.write { db in
        try db.execute(
          sql: "INSERT INTO sidebar_snapshot (id, format_version, saved_at, sha256, body) VALUES (1, 1, 0, 'x', 'text')")
      }
    }
  }

  @Test func persistsAcrossReopen() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let sidebar = TestSidebars.make("kept")
      do {
        let database = try ArktDatabase.open(at: url)
        _ = try await SidebarStore(database: database).save(sidebar, at: Date(timeIntervalSinceReferenceDate: 1))
        try database.close()
      }
      let reopened = try ArktDatabase.open(at: url)
      defer { try? reopened.close() }
      #expect(try await SidebarStore(database: reopened).load() == sidebar)
    }
  }

  @Test func usesRollbackJournalAndFullFsync() async throws {
    try await withTemporaryDirectory { directory in
      let database = try ArktDatabase.open(at: directory.appendingPathComponent("Arkt.sqlite"))
      defer { try? database.close() }
      let mode = try await database.writer.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
      #expect(mode == "delete")
      let fullfsync = try await database.writer.read { try Int.fetchOne($0, sql: "PRAGMA fullfsync") }
      #expect(fullfsync == 1)
    }
  }

  @Test func reopeningRunsNoMigrationTwice() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      try ArktDatabase.open(at: url).close()
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      let applied = try await database.writer.read { try ArktDatabase.migrator.completedMigrations($0) }
      #expect(applied == ["v1-sidebar", "v2-archive", "v3-settings"])
    }
  }

  @Test func openCreatesMissingNestedPrivateDirectory() async throws {
    try await withTemporaryDirectory { directory in
      let nested = directory.appendingPathComponent("a/b/c", isDirectory: true)
      let database = try ArktDatabase.open(at: nested.appendingPathComponent("Arkt.sqlite"))
      defer { try? database.close() }
      let attributes = try FileManager.default.attributesOfItem(atPath: nested.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
      #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("Arkt.sqlite").path))
    }
  }

  @Test func failedQuickCheckThrowsIntegrityCheckFailed() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let database = try ArktDatabase.open(at: url)
      let pages = try await database.writer.write { db -> (count: Int, size: Int) in
        try db.execute(sql: "CREATE TABLE filler (x TEXT)")
        for index in 0..<200 {
          try db.execute(
            sql: "INSERT INTO filler (x) VALUES (?)", arguments: [String(repeating: "x", count: 500) + "\(index)"])
        }
        return (
          count: try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
          size: try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0)
      }
      try database.close()
      // Damage the cell count of the last page (a filler leaf): the schema and migrations stay readable.
      try corrupt(url, at: UInt64((pages.count - 1) * pages.size + 3), with: [0xFF, 0xFF])
      #expect(throws: ArktDatabaseError.integrityCheckFailed) { try ArktDatabase.open(at: url) }
    }
  }

  @Test func databaseFromANewerBuildThrowsNewerSchema() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      try markAsMigratedByANewerBuild(url)
      let before = try Data(contentsOf: url)
      #expect(throws: ArktDatabaseError.newerSchema) { try ArktDatabase.open(at: url) }
      #expect(try Data(contentsOf: url) == before)
    }
  }

  @Test func newerFormatVersionThrowsNewerSchema() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    try await database.writer.write { db in
      try db.execute(
        sql: "UPDATE sidebar_snapshot SET format_version = ?", arguments: [SidebarStorageFormat.currentVersion + 1])
    }
    await #expect(throws: ArktDatabaseError.newerSchema) { try await store.load() }
  }

  @Test func pendingMigrationOnAnExistingFileIsBackedUpFirst() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let backups = directory.appendingPathComponent("Backups", isDirectory: true)
      let sidebar = TestSidebars.make("v1")
      let v1 = try ArktDatabase.open(at: url, migrator: ArktDatabase.migrator, backupBeforeMigrating: (backups, .now))
      #expect(try Backups.list(in: backups).isEmpty)  // a fresh file has nothing to protect
      _ = try await SidebarStore(database: v1).save(sidebar, at: Date(timeIntervalSinceReferenceDate: 1))
      try v1.close()

      var v2Migrator = ArktDatabase.migrator
      v2Migrator.registerMigration("v2-test") { db in
        try db.execute(sql: "CREATE TABLE v2_marker (id INTEGER PRIMARY KEY) STRICT")
      }
      let migrator = v2Migrator
      let v2 = try ArktDatabase.open(at: url, migrator: migrator, backupBeforeMigrating: (backups, .now))
      defer { try? v2.close() }
      #expect(
        try await v2.writer.read { try migrator.completedMigrations($0) }
          == ["v1-sidebar", "v2-archive", "v3-settings", "v2-test"])

      let made = try Backups.list(in: backups)
      #expect(made.count == 1)
      let backup = try ArktDatabase.open(at: try #require(made.first))
      defer { try? backup.close() }
      #expect(try await backup.writer.read { try $0.tableExists("v2_marker") } == false)
      #expect(try await SidebarStore(database: backup).load() == sidebar)
    }
  }

  @Test func openingInAnExistingDirectoryLeavesItsModeAlone() async throws {
    try await withTemporaryDirectory { directory in
      let shared = directory.appendingPathComponent("shared", isDirectory: true)
      try FileManager.default.createDirectory(
        at: shared, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
      let database = try ArktDatabase.open(at: shared.appendingPathComponent("Arkt.sqlite"))
      defer { try? database.close() }
      let attributes = try FileManager.default.attributesOfItem(atPath: shared.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    }
  }
}
