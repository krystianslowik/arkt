import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// The facade's tab state (#577, the engine side of #576), mapped by ChromiumEngine from scripted batches: crash and
/// recovery, zoom, HTML fullscreen and the crashed-session prompt.
@MainActor
struct ChromiumTabStateTests {
  let facade = ScriptedFacade()

  private func makeEngine() -> (ChromiumEngine, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let id = engine.createTab(url: URL(string: "arkt-test://page.test/State")!,
                              in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    let tab = engine.handle(of: id) as! ScriptedTab
    tab.finishLoad()
    facade.flush()
    return (engine, id, tab)
  }

  // MARK: Crash and recovery

  @Test func aCrashEndsTheLoadThenIsReportedOnceAndAReloadRecoversIt() throws {
    let (engine, id, tab) = makeEngine()
    engine.reload(id)
    facade.flush()
    let recorder = EventRecorder(engine)

    tab.crash(status: .killed)
    tab.crash(status: .crashed)
    facade.flush()

    #expect(recorder.events == [.loadingChanged(id, isLoading: false), .tabCrashed(id, .killed)])
    let crashed = try #require(engine.snapshot(of: id))
    #expect(crashed.crash == .killed && !crashed.isLoading && engine.tabIDs.contains(id))

    engine.reload(id)
    facade.flush()
    tab.finishLoad()
    facade.flush()

    let events = recorder.events.dropFirst(2)
    #expect(Array(events.prefix(2)) == [.loadingChanged(id, isLoading: true), .tabRecovered(id)])
    #expect(events.filter { $0 == .tabRecovered(id) }.count == 1)
    #expect(engine.snapshot(of: id)?.crash == nil)
  }

  @Test(arguments: [(ArktTerminationStatus.crashed, TabTerminationStatus.crashed), (.killed, .killed),
                    (.outOfMemory, .outOfMemory), (.launchFailed, .launchFailed), (.none, .crashed)])
  func everyTerminationStatusMaps(_ facadeStatus: ArktTerminationStatus, _ status: TabTerminationStatus) throws {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    // Recorded directly: a TabCrashed whose status is None (not one the facade sends) still counts as a crash.
    tab.terminationStatus = facadeStatus == .none ? .crashed : facadeStatus
    tab.record(.tabCrashed) { $0.terminationStatus = facadeStatus }
    facade.flush()

    #expect(recorder.events == [.tabCrashed(id, status)])
    #expect(engine.snapshot(of: id)?.crash == status)
  }

  @Test func aSecondCrashReportBeforeRecoveryIsDropped() {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    tab.crash(status: .crashed)
    tab.record(.tabCrashed) { $0.terminationStatus = .outOfMemory }
    tab.record(.tabRecovered)
    tab.record(.tabRecovered)
    facade.flush()

    #expect(recorder.events == [.tabCrashed(id, .crashed), .tabRecovered(id)])
  }

  // MARK: Zoom

  @Test func zoomCallsReportEachChangeOnceWhenTheCallReturns() throws {
    let (engine, id, _) = makeEngine()
    let recorder = EventRecorder(engine)

    engine.zoomIn(id)
    #expect(recorder.events == [.zoomChanged(id, TabZoom(percent: 110, isDefault: false), userInitiated: true)])
    engine.zoomOut(id)
    engine.zoomOut(id)
    engine.resetZoom(id)
    engine.resetZoom(id)
    facade.flush()

    #expect(recorder.events == [
      .zoomChanged(id, TabZoom(percent: 110, isDefault: false), userInitiated: true),
      .zoomChanged(id, .default, userInitiated: true),
      .zoomChanged(id, TabZoom(percent: 90, isDefault: false), userInitiated: true),
      .zoomChanged(id, .default, userInitiated: true),
    ])
    #expect(engine.snapshot(of: id)?.zoom == .default)
  }

  @Test func zoomStopsAtTheEndsOfTheSteps() {
    let (engine, id, _) = makeEngine()
    for _ in TabZoom.steps { engine.zoomIn(id) }
    facade.flush()
    #expect(engine.snapshot(of: id)?.zoom == TabZoom(percent: 500, isDefault: false))
    let recorder = EventRecorder(engine)
    engine.zoomIn(id)
    facade.flush()
    #expect(recorder.events.isEmpty)
  }

  @Test func anEngineZoomIsReportedAsNotUserInitiatedWithTheLiveValue() {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    // Two host zoom map changes in one batch: the first report already reads the live zoom, the second repeats it.
    tab.setZoom(125, userInitiated: false)
    tab.setZoom(150, userInitiated: false)
    facade.flush()

    #expect(recorder.events == [.zoomChanged(id, TabZoom(percent: 150, isDefault: false), userInitiated: false)])
    #expect(engine.snapshot(of: id)?.zoom == TabZoom(percent: 150, isDefault: false))
  }

  @Test func aCrashedTabDoesNotZoom() {
    let (engine, id, tab) = makeEngine()
    tab.crash()
    facade.flush()
    let recorder = EventRecorder(engine)
    engine.zoomIn(id)
    facade.flush()
    #expect(recorder.events.isEmpty)
  }

  // MARK: HTML fullscreen

  @Test func fullscreenIsReportedWithTheSnapshotAlreadyWritten() throws {
    let (engine, id, tab) = makeEngine()
    var seen: [(event: Bool, snapshot: Bool?)] = []
    let token = engine.observe { event in
      if case .tabFullscreenChanged(let tab, let fullscreen) = event {
        seen.append((fullscreen, engine.snapshot(of: tab)?.isTabFullscreen))
      }
    }
    defer { token.cancel() }

    tab.setTabFullscreen(true)
    tab.record(.tabFullscreenChanged) { $0.isTabFullscreen = true }  // a repeat changes nothing
    facade.flush()
    engine.navigate(id, to: URL(string: "arkt-test://page.test/Next")!)
    facade.flush()

    #expect(seen.map(\.event) == [true, false])
    #expect(seen.map(\.snapshot) == [true, false])
  }

  @Test func aCrashLeavesFullscreenFirst() {
    let (engine, id, tab) = makeEngine()
    tab.setTabFullscreen(true)
    facade.flush()
    let recorder = EventRecorder(engine)
    tab.crash()
    facade.flush()
    #expect(recorder.events == [.tabFullscreenChanged(id, isFullscreen: false), .tabCrashed(id, .crashed)])
  }

  // MARK: Seeding

  @Test func anAdoptedTabStartsFromItsLiveState() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    facade.flush()
    let browser = try #require(engine.windows[window]?.browser as? ScriptedBrowser)
    let tab = facade.engineCreateTab(in: browser, url: URL(string: "arkt-test://page.test/Adopted"), opener: nil,
                                     active: true)
    tab.terminationStatus = .outOfMemory
    tab.zoomPercent = 175
    tab.isTabFullscreen = true
    facade.flush()

    let id = try #require(engine.tabIDs.first { engine.handle(of: $0) === tab })
    let snapshot = try #require(engine.snapshot(of: id))
    #expect(snapshot.crash == .outOfMemory)
    #expect(snapshot.zoom == TabZoom(percent: 175, isDefault: false))
    #expect(snapshot.isTabFullscreen)
  }

  // MARK: Crashed session

  @Test func theCrashedSessionIsReadFromTheFacadeAndDismissedOnce() throws {
    facade.lastSessionCrashed = true
    let engine = ChromiumEngine(facade: facade)
    let recovery = try #require(engine.sessionRecovery)
    #expect(recovery.lastSessionCrashed)

    recovery.dismissLastSession()
    recovery.dismissLastSession()

    #expect(!recovery.lastSessionCrashed)
    #expect(facade.sessionDismissals == 1)
    #expect(engine.sessionRecovery === recovery)
  }

  @Test func aCleanLastSessionAsksNothing() throws {
    let engine = ChromiumEngine(facade: facade)
    let recovery = try #require(engine.sessionRecovery)
    #expect(!recovery.lastSessionCrashed)
    recovery.dismissLastSession()
    #expect(facade.sessionDismissals == 0)
  }
}
