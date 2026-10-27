import Foundation
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// The download model's values and the in-memory engine's scripted behavior beyond the shared contract.
@MainActor
struct EngineDownloadsTests {
  // MARK: Values

  @Test func interruptReasonsMatchChromiumValues() {
    // components/download/public/common/download_interrupt_reason_values.h at 156.0.8078.48.
    let expected: [DownloadInterruptReason: Int] = [
      .fileFailed: 1, .fileAccessDenied: 2, .fileNoSpace: 3, .fileNameTooLong: 5, .fileTooLarge: 6,
      .fileVirusInfected: 7, .fileTransientError: 10, .fileBlocked: 11, .fileSecurityCheckFailed: 12,
      .fileTooShort: 13, .fileHashMismatch: 14, .fileSameAsSource: 15, .networkFailed: 20, .networkTimeout: 21,
      .networkDisconnected: 22, .networkServerDown: 23, .networkInvalidRequest: 24, .serverFailed: 30,
      .serverNoRange: 31, .serverBadContent: 33, .serverUnauthorized: 34, .serverCertProblem: 35,
      .serverForbidden: 36, .serverUnreachable: 37, .serverContentLengthMismatch: 38,
      .serverCrossOriginRedirect: 39, .userCanceled: 40, .userShutdown: 41, .crash: 50, .localDownloadBlocked: 51,
    ]
    #expect(Set(DownloadInterruptReason.all) == Set(expected.keys))
    for (reason, value) in expected { #expect(reason.rawValue == value, "\(reason)") }
    #expect(DownloadInterruptReason(rawValue: 999).failureWords == "Interrupted", "an unnamed value still reads")
  }

  @Test func dangerTypesMatchChromiumValues() {
    // components/download/public/common/download_danger_type.h at 156.0.8078.48.
    let expected: [DownloadDangerType: Int] = [
      .notDangerous: 0, .dangerousFile: 1, .dangerousURL: 2, .dangerousContent: 3, .maybeDangerousContent: 4,
      .uncommonContent: 5, .userValidated: 6, .dangerousHost: 7, .potentiallyUnwanted: 8, .allowlistedByPolicy: 9,
      .asyncScanning: 10, .blockedPasswordProtected: 11, .blockedTooLarge: 12, .sensitiveContentWarning: 13,
      .sensitiveContentBlock: 14, .deepScannedSafe: 15, .deepScannedOpenedDangerous: 16, .promptForScanning: 17,
      .dangerousAccountCompromise: 19, .deepScannedFailed: 20, .promptForLocalPasswordScanning: 21,
      .asyncLocalPasswordScanning: 22, .blockedScanFailed: 23, .forceSaveToGDrive: 24, .forceSaveToOneDrive: 25,
    ]
    #expect(Set(DownloadDangerType.all) == Set(expected.keys))
    for (type, value) in expected { #expect(type.rawValue == value, "\(type)") }
  }

  @Test(arguments: [
    (DownloadDangerType.notDangerous, false, false, false),
    (.userValidated, false, false, false),
    (.dangerousFile, true, true, true),
    (.dangerousContent, true, true, true),
    (.uncommonContent, true, false, true),
    (.blockedTooLarge, true, true, false),
  ])
  func dangerClassification(_ type: DownloadDangerType, _ held: Bool, _ sheet: Bool, _ keep: Bool) {
    #expect(type.isHeldForDecision == held)
    #expect(type.needsSheet == sheet)
    #expect(type.canKeep == keep)
  }

  /// Only these four may be opened; every other named type, and a value nobody named, is held or pending.
  private static let openable: Set<DownloadDangerType> = [.notDangerous, .userValidated, .allowlistedByPolicy, .deepScannedSafe]

  @Test(arguments: DownloadDangerType.all + [DownloadDangerType(rawValue: 18), DownloadDangerType(rawValue: 999)])
  func `every danger type fails closed unless it is on the allow-list`(_ type: DownloadDangerType) {
    let safe = Self.openable.contains(type)
    #expect(type.canOpen == safe, "\(type)")
    #expect(type.isHeldForDecision == (!safe && !type.isScanning), "\(type)")
    #expect(!(type.canOpen && type.isHeldForDecision))
    if type.isBlocked { #expect(type.isHeldForDecision && !type.canKeep && type.needsSheet) }
    var item = DownloadItem(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", state: .complete,
                            dangerType: type)
    #expect(item.canBeOpened == safe, "\(type)")
    item.state = .inProgress
    #expect(!item.canBeOpened, "an unfinished file never opens")
  }

  @Test func `the types Chromium holds that were missing are held now`() {
    for type in [DownloadDangerType.promptForScanning, .promptForLocalPasswordScanning, .forceSaveToGDrive,
                 .forceSaveToOneDrive] {
      #expect(type.isHeldForDecision && !type.canOpen, "\(type)")
    }
    #expect(DownloadDangerType.forceSaveToGDrive.isBlocked && DownloadDangerType.forceSaveToOneDrive.isBlocked)
    #expect(DownloadDangerType.promptForLocalPasswordScanning.canKeep)
    #expect(DownloadDangerType.asyncScanning.isScanning && !DownloadDangerType.asyncScanning.isHeldForDecision)
  }

  @Test(arguments: DownloadDangerType.all)
  func `the in-memory engine opens a file only when its type is openable`(_ type: DownloadDangerType) {
    let engine = InMemoryEngine()
    let id = engine.beginDownload(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", totalBytes: 10)
    engine.deliverDownloadBytes(id, 10)
    engine.markDownloadDangerous(id, type)
    engine.perform(.open, on: id)
    #expect(engine.openedDownloads == (Self.openable.contains(type) ? [id] : []), "\(type)")
  }

  @Test(arguments: [
    ("report.pdf", "report.pdf"), ("../../etc/passwd", "passwd"), ("a/b/c.txt", "c.txt"), ("..\\..\\win.ini", "win.ini"),
    ("..", "download"), (".", "download"), ("", "download"), ("/", "download"), (".hidden", "hidden"),
    ("...dots.zip", "dots.zip"), ("trailing/", "trailing"), ("nul\u{0}byte.txt", "nulbyte.txt"), ("  spaced  .txt", "spaced  .txt"),
  ])
  func `a suggested name is reduced to one safe file name`(_ raw: String, _ expected: String) {
    #expect(DownloadFilename.sanitized(raw) == expected)
  }

  @Test func `a sanitized name always stays inside the folder`() {
    let folder = URL(filePath: "/tmp/arkt-downloads", directoryHint: .isDirectory)
    for raw in ["../escape", "/abs/path", "a/../../b", "..", "x/..", "~/home"] {
      let target = folder.appending(path: DownloadFilename.sanitized(raw))
      #expect(target.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL, "\(raw)")
    }
  }

  @Test func fractionAndTimeLeft() {
    let url = URL(string: "https://files.test/A.zip")!
    var item = DownloadItem(url: url, filename: "A.zip", totalBytes: 1_000, receivedBytes: 250, bytesPerSecond: 50)
    #expect(item.fraction == 0.25)
    #expect(item.secondsRemaining == 15)
    item.bytesPerSecond = 0
    #expect(item.secondsRemaining == nil, "not moving: no estimate")
    item.totalBytes = nil
    #expect(item.fraction == nil, "an unknown total has no fraction")
    item.state = .complete
    #expect(item.fraction == 1 && item.secondsRemaining == nil)
    item.state = .paused
    item.totalBytes = 1_000
    #expect(item.secondsRemaining == nil, "a paused download has no estimate")
  }

  @Test func stateClassification() {
    #expect(DownloadState.inProgress.isActive && DownloadState.paused.isActive)
    #expect(DownloadState.complete.isFinished && DownloadState.cancelled.isFinished)
    #expect(DownloadState.interrupted(.networkFailed).isFinished && !DownloadState.paused.isFinished)
  }

  // MARK: Hub

  @Test func downloadEventsShareTheFIFOWithTabEvents() {
    let engine = InMemoryEngine()
    var log: [String] = []
    let tabs = engine.observe { event in
      if case .tabCreated = event {
        // Emitted inside a tab handler: queued behind the tab event being delivered.
        engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
        log.append("tab")
      }
    }
    let downloads = engine.observeDownloads { event in
      if case .downloadCreated = event { log.append("download") }
    }
    engine.createTab(url: nil)
    #expect(log == ["tab", "download"], "\(log)")
    _ = (tabs, downloads)
  }

  @Test func cancelledDownloadObservationStopsDelivery() {
    let engine = InMemoryEngine()
    var count = 0
    let observation = engine.observeDownloads { _ in count += 1 }
    engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    observation.cancel()
    engine.beginDownload(url: URL(string: "https://files.test/B.bin")!, filename: "B.bin", totalBytes: 10)
    #expect(count == 1)
  }

  // MARK: In-memory scripting

  @Test func openAndShowInFinderAreRecordedForTheRightStates() async throws {
    let engine = InMemoryEngine()
    let id = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    engine.perform(.open, on: id)
    #expect(engine.openedDownloads.isEmpty, "an active download is not opened")
    engine.perform(.showInFinder, on: id)
    #expect(engine.revealedDownloads == [id])
    engine.deliverDownloadBytes(id, 10)
    engine.perform(.open, on: id)
    #expect(engine.openedDownloads == [id])
  }

  @Test func resumableInterruptionResumesInPlace() async throws {
    let engine = InMemoryEngine()
    let id = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 100)
    engine.deliverDownloadBytes(id, 40)
    engine.interruptDownload(id, reason: .networkTimeout, canResume: true)
    #expect(engine.download(id)?.state == .interrupted(.networkTimeout) && engine.download(id)?.canResume == true)
    engine.perform(.retry, on: id)
    #expect(engine.download(id)?.state == .inProgress && engine.download(id)?.receivedBytes == 40)
    #expect(engine.downloads.count == 1, "resumed in place, no second row")
  }

  @Test func cancelledPanelNeverListsTheDownload() async throws {
    let engine = InMemoryEngine()
    engine.downloadSavePreference = .ask
    engine.downloadDestinationChooser = { _ in nil }
    let recorder = EventRecorder(engine)
    engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    await Task.yield()
    await Task.yield()
    #expect(engine.downloads.isEmpty && recorder.downloadEvents.isEmpty)
  }

  @Test func askWithoutAChooserSavesToTheDefaultFolder() {
    let engine = InMemoryEngine()
    engine.downloadSavePreference = .ask
    let id = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    #expect(engine.download(id)?.targetPath?.deletingLastPathComponent().standardizedFileURL
              == engine.downloadDefaultFolder.standardizedFileURL)
  }

  @Test func `a suggested name cannot leave the folder in the in-memory engine either`() {
    let engine = InMemoryEngine()
    let id = engine.beginDownload(url: URL(string: "https://files.example/x")!, filename: "../../escape.bin", totalBytes: 1)
    let target = engine.download(id)?.targetPath
    #expect(target?.deletingLastPathComponent().standardizedFileURL == engine.downloadDefaultFolder.standardizedFileURL)
    #expect(engine.download(id)?.filename == "escape.bin")
  }

  @Test func existingNamesGetANumber() {
    let engine = InMemoryEngine()
    let first = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    let second = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    #expect(engine.download(first)?.filename == "A.bin" && engine.download(second)?.filename == "A (1).bin")
  }

  @Test func removeOfAnActiveDownloadCancelsFirst() {
    let engine = InMemoryEngine()
    let recorder = EventRecorder(engine)
    let id = engine.beginDownload(url: URL(string: "https://files.test/A.bin")!, filename: "A.bin", totalBytes: 10)
    engine.perform(.remove, on: id)
    let kinds = recorder.downloadEvents(for: id).map { event -> String in
      switch event {
      case .downloadCreated: "created"
      case .downloadUpdated(let item): "updated:\(item.state)"
      case .downloadRemoved: "removed"
      }
    }
    #expect(kinds == ["created", "updated:cancelled", "removed"], "\(kinds)")
  }
}
