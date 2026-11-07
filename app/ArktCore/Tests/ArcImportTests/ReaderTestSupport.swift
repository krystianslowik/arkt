import ArcImport
import CoreTestSupport
import Foundation
import SQLite3
import Synchronization

/// Shared helpers for the cookie and login reader tests. Everything runs against `FakeChromiumProfile` fixtures and
/// `FakeSafeStorageKeyProvider`; no real browser data or Keychain item is touched.
enum ReaderTestSupport {
  struct Failure: Error { let message: String }

  /// 2024-01-01 00:00:00 UTC, the fixtures' time base.
  static let fixtureBase = Date(timeIntervalSince1970: 1_704_067_200)

  /// A moment after the fixtures were written and before any fixture cookie expires.
  static let fixtureNow = fixtureBase.addingTimeInterval(60)

  /// Writes a fixture profile into a fresh directory, runs `body`, then removes the directory.
  static func withProfile<R>(
    _ options: FakeChromiumProfile.Options = .init(), _ body: (FixtureManifest) throws -> R
  ) throws -> R {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(try FakeChromiumProfile.make(at: directory, options: options))
  }

  static func provider(password: String = FakeChromiumProfile.safeStoragePassword) -> FakeSafeStorageKeyProvider {
    FakeSafeStorageKeyProvider(password: password)
  }

  /// Runs SQL against a fixture database, to tamper with rows or drop columns.
  static func execute(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw Failure(message: "open failed")
    }
    defer { sqlite3_close(db) }
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? "exec failed"
      sqlite3_free(error)
      throw Failure(message: "\(message): \(sql)")
    }
  }

  /// Doubles the rows of `table` `times` times, so a three-row fixture grows past a batch boundary.
  static func multiplyRows(_ url: URL, table: String, times: Int) throws {
    for _ in 0..<times { try execute(url, "INSERT INTO \(table) SELECT * FROM \(table)") }
  }

  static func text(_ secret: SecretBytes) -> String { secret.utf8String() }
}

/// Collects log lines so a test can inspect everything a reader logged.
final class LogCollector: Sendable {
  private let lines = Mutex<[String]>([])

  var sink: @Sendable (String) -> Void {
    { [self] line in lines.withLock { $0.append(line) } }
  }

  var all: [String] { lines.withLock { $0 } }
}

/// Wraps a provider and counts how often the password is requested.
final class CountingProvider: SafeStorageKeyProvider {
  private let base: FakeSafeStorageKeyProvider
  private let calls = Mutex(0)

  init(_ base: FakeSafeStorageKeyProvider) { self.base = base }

  var callCount: Int { calls.withLock { $0 } }

  func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
    calls.withLock { $0 += 1 }
    return try base.withPassword(body)
  }
}
