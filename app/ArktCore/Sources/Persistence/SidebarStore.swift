import CryptoKit
import Foundation
import GRDB
import SidebarModel

public enum SaveOutcome: Hashable, Sendable {
  case written
  /// The stored bytes were already identical; nothing was written.
  case unchanged
}

public enum SidebarStoreError: Error, Hashable, Sendable {
  /// The stored body is missing or does not match its SHA-256: the row was damaged after it was written.
  case checksumMismatch
}

/// Whole-sidebar snapshots in `sidebar_snapshot` (one row, replaced in one transaction).
public struct SidebarStore: Sendable {
  /// `setting` key holding node ids whose `.replace` archive write committed before their sidebar save (#213).
  static let pendingArchiveRemovalsKey = "archive.pendingRemovals"

  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// Encodes and writes `sidebar`. `@concurrent`: encoding runs on the global executor even when called from the
  /// main actor, and the write runs on GRDB's queue.
  @concurrent
  public func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let body = try SidebarStorageFormat.encode(sidebar)
    let digest = Self.sha256(body)
    let savedAt = date.timeIntervalSinceReferenceDate
    let presentIDs = Set(sidebar.nodes.keys)
    return try await database.writer.write { db -> SaveOutcome in
      let remaining = try Self.fetchPendingArchiveRemovals(db).filter { presentIDs.contains($0) }
      try Self.writePendingArchiveRemovals(db, ids: remaining, updatedAt: savedAt)
      let stored = try String.fetchOne(db, sql: "SELECT sha256 FROM sidebar_snapshot WHERE id = 1")
      if stored == digest { return .unchanged }
      try db.execute(
        sql: """
          INSERT INTO sidebar_snapshot (id, format_version, saved_at, sha256, body) VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET format_version = excluded.format_version, saved_at = excluded.saved_at,
            sha256 = excluded.sha256, body = excluded.body
          """,
        arguments: [SidebarStorageFormat.currentVersion, savedAt, digest, body])
      return .written
    }
  }

  /// The stored sidebar (with any pending archive removals from a crash between the archive write and the sidebar save
  /// replayed idempotently, #213), or nil when none was saved yet. Throws `checksumMismatch` or a decoding error
  /// (`SidebarDocumentError`, `DecodingError`) for a damaged row, and `ArktDatabaseError.newerSchema` when a newer
  /// build wrote a format version this build does not know (a downgrade, not corruption).
  @concurrent
  public func load() async throws -> Sidebar? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let (stored, pending) = try await database.writer.read { db in
      (try Self.fetchStored(db), try Self.fetchPendingArchiveRemovals(db))
    }
    guard let stored else { return nil }
    var sidebar = try Self.decode(stored)
    for id in pending { sidebar.removePane(id) }
    return sidebar
  }

  /// The raw snapshot row. Columns are read as optionals: the table is STRICT and NOT NULL, so storage classes are
  /// guaranteed and nil cannot occur in a healthy file, and a damaged row surfaces as an error instead of a GRDB
  /// conversion trap.
  struct StoredSnapshot: Sendable {
    var formatVersion: Int?
    var digest: String?
    var body: Data?
  }

  static func fetchStored(_ db: Database) throws -> StoredSnapshot? {
    try Row.fetchOne(db, sql: "SELECT format_version, sha256, body FROM sidebar_snapshot WHERE id = 1")
      .map { StoredSnapshot(formatVersion: $0["format_version"], digest: $0["sha256"], body: $0["body"]) }
  }

  static func decode(_ stored: StoredSnapshot) throws -> Sidebar {
    guard let version = stored.formatVersion, let digest = stored.digest, let body = stored.body,
      sha256(body) == digest
    else { throw SidebarStoreError.checksumMismatch }
    guard version <= SidebarStorageFormat.currentVersion else { throw ArktDatabaseError.newerSchema }
    return try SidebarStorageFormat.decode(body)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func fetchPendingArchiveRemovals(_ db: Database) throws -> [NodeID] {
    guard try db.tableExists("setting"),
      let data = try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?",
                                   arguments: [pendingArchiveRemovalsKey]),
      let ids = try? JSONDecoder().decode([NodeID].self, from: data)
    else { return [] }
    return ids
  }

  static func writePendingArchiveRemovals(_ db: Database, ids: [NodeID], updatedAt: Double) throws {
    guard try db.tableExists("setting") else { return }
    if ids.isEmpty {
      try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [pendingArchiveRemovalsKey])
      return
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let value = try encoder.encode(ids)
    try db.execute(
      sql: """
        INSERT INTO setting (key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
      arguments: [pendingArchiveRemovalsKey, value, updatedAt])
  }
}
