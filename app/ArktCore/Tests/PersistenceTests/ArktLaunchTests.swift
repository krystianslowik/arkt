import Foundation
import GRDB
import SQLite3
import Testing
@testable import Persistence
import SidebarModel

struct ArktLaunchTests {
  static func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

  /// A backup that must be written (the database holds a sidebar).
  static func backup(_ database: ArktDatabase, _ location: DatabaseLocation, at seconds: Double) async throws -> URL {
    try #require(try await database.makeBackup(in: location, now: at(seconds)))
  }

  static func siblings(of location: DatabaseLocation) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: location.directory.path).sorted()
  }

  @Test func firstLaunchCreatesAnEmptyDatabase() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      #expect(state.outcome == .created)
      #expect(state.sidebar == nil)
      #expect(FileManager.default.fileExists(atPath: location.databaseURL.path))
    }
  }

  @MainActor
  @Test func launchFromTheMainActorRunsOffTheMainThread() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory.appendingPathComponent("Nested/Arkt", isDirectory: true))
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      #expect(state.outcome == .created)
      let attributes = try FileManager.default.attributesOfItem(atPath: location.directory.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
  }

  @Test func relaunchLoadsTheSavedSidebar() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let sidebar = TestSidebars.make("a")
      let first = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: first.database).save(sidebar, at: Self.at(1))
      try first.database.close()
      let second = try await ArktLaunch.openAndLoad(location, now: Self.at(2))
      defer { try? second.database.close() }
      #expect(second.outcome == .opened)
      #expect(second.sidebar == sidebar)
    }
  }

  @Test func backupsKeepTheNewestFive() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(0))
      var made: [URL] = []
      for second in 1...7 { made.append(try await Self.backup(state.database, location, at: Double(second))) }
      let kept = try Backups.list(in: location.backupsDirectory)
      #expect(kept == Array(made.suffix(5).reversed()))
    }
  }

  @Test func backupLeavesNoTempFilesAndContainsTheSidebar() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      let sidebar = TestSidebars.make("b")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      let backup = try await Self.backup(state.database, location, at: 2)
      let names = try FileManager.default.contentsOfDirectory(atPath: location.backupsDirectory.path)
      #expect(names == [backup.lastPathComponent])
      let opened = try ArktDatabase.open(at: backup)
      defer { try? opened.close() }
      #expect(try await SidebarStore(database: opened).load() == sidebar)
    }
  }

  @Test func garbageLiveFileRestoresTheNewestBackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let store = SidebarStore(database: state.database)
      _ = try await store.save(TestSidebars.make("old"), at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      let newest = TestSidebars.make("new")
      _ = try await store.save(newest, at: Self.at(3))
      let newestBackup = try await Self.backup(state.database, location, at: 4)
      let backupBytes = try Data(contentsOf: newestBackup)
      try state.database.close()
      let garbage = Data(repeating: 0x42, count: 4096)
      try garbage.write(to: location.databaseURL)

      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(5))
      defer { try? recovered.database.close() }
      guard case .restoredFromBackup(let file, let quarantined) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(file == newestBackup.lastPathComponent)
      #expect(recovered.sidebar == newest)
      #expect(try Data(contentsOf: directory.appendingPathComponent(try #require(quarantined))) == garbage)
      #expect(try Data(contentsOf: newestBackup) == backupBytes)  // the backup itself is untouched
    }
  }

  @Test func checksumFailureAlsoFallsBackToABackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("good")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      try await state.database.writer.write { db in
        try db.execute(sql: "UPDATE sidebar_snapshot SET body = ?", arguments: [Data("bad".utf8)])
      }
      try state.database.close()
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recovered.database.close() }
      #expect(recovered.sidebar == sidebar)
      if case .restoredFromBackup = recovered.outcome {} else { Issue.record("expected restore") }
    }
  }

  @Test func validChecksumButUndecodableBodyFallsBackToABackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("good")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      try await state.database.writer.write { db in
        let body = Data(#"{"favorites":[],"spaces":[],"version":99}"#.utf8)
        try db.execute(
          sql: "UPDATE sidebar_snapshot SET body = ?, sha256 = ?", arguments: [body, SidebarStore.sha256(body)])
      }
      try state.database.close()
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recovered.database.close() }
      #expect(recovered.sidebar == sidebar)
      if case .restoredFromBackup = recovered.outcome {} else { Issue.record("expected restore") }
    }
  }

  @Test func failedQuickCheckFallsBackToABackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("good")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      let pages = try await state.database.writer.write { db -> (count: Int, size: Int) in
        try db.execute(sql: "CREATE TABLE filler (x TEXT)")
        for index in 0..<200 {
          try db.execute(
            sql: "INSERT INTO filler (x) VALUES (?)", arguments: [String(repeating: "x", count: 500) + "\(index)"])
        }
        return (
          count: try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
          size: try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0)
      }
      try state.database.close()
      try corrupt(location.databaseURL, at: UInt64((pages.count - 1) * pages.size + 3), with: [0xFF, 0xFF])
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recovered.database.close() }
      #expect(recovered.sidebar == sidebar)
      if case .restoredFromBackup = recovered.outcome {} else { Issue.record("expected restore") }
    }
  }

  @Test func newerSchemaIsNeitherQuarantinedNorRestored() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      try state.database.close()
      try markAsMigratedByANewerBuild(location.databaseURL)
      let before = try Data(contentsOf: location.databaseURL)
      let names = try Self.siblings(of: location)

      await #expect(throws: ArktDatabaseError.newerSchema) {
        try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      }
      #expect(try Data(contentsOf: location.databaseURL) == before)
      #expect(try Self.siblings(of: location) == names)
    }
  }

  @Test func unusableNewestBackupIsSkipped() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("older")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      let older = try await Self.backup(state.database, location, at: 2)
      let newer = try await Self.backup(state.database, location, at: 3)
      try state.database.close()
      try Data("not sqlite".utf8).write(to: newer)
      try Data("not sqlite".utf8).write(to: location.databaseURL)
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(4))
      defer { try? recovered.database.close() }
      guard case .restoredFromBackup(let file, _) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(file == older.lastPathComponent)
      #expect(recovered.sidebar == sidebar)
      // A bad backup is set aside unchanged, out of rotation, under its own name.
      let setAside = Backups.unusableDirectory(in: location.backupsDirectory)
        .appendingPathComponent(newer.lastPathComponent)
      #expect(try Data(contentsOf: setAside) == Data("not sqlite".utf8))
      #expect(!FileManager.default.fileExists(atPath: newer.path))
      #expect(try Backups.list(in: location.backupsDirectory) == [older])
    }
  }

  @Test func noUsableBackupRecreatesAnEmptyDatabase() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      try Data("not sqlite".utf8).write(to: location.databaseURL)
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? recovered.database.close() }
      guard case .recreatedEmpty(let quarantined) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(recovered.sidebar == nil)
      #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(try #require(quarantined)).path))
    }
  }

  @Test func backupNamesSortChronologically() {
    let early = Backups.fileName(for: Self.at(0))
    let late = Backups.fileName(for: Self.at(0.5))
    #expect(early.hasPrefix("Arkt-") && early.hasSuffix(".sqlite"))
    #expect(early < late)
  }

  @Test func missingLiveFileRestoresTheNewestBackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("kept")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      let backup = try await Self.backup(state.database, location, at: 2)
      try state.database.close()
      try FileManager.default.removeItem(at: location.databaseURL)

      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recovered.database.close() }
      #expect(recovered.outcome == .restoredFromBackup(fileName: backup.lastPathComponent, quarantinedAs: nil))
      #expect(recovered.sidebar == sidebar)
    }
  }

  @Test func missingLiveFileWithOnlyUnusableBackupsIsRecreatedNotCreated() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      try FileManager.default.createDirectory(at: location.backupsDirectory, withIntermediateDirectories: true)
      try Data("not sqlite".utf8).write(to: location.backupsDirectory.appendingPathComponent(Backups.fileName(for: Self.at(0))))
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(1))
      defer { try? state.database.close() }
      #expect(state.outcome == .recreatedEmpty(quarantinedAs: nil))
    }
  }

  @Test func emptyBackupsAfterARecreateNeverEvictTheRealOne() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("real"), at: Self.at(1))
      let real = try await Self.backup(state.database, location, at: 2)
      try state.database.close()
      // Make the only backup unusable for this build so launch has to recreate an empty database.
      try markAsMigratedByANewerBuild(real)
      try Data("not sqlite".utf8).write(to: location.databaseURL)
      let recreated = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recreated.database.close() }
      guard case .recreatedEmpty = recreated.outcome else {
        Issue.record("unexpected outcome \(recreated.outcome)")
        return
      }
      for second in 4...9 {
        #expect(try await recreated.database.makeBackup(in: location, now: Self.at(Double(second))) == nil)
      }
      #expect(try Backups.list(in: location.backupsDirectory).isEmpty)
      let setAside = Backups.unusableDirectory(in: location.backupsDirectory)
        .appendingPathComponent(real.lastPathComponent)
      #expect(FileManager.default.fileExists(atPath: setAside.path))
    }
  }

  /// A backup from a newer build may hold the user's newest real data: once launch finds it unusable it moves to
  /// `Backups/Unusable/`, where later routine backups and their pruning never reach it.
  @Test func newerSchemaBackupSetAsideSurvivesLaterPruning() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("real"), at: Self.at(1))
      let real = try await Self.backup(state.database, location, at: 2)
      try state.database.close()
      try markAsMigratedByANewerBuild(real)
      let realBytes = try Data(contentsOf: real)
      try Data("not sqlite".utf8).write(to: location.databaseURL)

      let recreated = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      defer { try? recreated.database.close() }
      guard case .recreatedEmpty = recreated.outcome else {
        Issue.record("unexpected outcome \(recreated.outcome)")
        return
      }
      _ = try await SidebarStore(database: recreated.database).save(TestSidebars.make("new"), at: Self.at(4))
      for second in 5...(5 + DatabaseLocation.backupsKept + 2) {
        _ = try await Self.backup(recreated.database, location, at: Double(second))
      }
      #expect(try Backups.list(in: location.backupsDirectory).count == DatabaseLocation.backupsKept)
      let setAside = Backups.unusableDirectory(in: location.backupsDirectory)
        .appendingPathComponent(real.lastPathComponent)
      #expect(try Data(contentsOf: setAside) == realBytes)
    }
  }

  @Test func settingAsideNeverOverwritesAnEarlierUnusableBackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let name = Backups.fileName(for: Self.at(0))
      let unusable = Backups.unusableDirectory(in: location.backupsDirectory)
      try FileManager.default.createDirectory(at: unusable, withIntermediateDirectories: true)
      try Data("earlier".utf8).write(to: unusable.appendingPathComponent(name))
      try Data("not sqlite".utf8).write(to: location.backupsDirectory.appendingPathComponent(name))

      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(1))
      defer { try? state.database.close() }
      #expect(state.outcome == .recreatedEmpty(quarantinedAs: nil))
      #expect(try Backups.list(in: location.backupsDirectory).isEmpty)
      #expect(try Data(contentsOf: unusable.appendingPathComponent(name)) == Data("earlier".utf8))
      let names = try FileManager.default.contentsOfDirectory(atPath: unusable.path).sorted()
      #expect(names.count == 2)
      let moved = try #require(names.first { $0 != name })
      #expect(try Data(contentsOf: unusable.appendingPathComponent(moved)) == Data("not sqlite".utf8))
    }
  }

  @Test func lockedLiveFileThrowsAndIsLeftUntouched() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      try state.database.close()
      let before = try Data(contentsOf: location.databaseURL)
      let names = try Self.siblings(of: location)

      var handle: OpaquePointer?
      #expect(sqlite3_open(location.databaseURL.path, &handle) == SQLITE_OK)
      defer { sqlite3_close(handle) }
      #expect(sqlite3_exec(handle, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
      let error = await #expect(throws: DatabaseError.self) {
        try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      }
      #expect(error?.resultCode == .SQLITE_BUSY)
      #expect(sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
      #expect(try Data(contentsOf: location.databaseURL) == before)
      #expect(try Self.siblings(of: location) == names)
    }
  }

  @Test func newerFormatVersionIsADowngradeNotCorruption() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      _ = try await Self.backup(state.database, location, at: 2)
      try await state.database.writer.write { db in
        try db.execute(sql: "UPDATE sidebar_snapshot SET format_version = ?", arguments: [SidebarStorageFormat.currentVersion + 1])
      }
      try state.database.close()
      let before = try Data(contentsOf: location.databaseURL)
      let names = try Self.siblings(of: location)
      await #expect(throws: ArktDatabaseError.newerSchema) {
        try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      }
      #expect(try Data(contentsOf: location.databaseURL) == before)
      #expect(try Self.siblings(of: location) == names)
    }
  }

  @Test func quarantineNamesNeverCollide() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      var quarantined: [String] = []
      for _ in 0..<2 {
        try Data("not sqlite".utf8).write(to: location.databaseURL)
        let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
        try state.database.close()
        guard case .recreatedEmpty(let name?) = state.outcome else {
          Issue.record("unexpected outcome \(state.outcome)")
          return
        }
        quarantined.append(name)
      }
      #expect(Set(quarantined).count == 2)
      for name in quarantined {
        #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == Data("not sqlite".utf8))
      }
    }
  }

  @Test func leftoversAreRemovedAndForeignBackupNamesIgnored() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: location.backupsDirectory, withIntermediateDirectories: true)
      let stale = [
        location.directory.appendingPathComponent(".Arkt.sqlite.restoring"),
        location.directory.appendingPathComponent(".Arkt.sqlite.restoring-journal"),
        location.backupsDirectory.appendingPathComponent(".Arkt-20260101T000000000Z.sqlite.tmp"),
        location.backupsDirectory.appendingPathComponent(".Arkt-20260101T000000000Z.sqlite.tmp-journal"),
      ]
      let foreign = ["Arkt-notes.sqlite", "Arkt-20260101T000000000Z.sqlite.bak", "arkt-20260101T000000000Z.sqlite"]
      for url in stale { try Data("x".utf8).write(to: url) }
      for name in foreign { try Data("x".utf8).write(to: location.backupsDirectory.appendingPathComponent(name)) }

      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      #expect(state.outcome == .created)
      for url in stale { #expect(!fileManager.fileExists(atPath: url.path)) }
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      for second in 2...8 { _ = try await Self.backup(state.database, location, at: Double(second)) }
      #expect(try Backups.list(in: location.backupsDirectory).count == DatabaseLocation.backupsKept)
      for name in foreign {
        #expect(fileManager.fileExists(atPath: location.backupsDirectory.appendingPathComponent(name).path))
      }
    }
  }

  @Test func existingAppDirectoryIsMadePrivate() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory.appendingPathComponent("Arkt", isDirectory: true))
      try FileManager.default.createDirectory(
        at: location.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      let attributes = try FileManager.default.attributesOfItem(atPath: location.directory.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
  }

  @Test func sameStampBackupsDoNotReplaceEachOther() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      let first = try await Self.backup(state.database, location, at: 2)
      let second = try await Self.backup(state.database, location, at: 2)
      #expect(first != second)
      #expect(try Backups.list(in: location.backupsDirectory) == [second, first])
    }
  }

  @Test func overlappingBackupsBothSucceed() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      defer { try? state.database.close() }
      _ = try await SidebarStore(database: state.database).save(TestSidebars.make("a"), at: Self.at(1))
      let database = state.database
      async let first = database.makeBackup(in: location, now: Self.at(2))
      async let second = database.makeBackup(in: location, now: Self.at(2))
      let made = try await [first, second].compactMap { $0 }
      #expect(Set(made).count == 2)
      #expect(Set(try Backups.list(in: location.backupsDirectory)) == Set(made))
      let names = try FileManager.default.contentsOfDirectory(atPath: location.backupsDirectory.path)
      #expect(names.count == 2)  // no temp files left behind
      for url in made {
        let opened = try ArktDatabase.open(at: url)
        defer { try? opened.close() }
        #expect(try await SidebarStore(database: opened).load() != nil)
      }
    }
  }
}
