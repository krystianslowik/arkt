import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import FakeEngineKit

/// FakeEngine's tab state from WebKit's own signals (#576): a web content process that really exits is a crash, and
/// `pageZoom` is the zoom.
@MainActor
struct FakeEngineTabStateTests {
  private let page = URL(string: "data:text/html,%3Ctitle%3ECrash%3C/title%3E%3Cp%3ECrash%3C/p%3E")!

  init() { _ = NSApplication.shared }

  private func loadedTab(_ engine: FakeEngine) async throws -> TabID {
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    try await EngineContract.waitUntil(timeout: .seconds(10)) {
      engine.snapshot(of: tab).map { !$0.isLoading && $0.title == "Crash" } ?? true
    }
    return tab
  }

  /// The pid of the tab's web content process; WebKit publishes it only on its private SPI.
  private func webContentProcess(of engine: FakeEngine, _ tab: TabID) throws -> pid_t {
    let view = try #require(engine.contentView(for: tab))
    let pid = try #require((view.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value)
    try #require(pid > 0, "the page has a web content process")
    return pid
  }

  @Test func webContentProcessExitIsACrashAndReloadRecovers() async throws {
    let engine = FakeEngine()
    let tab = try await loadedTab(engine)
    let recorder = EventRecorder(engine)

    #expect(kill(try webContentProcess(of: engine, tab), SIGKILL) == 0)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash != nil }

    #expect(recorder.events(for: tab).filter { if case .tabCrashed = $0 { true } else { false } }
              == [.tabCrashed(tab, .crashed)])
    #expect(engine.snapshot(of: tab)?.crash == .crashed)
    #expect(engine.tabIDs.contains(tab), "a crashed tab stays listed")

    engine.reload(tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash == nil }
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.isLoading == false }

    #expect(recorder.events(for: tab).filter { $0 == .tabRecovered(tab) }.count == 1)
    #expect(engine.snapshot(of: tab)?.title == "Crash")
    engine.closeTab(tab)
  }

  @Test func zoomFollowsPageZoomAndIsReportedOncePerChange() throws {
    let engine = FakeEngine()
    let tab = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    let recorder = EventRecorder(engine)

    engine.zoomIn(tab)
    engine.zoomOut(tab)
    engine.zoomOut(tab)
    engine.resetZoom(tab)
    engine.resetZoom(tab)

    #expect(recorder.events(for: tab) == [
      .zoomChanged(tab, TabZoom(percent: 115, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
      .zoomChanged(tab, TabZoom(percent: 85, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
    ])
    #expect(engine.snapshot(of: tab)?.zoom == .default)
  }

  @Test func zoomCommandsReportTheSameEvents() throws {
    let engine = FakeEngine()
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: nil, in: window)
    let forward = try #require(host.forward)
    let recorder = EventRecorder(engine)

    forward.execute(.zoomIn, .currentTab)
    forward.execute(.zoomReset, .currentTab)

    #expect(recorder.events(for: tab) == [
      .zoomChanged(tab, TabZoom(percent: 115, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
    ])
  }

  @Test func hasNoCrashedSession() {
    #expect(FakeEngine().sessionRecovery == nil)
  }
}
