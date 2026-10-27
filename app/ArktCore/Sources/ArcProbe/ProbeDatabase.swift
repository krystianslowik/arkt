import Foundation
import SQLite3

/// Read-only handle on a scratch copy of a Chromium SQLite file. Exposes only row counts of fixed table names and
/// numeric `meta` values; it never returns row content.
final class ProbeDatabase {
  private var handle: OpaquePointer?

  /// Nil when the file cannot be opened; `code` is the SQLite result code.
  static func open(_ url: URL) -> (ProbeDatabase?, code: Int32) {
    let database = ProbeDatabase()
    let code = sqlite3_open_v2(url.path, &database.handle, SQLITE_OPEN_READONLY, nil)
    return code == SQLITE_OK ? (database, code) : (nil, code)
  }

  private init() {}

  deinit { sqlite3_close(handle) }

  /// `SELECT COUNT(*)` over a fixed table name. Nil when the table is missing or unreadable.
  func count(table: String) -> Int? {
    scalar("SELECT COUNT(*) FROM \(table)")
  }

  /// Numeric values of the given `meta` keys; keys that are missing or not numeric are left out.
  func meta(keys: [String]) -> [String: Int] {
    var result: [String: Int] = [:]
    for key in keys {
      if let value = scalar("SELECT value FROM meta WHERE key = '\(key)'") { result[key] = value }
    }
    return result
  }

  private func scalar(_ sql: String) -> Int? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
    return Int(String(cString: text))
  }
}
