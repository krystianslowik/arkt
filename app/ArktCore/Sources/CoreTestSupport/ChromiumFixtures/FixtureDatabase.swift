import Foundation
import SQLite3

/// A throwaway SQLite file writer over the system sqlite3 C API. Fixture use only.
struct FixtureDatabase: ~Copyable {
  enum Value {
    case int(Int64)
    case text(String)
    case blob([UInt8])
  }

  struct Column {
    let name: String
    let type: String
    var defaultSQL: String = ""
  }

  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  private var handle: OpaquePointer?

  init(creating url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
      let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      sqlite3_close(db)
      throw Failure(description: message)
    }
    handle = db
  }

  deinit { sqlite3_close(handle) }

  func exec(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? "exec failed"
      sqlite3_free(error)
      throw Failure(description: "\(message): \(sql)")
    }
  }

  /// Creates `table` from `columns` (the first column is the primary key when `primaryKey` is set).
  func createTable(_ table: String, columns: [Column], primaryKey: String? = nil) throws {
    let defs = columns.map { column -> String in
      var def = "\(column.name) \(column.type)"
      if column.name == primaryKey { def += " PRIMARY KEY" }
      if !column.defaultSQL.isEmpty { def += " DEFAULT \(column.defaultSQL)" }
      return def
    }
    try exec("CREATE TABLE \(table) (\(defs.joined(separator: ", ")))")
  }

  /// Inserts the entries of `row` whose column exists in `columns`; others are dropped (schema drift).
  func insert(into table: String, columns: [Column], row: [String: Value]) throws {
    let names = columns.map(\.name).filter { row[$0] != nil }
    let sql = "INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(names.map { _ in "?" }.joined(separator: ", ")))"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw Failure(description: String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, name) in names.enumerated() {
      let position = Int32(index + 1)
      switch row[name] {
      case .int(let value): sqlite3_bind_int64(statement, position, value)
      case .text(let value): sqlite3_bind_text(statement, position, value, -1, transient)
      case .blob(let value): sqlite3_bind_blob(statement, position, value, Int32(value.count), transient)
      case nil: break
      }
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw Failure(description: String(cString: sqlite3_errmsg(handle)))
    }
  }
}
