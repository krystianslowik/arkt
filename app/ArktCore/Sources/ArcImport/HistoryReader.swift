import Foundation
import SQLite3

/// Reads `urls` and `visits` from the History copy of an Arc profile snapshot (#508), read-only.
///
/// Columns are probed by name with `PRAGMA table_info`, so extra columns are ignored and missing optional columns fall
/// back to defaults. Only the tables and the columns `urls.id`, `urls.url`, `visits.url` and `visits.visit_time` are
/// required. Rows that cannot be used are skipped and counted, never thrown.
///
/// The work is blocking disk I/O: call it off the main actor. Entries are handed to the caller in batches, so memory
/// is bounded by `Limits`, not by the size of the history.
public enum HistoryReader {
  public enum ReadError: Error, Equatable {
    /// The file could not be opened; `code` is the SQLite result code.
    case cannotOpen(code: Int32)
    case missingTable(String)
    case missingColumn(table: String, column: String)
    /// A query failed, for example because the file is not a database.
    case queryFailed(code: Int32)
  }

  /// The memory budget for one batch.
  public struct Limits: Sendable, Equatable {
    /// Most entries (URLs) in one batch.
    public var batchSize: Int
    /// A batch is also closed once it holds at least this many visits. One URL's visits are never split, so a single
    /// URL with more visits than this still arrives as one batch.
    public var maxVisitsPerBatch: Int

    public init(batchSize: Int = 500, maxVisitsPerBatch: Int = 25_000) {
      self.batchSize = max(1, batchSize)
      self.maxVisitsPerBatch = max(1, maxVisitsPerBatch)
    }
  }

  /// What a read produced and what it had to skip.
  public struct Summary: Sendable, Equatable {
    public var urlCount = 0
    public var visitCount = 0
    /// `urls` rows without a usable URL.
    public var skippedURLRows = 0
    /// `visits` rows with no usable time, no matching usable `urls` row, or a non-integer value.
    public var skippedVisitRows = 0
  }

  public struct Result: Sendable, Equatable {
    public var entries: [HistoryEntry]
    public var summary: Summary
  }

  // MARK: - Reading

  /// Reads `History` from a snapshot profile and returns every entry. Prefer `read(from:limits:handle:)` for large
  /// histories.
  public static func readAll(profile: ArcProfileSnapshot.Profile) throws -> Result {
    try readAll(from: profile.directory.appendingPathComponent("History"))
  }

  public static func readAll(from url: URL, limits: Limits = Limits()) throws -> Result {
    var entries: [HistoryEntry] = []
    let summary = try read(from: url, limits: limits) { entries += $0 }
    return Result(entries: entries, summary: summary)
  }

  /// Streams the history to `handle`, one batch at a time. A throw from `handle` stops the read and is rethrown.
  @discardableResult
  public static func read(
    from url: URL, limits: Limits = Limits(), handle: ([HistoryEntry]) throws -> Void
  ) throws -> Summary {
    let database = try Database(url)
    let urlColumns = try database.columns(of: "urls")
    let visitColumns = try database.columns(of: "visits")
    for column in ["id", "url"] where !urlColumns.contains(column) {
      throw ReadError.missingColumn(table: "urls", column: column)
    }
    for column in ["url", "visit_time"] where !visitColumns.contains(column) {
      throw ReadError.missingColumn(table: "visits", column: column)
    }

    let optionalURLColumns = ["title", "visit_count", "typed_count", "last_visit_time"].filter(urlColumns.contains)
    let urlStatement = try database.prepare(
      "SELECT id, url" + optionalURLColumns.map { ", \($0)" }.joined() + " FROM urls ORDER BY id")
    let hasTransition = visitColumns.contains("transition")
    let visitStatement = try database.prepare(
      "SELECT url, visit_time" + (hasTransition ? ", transition" : "") + " FROM visits ORDER BY url, visit_time")
    var visits = VisitCursor(statement: visitStatement, hasTransition: hasTransition)

    func index(_ name: String) -> Int32? { optionalURLColumns.firstIndex(of: name).map { Int32($0 + 2) } }
    let titleIndex = index("title")
    let visitCountIndex = index("visit_count")
    let typedCountIndex = index("typed_count")
    let lastVisitIndex = index("last_visit_time")

    var summary = Summary()
    var batch: [HistoryEntry] = []
    var batchVisits = 0
    func flush() throws {
      guard !batch.isEmpty else { return }
      let ready = batch
      batch.removeAll(keepingCapacity: true)
      batchVisits = 0
      try handle(ready)
    }

    while try urlStatement.nextRow() {
      let id = urlStatement.int(0) ?? 0
      let taken = try visits.take(forURL: id)
      summary.skippedVisitRows += taken.skipped
      guard let address = urlStatement.text(1), !address.isEmpty else {
        summary.skippedURLRows += 1
        summary.skippedVisitRows += taken.visits.count
        continue
      }
      let lastFromColumn = lastVisitIndex.flatMap { urlStatement.int($0) }.flatMap(WebKitTime.date(fromMicroseconds:))
      let entry = HistoryEntry(
        url: address,
        title: titleIndex.flatMap { urlStatement.text($0) } ?? "",
        visitCount: visitCountIndex.flatMap { urlStatement.int($0) }.map { Int(clamping: $0) } ?? taken.visits.count,
        typedCount: typedCountIndex.flatMap { urlStatement.int($0) }.map { Int(clamping: $0) } ?? 0,
        lastVisit: lastFromColumn ?? taken.visits.last?.time,
        visits: taken.visits)
      summary.urlCount += 1
      summary.visitCount += taken.visits.count
      batch.append(entry)
      batchVisits += taken.visits.count
      if batch.count >= limits.batchSize || batchVisits >= limits.maxVisitsPerBatch { try flush() }
    }
    // Visits after the last `urls` row have no row to belong to.
    summary.skippedVisitRows += try visits.drain()
    try flush()
    return summary
  }

