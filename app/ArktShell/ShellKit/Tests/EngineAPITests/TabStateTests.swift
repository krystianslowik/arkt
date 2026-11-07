import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Tab state seams (#576, part of #122): a crashed page and its recovery, page zoom, HTML element fullscreen and the
/// crashed-session prompt. InMemoryEngine emits each on demand; the defaults keep every other engine unchanged.
@MainActor
struct TabStateTests {
  private let page = URL(string: "arkt-test://page/State")!

  private func tabInWindow(_ engine: InMemoryEngine) -> TabID {
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    engine.finishLoad(tab, title: "State")
    return tab
  }

  // MARK: Crash and recovery

  @Test func newTabIsNotCrashedAtDefaultZoomAndNotFullscreen() throws {
    let engine = InMemoryEngine()
    let snapshot = try #require(engine.snapshot(of: tabInWindow(engine)))
    #expect(snapshot.crash == nil)
    #expect(snapshot.zoom == .default)
    #expect(snapshot.zoom.percent == 100 && snapshot.zoom.isDefault)
    #expect(!snapshot.isTabFullscreen)
  }

  @Test(arguments: [TabTerminationStatus.crashed, .killed, .outOfMemory, .launchFailed])
  func crashIsReportedOnceWithItsStatus(_ status: TabTerminationStatus) throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    let recorder = EventRecorder(engine)

    engine.crash(tab, status: status)
    engine.crash(tab, status: .crashed)

    #expect(recorder.events(for: tab) == [.tabCrashed(tab, status)])
    #expect(engine.snapshot(of: tab)?.crash == status)
    #expect(engine.tabIDs.contains(tab), "a crashed tab stays listed")
  }

  @Test func crashDuringALoadEndsTheLoadFirst() throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    let recorder = EventRecorder(engine)

    engine.crash(tab, status: .crashed)

    #expect(recorder.events(for: tab) == [.loadingChanged(tab, isLoading: false), .tabCrashed(tab, .crashed)])
    #expect(engine.snapshot(of: tab)?.isLoading == false)
  }

  @Test func reloadRecoversACrashedTab() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.crash(tab, status: .killed)
    let recorder = EventRecorder(engine)

    engine.reload(tab)

    #expect(recorder.events(for: tab) == [.tabRecovered(tab), .loadingChanged(tab, isLoading: true)])
    #expect(engine.snapshot(of: tab)?.crash == nil)
  }

  @Test func navigationRecoversACrashedTab() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.crash(tab, status: .outOfMemory)
    let recorder = EventRecorder(engine)
    let next = URL(string: "arkt-test://page/Next")!

    engine.navigate(tab, to: next)

    #expect(recorder.events(for: tab).first == .tabRecovered(tab))
    #expect(recorder.events(for: tab).contains(.urlChanged(tab, next)))
    #expect(engine.snapshot(of: tab)?.crash == nil)
  }

  @Test func reloadOfAHealthyTabReportsNoRecovery() {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    let recorder = EventRecorder(engine)
    engine.reload(tab)
    #expect(!recorder.events(for: tab).contains(.tabRecovered(tab)))
  }

  @Test func crashEndsHTMLFullscreen() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.setTabFullscreen(tab, true)
    let recorder = EventRecorder(engine)

    engine.crash(tab, status: .crashed)

    #expect(recorder.events(for: tab) == [.tabFullscreenChanged(tab, isFullscreen: false), .tabCrashed(tab, .crashed)])
    #expect(engine.snapshot(of: tab)?.isTabFullscreen == false)
  }

  // MARK: Zoom

  @Test func zoomStepsThroughChromiumsLevelsAndResets() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    let recorder = EventRecorder(engine)

    engine.zoomIn(tab)
    engine.zoomIn(tab)
    engine.zoomOut(tab)
    engine.resetZoom(tab)
    engine.resetZoom(tab)

    #expect(recorder.events(for: tab) == [
      .zoomChanged(tab, TabZoom(percent: 110, isDefault: false), userInitiated: true),
      .zoomChanged(tab, TabZoom(percent: 125, isDefault: false), userInitiated: true),
      .zoomChanged(tab, TabZoom(percent: 110, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
    ])
    #expect(engine.snapshot(of: tab)?.zoom == .default)
  }

  @Test func zoomStopsAtEitherEnd() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    for _ in 0..<TabZoom.steps.count { engine.zoomOut(tab) }
    #expect(engine.snapshot(of: tab)?.zoom.percent == TabZoom.steps.first)
    let recorder = EventRecorder(engine)
    engine.zoomOut(tab)
    #expect(recorder.log.isEmpty)

    for _ in 0..<TabZoom.steps.count { engine.zoomIn(tab) }
    #expect(engine.snapshot(of: tab)?.zoom.percent == TabZoom.steps.last)
    let atTop = recorder.log.count
    engine.zoomIn(tab)
    #expect(recorder.log.count == atTop)
  }

  @Test func engineZoomIsReportedAsNotUserInitiated() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    let recorder = EventRecorder(engine)

    engine.setZoom(tab, percent: 150, userInitiated: false)
    engine.setZoom(tab, percent: 150, userInitiated: false)

    let zoom = TabZoom(percent: 150, isDefault: false)
    #expect(recorder.events(for: tab) == [.zoomChanged(tab, zoom, userInitiated: false)])
    #expect(engine.snapshot(of: tab)?.zoom.percent == 150)
  }

  @Test func zoomEventsReachTheTabsWindowOnly() {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let other = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: main)
    var inMain: [EngineEvent] = []
    var inOther: [EngineEvent] = []
    let first = engine.observe(window: main) { inMain.append($0) }
    let second = engine.observe(window: other) { inOther.append($0) }
    defer { first.cancel(); second.cancel() }

    engine.zoomIn(tab)
    engine.setTabFullscreen(tab, true)
    engine.crash(tab, status: .crashed)

    #expect(inMain.contains(.zoomChanged(tab, TabZoom(percent: 110, isDefault: false), userInitiated: true)))
    #expect(inMain.contains(.tabFullscreenChanged(tab, isFullscreen: true)))
    #expect(inMain.contains(.tabCrashed(tab, .crashed)))
    #expect(inOther.isEmpty)
  }

  // MARK: HTML fullscreen

  @Test func tabFullscreenIsReportedOncePerChange() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    let recorder = EventRecorder(engine)

    engine.setTabFullscreen(tab, true)
    engine.setTabFullscreen(tab, true)
    #expect(engine.snapshot(of: tab)?.isTabFullscreen == true)
    engine.setTabFullscreen(tab, false)

    #expect(recorder.events(for: tab) == [
      .tabFullscreenChanged(tab, isFullscreen: true), .tabFullscreenChanged(tab, isFullscreen: false),
    ])
  }

  /// The shell reads `snapshot(of:)?.isTabFullscreen` when `.tabFullscreenChanged` arrives (#581), so the snapshot
  /// inside the handler already carries the event's value.
  @Test func theSnapshotInsideTheHandlerCarriesTheFullscreenValue() {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    var seen: [(event: Bool, snapshot: Bool?)] = []
    let token = engine.observe { event in
      if case .tabFullscreenChanged(let id, let fullscreen) = event {
        seen.append((fullscreen, engine.snapshot(of: id)?.isTabFullscreen))
      }
    }
    defer { token.cancel() }

    engine.setTabFullscreen(tab, true)
    engine.setTabFullscreen(tab, false)

    #expect(seen.map(\.event) == [true, false])
    #expect(seen.map(\.snapshot) == [true, false])
  }

  @Test func navigationEndsHTMLFullscreen() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.setTabFullscreen(tab, true)
    let recorder = EventRecorder(engine)

    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)

    #expect(recorder.events(for: tab).first == .tabFullscreenChanged(tab, isFullscreen: false))
    #expect(engine.snapshot(of: tab)?.isTabFullscreen == false)
  }

  // MARK: Unknown tabs, duplicates, event ids

  @Test func unknownOrClosedTabIsANoOp() {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.closeTab(tab)
    let recorder = EventRecorder(engine)
    for id in [tab, TabID()] {
      engine.zoomIn(id)
      engine.zoomOut(id)
      engine.resetZoom(id)
      engine.crash(id, status: .crashed)
      engine.setTabFullscreen(id, true)
      engine.setZoom(id, percent: 200, userInitiated: false)
    }
    #expect(recorder.log.isEmpty)
  }

  @Test func duplicateStartsHealthyAtDefaultZoom() throws {
    let engine = InMemoryEngine()
    let tab = tabInWindow(engine)
    engine.zoomIn(tab)
    engine.setTabFullscreen(tab, true)
    engine.crash(tab, status: .crashed)
    let copy = try #require(engine.duplicateTab(tab))
    let snapshot = try #require(engine.snapshot(of: copy))
    #expect(snapshot.crash == nil && snapshot.zoom == .default && !snapshot.isTabFullscreen)
  }

  @Test func tabStateEventsCarryTheirTabID() {
    let tab = TabID()
    #expect(EngineEvent.tabCrashed(tab, .crashed).tabID == tab)
    #expect(EngineEvent.tabRecovered(tab).tabID == tab)
    #expect(EngineEvent.zoomChanged(tab, .default, userInitiated: false).tabID == tab)
    #expect(EngineEvent.tabFullscreenChanged(tab, isFullscreen: true).tabID == tab)
  }

  // MARK: Crashed session

  @Test func noCrashedSessionByDefault() throws {
    let engine = InMemoryEngine()
    let recovery = try #require(engine.sessionRecovery)
    #expect(!recovery.lastSessionCrashed)
  }

  @Test func dismissAcknowledgesTheCrashedSessionOnce() throws {
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let recovery = try #require(engine.sessionRecovery)
    #expect(recovery.lastSessionCrashed)

    recovery.dismissLastSession()
    recovery.dismissLastSession()

    #expect(!recovery.lastSessionCrashed)
    #expect(engine.crashedSession.dismissals == 1)
  }

  // MARK: Defaults

  @Test func defaultsKeepAnEngineWithoutTabStateUnchanged() {
    let engine = MinimalEngine()
    let tab = TabID()
    engine.zoomIn(tab)
    engine.zoomOut(tab)
    engine.resetZoom(tab)
    #expect(engine.sessionRecovery == nil)
    #expect(engine.siteSettings == nil)  // page info (#582): no panel without it
  }
}

