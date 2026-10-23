import Foundation
import GRDB
import Synchronization
import Testing
@testable import Persistence
import SidebarModel

enum TestSidebars {
  /// A small sidebar distinguishable by `title` (space title and a tab title).
  static func make(_ title: String) -> Sidebar {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: title)
    _ = try? sidebar.addTab(url: URL(string: "https://example.com/\(title)")!, title: title, in: .today(space))
    return sidebar
  }
}

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

/// A manual stand-in for `Task.sleep`: each call parks until the test resumes it, or throws `CancellationError` when
/// its task is cancelled (also when cancelled before it parked).
final class ManualSleeper: Sendable {
  private struct Parked {
    let id: Int
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var nextID = 0
    var parked: [Parked] = []
    var cancelledEarly: Set<Int> = []
  }

  private let state = Mutex(State())

  var sleep: AutosaveSleep { { [self] duration in try await self.park(duration) } }
  var parkedCount: Int { state.withLock { $0.parked.count } }
  var parkedDurations: [Duration] { state.withLock { $0.parked.map(\.duration) } }

  /// Resumes the oldest parked sleeper.
  func resumeNext() {
    let parked = state.withLock { $0.parked.isEmpty ? nil : $0.parked.removeFirst() }
    parked?.continuation.resume()
  }

  /// Resumes the parked sleeper with `duration` (the oldest one if several).
  func resume(_ duration: Duration) {
    let parked = state.withLock { state -> Parked? in
      guard let index = state.parked.firstIndex(where: { $0.duration == duration }) else { return nil }
      return state.parked.remove(at: index)
    }
    parked?.continuation.resume()
  }

  private func park(_ duration: Duration) async throws {
    let id = state.withLock { state -> Int in
      state.nextID += 1
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = state.withLock { state -> Bool in
          if state.cancelledEarly.remove(id) != nil { return true }
          state.parked.append(Parked(id: id, duration: duration, continuation: continuation))
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      let parked = state.withLock { state -> Parked? in
        if let index = state.parked.firstIndex(where: { $0.id == id }) { return state.parked.remove(at: index) }
        state.cancelledEarly.insert(id)
        return nil
      }
      parked?.continuation.resume(throwing: CancellationError())
    }
  }
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
    var waiting: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  var saved: [Sidebar] { state.withLock { $0.saved } }
  var started: Int { state.withLock { $0.started } }
  /// The most saves that were ever running at the same time.
  var maxInFlight: Int { state.withLock { $0.maxInFlight } }
  func failNext(_ count: Int) { state.withLock { $0.failuresLeft = count } }
  func block() { state.withLock { $0.blocked = true } }

  func unblock() {
    let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.blocked = false
      defer { state.waiting = [] }
      return state.waiting
    }
    for continuation in waiting { continuation.resume() }
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
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = state.withLock { state -> Bool in
        guard state.blocked else { return false }
        state.waiting.append(continuation)
        return true
      }
      if !wait { continuation.resume() }
    }
    state.withLock { state in
      state.inFlight -= 1
      state.saved.append(sidebar)
    }
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