  // MARK: - Visits

  /// Walks `visits` ordered by `(url, visit_time)` in step with `urls` ordered by `id`.
  private struct VisitCursor {
    let statement: Statement
    let hasTransition: Bool
    private var pending: (url: Int64, visit: HistoryVisit?)?
    private var started = false

    init(statement: Statement, hasTransition: Bool) {
      self.statement = statement
      self.hasTransition = hasTransition
    }

    private mutating func advance() throws {
      guard try statement.nextRow() else {
        pending = nil
        return
      }
      let url = statement.int(0) ?? Int64.min
      var visit: HistoryVisit?
      if let micros = statement.int(1), let time = WebKitTime.date(fromMicroseconds: micros) {
        let raw = hasTransition ? statement.int(2) : 0
        visit = HistoryVisit(
          time: time, transition: HistoryTransition(webKitValue: Int32(truncatingIfNeeded: raw ?? 0)))
      }
      pending = (url, visit)
    }

    /// The usable visits of `id`, and how many visit rows were dropped on the way (bad rows and orphans).
    mutating func take(forURL id: Int64) throws -> (visits: [HistoryVisit], skipped: Int) {
      if !started {
        started = true
        try advance()
      }
      var visits: [HistoryVisit] = []
      var skipped = 0
      while let current = pending, current.url <= id {
        if current.url == id, let visit = current.visit {
          visits.append(visit)
        } else {
          skipped += 1
        }
        try advance()
      }
      return (visits, skipped)
    }

    /// Counts and discards every remaining visit row.
    mutating func drain() throws -> Int {
      if !started {
        started = true
        try advance()
      }
      var count = 0
      while pending != nil {
        count += 1
        try advance()
      }
      return count
    }
  }

  // MARK: - SQLite

  private final class Database {
    private var handle: OpaquePointer?

    init(_ url: URL) throws {
      let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
      guard code == SQLITE_OK else {
        sqlite3_close(handle)
        throw ReadError.cannotOpen(code: code)
      }
    }

    deinit { sqlite3_close(handle) }

    func prepare(_ sql: String) throws -> Statement {
      var statement: OpaquePointer?
      let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
      guard code == SQLITE_OK, let statement else { throw ReadError.queryFailed(code: code) }
      return Statement(statement, owner: self)
    }

    /// Lowercased column names of `table`; throws `missingTable` when it has none.
    func columns(of table: String) throws -> Set<String> {
      let statement = try prepare("PRAGMA table_info(\(table))")
      var names: Set<String> = []
      while try statement.nextRow() {
        if let name = statement.text(1) { names.insert(name.lowercased()) }
      }
      guard !names.isEmpty else { throw ReadError.missingTable(table) }
      return names
    }
  }

  private final class Statement {
    private let handle: OpaquePointer
    private let owner: Database

    init(_ handle: OpaquePointer, owner: Database) {
      self.handle = handle
      self.owner = owner
    }

    deinit { sqlite3_finalize(handle) }

    func nextRow() throws -> Bool {
      switch sqlite3_step(handle) {
      case SQLITE_ROW: return true
      case SQLITE_DONE: return false
      case let code: throw ReadError.queryFailed(code: code)
      }
    }

    /// The column as an integer; nil for NULL and for any other storage class.
    func int(_ column: Int32) -> Int64? {
      sqlite3_column_type(handle, column) == SQLITE_INTEGER ? sqlite3_column_int64(handle, column) : nil
    }

    /// The column as text; nil for NULL and for any other storage class.
    func text(_ column: Int32) -> String? {
      guard sqlite3_column_type(handle, column) == SQLITE_TEXT, let bytes = sqlite3_column_text(handle, column) else {
        return nil
      }
      return String(cString: bytes)
    }
  }
}
