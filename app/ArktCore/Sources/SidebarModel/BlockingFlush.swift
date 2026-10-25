import Dispatch
import Synchronization

/// Runs a flush for a quit the main thread does not come back from (#298). On SIGTERM (logout, shutdown, an update)
/// Chromium's `chrome::SessionEnding()` calls the quit-start seam on the main thread, then blocks that thread in
/// `EndSession()` and exits the process without running the run loop again, so no main-actor job ever runs after the
/// seam returns. Shared by `SidebarAutosaver` and `ArchiveCoordinator`.
public enum BlockingFlush {
  /// Runs `operation` on the global concurrent executor and blocks the calling thread until it returns or `timeout`
  /// passes. Returns the operation's result, or nil at the timeout (the operation then finishes in the background, if
  /// the process lives that long). `operation` must not need the calling thread's actor: on the main thread a
  /// main-actor hop inside it waits for the timeout.
  ///
  /// Deliberately synchronous: the caller is about to lose its thread for good, so waiting on a semaphore here is the
  /// only way to keep the write. Never call it from an `async` context that could suspend instead.
  public static func run<T: Sendable>(timeout: Duration, _ operation: @escaping @Sendable () async -> T) -> T? {
    let outcome = Outcome<T>()
    let done = DispatchSemaphore(value: 0)
    // Detached on purpose: a task created on the main actor would inherit it and never start while the caller waits.
    Task.detached {
      let result = await operation()
      outcome.value.withLock { $0 = result }
      done.signal()
    }
    let (seconds, attoseconds) = timeout.components
    let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
    guard done.wait(timeout: .now() + .nanoseconds(nanoseconds)) == .success else { return nil }
    return outcome.value.withLock { $0 }
  }

  private final class Outcome<T: Sendable>: Sendable {
    let value = Mutex<T?>(nil)
  }
}
