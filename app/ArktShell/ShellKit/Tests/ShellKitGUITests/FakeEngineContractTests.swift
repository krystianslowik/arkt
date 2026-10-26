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

  /// Windows the `showPage` driver ordered in, closed after each test.
  static var shownWindows: [NSWindow] = []

  override func tearDown() async throws {
    for window in Self.shownWindows { window.close() }
    Self.shownWindows = []
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
  func testHistoryMovesBackAndForward() async throws { try await EngineContract.historyMovesBackAndForward(harness) }
  func testHistoryAvailabilityIsReported() async throws { try await EngineContract.historyAvailabilityIsReported(harness) }
  func testHistoryEntriesAndOffsetNavigation() async throws { try await EngineContract.historyEntriesAndOffsetNavigation(harness) }
  func testDuplicateTabCopiesURLTitleAndHistory() async throws { try await EngineContract.duplicateTabCopiesURLTitleAndHistory(harness) }
  // Rules 11, 12 and 15 apply; 13, 14 and 16 need engine drivers FakeEngine does not have and are skipped.
  func testWindowIsListedAndAnnounced() async throws { try await EngineContract.windowIsListedAndAnnounced(harness) }
  func testCloseWindowClosesItsTabsThenReportsWindowClosed() async throws {
    try await EngineContract.closeWindowClosesItsTabsThenReportsWindowClosed(harness)
  }
  func testHostCloseRequestClosesTheWindow() async throws { try await EngineContract.hostCloseRequestClosesTheWindow(harness) }
  func testEmptiedWindowReportsLastTabClosed() async throws {
    try await EngineContract.emptiedWindowReportsLastTabClosed(harness)
  }
  func testExtensionWindowCloseReportsExtension() async throws {
    try await notApplicable { try await EngineContract.extensionWindowCloseReportsExtension(harness) }
  }
  func testActivationIsOneTabPerWindow() async throws { try await EngineContract.activationIsOneTabPerWindow(harness) }
  func testWindowlessCreateTabLandsInMostRecentlyActiveWindow() async throws {
    try await EngineContract.windowlessCreateTabLandsInMostRecentlyActiveWindow(harness)
  }
  func testEngineCreatedTabIsAnnounced() async throws {
    try await notApplicable { try await EngineContract.engineCreatedTabIsAnnounced(harness) }
  }
  func testEngineCloseIsTerminal() async throws {
    try await notApplicable { try await EngineContract.engineCloseIsTerminal(harness) }
  }
  func testHeldCloseKeepsTheTabUntilAnswered() async throws {
    try await notApplicable { try await EngineContract.heldCloseKeepsTheTabUntilAnswered(harness) }
  }
  func testSkipUnloadHandlersNeverHolds() async throws {
    try await notApplicable { try await EngineContract.skipUnloadHandlersNeverHolds(harness) }
  }
  func testCancelledWindowCloseKeepsTheWindow() async throws {
    try await notApplicable { try await EngineContract.cancelledWindowCloseKeepsTheWindow(harness) }
  }
  // Rule 17 (#364): mute is engine state; WKWebView has no public audible signal.
  func testMuteIsReportedOnce() async throws { try await EngineContract.muteIsReportedOnce(harness) }
  func testAudibleStateIsReported() async throws {
    try await notApplicable { try await EngineContract.audibleStateIsReported(harness) }
  }
  // Rule 18 (#370): WKWebView's takeSnapshot of a page shown in a window.
  func testPageImageFitsTheCaps() async throws { try await EngineContract.pageImageFitsTheCaps(harness) }
  func testPageImageOfAClosedTabIsNil() async throws { try await EngineContract.pageImageOfAClosedTabIsNil(harness) }
  // Rule 19 (#400): WKWebView dialogs go through its own UI delegate; the FakeEngine raises none.
  func testDialogIsReportedAnsweredAndEndedOnce() async throws {
    try await notApplicable { try await EngineContract.dialogIsReportedAnsweredAndEndedOnce(harness) }
  }
  func testPendingDialogEndsBeforeItsTabCloses() async throws {
    try await notApplicable { try await EngineContract.pendingDialogEndsBeforeItsTabCloses(harness) }
  }
  func testHiddenTabEndsItsConfirmAndPrompt() async throws {
    try await notApplicable { try await EngineContract.hiddenTabEndsItsConfirmAndPrompt(harness) }
  }

  /// FakeEngine only: a tab that is not in a window has nothing to snapshot.
  func testPageImageOfAnUnshownTabIsNil() async throws {
    let engine = FakeEngine()
    let id = engine.createTab(url: try harness.pageURL("Unshown"))
    try await harness.settle(engine, id)
    let image = await engine.pageImage(of: id, .thumbnail)
    XCTAssertNil(image)
  }

  /// Reports a rule without its driver as skipped (not applicable), never as passed.
  private func notApplicable(_ rule: () async throws -> Void) async throws {
    do {
      try await rule()
    } catch let missing as ContractNotApplicable {
      throw XCTSkip(missing.description)
    }
  }

  /// FakeEngine only: closes never hold, so both modes close at once and nothing would hold.
  func testClosesNeverHold() async throws {
    let engine = FakeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: StubWindowHost())
    let id = engine.createTab(url: try harness.pageURL("NeverHeld"), in: window)
    try await harness.settle(engine, id)
    XCTAssertEqual(engine.snapshot(of: id)?.wouldHoldClose, false)
    XCTAssertEqual(engine.snapshot(of: id)?.origin, .client)
    engine.closeTab(id, mode: .honourUnloadHandlers)
    XCTAssertNil(engine.snapshot(of: id))
    XCTAssertEqual(recorder.events(for: id).last, .tabClosed(id, reason: .client))
  }

  /// FakeEngine only: a favicon that is not HTTP 200 + image/* is ignored.
  func testRejectsNonImageFavicon() async throws {
    let engine = FakeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "http://127.0.0.1:\(server.port)/bad-icon.html")!)
    try await harness.settle(engine, id)
    await engine.waitForFaviconFetch(id)
    XCTAssertNil(engine.snapshot(of: id)?.faviconData)
    XCTAssertFalse(recorder.events(for: id).contains { if case .faviconChanged(_, .some) = $0 { return true }; return false })
  }

  /// FakeEngine only: pages see a Safari user agent. No network: a local page reports `navigator.userAgent`
  /// as its title. Without the Safari tokens sites serve WKWebView their legacy pages.
  func testPagesSeeSafariUserAgent() async throws {
    let page = pages.appending(path: "user-agent.html")
    try "<!doctype html><script>document.title = navigator.userAgent</script>"
      .write(to: page, atomically: true, encoding: .utf8)
    let engine = FakeEngine()
    let id = engine.createTab(url: page)
    try await harness.settle(engine, id)
    let userAgent = try XCTUnwrap(engine.snapshot(of: id)?.title)
    XCTAssertTrue(userAgent.hasPrefix("Mozilla/5.0 (Macintosh;"), userAgent)
    XCTAssertTrue(userAgent.contains("AppleWebKit/"), userAgent)
    XCTAssertTrue(userAgent.hasSuffix(" " + SafariUserAgent.applicationName()), userAgent)
    XCTAssertFalse(userAgent.contains("Arkt"), userAgent)
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
      },
      showPage: { engine, id in
        let view = try XCTUnwrap(engine.contentView(for: id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        FakeEngineContractTests.shownWindows.append(window)
        // The fixed 300 ms turn was a guess. This waits only for the state the snapshot call needs: the page
        // loaded and the view mounted in its window. takeSnapshot renders on demand; this is not a paint guarantee.
        try await EngineContract.waitUntil(timeout: .seconds(10)) {
          guard let snapshot = engine.snapshot(of: id) else { return false }
          return !snapshot.isLoading && snapshot.url != nil && view.window === window
            && view.bounds.width > 0 && view.bounds.height > 0
        }
      }
    )
  }
}