/// An engine that implements only the required members, so the new tab state members use their defaults.
@MainActor
private final class MinimalEngine: EngineClient {
  let tabIDs: [TabID] = []
  let windowIDs: [EngineWindowID] = []
  private let hub = EngineEventHub()
  func createTab(url: URL?) -> TabID { TabID() }
  func createTab(url: URL?, in window: EngineWindowID) -> TabID { TabID() }
  func closeTab(_ id: TabID) {}
  func closeTab(_ id: TabID, mode: CloseMode) {}
  func navigate(_ id: TabID, to url: URL) {}
  func reload(_ id: TabID) {}
  func goBack(_ id: TabID) {}
  func goForward(_ id: TabID) {}
  func goToHistory(_ id: TabID, offset: Int) {}
  func history(of id: TabID) -> TabHistory? { nil }
  func duplicateTab(_ id: TabID) -> TabID? { nil }
  func snapshot(of id: TabID) -> TabSnapshot? { nil }
  func contentView(for id: TabID) -> NSView? { nil }
  func setMuted(_ id: TabID, muted: Bool) {}
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { hub.add(handler) }
  func createWindow(host: any EngineWindowHosting) -> EngineWindowID { EngineWindowID() }
  func closeWindow(_ id: EngineWindowID) {}
  func activateTab(_ id: TabID) {}
  func activeTab(in window: EngineWindowID) -> TabID? { nil }
  func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    hub.addWindowObserver(handler)
  }
  func observe(window: EngineWindowID, _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(window: window, handler)
  }
}

/// Rule 25 of the shared contract on InMemoryEngine.
@MainActor
struct InMemoryTabStateContractTests {
  let harness = EngineHarness.inMemory()

  @Test func zoomStepIsReportedOnceAndNothingAtTheEnds() async throws {
    try await EngineContract.zoomStepIsReportedOnceAndNothingAtTheEnds(harness)
  }
  @Test func crashedTabStaysListed() async throws { try await EngineContract.crashedTabStaysListed(harness) }
  @Test func reloadRecoversACrashedTabOnce() async throws {
    try await EngineContract.reloadRecoversACrashedTabOnce(harness)
  }
}
