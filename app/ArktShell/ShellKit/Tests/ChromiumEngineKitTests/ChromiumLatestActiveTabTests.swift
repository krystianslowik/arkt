import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

@MainActor
struct ChromiumLatestActiveTabTests {
  let facade = ScriptedFacade()

  private func makeEngine() -> (ChromiumEngine, EngineWindowID) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    return (engine, engine.createWindow(host: StubWindowHost()))
  }

  @Test func latestSelectionDoesNotAdvanceCachedStateOrEmitEvents() {
    let (engine, window) = makeEngine()
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    facade.flush()
    let recorder = EventRecorder(engine)
    let client: any EngineClient = engine

    engine.activateTab(b)

    #expect(client.latestActiveTab(in: window) == b)
    #expect(engine.activeTab(in: window) == a)
    #expect(engine.snapshot(of: a)?.isActive == true)
    #expect(engine.snapshot(of: b)?.isActive == false)
    #expect(recorder.events.isEmpty)
    facade.flush()
    #expect(engine.activeTab(in: window) == b)
    #expect(recorder.events == [.activeTabChanged(b)])
  }

  @Test func latestSelectionStaysAuthoritativeThroughoutAnOlderActivationBatch() {
    let (engine, window) = makeEngine()
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    let c = engine.createTab(url: nil, in: window)
    facade.flush()
    var reported: [TabID] = []
    var cached: [TabID?] = []
    var latest: [TabID?] = []
    let observation = engine.observe(window: window) { event in
      guard case .activeTabChanged(let tab) = event else { return }
      reported.append(tab)
      cached.append(engine.activeTab(in: window))
      latest.append(engine.latestActiveTab(in: window))
    }
    defer { observation.cancel() }

    for tab in [b, c, b] {
      engine.activateTab(tab)
      #expect(engine.latestActiveTab(in: window) == tab)
      #expect(engine.activeTab(in: window) == a)
    }
    facade.flush()

    #expect(reported == [b, c, b])
    #expect(cached == [b, c, b])
    #expect(latest == [b, b, b])
  }

  @Test func rapidReturnToCachedTabIsForwardedEvenWhenIntermediateTabCloses() {
    let (engine, window) = makeEngine()
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    facade.flush()
    let recorder = EventRecorder(engine)

    engine.activateTab(b)
    #expect(engine.latestActiveTab(in: window) == b)
    #expect(engine.activeTab(in: window) == a)
    engine.activateTab(a)
    #expect(engine.latestActiveTab(in: window) == a, "cached A must not prevent forwarding the return from live B")
    engine.closeTab(b)
    #expect(engine.latestActiveTab(in: window) == a)
    facade.flush()

    #expect(engine.activeTab(in: window) == a)
    #expect(recorder.events == [.tabClosed(b, reason: .client)], "both old activation events are suppressed")
  }

  @Test func unmappedLiveHandleReturnsNilWithoutAdoptingOrAnnouncingIt() throws {
    let (engine, window) = makeEngine()
    let a = engine.createTab(url: nil, in: window)
    facade.flush()
    let browser = try #require(engine.windows[window]?.browser as? ScriptedBrowser)
    let recorder = EventRecorder(engine)
    let live = browser.insertTab(opener: nil, origin: .engine, active: true)

    #expect(engine.latestActiveTab(in: window) == nil)
    #expect(engine.tabIDs == [a])
    #expect(engine.activeTab(in: window) == a)
    #expect(recorder.events.isEmpty)
    facade.flush()
    let adopted = try #require(engine.tabByHandle[ObjectIdentifier(live)])
    #expect(engine.latestActiveTab(in: window) == adopted)
  }

  @Test func latestSelectionIsNilAfterLastTabAndWindowCloseBeforeBatchDelivery() {
    let (engine, window) = makeEngine()
    let a = engine.createTab(url: nil, in: window)
    facade.flush()
    engine.closeTab(a)
    #expect(engine.latestActiveTab(in: window) == nil)
    facade.flush()
    let b = engine.createTab(url: nil, in: window)
    facade.flush()
    #expect(engine.latestActiveTab(in: window) == b)

    engine.closeWindow(window)

    #expect(engine.latestActiveTab(in: window) == nil)
    #expect(engine.activeTab(in: window) == b, "cached state still waits for the window-close batch")
    facade.flush()
    #expect(engine.latestActiveTab(in: window) == nil)
    #expect(engine.latestActiveTab(in: EngineWindowID()) == nil)
  }
}
