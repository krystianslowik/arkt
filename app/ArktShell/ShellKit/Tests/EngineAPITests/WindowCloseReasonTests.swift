import Foundation
import Testing
import EngineAPI
import EngineAPITestSupport

/// Why a window closed (#401), on the in-memory engine: each engine-side close reports its tabs with the matching tab
/// reason, then `.windowClosed` with the window's reason.
@MainActor
struct WindowCloseReasonTests {
  @Test(arguments: [(WindowCloseReason.userClose, CloseReason.windowClosing),
                    (.extension, .extension),
                    (.appQuit, .appTerminating),
                    (.lastTabClosed, .windowClosing)])
  func engineWindowCloseReportsItsReason(_ reason: WindowCloseReason, _ tabReason: CloseReason) {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: nil, in: window)
    let recorder = EventRecorder(engine)

    engine.engineCloseWindow(window, reason: reason)

    #expect(recorder.events(for: tab) == [.tabClosed(tab, reason: tabReason)])
    #expect(recorder.windowEvents == [.windowClosed(window, reason: reason)])
    #expect(!engine.windowIDs.contains(window))
  }

  @Test func closingAnUnknownWindowReportsNothing() {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    engine.closeWindow(window)
    let recorder = EventRecorder(engine)

    engine.engineCloseWindow(window, reason: .extension)

    #expect(recorder.windowEvents.isEmpty)
  }

  @Test func theEventNamesItsWindow() {
    let window = EngineWindowID()
    #expect(EngineWindowEvent.windowClosed(window, reason: .extension).windowID == window)
  }
}
