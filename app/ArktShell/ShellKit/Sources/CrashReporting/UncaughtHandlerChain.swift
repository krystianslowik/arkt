import Foundation
import Synchronization

/// The bookkeeping of the uncaught-exception hook (#129): installs once, and always hands the exception on to the
/// handler that was there first. Kept apart from the AppKit-facing capture so both rules can be tested.
public final class UncaughtHandlerChain: Sendable {
  public typealias Handler = @convention(c) (NSException) -> Void

  private struct State: Sendable {
    var isInstalled = false
    var previous: Handler?
  }

  private let state = Mutex(State())

  public init() {}

  /// Remembers `previous` as the handler to chain to. True the first time; later calls change nothing and return
  /// false, so the chain never captures its own hook as the previous one and loops.
  public func install(previous: Handler?) -> Bool {
    state.withLock { state in
      guard !state.isInstalled else { return false }
      state = State(isInstalled: true, previous: previous)
      return true
    }
  }

  /// Runs `record`, then the previous handler, also when `record` throws.
  public func handle(_ exception: NSException, record: () throws -> Void) {
    let previous = state.withLock { $0.previous }
    defer { previous?(exception) }
    try? record()
  }
}
