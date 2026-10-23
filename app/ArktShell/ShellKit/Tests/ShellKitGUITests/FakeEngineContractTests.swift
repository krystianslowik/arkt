import AppKit
import XCTest
import EngineAPI
@testable import FakeEngineKit
@testable import EngineAPITestSupport

@MainActor
final class FakeEngineContractTests: XCTestCase {
  var harness: EngineHarness!
  var pages: URL!
  var server: LoopbackServer!

  override func setUp() async throws {
    _ = NSApplication.shared
    pages = FileManager.default.temporaryDirectory.appending(path: "arkt-fake-engine-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
    server = try await LoopbackServer.start(routes: Self.routes)
    harness = EngineHarness.fake(pages: pages, port: server.port)
  }

  override func tearDown() async throws {
    server?.stop()
    if let pages { try? FileManager.default.removeItem(at: pages) }
  }

  func testCreatedTabIsListedAndAnnounced() async throws { try await EngineContract.createdTabIsListedAndAnnounced(harness) }
  func testNavigateReportsURLLoadingAndTitle() async throws { try await EngineContract.navigateReportsURLLoadingAndTitle(harness) }
  func testTitleChangedAfterLoadIsReported() async throws { try await EngineContract.titleChangedAfterLoadIsReported(harness) }
  func testContentViewIsStable() async throws { try await EngineContract.contentViewIsStable(harness) }
  func testCloseIsTerminal() async throws { try await EngineContract.closeIsTerminal(harness) }
  func testCloseInsideObserverKeepsOrder() async throws { try await EngineContract.closeInsideObserverKeepsOrder(harness) }
  func testCancelledObservationStopsDelivery() async throws { try await EngineContract.cancelledObservationStopsDelivery(harness) }
  func testDroppedObservationStopsDelivery() async throws { try await EngineContract.droppedObservationStopsDelivery(harness) }
  func testTabIDsKeepCreationOrder() async throws { try await EngineContract.tabIDsKeepCreationOrder(harness) }
  func testHostChangeClearsFavicon() async throws { try await EngineContract.hostChangeClearsFavicon(harness) }

  /// FakeEngine only: a favicon that is not HTTP 200 + image/* is ignored.
  func testRejectsNonImageFavicon() async throws {
    let engine = FakeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "http://127.0.0.1:\(server.port)/bad-icon.html")!)
    try await harness.settle(engine, id)
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertNil(engine.snapshot(of: id)?.faviconData)
    XCTAssertFalse(recorder.events(for: id).contains { if case .faviconChanged(_, .some) = $0 { return true }; return false })
  }

  static let png = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

  static let routes: [String: LoopbackServer.Response] = [
    "/icon.html": .init(mime: "text/html",
                        body: Data("<!doctype html><title>Icon</title><link rel=icon href=/icon.png><p>x".utf8)),
    "/icon.png": .init(mime: "image/png", body: png),
    "/bad-icon.html": .init(mime: "text/html",
                            body: Data("<!doctype html><title>Bad</title><link rel=icon href=/not-an-image><p>x".utf8)),
    "/not-an-image": .init(mime: "text/plain", body: Data("nope".utf8)),
  ]
}

extension EngineHarness {
  /// File pages for most checks (no network); the loopback server only for the favicon rules.
  @MainActor static func fake(pages: URL, port: UInt16) -> EngineHarness {
    EngineHarness(
      makeEngine: { FakeEngine() },
      pageURL: { title in
        let url = pages.appending(path: "\(title).html")
        try "<!doctype html><title>\(title)</title><p>\(title)</p>".write(to: url, atomically: true, encoding: .utf8)
        return url
      },
      settle: { engine, id in
        try await EngineContract.waitUntil(timeout: .seconds(10)) {
          engine.snapshot(of: id).map { !$0.isLoading && !$0.title.isEmpty } ?? true
        }
      },
      retitle: { engine, id, title in
        let fake = try XCTUnwrap(engine as? FakeEngine)
        await fake.runScript("document.title = '\(title)'", in: id)
      },
      pagesOnTwoHosts: {
        (URL(string: "http://127.0.0.1:\(port)/icon.html")!, URL(string: "http://localhost:\(port)/icon.html")!)
      }
    )
  }
}
