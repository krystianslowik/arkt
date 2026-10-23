import Foundation
import Synchronization

/// Resumes a `flush` continuation exactly once: with the attempt's result or, when `timeout` elapses first, with
/// `false` while the attempt finishes in the background. Shared by `SidebarAutosaver` and `ArchiveCoordinator` (#93).
public final class FlushRace: Sendable {
  private let continuation = Mutex<CheckedContinuation<Bool, Never>?>(nil)

  public init() {}

  public func arm(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation.withLock { $0 = continuation }
  }

  public func finish(_ succeeded: Bool) {
    continuation.withLock { $0.take() }?.resume(returning: succeeded)
  }

  /// Races `attempt` against `sleep(timeout)` and returns whichever finishes first (`false` on timeout).
  public static func run(
    timeout: Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    attempt: Task<Bool, Never>
  ) async -> Bool {
    let race = FlushRace()
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      race.arm(continuation)
      let deadline = Task {
        do { try await sleep(timeout) } catch { return }
        race.finish(false)
      }
      Task {
        let succeeded = await attempt.value
        deadline.cancel()
        race.finish(succeeded)
      }
    }
  }
}
