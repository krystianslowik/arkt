import Foundation
import SQLite3
import os

/// Why a Chromium database could not be read as a whole. Bad individual rows are never this: they are counted.
public enum ChromiumReadError: Error, Equatable, Sendable {
  /// SQLite could not open the file; the payload is its result code.
  case cannotOpen(Int32)
  /// The expected table does not exist.
  case tableMissing(String)
  /// Columns the reader cannot work without are absent.
  case missingColumns(table: String, columns: [String])
  /// The `meta` table has no numeric `version`, so the value format cannot be chosen safely.
  case metaVersionUnavailable
  /// SQLite failed while preparing or stepping a query; the payload is its result code.
  case queryFailed(Int32)
}

/// A read-only SQLite connection to a scratch copy of a Chromium database. Internal: only the readers use it.
final class ChromiumDatabase {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
    guard code == SQLITE_OK else {
      sqlite3_close(handle)
      throw ChromiumReadError.cannotOpen(code)
    }
  }

  deinit { sqlite3_close(handle) }

  /// Column names of `table`. Throws `tableMissing` when it has none.
  func columns(of table: String) throws -> Set<String> {
    var names: Set<String> = []
    let statement = try prepare("PRAGMA table_info(\(table))")
    defer { sqlite3_finalize(statement) }
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW else { throw ChromiumReadError.queryFailed(code) }
      if let text = sqlite3_column_text(statement, 1) { names.insert(String(cString: text)) }
    }
    guard !names.isEmpty else { throw ChromiumReadError.tableMissing(table) }
    return names
  }

  /// The numeric `version` row of the `meta` table.
  func metaVersion() throws -> Int {
    let statement: OpaquePointer
    do { statement = try prepare("SELECT value FROM meta WHERE key = 'version'") } catch {
      throw ChromiumReadError.metaVersionUnavailable
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0),
      let version = Int(String(cString: text))
    else { throw ChromiumReadError.metaVersionUnavailable }
    return version
  }

  /// A cursor over `columns` of `table`, in storage order. The column names must come from a fixed list in the
  /// caller, never from file content or input.
  func query(table: String, columns: [String]) throws -> ChromiumCursor {
    let statement = try prepare("SELECT \(columns.joined(separator: ", ")) FROM \(table)")
    var index: [String: Int32] = [:]
    for (position, name) in columns.enumerated() { index[name] = Int32(position) }
    return ChromiumCursor(database: self, statement: statement, index: index)
  }

  fileprivate func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard code == SQLITE_OK, let statement else { throw ChromiumReadError.queryFailed(code) }
    return statement
  }
}

/// Steps through the rows of one query. Accessors take a column name and return nil when the column was not selected
/// or the value is NULL (or has the wrong type), so callers handle schema drift in one place.
struct ChromiumCursor: ~Copyable {
  /// Keeps the connection open while the statement is alive.
  private let database: ChromiumDatabase
  private let statement: OpaquePointer
  private let index: [String: Int32]

  fileprivate init(database: ChromiumDatabase, statement: OpaquePointer, index: [String: Int32]) {
    self.database = database
    self.statement = statement
    self.index = index
  }

  deinit { sqlite3_finalize(statement) }

  /// Moves to the next row. False when there are no more.
  mutating func next() throws -> Bool {
    let code = sqlite3_step(statement)
    if code == SQLITE_ROW { return true }
    if code == SQLITE_DONE { return false }
    throw ChromiumReadError.queryFailed(code)
  }

  func int(_ column: String) -> Int64? {
    guard let position = index[column], sqlite3_column_type(statement, position) == SQLITE_INTEGER else { return nil }
    return sqlite3_column_int64(statement, position)
  }

  /// Nil for NULL, for another storage class, and for text that is not valid UTF-8.
  func text(_ column: String) -> String? {
    guard let position = index[column], sqlite3_column_type(statement, position) == SQLITE_TEXT,
      let pointer = sqlite3_column_text(statement, position)
    else { return nil }
    let length = Int(sqlite3_column_bytes(statement, position))
    return String(validating: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
  }

  /// Nil for NULL. An empty blob is an empty array.
  func blob(_ column: String) -> [UInt8]? {
    guard let position = index[column] else { return nil }
    switch sqlite3_column_type(statement, position) {
    case SQLITE_BLOB, SQLITE_TEXT:
      let length = Int(sqlite3_column_bytes(statement, position))
      guard length > 0, let base = sqlite3_column_blob(statement, position) else { return [] }
      return Array(UnsafeRawBufferPointer(start: base, count: length))
    default: return nil
    }
  }
}

/// WebKit (Chromium) timestamps: microseconds since 1601-01-01 UTC.
enum WebKitTimestamp {
  static let unixEpochOffsetSeconds = 11_644_473_600.0

  static func date(_ micros: Int64) -> Date {
    Date(timeIntervalSince1970: Double(micros) / 1_000_000 - unixEpochOffsetSeconds)
  }

  /// Nil for 0, which Chromium uses for "never set".
  static func optionalDate(_ micros: Int64?) -> Date? {
    guard let micros, micros != 0 else { return nil }
    return date(micros)
  }
}

/// Counts-only logging for the import readers. Messages are built from numbers and fixed words, never from row data,
/// so they are safe to mark public.
enum ImportLog {
  typealias Sink = @Sendable (String) -> Void

  private static let logger = Logger(subsystem: "dev.arkt.core", category: "arc-import")

  static let live: Sink = { message in logger.info("\(message, privacy: .public)") }
}
