import EngineAPI

/// Records tab and window events in one log, in delivery order.
@MainActor
public final class EventRecorder {
  public enum Entry: Equatable, Sendable {
    case tab(EngineEvent)
    case window(EngineWindowEvent)
  }

  public private(set) var log: [Entry] = []
  private var token: EngineObservation?
  private var windowToken: EngineObservation?

  public init(_ engine: any EngineClient) {
    token = engine.observe { [weak self] in self?.log.append(.tab($0)) }
    windowToken = engine.observeWindows { [weak self] in self?.log.append(.window($0)) }
  }

  public var events: [EngineEvent] {
    log.compactMap { if case .tab(let event) = $0 { event } else { nil } }
  }

  public var windowEvents: [EngineWindowEvent] {
    log.compactMap { if case .window(let event) = $0 { event } else { nil } }
  }

  public func events(for id: TabID) -> [EngineEvent] { events.filter { $0.tabID == id } }
  public func stop() { token?.cancel(); token = nil; windowToken?.cancel(); windowToken = nil }
}
