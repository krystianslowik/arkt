import Archive
import Foundation
import GRDB
import SidebarModel

/// The `archived_item` table. Snapshots are stored as canonical D1 `NodeSnapshot` JSON; title, URL, reason, source
/// and section are columns. Every method is `@concurrent`: encoding and decoding run on the global executor even when
/// called from the main actor, and SQL runs on GRDB's queue.
///
/// Retention (Track D open question 9, #100 maintainer decision 2026-10-23): archive entries older than 30 days
/// (`retentionInterval`) are pruned automatically (like Arc) via `pruneExpired(now:)`, in addition to user restore
/// (`remove`) and Clear Archive (`removeAll`, BH-087).
public struct ArchiveStore: Sendable {
  /// Archive retention window (30 days, matching Arc; #100 maintainer decision).
  public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

  /// `archived_item.format_version`: the version of the stored `NodeSnapshot` JSON. It is versioned apart from the
  /// sidebar document (`SidebarStorageFormat.currentVersion`) because a snapshot holds no Space data: sidebar format
  /// 2 added `Space.icon` and left `NodeSnapshot` unchanged, so archive rows stay at 1 and builds that read only
  /// version 1 keep reading them. Bump this only when `NodeSnapshot`'s stored shape changes.
  public static let snapshotFormatVersion = 1

  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// Writes `items` in one transaction and returns how many rows were inserted or (with `.replace`) overwritten.
  /// Within one call, later duplicates of an id follow the same policy as stored ones. No default policy: every
  /// caller states it (the app's archive events `.replace`, an Arc re-import `.keepExisting`).
  @concurrent
  public func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let encoder = SidebarStorageFormat.makeEncoder()
    let rows = try items.map { try InsertRow($0, encoder: encoder) }
    let conflictClause = switch policy {
    case .keepExisting: "ON CONFLICT (id) DO NOTHING"
    case .replace:
      """
      ON CONFLICT (id) DO UPDATE SET format_version = excluded.format_version, reason = excluded.reason,
        archived_at = excluded.archived_at, source_kind = excluded.source_kind,
        source_space_id = excluded.source_space_id, section_kind = excluded.section_kind,
        section_profile = excluded.section_profile, title = excluded.title, url = excluded.url,
        snapshot = excluded.snapshot, search_text = excluded.search_text
      """
    }
    let sql = """
      INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, source_space_id,
        section_kind, section_profile, title, url, snapshot, search_text)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      \(conflictClause)
      """
    let addedIDs = policy == .replace ? items.map(\.id) : []
    return try await database.writer.write { db in
      var written = 0
      for row in rows {
        try db.execute(
          sql: sql,
          arguments: [
            row.id, Self.snapshotFormatVersion, row.reason, row.archivedAt, row.sourceKind,
            row.sourceSpaceID, row.sectionKind, row.sectionProfile, row.title, row.url, row.snapshot,
            row.searchText,
          ])
        written += db.changesCount
      }
      if !addedIDs.isEmpty {
        var pending = try SidebarStore.fetchPendingArchiveRemovals(db)
        for id in addedIDs where !pending.contains(id) { pending.append(id) }
        try SidebarStore.writePendingArchiveRemovals(db, ids: pending, updatedAt: rows.last?.archivedAt ?? 0)
      }
      return written
    }
  }

  /// Matching items, newest first (ties by id), plus how many matching rows could not be read back (an undecodable
  /// snapshot, an unknown format version, a snapshot whose root id is not the row id, inconsistent columns). Such
  /// rows are skipped and never fill the page: with a `limit`, rows are fetched in batches along the
  /// (archived_at DESC, id) order until `limit` readable items are collected or the matches run out, so
  /// `unreadable` counts only the rows passed on the way. Each batch is its own read; a write landing between
  /// batches can be missed or seen, but no row is returned twice.
  @concurrent
  public func items(matching filter: ArchiveFilter = ArchiveFilter(), limit: Int? = nil) async throws -> ArchivePage {
    dispatchPrecondition(condition: .notOnQueue(.main))
    var page = ArchivePage(items: [], unreadable: 0)
    if let limit, limit <= 0 { return page }
    let decoder = SidebarStorageFormat.makeDecoder()
    var after: Cursor?
    while true {
      let wanted = limit.map { $0 - page.items.count }
      let start = after
      let rows = try await database.writer.read { db in
        try Self.fetchRows(db, filter: filter, after: start, limit: wanted)
      }
      for row in rows {
        if let item = row.item(decoder) { page.items.append(item) } else { page.unreadable += 1 }
      }
      guard let wanted, rows.count == wanted, page.items.count < (limit ?? 0),
        let last = rows.last, let archivedAt = last.archivedAt, let id = last.id
      else { return page }
      after = Cursor(archivedAt: archivedAt, id: id)
    }
  }

  /// Every row, readable or not: for backups and diagnostics, not a display count (see `ArchivePage.unreadable`).
  @concurrent
  public func count() async throws -> Int {
    dispatchPrecondition(condition: .notOnQueue(.main))
    return try await database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM archived_item") ?? 0 }
  }

  /// How many rows match `filter`, readable or not (the Archive window's "3 of 42 items").
  @concurrent
  public func count(matching filter: ArchiveFilter) async throws -> Int {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let (clauses, arguments) = Self.whereClauses(filter)
    let sql = "SELECT COUNT(*) FROM archived_item"
      + (clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND "))
    return try await database.writer.read { try Int.fetchOne($0, sql: sql, arguments: arguments) ?? 0 }
  }

  /// Deletes entries, for example after a restore, in one transaction. Unknown ids are ignored.
  @concurrent
  public func remove(_ ids: [NodeID]) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard !ids.isEmpty else { return }
    let removedSet = Set(ids)
    let strings = ids.map(\.uuidString)
    try await database.writer.write { db in
      // Chunked to stay far below SQLite's bound-parameter limit.
      for start in stride(from: 0, to: strings.count, by: 500) {
        let chunk = Array(strings[start..<min(start + 500, strings.count)])
        let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
        try db.execute(
          sql: "DELETE FROM archived_item WHERE id IN (\(placeholders))", arguments: StatementArguments(chunk))
      }
      let pending = try SidebarStore.fetchPendingArchiveRemovals(db).filter { !removedSet.contains($0) }
      try SidebarStore.writePendingArchiveRemovals(db, ids: pending, updatedAt: 0)
    }
  }

  /// Clear Archive (BH-087). The confirmation dialog is the caller's.
  @concurrent
  public func removeAll() async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try await database.writer.write { db in
      try db.execute(sql: "DELETE FROM archived_item")
      try SidebarStore.writePendingArchiveRemovals(db, ids: [], updatedAt: 0)
    }
  }

  /// Deletes archive entries whose `archived_at` is strictly older than `now - retentionInterval` (30 days, matching
  /// Arc; #100 maintainer decision) and returns the number of pruned rows.
  @concurrent
  @discardableResult
  public func pruneExpired(now: Date) async throws -> Int {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let cutoff = now.timeIntervalSinceReferenceDate - Self.retentionInterval
    return try await database.writer.write { db in
      try db.execute(sql: "DELETE FROM archived_item WHERE archived_at < ?", arguments: [cutoff])
      return db.changesCount
    }
  }

  /// The last row of a batch; the next batch starts strictly after it in (archived_at DESC, id) order.
  struct Cursor: Sendable {
    var archivedAt: Double
    var id: String
  }

  private static func fetchRows(
    _ db: Database, filter: ArchiveFilter, after cursor: Cursor?, limit: Int?
  ) throws -> [FetchedRow] {
    var (clauses, arguments) = whereClauses(filter)
    if let cursor {
      clauses.append("(archived_at < ? OR (archived_at = ? AND id > ?))")
      arguments += [cursor.archivedAt, cursor.archivedAt, cursor.id]
    }
    var sql = """
      SELECT id, format_version, reason, archived_at, source_kind, source_space_id, section_kind, section_profile,
        snapshot FROM archived_item
      """
    if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
    sql += " ORDER BY archived_at DESC, id"
    if let limit { sql += " LIMIT \(limit)" }
    return try Row.fetchAll(db, sql: sql, arguments: arguments).map(FetchedRow.init)
  }

  /// The filter as SQL. Text matches the folded `search_text` column with `instr`: a plain substring test, so the
  /// query needs no escaping and has no wildcards.
  private static func whereClauses(_ filter: ArchiveFilter) -> ([String], StatementArguments) {
    var clauses: [String] = []
    var arguments: StatementArguments = []
    switch filter.source {
    case .space(let id)?:
      clauses.append("source_kind = 'space' AND source_space_id = ?")
      arguments += [id.uuidString]
    case .littleArc?:
      clauses.append("source_kind = 'littleArc'")
    case nil:
      break
    }
    if let reason = filter.reason {
      clauses.append("reason = ?")
      arguments += [reason.rawValue]
    }
    if let query = ArchiveSearch.query(filter.text) {
      clauses.append("instr(search_text, ?) > 0")
      arguments += [query]
    }
    return (clauses, arguments)
  }
}

