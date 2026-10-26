import Archive
import Foundation
import GRDB
import SidebarModel

/// Arkt's single SQLite database: sidebar snapshot, archive and settings.
///
/// `DatabaseQueue` with GRDB's default rollback journal (`journal_mode=delete`): one connection, one self-contained
/// file. Every access goes through GRDB's async `read`/`write`, which run on GRDB's serial queue, never on the caller's
/// thread. Migrations are forward-only: never edit a released migration, add a new one.
public struct ArktDatabase: Sendable {
  let writer: DatabaseQueue

  init(writer: DatabaseQueue) { self.writer = writer }

  /// A migrated in-memory database, for tests and previews.
  public static func inMemory() throws -> ArktDatabase {
    let queue = try DatabaseQueue(configuration: configuration)
    try migrator.migrate(queue)
    return ArktDatabase(writer: queue)
  }

  /// Opens (creating it and its directory, mode 0700, if needed) and migrates the database at `url`, then runs
  /// `PRAGMA quick_check`. Throws `newerSchema` without touching the file when a newer build migrated it, and any
  /// other error for an unusable file; `ArktLaunch` decides what to do about it. Blocking: call off the main thread.
  public static func open(at url: URL) throws -> ArktDatabase {
    try open(at: url, migrator: migrator, backupBeforeMigrating: nil)
  }

