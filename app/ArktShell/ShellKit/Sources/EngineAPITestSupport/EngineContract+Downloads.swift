import EngineAPI
import Foundation

/// What a harness needs to make downloads happen in its engine (rule 24). The drivers stand in for the network, the
/// disk and the engine's safety check: the in-memory engine scripts them, FakeEngine serves a held response from a
/// loopback server, and a real engine runs them against a local server.
@MainActor
public struct DownloadDrivers {
  /// Begins a download of `size` bytes named `name`. The download stays in progress until `advance` supplies every
  /// byte, and the call returns its id once the engine has listed it.
  public let start: @MainActor (_ engine: any EngineClient, _ name: String, _ size: Int64) async throws -> DownloadID
  /// `bytes` more bytes of the download arrive; the last ones complete it.
  public let advance: @MainActor (_ engine: any EngineClient, _ id: DownloadID, _ bytes: Int64) async throws -> Void
  /// The engine can pause (WKDownload cannot).
  public let canPause: Bool
  /// The connection fails with `reason`. Nil: not applicable.
  public let fail: (@MainActor (_ engine: any EngineClient, _ id: DownloadID, _ reason: DownloadInterruptReason) async
    throws -> Void)?
  /// The engine's safety check judges the download `type`. Nil: not applicable (WebKit makes no such judgement).
  public let markDangerous: (@MainActor (_ engine: any EngineClient, _ id: DownloadID, _ type: DownloadDangerType)
    async throws -> Void)?

  public init(
    start: @escaping @MainActor (any EngineClient, String, Int64) async throws -> DownloadID,
    advance: @escaping @MainActor (any EngineClient, DownloadID, Int64) async throws -> Void,
    canPause: Bool = true,
    fail: (@MainActor (any EngineClient, DownloadID, DownloadInterruptReason) async throws -> Void)? = nil,
    markDangerous: (@MainActor (any EngineClient, DownloadID, DownloadDangerType) async throws -> Void)? = nil
  ) {
    self.start = start; self.advance = advance; self.canPause = canPause
    self.fail = fail; self.markDangerous = markDangerous
  }
}

// MARK: - Rule 24

extension EngineContract {
  /// The size every check's download has.
  static let downloadSize: Int64 = 4_000

  static func downloadEngine(_ h: EngineHarness) throws -> (any EngineClient, any EngineDownloads, DownloadDrivers) {
    let drivers = try driver(h.downloads, "downloads")
    let engine = h.makeEngine()
    guard let downloads = engine as? any EngineDownloads else {
      throw ContractViolation(description: "the engine does not adopt EngineDownloads: \(type(of: engine))")
    }
    return (engine, downloads, drivers)
  }

  static func downloadState(_ engine: any EngineDownloads, _ id: DownloadID) -> DownloadState? {
    engine.download(id)?.state
  }

  static func updates(_ recorder: EventRecorder, _ id: DownloadID) -> [DownloadItem] {
    recorder.downloadEvents(for: id).compactMap { if case .downloadUpdated(let item) = $0 { item } else { nil } }
  }

  static func removals(_ recorder: EventRecorder, _ id: DownloadID) -> Int {
    recorder.downloadEvents(for: id).filter { if case .downloadRemoved = $0 { true } else { false } }.count
  }

  /// A fresh writable folder under the temporary directory, removed by the caller.
  static func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "arkt-downloads-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  public static func downloadIsReportedProgressesAndCompletes(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    let recorder = EventRecorder(client)
    let id = try await drivers.start(client, "Report.bin", downloadSize)
    guard case .downloadCreated(let created)? = recorder.downloadEvents(for: id).first else {
      throw ContractViolation(description: "the first event must be downloadCreated: \(recorder.downloadEvents)")
    }
    try require(created.filename == "Report.bin" && created.totalBytes == downloadSize && created.state == .inProgress
                  && created.receivedBytes < downloadSize && created.dangerType == .notDangerous
                  && created.endTime == nil, "the created item must carry the engine's values: \(created)")
    try require(engine.downloads.map(\.id).contains(id), "the list must contain the download")

    try await drivers.advance(client, id, downloadSize / 2)
    try await waitUntil(timeout: .seconds(10)) { (engine.download(id)?.receivedBytes ?? 0) > 0 }
    try require(engine.download(id)?.state == .inProgress, "half the bytes leave it in progress")

