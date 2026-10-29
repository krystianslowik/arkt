import AppKit
import XCTest
import EngineAPI
@testable import FakeEngineKit
@testable import EngineAPITestSupport

/// Rule 24 against FakeEngine: real WKDownloads from a loopback server that holds each response until the check says
/// so. WebKit cannot pause and judges nothing dangerous, so those two checks are not applicable; the rest run.
@MainActor
final class FakeEngineDownloadContractTests: XCTestCase {
  var harness: EngineHarness!
  var server: HeldDownloadServer!
  var folder: URL!

  override func setUp() async throws {
    _ = NSApplication.shared
    folder = FileManager.default.temporaryDirectory.appending(path: "arkt-fake-downloads-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    server = try await HeldDownloadServer.start()
    harness = .fakeDownloads(server: server, folder: folder)
  }

  override func tearDown() async throws {
    server?.stop()
    if let folder { try? FileManager.default.removeItem(at: folder) }
  }

  func testDownloadIsReportedProgressesAndCompletes() async throws {
    try await EngineContract.downloadIsReportedProgressesAndCompletes(harness)
  }
  func testCancelEndsAnActiveDownloadOnce() async throws {
    func note(_ text: String) { FileHandle.standardError.write(Data("DIAG \(text)\n".utf8)) }
    do {
      let h = harness!
      let (client, engine, drivers) = try EngineContract.downloadEngine(h)
      note("engine ready")
      let recorder = EventRecorder(client)
      let id = try await drivers.start(client, "Cancel.bin", EngineContract.downloadSize)
      note("started \(id)")
      engine.perform(.cancel, on: id)
      note("cancel performed")
      try await EngineContract.waitUntil(timeout: .seconds(10)) { EngineContract.downloadState(engine, id) == .cancelled }
      note("cancelled")
      try EngineContract.require(engine.download(id)?.endTime != nil, "a cancelled download has an end time")
      note("endTime ok")
      let count = recorder.downloadEvents(for: id).count
      engine.perform(.cancel, on: id)
      engine.perform(.pause, on: id)
      engine.perform(.resume, on: id)
      engine.perform(.cancel, on: DownloadID("unknown"))
      note("repeat commands done")
      try EngineContract.require(recorder.downloadEvents(for: id).count == count && EngineContract.downloadState(engine, id) == .cancelled,
                  "a command that does not apply must change nothing: \(recorder.downloadEvents(for: id))")
      note("unchanged ok")
      if let target = engine.download(id)?.targetPath {
        note("target \(target.lastPathComponent)")
        try EngineContract.require(!FileManager.default.fileExists(atPath: target.path()), "the partial file is deleted")
      }
      note("finished")
    } catch {
      note("ERROR type=\(String(reflecting: type(of: error))) description=\(error)")
      note("ERROR mirror=\(String(reflecting: Mirror(reflecting: error).children.map { "\($0.label ?? "?")=\($0.value)" }))")
      note("ERROR nsdomain=\((error as NSError).domain) code=\((error as NSError).code)")
      throw error
    }
  }
  func testRemoveForgetsADownloadAndKeepsItsFile() async throws {
    try await EngineContract.removeForgetsADownloadAndKeepsItsFile(harness)
  }
  func testPauseHoldsTheBytesUntilResume() async throws {
    try await notApplicable { try await EngineContract.pauseHoldsTheBytesUntilResume(harness) }
  }
  func testInterruptedDownloadRetriesAndReplacesItsRow() async throws {
    try await EngineContract.interruptedDownloadRetriesAndReplacesItsRow(harness)
  }
  func testDangerousDownloadIsHeldUntilDecided() async throws {
    try await notApplicable { try await EngineContract.dangerousDownloadIsHeldUntilDecided(harness) }
  }
  func testSavePreferenceDecidesTheFolder() async throws { try await EngineContract.savePreferenceDecidesTheFolder(harness) }

  /// A suggested name never leaves the download folder, whatever it holds.
  func testASuggestedNameStaysInsideTheFolder() {
    let engine = FakeEngine(downloadFolder: folder)
    for raw in ["../../escape.bin", "/etc/passwd", "a/../../b.bin", "..", ".hidden", ""] {
      let target = engine.uniqueTarget(raw, in: folder)
      XCTAssertEqual(target.standardizedFileURL.deletingLastPathComponent(), folder.standardizedFileURL, raw)
      XCTAssertFalse(target.lastPathComponent.hasPrefix("."), raw)
    }
    XCTAssertEqual(engine.uniqueTarget("../x.bin", in: folder).lastPathComponent, "x.bin")
  }

  /// A rule that needs a driver this engine lacks is skipped, never passed.
  private func notApplicable(_ check: () async throws -> Void) async throws {
    do { try await check() } catch let skip as ContractNotApplicable { throw XCTSkip("\(skip)") }
  }
}

extension EngineHarness {
  /// FakeEngine with downloads into `folder`, served by `server`.
  @MainActor static func fakeDownloads(server: HeldDownloadServer, folder: URL) -> EngineHarness {
    func fake(_ engine: any EngineClient) throws -> FakeEngine {
      guard let engine = engine as? FakeEngine else { throw ContractViolation(description: "needs a FakeEngine") }
      return engine
    }
    return EngineHarness(
      makeEngine: {
        let engine = FakeEngine(downloadFolder: folder)
        engine.downloadOpener = { _ in }
        engine.downloadRevealer = { _ in }
        return engine
      },
      pageURL: { _ in URL(string: "about:blank")! },
      settle: { _, _ in },
      retitle: { _, _, _ in },
      pagesOnTwoHosts: { (URL(string: "about:blank")!, URL(string: "about:blank")!) },
      downloads: DownloadDrivers(
        start: { engine, name, size in
          let fake = try fake(engine)
          let before = Set(fake.downloads.map(\.id))
          fake.startDownload(from: server.url(name: name, size: Int(size)))
          try await EngineContract.waitUntil(timeout: .seconds(10)) { fake.downloads.contains { !before.contains($0.id) } }
          return fake.downloads.first { !before.contains($0.id) }!.id
        },
        advance: { engine, id, bytes in
          guard let name = try fake(engine).download(id)?.url.pathComponents.dropFirst().first else { return }
          server.release(name, Int(bytes))
        },
        canPause: false,
        fail: { engine, id, _ in
          guard let name = try fake(engine).download(id)?.url.pathComponents.dropFirst().first else { return }
          server.fail(name)
        }
      )
    )
  }
}
