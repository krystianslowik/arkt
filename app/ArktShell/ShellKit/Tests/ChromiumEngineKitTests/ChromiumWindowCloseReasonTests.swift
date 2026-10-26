import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// The facade's `WindowClosed` reason reaches the shell as `WindowCloseReason` (#401).
@MainActor
struct ChromiumWindowCloseReasonTests {
  let facade = ScriptedFacade()

  @Test func facadeReasonsMapOneToOne() {
    #expect(WindowCloseReason(facade: .user) == .userClose)
    #expect(WindowCloseReason(facade: .extension) == .extension)
    #expect(WindowCloseReason(facade: .lastTabClosed) == .lastTabClosed)
    #expect(WindowCloseReason(facade: .appTerminating) == .appQuit)
    // A WindowClosed the facade did not classify closes the shell window, as any close it did not expect.
    #expect(WindowCloseReason(facade: .none) == .userClose)
  }

  @Test func quittingReportsAppQuit() async throws {
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    _ = engine.createTab(url: nil, in: window)
    let recorder = EventRecorder(engine)
    try await ScriptedHarness.delivered(engine)

    facade.terminate()
    try await ScriptedHarness.delivered(engine)

    #expect(recorder.windowEvents == [.windowClosed(window, reason: .appQuit)])
  }

  @Test func theHostsCloseRequestReportsUserClose() async throws {
    let engine = ChromiumEngine(facade: facade)
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let recorder = EventRecorder(engine)
    let close = try #require(host.onCloseRequested)

    close()
    try await ScriptedHarness.delivered(engine)

    #expect(recorder.windowEvents == [.windowClosed(window, reason: .userClose)])
  }
}