private struct InsertRow: Sendable {
  var id: String
  var reason: String
  var archivedAt: Double
  var sourceKind: String
  var sourceSpaceID: String?
  var sectionKind: String?
  var sectionProfile: String?
  var title: String
  var url: String?
  var snapshot: Data
  var searchText: String

  init(_ item: ArchivedItem, encoder: JSONEncoder) throws {
    id = item.id.uuidString
    reason = item.reason.rawValue
    archivedAt = item.archivedAt.timeIntervalSinceReferenceDate
    switch item.source {
    case .space(let space): (sourceKind, sourceSpaceID) = ("space", space.uuidString)
    case .littleArc: (sourceKind, sourceSpaceID) = ("littleArc", nil)
    case .unknown: (sourceKind, sourceSpaceID) = ("unknown", nil)
    }
    switch item.section {
    case .pinned: (sectionKind, sectionProfile) = ("pinned", nil)
    case .today: (sectionKind, sectionProfile) = ("today", nil)
    case .favorites(let profile): (sectionKind, sectionProfile) = ("favorites", profile)
    case nil: (sectionKind, sectionProfile) = (nil, nil)
    }
    title = item.title
    url = item.url?.absoluteString
    snapshot = try encoder.encode(item.snapshot)
    searchText = ArchiveSearch.searchText(of: item.snapshot)
  }
}

