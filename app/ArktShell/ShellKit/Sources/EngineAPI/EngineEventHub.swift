import Foundation

/// Fan-out used by engine implementations. Guarantees contract rule 4: nothing after `.tabClosed`.
///
/// Delivery is non-reentrant: an event emitted while another is being delivered (a handler that
/// closes or navigates a tab) is queued and delivered, FIFO, after the current event has reached
/// every handler. All handlers therefore see the same order. A handler cancelled mid-dispatch
/// receives nothing further, including the rest of the current event's fan-out.
/// Per-frame batching (design section 4) will be added here, not in the UI.
@MainActor
public final class EngineEventHub {
  private var handlers: [(key: UUID, handler: @MainActor (EngineEvent) -> Void)] = []
  private var live: Set<UUID> = []
  private var closed: Set<TabID> = []
  private var pending: [EngineEvent] = []
  private var isDispatching = false

  public init() {}

  public func add(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    let key = UUID()
    handlers.append((key, handler))
    live.insert(key)
    return EngineObservation { [weak self] in
      self?.live.remove(key)
      self?.handlers.removeAll { $0.key == key }
    }
  }

  public func emit(_ event: EngineEvent) {
    pending.append(event)
    guard !isDispatching else { return }
    isDispatching = true
    defer { isDispatching = false }
    var next = 0
    while next < pending.count {
      let event = pending[next]
      next += 1
      guard !closed.contains(event.tabID) else { continue }
      if case .tabClosed(let id) = event { closed.insert(id) }
      for entry in handlers where live.contains(entry.key) { entry.handler(event) }
    }
    pending.removeAll()
  }
}
