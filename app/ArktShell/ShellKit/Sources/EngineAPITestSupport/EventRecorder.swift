import EngineAPI

@MainActor
public final class EventRecorder {
  public private(set) var events: [EngineEvent] = []
  private var token: EngineObservation?

  public init(_ engine: any EngineClient) {
    token = engine.observe { [weak self] in self?.events.append($0) }
  }

  public func events(for id: TabID) -> [EngineEvent] { events.filter { $0.tabID == id } }
  public func stop() { token?.cancel(); token = nil }
}
