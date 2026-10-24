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
    hub.emit(.tabClosed(id, reason: .client))
    hub.emit(.titleChanged(id, "late"))
    hub.emit(.tabClosed(id, reason: .client))
    #expect(events == [.tabClosed(id, reason: .client)])
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
        hub.emit(.tabClosed(id, reason: .client))
        hub.emit(.titleChanged(id, "after close"))
      }
    }
    let b = hub.add { second.append($0) }
    hub.emit(.titleChanged(id, "Page"))
    hub.emit(.loadingChanged(id, isLoading: false))
    let expected: [EngineEvent] = [.titleChanged(id, "Page"), .tabClosed(id, reason: .client)]
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

  // MARK: - Window stream and per-window routing

  @Test func windowEventsShareTheQueueWithTabEvents() {
    let hub = EngineEventHub()
    let window = EngineWindowID()
    let tab = TabID()
    hub.assign(tab, to: window)
    var log: [String] = []
    let tabs = hub.add { event in
      log.append("tab \(event)")
      if case .tabClosed = event { hub.emit(EngineWindowEvent.windowClosed(window)) }
    }
    let windows = hub.addWindowObserver { log.append("window \($0)") }
    let late = hub.add { log.append("late \($0)") }
    hub.emit(.tabClosed(tab, reason: .windowClosing))
    #expect(log == [
      "tab \(EngineEvent.tabClosed(tab, reason: .windowClosing))",
      "late \(EngineEvent.tabClosed(tab, reason: .windowClosing))",
      "window \(EngineWindowEvent.windowClosed(window))",
    ])
    tabs.cancel(); windows.cancel(); late.cancel()
  }

  @Test func nothingAfterWindowClosed() {
    let hub = EngineEventHub()
    let window = EngineWindowID()
    var events: [EngineWindowEvent] = []
    let token = hub.addWindowObserver { events.append($0) }
    hub.emit(EngineWindowEvent.windowOpened(window))
    hub.emit(EngineWindowEvent.windowClosed(window))
    hub.emit(EngineWindowEvent.extensionActionsChanged(window))
    hub.emit(EngineWindowEvent.windowClosed(window))
    #expect(events == [.windowOpened(window), .windowClosed(window)])
    token.cancel()
  }

  @Test func windowObserversCanBeCancelledAndDropped() {
    let hub = EngineEventHub()
    var count = 0
    var token: EngineObservation? = hub.addWindowObserver { _ in count += 1 }
    hub.emit(EngineWindowEvent.windowOpened(EngineWindowID()))
    #expect(token != nil)
    token = nil
    hub.emit(EngineWindowEvent.windowOpened(EngineWindowID()))
    #expect(count == 1)
  }

  /// `observe(window:)` gets only its window's tabs, routed by the window at emit time: a tab's `.tabClosed`
  /// still arrives after its assignment is gone, and a tab moved to another window follows it.
  @Test func perWindowObserversSeeOnlyTheirTabs() {
    let hub = EngineEventHub()
    let (first, second) = (EngineWindowID(), EngineWindowID())
    let (a, b, loose) = (TabID(), TabID(), TabID())
    var inFirst: [EngineEvent] = []
    var inSecond: [EngineEvent] = []
    var all: [EngineEvent] = []
    let t1 = hub.add(window: first) { inFirst.append($0) }
    let t2 = hub.add(window: second) { inSecond.append($0) }
    let t3 = hub.add { all.append($0) }
    hub.assign(a, to: first)
    hub.emit(.tabCreated(a))
    hub.assign(b, to: second)
    hub.emit(.tabCreated(b))
    hub.emit(.tabCreated(loose))
    hub.emit(.activeTabChanged(a))
    hub.assign(a, to: second)
    hub.emit(.titleChanged(a, "moved"))
    hub.emit(.tabClosed(b, reason: .page))
    hub.emit(.tabClosed(a, reason: .client))
    #expect(inFirst == [.tabCreated(a), .activeTabChanged(a)])
    #expect(inSecond == [.tabCreated(b), .titleChanged(a, "moved"), .tabClosed(b, reason: .page),
                         .tabClosed(a, reason: .client)])
    #expect(all.count == 7, "unfiltered observers see every event, window-less tabs included")
    t1.cancel(); t2.cancel(); t3.cancel()
  }

  /// A routed event emitted from inside a handler is still queued behind the current one.
  @Test func perWindowDeliveryIsNonReentrant() {
    let hub = EngineEventHub()
    let window = EngineWindowID()
    let id = TabID()
    hub.assign(id, to: window)
    var routed: [EngineEvent] = []
    var all: [EngineEvent] = []
    let a = hub.add { event in
      all.append(event)
      if case .titleChanged = event { hub.emit(.tabClosed(id, reason: .client)) }
    }
    let b = hub.add(window: window) { routed.append($0) }
    hub.emit(.titleChanged(id, "Page"))
    #expect(routed == all)
    #expect(routed == [.titleChanged(id, "Page"), .tabClosed(id, reason: .client)])
    a.cancel(); b.cancel()
  }
}