/// Columns are read as optionals: the table is STRICT, so storage classes are guaranteed and a damaged row is
/// skipped instead of hitting a GRDB conversion trap.
private struct FetchedRow: Sendable {
  var id: String?
  var formatVersion: Int?
  var reason: String?
  var archivedAt: Double?
  var sourceKind: String?
  var sourceSpaceID: String?
  var sectionKind: String?
  var sectionProfile: String?
  var snapshot: Data?

  init(_ row: Row) {
    id = row["id"]
    formatVersion = row["format_version"]
    reason = row["reason"]
    archivedAt = row["archived_at"]
    sourceKind = row["source_kind"]
    sourceSpaceID = row["source_space_id"]
    sectionKind = row["section_kind"]
    sectionProfile = row["section_profile"]
    snapshot = row["snapshot"]
  }

  func item(_ decoder: JSONDecoder) -> ArchivedItem? {
    guard let id = id.flatMap(UUID.init(uuidString:)),
      let version = formatVersion, version <= ArchiveStore.snapshotFormatVersion,
      let reason = reason.flatMap(ArchiveReason.init(rawValue:)),
      let archivedAt, let body = snapshot,
      let snapshot = try? decoder.decode(NodeSnapshot.self, from: body), snapshot.id == id
    else { return nil }
    let source: ArchiveSource
    switch sourceKind {
    case "space":
      guard let space = sourceSpaceID.flatMap(UUID.init(uuidString:)) else { return nil }
      source = .space(space)
    case "littleArc": source = .littleArc
    case "unknown": source = .unknown
    default: return nil
    }
    let section: ArchivedSection?
    switch sectionKind {
    case nil: section = nil
    case "pinned": section = .pinned
    case "today": section = .today
    case "favorites":
      guard let sectionProfile else { return nil }
      section = .favorites(profile: sectionProfile)
    default: return nil
    }
    return ArchivedItem(
      reason: reason, archivedAt: Date(timeIntervalSinceReferenceDate: archivedAt), source: source,
      section: section, snapshot: snapshot)
  }
}

extension ArchiveStore: ArchiveStoring {}
