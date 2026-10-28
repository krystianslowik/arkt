import Foundation
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Downloads over the facade (#132) beyond the shared contract: what the engine gates before it reaches the facade,
/// what it drops, what it seeds, and how the save preference reaches the profile's prefs.
@MainActor
struct ChromiumDownloadTests {
  let facade = ScriptedFacade()

  private func make() -> (ChromiumEngine, EventRecorder) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    return (engine, EventRecorder(engine))
  }

  private func start(_ name: String, size: Int64 = 100) throws -> DownloadID {
    DownloadID(facade.beginDownload(url: URL(string: "https://files.test/\(name)")!, filename: name, totalBytes: size,
                                    mimeType: "application/octet-stream"))
  }

  @Test func aRepeatedUpdateIsReportedOnce() throws {
    let (engine, recorder) = make()
    let id = try start("Once.bin")
    facade.flush()
    facade.deliverDownloadBytes(id.rawValue, 100)
    facade.flush()
    let completed = recorder.downloadEvents(for: id).count
    // Chromium reports the "opened" flag and history writes after completion: the same values again.
    facade.record(facade.completionEvent(for: id.rawValue))
    facade.record(facade.completionEvent(for: id.rawValue))
    facade.flush()
    #expect(recorder.downloadEvents(for: id).count == completed)
    #expect(engine.download(id)?.state == .complete)
  }

  @Test func anUpdateForAnUnlistedDownloadListsIt() throws {
    let (engine, recorder) = make()
    let id = try start("Late.bin")                       // its Created event stays in the held batch
    engine.receive([facade.completionEvent(for: id.rawValue)])
    #expect(engine.downloads.map(\.id) == [id])
    guard case .downloadCreated? = recorder.downloadEvents(for: id).first else {
      Issue.record("the first event must be downloadCreated: \(recorder.downloadEvents)")
      return
    }
    #expect(recorder.downloadEvents(for: id).count == 1)
  }

  @Test func downloadsFoundAtLaunchAreListedBeforeAnyEvent() throws {
    let id = try start("Found.bin")
    facade.flush()
    let engine = ChromiumEngine(facade: facade)
    #expect(engine.downloads.map(\.id) == [id])
    #expect(engine.download(id)?.filename == "Found.bin")
  }

  @Test func theGatesStopCommandsBeforeTheFacade() throws {
    let (engine, _) = make()
    let held = try start("Held.dmg")
    facade.flush()
    facade.markDownloadDangerous(held.rawValue, type: DownloadDangerType.dangerousFile.rawValue)
    facade.deliverDownloadBytes(held.rawValue, 100)
    facade.flush()
    engine.perform(.open, on: held)
    #expect(facade.openedDownloads.isEmpty, "a held file is never opened")
    let plain = try start("Plain.bin")
    facade.flush()
    engine.perform(.open, on: plain)                     // still in progress
    engine.perform(.keepDangerous, on: plain)
    engine.perform(.discardDangerous, on: plain)
    engine.perform(.retry, on: plain)
    #expect(engine.download(plain)?.state == .inProgress && engine.download(plain)?.dangerType == .notDangerous)
  }

  @Test func openAndShowInFinderReachTheFacadeForTheRightStates() throws {
    let (engine, _) = make()
    let id = try start("Done.bin")
    facade.flush()
    engine.perform(.showInFinder, on: id)
    facade.deliverDownloadBytes(id.rawValue, 100)
    facade.flush()
    engine.perform(.open, on: id)
    #expect(facade.openedDownloads == [id.rawValue] && facade.revealedDownloads == [id.rawValue])
  }

  @Test func theSavePreferenceReachesTheProfilePrefs() throws {
    let (engine, _) = make()
    let folder = FileManager.default.temporaryDirectory.appending(path: "arkt-chromium-dl-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    engine.downloadSavePreference = .folder(folder)
    #expect(!facade.downloadPromptsForLocation && facade.downloadDirectory == folder)
    #expect(facade.downloadDestinationHandler == nil)

    engine.downloadSavePreference = .folder(folder.appending(path: "gone"))
    #expect(facade.downloadDirectory == engine.downloadDefaultFolder, "a missing folder is replaced by the default")

    engine.downloadSavePreference = .ask
    #expect(facade.downloadPromptsForLocation && facade.downloadDestinationHandler != nil)
    engine.downloadSavePreference = .folder(folder)
    #expect(!facade.downloadPromptsForLocation && facade.downloadDestinationHandler == nil)
  }

  @Test func theEngineStartsFromThePrefsTheProfileHas() {
    facade.downloadPromptsForLocation = true
    #expect(ChromiumEngine(facade: facade).downloadSavePreference == .ask)
    facade.downloadPromptsForLocation = false
    #expect(ChromiumEngine(facade: facade).downloadSavePreference == .folder(facade.downloadDirectory))
  }

  @Test func askWithoutAChooserSavesToTheDefaultFolder() async throws {
    let (engine, _) = make()
    engine.downloadSavePreference = .ask
    let id = try start("Plain.bin")
    try await ScriptedWait.until("the download to be listed") {
      facade.flush()
      return engine.download(id) != nil
    }
    #expect(engine.download(id)?.targetPath?.deletingLastPathComponent().standardizedFileURL
            == engine.downloadDefaultFolder.standardizedFileURL)
  }
}

extension ScriptedFacade {
  /// An update event repeating the item's current values.
  func completionEvent(for guid: String, kind: ArktEngineEventKind = .downloadUpdated) -> ScriptedEvent {
    let event = ScriptedEvent(kind, tab: nil, browser: nil)
    event.download = downloads.first { $0.guid == guid }
    return event
  }
}