    try await drivers.advance(client, id, downloadSize)
    try await waitUntil(timeout: .seconds(10)) { engine.download(id)?.state == .complete }
    let done = try requireValue(engine.download(id), "the finished item")
    try require(done.receivedBytes == downloadSize && done.endTime != nil && done.targetPath != nil,
                "a complete item has every byte, an end time and a target: \(done)")
    let received = updates(recorder, id).map(\.receivedBytes)
    try require(received == received.sorted(), "received bytes went backwards: \(received)")
    try require(updates(recorder, id).filter { $0.state == .complete }.count == 1,
                "completion is reported once: \(recorder.downloadEvents(for: id))")
    if let target = done.targetPath {
      try require(FileManager.default.fileExists(atPath: target.path()), "the file must be on disk at \(target)")
    }
  }

  public static func cancelEndsAnActiveDownloadOnce(_ h: EngineHarness) async throws {
    print("DIAG cancel 1")
    let (client, engine, drivers) = try downloadEngine(h)
    let recorder = EventRecorder(client)
    print("DIAG cancel 2")
    let id = try await drivers.start(client, "Cancel.bin", downloadSize)
    print("DIAG cancel 3 started \(String(describing: engine.download(id)))")
    engine.perform(.cancel, on: id)
    print("DIAG cancel 4 performed \(String(describing: engine.download(id)?.state))")
    do { try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .cancelled } } catch {
      print("DIAG cancel wait threw \(String(reflecting: error)) \(type(of: error))"); throw error
    }
    print("DIAG cancel 5")
    try require(engine.download(id)?.endTime != nil, "a cancelled download has an end time")
    let count = recorder.downloadEvents(for: id).count
    print("DIAG cancel 6 events \(recorder.downloadEvents(for: id))")
    engine.perform(.cancel, on: id)                                  // finished: nothing happens
    engine.perform(.pause, on: id)
    engine.perform(.resume, on: id)
    engine.perform(.cancel, on: DownloadID("unknown"))               // unknown: nothing happens
    print("DIAG cancel 7")
    try require(recorder.downloadEvents(for: id).count == count && downloadState(engine, id) == .cancelled,
                "a command that does not apply must change nothing: \(recorder.downloadEvents(for: id))")
    print("DIAG cancel 8")
    if let target = engine.download(id)?.targetPath {
      try require(!FileManager.default.fileExists(atPath: target.path()), "the partial file is deleted")
    }
  }

  public static func removeForgetsADownloadAndKeepsItsFile(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    let recorder = EventRecorder(client)
    let id = try await drivers.start(client, "Keep.bin", downloadSize)
    try await drivers.advance(client, id, downloadSize)
    try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .complete }
    let target = try requireValue(engine.download(id)?.targetPath, "target of a complete download")
    engine.perform(.remove, on: id)
    try await waitUntil(timeout: .seconds(10)) { engine.download(id) == nil }
    engine.perform(.remove, on: id)                                  // gone: nothing happens
    try require(removals(recorder, id) == 1, "removal is reported once: \(recorder.downloadEvents(for: id))")
    try require(recorder.downloadEvents(for: id).last == .downloadRemoved(id), "nothing follows the removal")
    try require(FileManager.default.fileExists(atPath: target.path()), "Remove keeps the file")
  }

  public static func pauseHoldsTheBytesUntilResume(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    guard drivers.canPause else { throw ContractNotApplicable(driver: "pause (the engine cannot pause)") }
    let id = try await drivers.start(client, "Pause.bin", downloadSize)
    try await drivers.advance(client, id, downloadSize / 4)
    try await waitUntil(timeout: .seconds(10)) { (engine.download(id)?.receivedBytes ?? 0) > 0 }
    engine.perform(.pause, on: id)
    try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .paused }
    let held = engine.download(id)?.receivedBytes
    try await drivers.advance(client, id, downloadSize / 4)
    try require(engine.download(id)?.receivedBytes == held && downloadState(engine, id) == .paused,
                "a paused download receives nothing")
    engine.perform(.resume, on: id)
    try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .inProgress }
    try await drivers.advance(client, id, downloadSize)
    try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .complete }
  }

  public static func interruptedDownloadRetriesAndReplacesItsRow(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    let fail = try driver(drivers.fail, "fail")
    let recorder = EventRecorder(client)
    let id = try await drivers.start(client, "Retry.bin", downloadSize)
    let url = try requireValue(engine.download(id)?.url, "url of the download")
    try await fail(client, id, .networkDisconnected)
    try await waitUntil(timeout: .seconds(10)) { downloadState(engine, id) == .interrupted(.networkDisconnected) }
    engine.perform(.retry, on: id)
    try await waitUntil(timeout: .seconds(10)) {
      engine.downloads.contains { $0.url == url && $0.state.isActive }
    }
    let active = engine.downloads.filter { $0.url == url && $0.state.isActive }
    try require(active.count == 1, "retry starts exactly one download: \(engine.downloads)")
    let replaced = active[0].id != id
    if replaced {
      try require(engine.download(id) == nil && removals(recorder, id) == 1,
                  "a retry that starts a new download removes the old item: \(recorder.downloadEvents)")
    }
    engine.perform(.retry, on: active[0].id)                         // active: nothing happens
    try require(engine.downloads.filter { $0.url == url }.count == 1, "retry of an active download does nothing")
  }

  public static func dangerousDownloadIsHeldUntilDecided(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    let markDangerous = try driver(drivers.markDangerous, "markDangerous")
    let recorder = EventRecorder(client)

    let kept = try await drivers.start(client, "Keep.dmg", downloadSize)
    try await markDangerous(client, kept, .dangerousFile)
    try await waitUntil(timeout: .seconds(10)) { engine.download(kept)?.dangerType == .dangerousFile }
    try require(engine.download(kept)?.isHeldForDecision == true, "a dangerous file is held")
    engine.perform(.open, on: kept)                                  // held: never opened
    engine.perform(.keepDangerous, on: kept)
    try await waitUntil(timeout: .seconds(10)) { engine.download(kept)?.dangerType == .userValidated }
    let count = recorder.downloadEvents(for: kept).count
    engine.perform(.keepDangerous, on: kept)                         // answered: nothing happens
    try require(recorder.downloadEvents(for: kept).count == count, "a second answer does nothing")
    try require(engine.download(kept)?.isHeldForDecision == false, "a validated file is no longer held")

    let discarded = try await drivers.start(client, "Discard.dmg", downloadSize)
    try await drivers.advance(client, discarded, downloadSize)
    try await markDangerous(client, discarded, .dangerousContent)
    try await waitUntil(timeout: .seconds(10)) { engine.download(discarded)?.dangerType == .dangerousContent }
    let target = engine.download(discarded)?.targetPath
    engine.perform(.discardDangerous, on: discarded)
    try await waitUntil(timeout: .seconds(10)) { engine.download(discarded) == nil }
    try require(removals(recorder, discarded) == 1, "discard removes the item once")
    if let target { try require(!FileManager.default.fileExists(atPath: target.path()), "discard deletes the file") }

    let blocked = try await drivers.start(client, "Blocked.zip", downloadSize)
    try await markDangerous(client, blocked, .blockedTooLarge)
    try await waitUntil(timeout: .seconds(10)) { engine.download(blocked)?.dangerType == .blockedTooLarge }
    engine.perform(.keepDangerous, on: blocked)
    try require(engine.download(blocked)?.dangerType == .blockedTooLarge, "a blocked download cannot be kept")
    engine.perform(.discardDangerous, on: blocked)
    try await waitUntil(timeout: .seconds(10)) { engine.download(blocked) == nil }

    let plain = try await drivers.start(client, "Plain.bin", downloadSize)
    engine.perform(.keepDangerous, on: plain)                        // not dangerous: nothing happens
    engine.perform(.discardDangerous, on: plain)
    try require(engine.download(plain)?.state == .inProgress, "a safe download ignores the danger commands")
  }

  public static func savePreferenceDecidesTheFolder(_ h: EngineHarness) async throws {
    let (client, engine, drivers) = try downloadEngine(h)
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    engine.downloadSavePreference = .folder(folder)
    let saved = try await drivers.start(client, "Saved.bin", downloadSize)
    try require(engine.download(saved)?.targetPath?.deletingLastPathComponent().standardizedFileURL
                  == folder.standardizedFileURL, "a download goes to the chosen folder: \(String(describing: engine.download(saved)))")

    let missing = folder.appending(path: "gone-\(UUID().uuidString)")
    engine.downloadSavePreference = .folder(missing)
    let fallback = try await drivers.start(client, "Fallback.bin", downloadSize)
    try require(engine.download(fallback)?.targetPath?.deletingLastPathComponent().standardizedFileURL
                  == engine.downloadDefaultFolder.standardizedFileURL,
                "a missing folder falls back to the default folder: \(String(describing: engine.download(fallback)))")

    // `.ask`: the chooser decides. The one panel per download is asked the suggested name and the folder it opens in.
    var requests: [DownloadDestinationRequest] = []
    let chosen = folder.appending(path: "Chosen name.bin")
    engine.downloadDestinationChooser = { request in requests.append(request); return chosen }
    engine.downloadSavePreference = .ask
    let asked = try await drivers.start(client, "Asked.bin", downloadSize)
    try require(requests.map(\.suggestedFilename) == ["Asked.bin"], "the chooser sees the suggested name: \(requests)")
    try require(engine.download(asked)?.targetPath?.standardizedFileURL == chosen.standardizedFileURL,
                "the chooser's answer is the target: \(String(describing: engine.download(asked)))")

    engine.downloadDestinationChooser = nil
  }
}
