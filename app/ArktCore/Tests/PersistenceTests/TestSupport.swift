@_exported import CoreTestSupport
import Foundation
import GRDB
import Synchronization
import Testing
@testable import Persistence
import SidebarModel

/// A fresh empty directory under the temp dir, removed after `body`. Close every database opened inside `body`
/// before it returns.
nonisolated(nonsending) func withTemporaryDirectory<T>(
  _ body: nonisolated(nonsending) (URL) async throws -> T
) async throws -> T {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("arkt-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: url) }
  return try await body(url)
}

/// Overwrites `bytes` at `offset` in the file at `url`.
func corrupt(_ url: URL, at offset: UInt64, with bytes: [UInt8]) throws {
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.seek(toOffset: offset)
  try handle.write(contentsOf: Data(bytes))
}

/// Creates (or reuses) the database at `url` and records a migration this build does not know.
func markAsMigratedByANewerBuild(_ url: URL) throws {
  let database = try ArktDatabase.open(at: url)
  try database.writer.write { db in
    try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99-from-the-future')")
  }
  try database.close()
}

struct InjectedFailure: Error {}

/// Records saves; can fail the next N calls or hold calls until `unblock()`.
final class RecordingStore: SidebarSaving, Sendable {
  private struct State {
    var saved: [Sidebar] = []
    var started = 0
    var inFlight = 0
    var maxInFlight = 0
    var failuresLeft = 0
    var blocked = false
    var waiting: [CheckedContinuation<Bool, Never>] = []
  }

  private let state = Mutex(State())

  var saved: [Sidebar] { state.withLock { $0.saved } }
  var started: Int { state.withLock { $0.started } }
  /// The most saves that were ever running at the same time.
  var maxInFlight: Int { state.withLock { $0.maxInFlight } }
  func failNext(_ count: Int) { state.withLock { $0.failuresLeft = count } }
  func block() { state.withLock { $0.blocked = true } }

  func unblock() { release(failing: false) }

  /// Releases the held saves and makes each of them throw; later saves are not affected.
  func unblockFailing() { release(failing: true) }

  private func release(failing: Bool) {
    let waiting = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
      state.blocked = false
      defer { state.waiting = [] }
      return state.waiting
    }
    for continuation in waiting { continuation.resume(returning: failing) }
  }

  func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome {
    let fail = state.withLock { state -> Bool in
      state.started += 1
      guard state.failuresLeft > 0 else { return false }
      state.failuresLeft -= 1
      return true
    }
    if fail { throw InjectedFailure() }
    state.withLock { state in
      state.inFlight += 1
      state.maxInFlight = max(state.maxInFlight, state.inFlight)
    }
    let failHeld = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      let wait = state.withLock { state -> Bool in
        guard state.blocked else { return false }
        state.waiting.append(continuation)
        return true
      }
      if !wait { continuation.resume(returning: false) }
    }
    state.withLock { state in
      state.inFlight -= 1
      if !failHeld { state.saved.append(sidebar) }
    }
    if failHeld { throw InjectedFailure() }
    return .written
  }
}

/// Yields until `condition` holds; records an issue instead of hanging.
@MainActor
func waitUntil(
  _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  let deadline = ContinuousClock.now + .seconds(5)  // a failure ceiling, not a wait: passing tests return at once
  while ContinuousClock.now < deadline {
    if condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}
