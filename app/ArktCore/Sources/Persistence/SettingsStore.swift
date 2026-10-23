import ArcImport
import Archive
import Foundation
import GRDB

/// A typed group of settings stored as one JSON value under `storageKey`.
public protocol SettingsGroup: Codable, Sendable {
  static var storageKey: String { get }
  static var defaultValue: Self { get }
}

extension ArchiveSettings: SettingsGroup {
  public static let storageKey = "archive.settings"
  public static var defaultValue: ArchiveSettings { ArchiveSettings() }
}

extension ArchiveState: SettingsGroup {
  public static let storageKey = "archive.state"
  public static var defaultValue: ArchiveState { ArchiveState() }
}

extension ArcImportRecord: SettingsGroup {
  public static let storageKey = "arcImport.record"
  public static var defaultValue: ArcImportRecord { ArcImportRecord() }
}

/// Profile data settings in SQLite (`setting` table): they travel with the database and its backups. App-level
/// preferences stay in user defaults (design 4). Values are JSON with sorted keys; every method is `@concurrent`.
public struct SettingsStore: Sendable {
  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// The stored group, or its default when missing or unreadable.
  @concurrent
  public func load<Group: SettingsGroup>(_ type: Group.Type) async throws -> Group {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let key = Group.storageKey
    let data = try await database.writer.read { db in try Self.fetchValue(db, key: key) }
    return Self.decode(Group.self, from: data)
  }

  @concurrent
  public func save<Group: SettingsGroup>(_ value: Group, at date: Date) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let data = try Self.encode(value)
    let key = Group.storageKey
    let updatedAt = date.timeIntervalSinceReferenceDate
    try await database.writer.write { db in try Self.store(db, key: key, value: data, updatedAt: updatedAt) }
  }

  /// `ArchiveState.autoArchiveStartedAt`, set to `now` and persisted the first time, in one transaction. Feed the
  /// result to `AutoArchiveInput.startedAt`. An unreadable stored state counts as missing.
  @concurrent
  public func resolveAutoArchiveStart(now: Date) async throws -> Date {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let key = ArchiveState.storageKey
    let updatedAt = now.timeIntervalSinceReferenceDate
    return try await database.writer.write { db in
      var state = Self.decode(ArchiveState.self, from: try Self.fetchValue(db, key: key))
      if let started = state.autoArchiveStartedAt { return started }
      let started = state.resolveAutoArchiveStart(now: now)
      try Self.store(db, key: key, value: try Self.encode(state), updatedAt: updatedAt)
      return started
    }
  }

  /// Sets `ArchiveState.autoArchiveStartedAt` to `date`, overwriting any stored start and keeping the other fields,
  /// in one transaction. An Arc sidebar import calls it with the import time (Track E decision 7), so imported Today
  /// tabs each get one full threshold from the import instead of archiving on the first tick.
  @concurrent
  public func resetAutoArchiveStart(to date: Date) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let key = ArchiveState.storageKey
    let updatedAt = date.timeIntervalSinceReferenceDate
    try await database.writer.write { db in
      var state = Self.decode(ArchiveState.self, from: try Self.fetchValue(db, key: key))
      state.autoArchiveStartedAt = date
      try Self.store(db, key: key, value: try Self.encode(state), updatedAt: updatedAt)
    }
  }

  /// The Arc ids earlier Arc imports handled, or an empty record.
  @concurrent
  public func loadArcImportRecord() async throws -> ArcImportRecord { try await load(ArcImportRecord.self) }

  /// Adds `record`'s ids to the stored record (read, union, write in one transaction), so two imports can never
  /// drop each other's ids. An unreadable stored record counts as empty.
  @concurrent
  public func recordArcImport(_ record: ArcImportRecord, at date: Date) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let key = ArcImportRecord.storageKey
    let updatedAt = date.timeIntervalSinceReferenceDate
    try await database.writer.write { db in
      var stored = Self.decode(ArcImportRecord.self, from: try Self.fetchValue(db, key: key))
      stored.formUnion(record)
      try Self.store(db, key: key, value: try Self.encode(stored), updatedAt: updatedAt)
    }
  }

  /// The stored `ArchiveSettings`, or the defaults.
  @concurrent
  public func loadArchiveSettings() async throws -> ArchiveSettings { try await load(ArchiveSettings.self) }

  private static func fetchValue(_ db: Database, key: String) throws -> Data? {
    // Optional read: the table is STRICT, so a non-BLOB value cannot occur; nil means missing.
    try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
  }

  private static func store(_ db: Database, key: String, value: Data, updatedAt: Double) throws {
    try db.execute(
      sql: """
        INSERT INTO setting (key, value, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
      arguments: [key, value, updatedAt])
  }

  private static func encode(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private static func decode<Group: SettingsGroup>(_ type: Group.Type, from data: Data?) -> Group {
    guard let data else { return Group.defaultValue }
    return (try? JSONDecoder().decode(Group.self, from: data)) ?? Group.defaultValue
  }
}

extension SettingsStore: ArchiveStateStoring {}

extension SettingsStore: ArcImportRecordStoring {}
