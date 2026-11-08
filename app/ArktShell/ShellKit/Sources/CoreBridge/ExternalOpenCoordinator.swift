import Foundation

/// Retains external opens until the caller's routing read succeeds, then reports each delivery in order.
@MainActor
public final class ExternalOpenCoordinator<Outcome> {
  public enum State {
    case waiting, loading, ready, failed
  }

  public private(set) var state: State = .waiting
  public var pendingCount: Int { pending.count - nextIndex }

  private var pending: [URL] = []
  private var nextIndex = 0
  private var isDraining = false
  private var deliveryPaused = false
  private var loading: Task<Bool, Never>?
  private var deliver: (@MainActor (URL) -> Outcome)?
  private var onResult: (@MainActor (URL, Outcome) -> Void)?

  public init() {}

  public func receive(_ urls: [URL]) {
    pending.append(contentsOf: urls)
    drain()
  }

  /// Freeze delivery before quit capture. A read may finish while paused, but its inputs stay queued.
  public func pauseDelivery() { deliveryPaused = true }

  /// The caller restores session writes before resuming queued delivery after a cancelled quit.
  public func resumeDelivery() {
    deliveryPaused = false
    drain()
  }

  /// Concurrent callers join the active read. Once ready, the original callbacks remain installed.
  public func start(read: @escaping @MainActor () async throws -> Void,
                    deliver: @escaping @MainActor (URL) -> Outcome,
                    onResult: @escaping @MainActor (URL, Outcome) -> Void) async -> Bool {
    if state == .ready { return true }
    if let loading { return await loading.value }

    state = .loading
    let task = Task { @MainActor in
      do {
        try await read()
        self.deliver = deliver
        self.onResult = onResult
        self.state = .ready
        self.loading = nil
        self.drain()
        return true
      } catch {
        self.state = .failed
        self.loading = nil
        return false
      }
    }
    loading = task
    return await task.value
  }

  private func drain() {
    guard state == .ready, !deliveryPaused, !isDraining, let deliver, let onResult else { return }
    isDraining = true
    defer {
      if nextIndex == pending.count {
        pending.removeAll(keepingCapacity: true)
        nextIndex = 0
      }
      isDraining = false
    }
    while !deliveryPaused, nextIndex < pending.count {
      let url = pending[nextIndex]
      let outcome = deliver(url)
      onResult(url, outcome)
      nextIndex += 1
    }
  }
}
