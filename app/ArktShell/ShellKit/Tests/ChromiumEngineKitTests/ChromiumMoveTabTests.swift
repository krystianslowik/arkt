import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Little Arkt's facade seams (#314): a popup request keeps its popup flag, and `moveTab(_:to:)` moves the tab
/// through the facade with the same id and container, its events following it, the emptied window closing.
@MainActor
struct ChromiumMoveTabTests {
  let facade = ScriptedFacade()

  @Test func popupFlagReachesTheEngineRequest() {
    let engine = ChromiumEngine(facade: facade)
    let popup = engine.engineRequest(from: ScriptedRequest(kind: .page, bounds: NSRect(x: 0, y: 0, width: 400,
                                                                                        height: 500),
                                                           isPopup: true))
    let normal = engine.engineRequest(from: ScriptedRequest(kind: .extension))
    #expect(popup.kind == .page && popup.isPopup)
    #expect(popup.bounds?.size == CGSize(width: 400, height: 500))
    #expect(normal.kind == .extension && !normal.isPopup)
  }

  @Test func moveKeepsTheTabAndClosesTheEmptiedWindow() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let main = engine.createWindow(host: StubWindowHost())
    let little = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: URL(string: "arkt-test://page/Popup"), in: little)
    facade.flush()
    let view = try #require(engine.contentView(for: tab))
    let recorder = EventRecorder(engine)
    var inMain: [EngineEvent] = []
    let observation = engine.observe(window: main) { inMain.append($0) }
    defer { observation.cancel() }

    engine.moveTab(tab, to: main)
    facade.flush()

    #expect(engine.snapshot(of: tab)?.window == main)
    #expect(engine.activeTab(in: main) == tab)
    #expect(engine.contentView(for: tab) === view)
    #expect(inMain == [.activeTabChanged(tab)])
    #expect(recorder.windowEvents == [.windowClosed(little)])
    #expect(!recorder.events.contains { if case .tabClosed = $0 { true } else { false } })
  }

  @Test func ownWindowAndUnknownWindowAreNoOps() {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: nil, in: window)
    facade.flush()
    let recorder = EventRecorder(engine)
    engine.moveTab(tab, to: window)
    engine.moveTab(tab, to: EngineWindowID())
    facade.flush()
    #expect(recorder.log.isEmpty)
    #expect(engine.snapshot(of: tab)?.window == window)
  }
}
