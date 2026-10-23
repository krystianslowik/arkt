import Foundation
import GRDB
import SidebarModel
import Synchronization

/// Where Arkt keeps its database. App code uses `applicationSupport()`; tests pass a temp directory.
public struct DatabaseLocation: Hashable, Sendable {
  public static let backupsKept = 5

  public let directory: URL
  public init(directory: URL) { self.directory = directory }

  public var databaseURL: URL { directory.appendingPathComponent("Arkt.sqlite", isDirectory: false) }
  public var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

  /// `~/Library/Application Support/Arkt`. Never Arc's directory.
  public static func applicationSupport() throws -> DatabaseLocation {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return DatabaseLocation(directory: base.appendingPathComponent("Arkt", isDirectory: true))
  }
}

/// Rolling file backups: `Backups/Arkt-<UTC stamp>.sqlite`, newest `DatabaseLocation.backupsKept` kept.
enum Backups {
  static func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
    return formatter.string(from: date)
  }

  static func fileName(for date: Date) -> String { "Arkt-\(stamp(date)).sqlite" }

  /// Backup files, newest first. Only exact `Arkt-<stamp>.sqlite` names count; anything else is ignored (never
  /// restored, never pruned).
  static func list(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.wholeMatch(of: /Arkt-[0-9]{8}T[0-9]{9}Z\.sqlite/) != nil }
      .sorted(by: >)
      .map { directory.appendingPathComponent($0, isDirectory: false) }
  }

  /// Serializes every backup and leftover sweep in the process (routine `makeBackup`, pre-migration backups and the
  /// launch sweep), so the free-name check and the temp files of one backup can never race another.
  /// NOT re-entrant (`Mutex` deadlocks or traps on a nested lock): nothing called inside `writeLocked` or
  /// `removeLeftoversLocked` may call `write` or `removeLeftovers`.
  private static let lock = Mutex(())

  /// Copies `source` with SQLite's online backup API into a hidden temp file, renames it into place, then prunes to
  /// the newest `DatabaseLocation.backupsKept`. Returns nil without writing when `source` holds no user data (see
  /// `hasContent`): an empty backup restores nothing, and writing it would prune a real one. Because every backup
  /// written has user data (or content that could not be judged), pruning never evicts the newest backup holding
  /// user data.
  /// Blocking (and serialized process-wide): call only from a `@concurrent` context.
  static func write(from source: some DatabaseReader, to directory: URL, now: Date) throws -> URL? {
    guard hasContent(source) else { return nil }
    return try lock.withLock { _ in try writeLocked(from: source, to: directory, now: now) }
  }

  private static func writeLocked(from source: some DatabaseReader, to directory: URL, now: Date) throws -> URL {
    let fileManager = FileManager.default
    try ArktDatabase.createOwnedDirectory(at: directory)
    var date = now
    var final = directory.appendingPathComponent(fileName(for: date), isDirectory: false)
    while fileManager.fileExists(atPath: final.path) {  // never replace an existing backup
      date += 0.001
      final = directory.appendingPathComponent(fileName(for: date), isDirectory: false)
    }
    let temp = directory.appendingPathComponent(".\(final.lastPathComponent).tmp", isDirectory: false)
    do {
      let destination = try DatabaseQueue(path: temp.path, configuration: ArktDatabase.configuration)
      do {
        try source.backup(to: destination)
      } catch {
        try? destination.close()
        throw error
      }
      try destination.close()
      try fileManager.moveItem(at: temp, to: final)
      syncDirectory(directory)
    } catch {
      // Only this backup's own files; leftovers of crashed runs are swept at launch.
      try? fileManager.removeItem(at: temp)
      try? fileManager.removeItem(at: URL(fileURLWithPath: temp.path + "-journal"))
      throw error
    }
    // Pruning is best effort: the backup is already in place, so a failed listing must not report it as failed.
    for old in ((try? list(in: directory)) ?? []).dropFirst(DatabaseLocation.backupsKept) {
      try? fileManager.removeItem(at: old)
    }
    return final
  }

  /// User data is a sidebar with any Space or node, or at least one `archived_item` row. Archive rows only come from
  /// real use or a real import, so counting them cannot let a seeded empty sidebar start evicting real backups. A
  /// schema without `archived_item` (v1) falls back to the sidebar check. Unknown content (a damaged row, an
  /// unreadable file) counts as content: skipping a backup must never risk skipping user data.
  static func hasContent(_ source: some DatabaseReader) -> Bool {
    do {
      let (stored, archivedItems) = try source.read { db -> (SidebarStore.StoredSnapshot?, Int) in
        let archivedItems =
          try db.tableExists("archived_item")
          ? try Int.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM archived_item)") ?? 0 : 0
        return (try SidebarStore.fetchStored(db), archivedItems)
      }
      if archivedItems > 0 { return true }
      guard let stored else { return false }
      let sidebar = try SidebarStore.decode(stored)
      return !(sidebar.spaces.isEmpty && sidebar.nodes.isEmpty)
    } catch {
      return true
    }
  }

  /// Removes temp files an interrupted backup left behind (`.Arkt-<stamp>.sqlite.tmp` and its `-journal`). Called at
  /// launch only, under the backup lock, so it never deletes the temp file of a backup in progress.
  static func removeLeftovers(in directory: URL) {
    lock.withLock { _ in removeLeftoversLocked(in: directory) }
  }

  private static func removeLeftoversLocked(in directory: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in names where name.hasPrefix(".Arkt-") && (name.hasSuffix(".tmp") || name.hasSuffix(".tmp-journal")) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
    }
  }

  /// Makes renames in `directory` durable: F_FULLFSYNC on the directory, falling back to fsync. Best effort.
  static func syncDirectory(_ directory: URL) {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { return }
    defer { _ = Darwin.close(descriptor) }
    if fcntl(descriptor, F_FULLFSYNC) != 0 { _ = fsync(descriptor) }
  }
}

extension ArktDatabase {
  /// Makes one rolling backup. Call on launch after a successful load and periodically; not per save. Returns nil,
  /// writing nothing, while the database holds no user data: an empty sidebar and an empty archive (for example right
  /// after `.created` or `.recreatedEmpty`).
  @concurrent
  public func makeBackup(in location: DatabaseLocation, now: Date) async throws -> URL? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try Backups.write(from: writer, to: location.backupsDirectory, now: now)
  }
}
