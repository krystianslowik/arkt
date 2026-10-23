import Testing
@testable import EngineAPI

@MainActor
struct EngineEventHubTests {
  @Test func deliversInRegistrationOrder() {
    let hub = EngineEventHub()
    var log: [String] = []
    let a = hub.add { _ in log.append("a") }
    let b = hub.add { _ in log.append("b") }
    hub.emit(.tabCreated(TabID()))
    #expect(log == ["a", "b"])
    a.cancel(); b.cancel()
  }

  @Test func dropsEventsAfterTabClosed() {
    let hub = EngineEventHub()
    var events: [EngineEvent] = []
    let token = hub.add { events.append($0) }
    let id = TabID()
    hub.emit(.tabClosed(id))
    hub.emit(.titleChanged(id, "late"))
    hub.emit(.tabClosed(id))
    #expect(events == [.tabClosed(id)])
    token.cancel()
  }

  /// A handler that emits (here: closes the tab) while an event is being delivered must not let
  /// later handlers see the nested event before the current one.
  @Test func nestedEmitIsQueuedBehindTheCurrentEvent() {
    let hub = EngineEventHub()
    let id = TabID()
    var first: [EngineEvent] = []
    var second: [EngineEvent] = []
    let a = hub.add { event in
      first.append(event)
      if case .titleChanged = event {
        hub.emit(.tabClosed(id))
        hub.emit(.titleChanged(id, "after close"))
      }
    }
    let b = hub.add { second.append($0) }
    hub.emit(.titleChanged(id, "Page"))
    hub.emit(.loadingChanged(id, isLoading: false))
    let expected: [EngineEvent] = [.titleChanged(id, "Page"), .tabClosed(id)]
    #expect(first == expected)
    #expect(second == expected)
    a.cancel(); b.cancel()
  }

  @Test func handlerCancelledDuringDispatchGetsNothingFurther() {
    let hub = EngineEventHub()
    var bEvents: [EngineEvent] = []
    var bToken: EngineObservation?
    let a = hub.add { _ in bToken?.cancel() }
    bToken = hub.add { bEvents.append($0) }
    hub.emit(.tabCreated(TabID()))
    hub.emit(.tabCreated(TabID()))
    #expect(bEvents.isEmpty)
    a.cancel()
  }

  @Test func droppingTheTokenStopsDelivery() {
    let hub = EngineEventHub()
    var count = 0
    var token: EngineObservation? = hub.add { _ in count += 1 }
    hub.emit(.tabCreated(TabID()))
    #expect(token != nil)
    token = nil
    hub.emit(.tabCreated(TabID()))
    #expect(count == 1)
  }
}