  /// `backupBeforeMigrating`: when the file already has applied migrations and this build has pending ones, a
  /// rolling backup is written there (stamped `now`) before any migration runs, so a bad migration never loses data.
  static func open(
    at url: URL, migrator: DatabaseMigrator, backupBeforeMigrating: (directory: URL, now: Date)?
  ) throws -> ArktDatabase {
    try createPrivateDirectory(at: url.deletingLastPathComponent())
    let queue = try DatabaseQueue(path: url.path, configuration: configuration)
    do {
      if try queue.read({ try migrator.hasBeenSuperseded($0) }) { throw ArktDatabaseError.newerSchema }
      let check = try queue.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }
      guard check == "ok" else { throw ArktDatabaseError.integrityCheckFailed }
      if let backup = backupBeforeMigrating {
        let pending = try queue.read { db in
          try !migrator.appliedIdentifiers(db).isEmpty && !migrator.hasCompletedMigrations(db)
        }
        if pending { _ = try Backups.write(from: queue, to: backup.directory, now: backup.now) }
      }
      try migrator.migrate(queue)
    } catch {
      try? queue.close()
      throw error
    }
    return ArktDatabase(writer: queue)
  }

  /// Closes the connection. Further use of this database throws.
  public func close() throws { try writer.close() }

  /// Creates `directory` and any missing parents with mode 0700 (the sidebar holds the user's browsing data). An
  /// existing directory keeps its mode: `open(at:)` may be pointed anywhere and must not chmod someone else's folder.
  static func createPrivateDirectory(at directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }

  /// Like `createPrivateDirectory`, and also tightens an existing directory to 0700. Only for directories Arkt owns:
  /// the app directory and its `Backups`.
  static func createOwnedDirectory(at directory: URL) throws {
    try createPrivateDirectory(at: directory)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  /// `fullfsync`: on Apple platforms plain fsync does not flush the drive's write cache, so a power loss could tear
  /// a committed transaction. F_FULLFSYNC costs a cache flush per commit (low milliseconds on internal SSDs, more on
  /// external volumes); acceptable because writes are debounced and run off the main thread.
  static var configuration: Configuration {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA fullfsync = ON")
    }
    return configuration
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    // Never set eraseDatabaseOnSchemaChange: it deletes user data.
    migrator.registerMigration("v1-sidebar") { db in
      try db.execute(sql: """
        CREATE TABLE sidebar_snapshot (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          format_version INTEGER NOT NULL,
          saved_at REAL NOT NULL,
          sha256 TEXT NOT NULL,
          body BLOB NOT NULL
        ) STRICT
        """)
      // STRICT enforces each column's storage class, which keeps SidebarStore's optional reads trap-free.
    }
    // Opening an existing v1 file runs this after `open`'s pre-migration backup.
    migrator.registerMigration("v2-archive") { db in
      // One row per archived root node (`id` = the snapshot's root id). `snapshot` is the canonical D1 NodeSnapshot
      // JSON written with `format_version`; title, url, reason and source are denormalized for search and filters
      // (BH-087, BH-088). The section columns are nullable: nil means unknown (for example an Arc import). The
      // CHECKs keep the source and section column pairs consistent with `ArchiveSource` and `ArchivedSection`.
      try db.execute(sql: """
        CREATE TABLE archived_item (
          id TEXT PRIMARY KEY NOT NULL,
          format_version INTEGER NOT NULL,
          reason TEXT NOT NULL CHECK (reason IN ('manual', 'auto')),
          archived_at REAL NOT NULL,
          source_kind TEXT NOT NULL CHECK (source_kind IN ('space', 'littleArc', 'unknown')),
          source_space_id TEXT,
          section_kind TEXT CHECK (section_kind IN ('pinned', 'today', 'favorites')),
          section_profile TEXT,
          title TEXT NOT NULL,
          url TEXT,
          snapshot BLOB NOT NULL,
          CHECK ((source_kind IS 'space') = (source_space_id IS NOT NULL)),
          CHECK ((section_kind IS 'favorites') = (section_profile IS NOT NULL))
        ) STRICT;
        CREATE INDEX archived_item_archived_at_id ON archived_item (archived_at DESC, id);
        CREATE INDEX archived_item_source ON archived_item (source_kind, source_space_id);
        """)
    }
    // Opening an existing v1 or v2 file runs this after `open`'s pre-migration backup.
    migrator.registerMigration("v3-settings") { db in
      // One JSON value per typed settings group (`SettingsGroup.storageKey`), for example per-profile archive
      // thresholds (BH-083, BH-179): profile data that travels with the database and its backups.
      try db.execute(sql: """
        CREATE TABLE setting (
          key TEXT PRIMARY KEY NOT NULL,
          value BLOB NOT NULL,
          updated_at REAL NOT NULL
        ) STRICT
        """)
    }
    // Opening an existing v1, v2 or v3 file runs this after `open`'s pre-migration backup.
    migrator.registerMigration("v4-archive-search") { db in
      // #111: `search_text` holds `ArchiveSearch.searchText(of:)` (folded titles and URLs of the item and every node
      // inside it), so the Archive search is Unicode case- and diacritic-insensitive and finds folder children.
      // Existing rows are filled from their snapshot; a row whose snapshot does not decode keeps its title and URL.
      try db.execute(sql: "ALTER TABLE archived_item ADD COLUMN search_text TEXT NOT NULL DEFAULT ''")
      let decoder = SidebarStorageFormat.makeDecoder()
      let rows = try Row.fetchAll(db, sql: "SELECT id, title, url, snapshot FROM archived_item")
      for row in rows {
        let id: String? = row["id"]
        let body: Data? = row["snapshot"]
        let text: String
        if let body, let snapshot = try? decoder.decode(NodeSnapshot.self, from: body) {
          text = ArchiveSearch.searchText(of: snapshot)
        } else {
          let title: String? = row["title"]
          let url: String? = row["url"]
          text = [title, url].compactMap { $0 }.map(ArchiveSearch.fold).joined(separator: "\n")
        }
        try db.execute(sql: "UPDATE archived_item SET search_text = ? WHERE id = ?", arguments: [text, id])
      }
    }
    return migrator
  }
}

public enum ArktDatabaseError: Error, Hashable, Sendable {
  case integrityCheckFailed
  /// The file was migrated by a newer Arkt build (a downgrade). It is left untouched: not quarantined, not replaced.
  case newerSchema
}
