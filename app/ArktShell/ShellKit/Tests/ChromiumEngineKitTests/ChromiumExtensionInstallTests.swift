import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// The install event (#592): the facade's profile-wide `ExtensionInstalled` reaches `observeExtensions` as one
/// `.installed` per install. Ids of an `installExtensionResults` batch are tagged `.browserImport` (#594), even when
/// the event lands after the batch's completion; every other install is `.user`.
@MainActor
struct ChromiumExtensionInstallTests {
  let facade = ScriptedFacade()
  let alpha = String(repeating: "a", count: 32)
  let beta = String(repeating: "b", count: 32)
  let gamma = String(repeating: "c", count: 32)

  private func observe(_ engine: ChromiumEngine) -> (EngineObservation, () -> [EngineExtensionEvent]) {
    var events: [EngineExtensionEvent] = []
    let observation = engine.observeExtensions { events.append($0) }
    return (observation, { events })
  }

  /// Waits until the held batch reached the facade.
  private func batchStarted(_ count: Int = 1) async throws {
    try await ScriptedWait.until("the batch to reach the facade") { facade.installedExtensionBatches.count == count }
  }

  @Test func anInstallTheUserMadeArrivesOnceAsUser() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }

    facade.recordExtensionInstalled(alpha, name: "Alpha Clips")
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [.installed(InstalledExtension(id: alpha, name: "Alpha Clips", source: .user))])
  }

  @Test func anEventWithoutAnIdIsDropped() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }

    facade.recordExtensionInstalled(nil, name: "Nameless")
    facade.recordExtensionInstalled(beta, name: nil)
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [.installed(InstalledExtension(id: beta, name: "", source: .user))])
  }

  @Test func idsOfABatchInFlightArriveAsBrowserImport() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }
    facade.holdsExtensionBatch = true
    let batch = Task { @MainActor in await engine.installExtensionResults(ids: [alpha, beta]) }
    try await batchStarted()

    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)
    facade.finishHeldExtensionBatch()
    _ = await batch.value

    #expect(events() == [.installed(InstalledExtension(id: alpha, name: "Alpha", source: .browserImport))])
  }

  /// The facade delivers its events on a later task than the batch's completion may run: an installed id stays
  /// tagged until its event has arrived.
  @Test func anEventThatLandsAfterTheBatchCompletedIsStillBrowserImport() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }

    _ = await engine.installExtensionResults(ids: [alpha])
    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [.installed(InstalledExtension(id: alpha, name: "Alpha", source: .browserImport))])
  }

  @Test func anIdTheBatchDidNotInstallIsUserWhenTheUserInstallsItLater() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }
    facade.extensionAnswers = [beta: (.failed, "not available from the Web Store"), gamma: (.alreadyInstalled, nil)]

    _ = await engine.installExtensionResults(ids: [beta, gamma])
    facade.recordExtensionInstalled(beta, name: "Beta")
    facade.recordExtensionInstalled(gamma, name: "Gamma")
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [
      .installed(InstalledExtension(id: beta, name: "Beta", source: .user)),
      .installed(InstalledExtension(id: gamma, name: "Gamma", source: .user)),
    ])
  }

  @Test func aCancelledBatchTagsNothing() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }
    facade.holdsExtensionBatch = true
    let batch = Task { @MainActor in await engine.installExtensionResults(ids: [alpha]) }
    try await batchStarted()
    batch.cancel()
    _ = await batch.value

    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [.installed(InstalledExtension(id: alpha, name: "Alpha", source: .user))])
  }

  /// Each tag is used once: after the import's event, a later install of the same id (removed and added again from
  /// the Web Store) is the user's.
  @Test func aTagIsConsumedByItsEvent() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    defer { observation.cancel() }

    _ = await engine.installExtensionResults(ids: [alpha, alpha])
    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)
    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)

    #expect(events() == [
      .installed(InstalledExtension(id: alpha, name: "Alpha", source: .browserImport)),
      .installed(InstalledExtension(id: alpha, name: "Alpha", source: .user)),
    ])
  }

  @Test func aCancelledObservationReceivesNothing() async throws {
    let engine = ChromiumEngine(facade: facade)
    let (observation, events) = observe(engine)
    observation.cancel()

    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)

    #expect(events().isEmpty)
  }

  /// The event is profile-wide: it reaches the extension stream only, never the tab or window streams.
  @Test func theEventStaysOffTheTabAndWindowStreams() async throws {
    let engine = ChromiumEngine(facade: facade)
    _ = engine.createWindow(host: StubWindowHost())
    try await ScriptedHarness.delivered(engine)
    var others = 0
    let tabs = engine.observe { _ in others += 1 }
    let windows = engine.observeWindows { _ in others += 1 }
    defer { tabs.cancel(); windows.cancel() }

    facade.recordExtensionInstalled(alpha, name: "Alpha")
    try await ScriptedHarness.delivered(engine)

    #expect(others == 0)
  }
}
