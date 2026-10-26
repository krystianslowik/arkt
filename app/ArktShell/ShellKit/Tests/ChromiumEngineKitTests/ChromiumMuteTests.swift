import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// The mute seam over the facade (#364): `setMuted(_:muted:)` goes to the tab handle, the facade's `MutedChanged` and
/// `AudibleChanged` update the snapshot and reach observers once per change, and a tab that is already playing or
/// muted when it is listed starts with that state.
@MainActor
struct ChromiumMuteTests {
  let facade = ScriptedFacade()
  private let page = URL(string: "arkt-test://page.test/Tone")!

  private func makeTab() throws -> (ChromiumEngine, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    return (engine, tab, try #require(engine.handle(of: tab) as? ScriptedTab))
  }

  @Test func setMutedReachesTheHandleAndIsReportedFromItsEvent() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)

    engine.setMuted(tab, muted: true)
    #expect(handle.isMuted)
    facade.flush()

    #expect(engine.snapshot(of: tab)?.isMuted == true)
    #expect(recorder.events(for: tab) == [.mutedChanged(tab, isMuted: true)])
  }

  @Test func repeatedFacadeEventsAreReportedOnce() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)

    handle.setAudible(true)
    handle.recordAudible(true)                 // a repeated report the facade should not send, but might
    handle.setAudible(false)
    facade.flush()

    #expect(recorder.events(for: tab) == [.audibleChanged(tab, isAudible: true),
                                          .audibleChanged(tab, isAudible: false)])
    #expect(engine.snapshot(of: tab)?.isAudible == false)
  }

  @Test func listedTabStartsWithItsHandlesSoundState() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    facade.flush()
    let browser = try #require(facade.browsers.first as? ScriptedBrowser)
    let opened = facade.engineCreateTab(in: browser, url: page, opener: nil, active: false)
    opened.isAudible = true
    opened.isMuted = true
    facade.flush()

    let tab = try #require(engine.tabIDs.first { engine.handle(of: $0) === opened })
    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(snapshot.window == window)
    #expect(snapshot.isAudible && snapshot.isMuted)
  }

  @Test func unknownTabIsANoOp() throws {
    let (engine, _, handle) = try makeTab()
    engine.setMuted(TabID(), muted: true)
    #expect(!handle.isMuted)
  }

  /// The real facade queues a call made before a deferred insert ran; the scripted one does too.
  @Test func muteOfAPendingTabRunsAfterItsInsert() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    facade.flush()
    facade.isNested = true
    let tab = engine.createTab(url: page, in: window)
    engine.setMuted(tab, muted: true)
    facade.isNested = false
    facade.flush()
    facade.flush()
    #expect(engine.snapshot(of: tab)?.isMuted == true)
  }
}
