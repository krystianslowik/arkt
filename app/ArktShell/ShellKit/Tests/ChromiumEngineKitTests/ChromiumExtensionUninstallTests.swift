import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Uninstall through the facade (#721): the shell's remove sheet calls `uninstallExtension`, ChromiumEngine hands the id
/// and the Report abuse state to the facade once, and the removal comes back as the window's
/// `.extensionActionsChanged`; a refused uninstall changes nothing.
@MainActor
struct ChromiumExtensionUninstallTests {
  let facade = ScriptedFacade()

  private func makeEngine() throws -> (ChromiumEngine, EngineWindowID, EngineWindowID) {
    let engine = ChromiumEngine(facade: facade)
    let first = engine.createWindow(host: StubWindowHost())
    let second = engine.createWindow(host: StubWindowHost())
    for window in [first, second] {
      facade.setActions([ScriptedAction(actionId: "probe", name: "Probe"),
                         ScriptedAction(actionId: "other", name: "Other")],
                        in: try ScriptedHarness.scriptedBrowser(engine, window))
    }
    return (engine, first, second)
  }

  private func delivered(_ engine: ChromiumEngine) async throws {
    try await ScriptedHarness.delivered(engine)
    try await ScriptedWait.until("the uninstall to answer") { facade.uninstallAnswers.count == facade.uninstallCalls.count }
  }

  @Test(arguments: [false, true])
  func uninstallReachesTheFacadeOnceWithTheReportAbuseState(reportAbuse: Bool) async throws {
    let (engine, _, _) = try makeEngine()
    engine.uninstallExtension("probe", reportAbuse: reportAbuse)
    #expect(facade.uninstallCalls.map(\.extensionID) == ["probe"])
    #expect(facade.uninstallCalls.map(\.reportAbuse) == [reportAbuse])
    try await delivered(engine)
    #expect(facade.uninstallCalls.count == 1, "one call, no retry")
  }

  @Test func theActionLeavesEveryWindowThatListedIt() async throws {
    let (engine, first, second) = try makeEngine()
    try await delivered(engine)
    let recorder = EventRecorder(engine)

    engine.uninstallExtension("probe", reportAbuse: false)
    try await delivered(engine)

    #expect(facade.uninstallAnswers.map(\.uninstalled) == [true])
    #expect(engine.extensionActions(in: first).map(\.id) == ["other"])
    #expect(engine.extensionActions(in: second).map(\.id) == ["other"])
    #expect(recorder.windowEvents.filter { $0 == .extensionActionsChanged(first) }.count == 1)
    #expect(recorder.windowEvents.filter { $0 == .extensionActionsChanged(second) }.count == 1)
  }

  @Test(arguments: [("missing", "unknown extension"), ("probe", "not removable")])
  func aRefusedUninstallChangesNothing(id: String, reason: String) async throws {
    let (engine, first, second) = try makeEngine()
    facade.nonRemovableExtensions = ["probe"]
    try await delivered(engine)
    let recorder = EventRecorder(engine)

    engine.uninstallExtension(id, reportAbuse: true)
    try await delivered(engine)

    #expect(facade.uninstallCalls.map(\.extensionID) == [id])
    #expect(facade.uninstallAnswers.map(\.reason) == [reason])
    #expect(engine.extensionActions(in: first).map(\.id) == ["probe", "other"])
    #expect(engine.extensionActions(in: second).map(\.id) == ["probe", "other"])
    #expect(recorder.windowEvents.isEmpty)
  }
}
