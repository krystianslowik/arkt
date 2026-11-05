import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Until the engine side of the tab state seams lands (#577), ChromiumEngine keeps the `EngineClient` defaults (#576):
/// the zoom calls report nothing, the snapshot keeps its defaults and there is no crashed-session prompt.
@MainActor
struct ChromiumTabStateDefaultsTests {
  let facade = ScriptedFacade()

  @Test func keepsTheDefaultsUntilTheFacadeReportsTabState() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let tab = engine.createTab(url: URL(string: "arkt-test://page.test/State")!,
                               in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    let recorder = EventRecorder(engine)

    engine.zoomIn(tab)
    engine.zoomOut(tab)
    engine.resetZoom(tab)
    facade.flush()

    #expect(recorder.log.isEmpty)
    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(snapshot.crash == nil && snapshot.zoom == .default && !snapshot.isTabFullscreen)
    #expect(engine.sessionRecovery == nil)
  }
}
