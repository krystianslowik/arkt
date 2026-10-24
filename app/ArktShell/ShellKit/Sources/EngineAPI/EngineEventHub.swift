import Foundation

/// Fan-out used by engine implementations. Guarantees contract rule 4 (nothing after `.tabClosed`) and its window
/// form (nothing after `.windowClosed`).
///
/// Delivery is non-reentrant: an event emitted while another is being delivered (a handler that
/// closes or navigates a tab) is queued and delivered, FIFO, after the current event has reached
/// every handler. All handlers therefore see the same order. Tab and window events share the queue, so a window's
/// `.windowClosed` reaches window observers after its tabs' `.tabClosed` reached tab observers. A handler cancelled
/// mid-dispatch receives nothing further, including the rest of the current event's fan-out.
///
/// Per-window routing (`add(window:_:)`): the engine tells the hub which window a tab is in with `assign(_:to:)`
/// before it emits the tab's `.tabCreated`, and again when the tab moves. Each event is routed by the tab's window
/// at the time it is emitted, so a handler still gets the `.tabClosed` of a tab whose snapshot is already gone.
/// Per-frame batching (design section 4) will be added here, not in the UI.
@MainActor
public final class EngineEventHub {
  private struct Handler {
    let key: UUID
    /// nil: every tab event; otherwise only the events of tabs in this window.
    let window: EngineWindowID?
    let deliver: @MainActor (EngineEvent) -> Void
  }

  private enum Pending {
    case tab(EngineEvent, window: EngineWindowID?)
    case window(EngineWindowEvent)
  }

  private var handlers: [Handler] = []
  private var windowHandlers: [(key: UUID, deliver: @MainActor (EngineWindowEvent) -> Void)] = []
  private var live: Set<UUID> = []
  private var closed: Set<TabID> = []
  private var closedWindows: Set<EngineWindowID> = []
  private var windowOfTab: [TabID: EngineWindowID] = [:]
  private var pending: [Pending] = []
  private var isDispatching = false

  public init() {}

  /// Every tab event.
  public func add(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    register(Handler(key: UUID(), window: nil, deliver: handler))
  }

  /// The events of tabs in `window` (by `assign(_:to:)` at emit time).
  public func add(window: EngineWindowID,
                  _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    register(Handler(key: UUID(), window: window, deliver: handler))
  }

  /// Every window event.
  public func addWindowObserver(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    let key = UUID()
    windowHandlers.append((key, handler))
    live.insert(key)
    return EngineObservation { [weak self] in
      self?.live.remove(key)
      self?.windowHandlers.removeAll { $0.key == key }
    }
  }

  /// Records the window `tab` is in (nil: none). Call before emitting the tab's `.tabCreated`, and on a move.
  public func assign(_ tab: TabID, to window: EngineWindowID?) {
    windowOfTab[tab] = window
  }

  public func emit(_ event: EngineEvent) {
    let window = windowOfTab[event.tabID]
    if case .tabClosed(let id, _) = event { windowOfTab[id] = nil }
    enqueue(.tab(event, window: window))
  }

  public func emit(_ event: EngineWindowEvent) {
    enqueue(.window(event))
  }

  // MARK: - Delivery

  private func register(_ handler: Handler) -> EngineObservation {
    handlers.append(handler)
    live.insert(handler.key)
    let key = handler.key
    return EngineObservation { [weak self] in
      self?.live.remove(key)
      self?.handlers.removeAll { $0.key == key }
    }
  }

  private func enqueue(_ item: Pending) {
    pending.append(item)
    guard !isDispatching else { return }
    isDispatching = true
    defer { isDispatching = false }
    var next = 0
    while next < pending.count {
      let item = pending[next]
      next += 1
      switch item {
      case .tab(let event, let window): deliver(event, window: window)
      case .window(let event): deliver(event)
      }
    }
    pending.removeAll()
  }

  private func deliver(_ event: EngineEvent, window: EngineWindowID?) {
    guard !closed.contains(event.tabID) else { return }
    if case .tabClosed(let id, _) = event { closed.insert(id) }
    for handler in handlers where live.contains(handler.key) {
      if let filter = handler.window, filter != window { continue }
      handler.deliver(event)
    }
  }

  private func deliver(_ event: EngineWindowEvent) {
    guard !closedWindows.contains(event.windowID) else { return }
    if case .windowClosed(let id) = event { closedWindows.insert(id) }
    for entry in windowHandlers where live.contains(entry.key) { entry.deliver(event) }
  }
}
