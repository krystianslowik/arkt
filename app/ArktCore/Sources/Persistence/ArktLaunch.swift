import Foundation
import GRDB
import SidebarModel

/// After `.created` or `.recreatedEmpty`, do not seed a default Space (or anything else) into the sidebar before the
/// user acts: backups are skipped only while the sidebar and the archive are empty, so a seeded sidebar would start
/// rolling backups that can prune older backups still holding the user's real data.
public enum OpenOutcome: Hashable, Sendable {
  /// No database and no backup existed; a new one was created. See the seeding note above.
  case created
  /// The live database opened, checked and decoded.
  case opened
  /// Backup `fileName` was restored. `quarantinedAs` names the corrupt live file renamed aside, or is nil when the
  /// live file was missing.
  case restoredFromBackup(fileName: String, quarantinedAs: String?)
  /// No backup was usable; a new empty database was created. `quarantinedAs` as for `restoredFromBackup`. See the
  /// seeding note above.
  case recreatedEmpty(quarantinedAs: String?)
}

public struct LaunchState: Sendable {
  public let database: ArktDatabase
  /// Nil when nothing was saved yet (or after `recreatedEmpty`).
  public let sidebar: Sidebar?
  public let outcome: OpenOutcome
}

public enum ArktLaunch {
  static let stagingName = ".Arkt.sqlite.restoring"

  /// Opens and loads the database, falling back to the newest usable backup. Never deletes user data: a corrupt live
  /// file is renamed aside, and backups are only ever copied. `@concurrent`: all disk work runs off the main thread,
  /// so the main actor only awaits.
  ///
  /// Only corruption (SQLITE_CORRUPT, SQLITE_NOTADB, failed quick_check, checksum mismatch, undecodable sidebar)
  /// quarantines the live file. Anything else (busy, locked, I/O, disk full, permissions) and
  /// `ArktDatabaseError.newerSchema` (a downgrade) are thrown with the live file untouched.
  @concurrent
  public static func openAndLoad(_ location: DatabaseLocation, now: Date) async throws -> LaunchState {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let fileManager = FileManager.default
    try ArktDatabase.createOwnedDirectory(at: location.directory)
    let live = location.databaseURL
    let journal = URL(fileURLWithPath: live.path + "-journal")
    for leftover in [stagingName, stagingName + "-journal"] {
      try? fileManager.removeItem(at: location.directory.appendingPathComponent(leftover, isDirectory: false))
    }
    Backups.removeLeftovers(in: location.backupsDirectory)

    var quarantined: String?
    if fileManager.fileExists(atPath: live.path) {
      let backupBeforeMigrating = (directory: location.backupsDirectory, now: now)
      if let opened = try await attempt(live, backupBeforeMigrating: backupBeforeMigrating) {
        return LaunchState(database: opened.database, sidebar: opened.sidebar, outcome: .opened)
      }
      quarantined = try quarantine(live, journal: journal, in: location.directory, now: now)
    } else if fileManager.fileExists(atPath: journal.path) {
      // A journal without its database would be rolled back into whatever file takes the name next.
      _ = try quarantine(nil, journal: journal, in: location.directory, now: now)
    }

    let backups = try Backups.list(in: location.backupsDirectory)
    for backup in backups {
      let staging = location.directory.appendingPathComponent(stagingName, isDirectory: false)
      try? fileManager.removeItem(at: staging)
      try fileManager.copyItem(at: backup, to: staging)
      try fileManager.moveItem(at: staging, to: live)
      Backups.syncDirectory(location.directory)
      do {
        // A backup from a newer build is as unusable here as a damaged one.
        if let opened = try await attempt(live, backupBeforeMigrating: nil) {
          return LaunchState(
            database: opened.database, sidebar: opened.sidebar,
            outcome: .restoredFromBackup(fileName: backup.lastPathComponent, quarantinedAs: quarantined))
        }
      } catch ArktDatabaseError.newerSchema {
      } catch {
        removeCopy(live, journal: journal)
        throw error
      }
      removeCopy(live, journal: journal)  // only our copy; the backup file is untouched
    }

    let database = try ArktDatabase.open(at: live)
    let outcome: OpenOutcome =
      quarantined == nil && backups.isEmpty ? .created : .recreatedEmpty(quarantinedAs: quarantined)
    return LaunchState(database: database, sidebar: nil, outcome: outcome)
  }

  /// Open (with a pre-migration backup), migrate, quick_check, checksum and decode. Nil when the file is corrupt, with
  /// the connection closed; any other error is rethrown.
  private static func attempt(
    _ url: URL, backupBeforeMigrating: (directory: URL, now: Date)?
  ) async throws -> (database: ArktDatabase, sidebar: Sidebar?)? {
    let database: ArktDatabase
    do {
      database = try ArktDatabase.open(
        at: url, migrator: ArktDatabase.migrator, backupBeforeMigrating: backupBeforeMigrating)
    } catch {
      if isCorruption(error) { return nil }
      throw error
    }
    do {
      return (database: database, sidebar: try await SidebarStore(database: database).load())
    } catch {
      try? database.close()
      if isCorruption(error) { return nil }
      throw error
    }
  }

  static func isCorruption(_ error: any Error) -> Bool {
    switch error {
    case let error as ArktDatabaseError: error == .integrityCheckFailed
    case is SidebarStoreError, is SidebarDocumentError, is DecodingError: true
    case let error as DatabaseError: error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB
    default: false
    }
  }

  /// Renames the live file (journal first) to `Arkt.sqlite.corrupt-<stamp>[-n]`, never overwriting an earlier
  /// quarantine, and returns the new name.
  private static func quarantine(_ live: URL?, journal: URL, in directory: URL, now: Date) throws -> String {
    let fileManager = FileManager.default
    let base = "Arkt.sqlite.corrupt-\(Backups.stamp(now))"
    var name = base
    var counter = 1
    func taken(_ name: String) -> Bool {
      fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        || fileManager.fileExists(atPath: directory.appendingPathComponent(name + "-journal").path)
    }
    while taken(name) {
      counter += 1
      name = "\(base)-\(counter)"
    }
    // Journal first: a crash between the two renames leaves the database without its hot journal under the live
    // name, and the journal already aside under the quarantine name. SQLite then sees no journal to roll back, the
    // next launch finds the same damage and quarantines the database under a fresh name (the counter above), and
    // both halves survive side by side for diagnosis. Moving the database first would instead leave a hot journal
    // under the live name that SQLite would roll back into whichever file takes that name next (a restored backup).
    if fileManager.fileExists(atPath: journal.path) {
      try fileManager.moveItem(at: journal, to: directory.appendingPathComponent(name + "-journal"))
    }
    if let live { try fileManager.moveItem(at: live, to: directory.appendingPathComponent(name)) }
    Backups.syncDirectory(directory)
    return name
  }

  private static func removeCopy(_ live: URL, journal: URL) {
    try? FileManager.default.removeItem(at: live)
    try? FileManager.default.removeItem(at: journal)
  }
}
