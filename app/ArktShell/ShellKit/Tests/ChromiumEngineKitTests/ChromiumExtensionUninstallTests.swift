import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Uninstall through the facade (#721): the shell's remove sheet calls `uninstallExtension`, ChromiumEngine hands the
/// id, the Report abuse state and the sheet's window to the facade once, and the removal comes back as the window's
/// `.extensionActionsChanged`; a refused uninstall changes nothing. The listing carries what the user may do
/// (`canUninstall`, `canReportAbuse`).
@MainActor
struct ChromiumExtensionUninstallTests {
  let facade = ScriptedFacade()

  private func makeEngine(probe: ScriptedAction = ScriptedAction(actionId: "probe", name: "Probe"))
    throws -> (ChromiumEngine, EngineWindowID, EngineWindowID) {
    let engine = ChromiumEngine(facade: facade)
    let first = engine.createWindow(host: StubWindowHost())
    let second = engine.createWindow(host: StubWindowHost())
    for window in [first, second] {
      facade.setActions([probe, ScriptedAction(actionId: "other", name: "Other")],
                        in: try ScriptedHarness.scriptedBrowser(engine, window))
    }
    return (engine, first, second)
  }

  private func delivered(_ engine: ChromiumEngine) async throws {
    try await ScriptedHarness.delivered(engine)
    try await ScriptedWait.until("the uninstall to answer") { facade.uninstallAnswers.count == facade.uninstallCalls.count }
  }

  private func windowId(_ engine: ChromiumEngine, _ window: EngineWindowID) throws -> Int32 {
    try ScriptedHarness.scriptedBrowser(engine, window).windowId
  }

  @Test(arguments: [(true, true), (false, false), (true, false), (false, true)])
  func theListingCarriesWhatTheUserMayDo(canUninstall: Bool, canReportAbuse: Bool) throws {
    let (engine, first, _) = try makeEngine(probe: ScriptedAction(
      actionId: "probe", name: "Probe", canUninstall: canUninstall, canReportAbuse: canReportAbuse))
    let probe = try #require(engine.extensionActions(in: first).first { $0.id == "probe" })
    #expect(probe.canUninstall == canUninstall)
    #expect(probe.canReportAbuse == canReportAbuse)
  }

  @Test(arguments: [false, true])
  func uninstallReachesTheFacadeOnceWithTheReportAbuseStateAndTheWindow(reportAbuse: Bool) async throws {
    let (engine, _, second) = try makeEngine()
    engine.uninstallExtension("probe", reportAbuse: reportAbuse, in: second)
    #expect(facade.uninstallCalls.map(\.extensionID) == ["probe"])
    #expect(facade.uninstallCalls.map(\.reportAbuse) == [reportAbuse])
    #expect(facade.uninstallCalls.map(\.window) == [try windowId(engine, second)])
    try await delivered(engine)
    #expect(facade.uninstallCalls.count == 1, "one call, no retry")
  }

  @Test func theReportPageGoesToTheNamedWindow() async throws {
    let (engine, first, _) = try makeEngine()
    engine.uninstallExtension("probe", reportAbuse: true, in: first)
    try await delivered(engine)
    #expect(facade.reportPageWindows == [try windowId(engine, first)], "the first window, not the last one")
  }

  @Test func theCallWithoutAWindowNamesNone() async throws {
    let (engine, _, _) = try makeEngine()
    engine.uninstallExtension("probe", reportAbuse: false)
    #expect(facade.uninstallCalls.map(\.window) == [nil])
    try await delivered(engine)
  }

  @Test func aClosedWindowIsNotNamed() async throws {
    let (engine, first, _) = try makeEngine()
    engine.closeWindow(first)
    try await delivered(engine)
    engine.uninstallExtension("probe", reportAbuse: true, in: first)
    #expect(facade.uninstallCalls.map(\.window) == [nil])
    try await delivered(engine)
  }

  @Test func theActionLeavesEveryWindowThatListedIt() async throws {
    let (engine, first, second) = try makeEngine()
    try await delivered(engine)
    let recorder = EventRecorder(engine)

    engine.uninstallExtension("probe", reportAbuse: false, in: first)
    try await delivered(engine)

    #expect(facade.uninstallAnswers.map(\.uninstalled) == [true])
    #expect(engine.extensionActions(in: first).map(\.id) == ["other"])
    #expect(engine.extensionActions(in: second).map(\.id) == ["other"])
    #expect(recorder.windowEvents.filter { $0 == .extensionActionsChanged(first) }.count == 1)
    #expect(recorder.windowEvents.filter { $0 == .extensionActionsChanged(second) }.count == 1)
    #expect(facade.reportPageWindows.isEmpty, "Report abuse off: no page")
  }

  @Test func noReportPageForAnExtensionWithoutOne() async throws {
    let (engine, first, _) = try makeEngine(probe: ScriptedAction(actionId: "probe", name: "Probe",
                                                                  canReportAbuse: false))
    engine.uninstallExtension("probe", reportAbuse: true, in: first)
    try await delivered(engine)
    #expect(facade.uninstallAnswers.map(\.uninstalled) == [true])
    #expect(facade.reportPageWindows.isEmpty)
  }

  @Test(arguments: [("missing", "unknown extension"), ("probe", "not removable")])
  func aRefusedUninstallChangesNothing(id: String, reason: String) async throws {
    let (engine, first, second) = try makeEngine(probe: ScriptedAction(actionId: "probe", name: "Probe",
                                                                       canUninstall: false))
    try await delivered(engine)
    let recorder = EventRecorder(engine)

    engine.uninstallExtension(id, reportAbuse: true, in: first)
    try await delivered(engine)

    #expect(facade.uninstallCalls.map(\.extensionID) == [id])
    #expect(facade.uninstallAnswers.map(\.reason) == [reason])
    #expect(engine.extensionActions(in: first).map(\.id) == ["probe", "other"])
    #expect(engine.extensionActions(in: second).map(\.id) == ["probe", "other"])
    #expect(recorder.windowEvents.isEmpty)
    #expect(facade.reportPageWindows.isEmpty)
  }
}
