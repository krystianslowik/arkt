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
    return try await database.writer.write { db -> SaveOutcome in
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

  /// The stored sidebar, or nil when none was saved yet. Throws `checksumMismatch` or a decoding error
  /// (`SidebarDocumentError`, `DecodingError`) for a damaged row, and `ArktDatabaseError.newerSchema` when a newer
  /// build wrote a format version this build does not know (a downgrade, not corruption).
  @concurrent
  public func load() async throws -> Sidebar? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let stored = try await database.writer.read({ try Self.fetchStored($0) }) else { return nil }
    return try Self.decode(stored)
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
}
