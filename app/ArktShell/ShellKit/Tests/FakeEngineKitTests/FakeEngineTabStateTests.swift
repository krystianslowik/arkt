import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import FakeEngineKit

/// FakeEngine's zoom on WebKit's `pageZoom` (#576), with no page load, so the required lane stays deterministic. The
/// crash checks and contract rule 25 kill a real web content process and load pages; they run in the GUI lane
/// (`FakeEngineTabStateGUITests`).
@MainActor
struct FakeEngineTabStateTests {
  init() { _ = NSApplication.shared }

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
