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
  /// Holds `/slow.html` in its provisional load until the test opens it (#404).
  var slowGate: LoopbackServer.Gate!

  override func setUp() async throws {
    _ = NSApplication.shared
    pages = FileManager.default.temporaryDirectory.appending(path: "arkt-fake-engine-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
    slowGate = LoopbackServer.Gate()
    var routes = Self.routes
    routes["/slow.html"] = .init(mime: "text/html", body: Data("<!doctype html><title>Slow</title><p>Slow".utf8),
                                 gate: slowGate)
    server = try await LoopbackServer.start(routes: routes)
    harness = EngineHarness.fake(pages: pages, port: server.port)
  }

  /// Windows the `showPage` driver ordered in, closed after each test.
  static var shownWindows: [NSWindow] = []

  override func tearDown() async throws {
    for window in Self.shownWindows { window.close() }
    Self.shownWindows = []
    slowGate?.open()
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
  // Rule 20 (#400): WKWebView asks for camera, microphone and location through its own delegates; the FakeEngine raises
  // none.
  func testPermissionIsReportedAnsweredAndEndedOnce() async throws {
    try await notApplicable { try await EngineContract.permissionIsReportedAnsweredAndEndedOnce(harness) }
  }
  func testPendingPermissionEndsBeforeItsTabCloses() async throws {
    try await notApplicable { try await EngineContract.pendingPermissionEndsBeforeItsTabCloses(harness) }
  }
  func testNavigationEndsItsPermission() async throws {
    try await notApplicable { try await EngineContract.navigationEndsItsPermission(harness) }
  }
  func testHiddenTabEndsItsPermissionAndAsksAgain() async throws {
    try await notApplicable { try await EngineContract.hiddenTabEndsItsPermissionAndAsksAgain(harness) }
  }
  // Rule 21 (#400): WKWebView has no infobars; the FakeEngine shows none.
  func testInfobarIsReportedActedOnAndRemoved() async throws {
    try await notApplicable { try await EngineContract.infobarIsReportedActedOnAndRemoved(harness) }
  }
  func testInfobarsStayWithTheirTabWhileHidden() async throws {
    try await notApplicable { try await EngineContract.infobarsStayWithTheirTabWhileHidden(harness) }
  }
  func testPendingInfobarsEndBeforeTheirTabCloses() async throws {
    try await notApplicable { try await EngineContract.pendingInfobarsEndBeforeTheirTabCloses(harness) }
  }

  // Rules 22 and 23 (#134, #114): WKWebView find is driven by `window.find` and counted in page script; the hovered link
  // comes from a script on `mouseover` and `mouseout`, which the harness dispatches (no synthetic pointer input).
  func testFindCountsMatchesAndMovesTheOrdinal() async throws {
    try await notApplicable { try await EngineContract.findCountsMatchesAndMovesTheOrdinal(harness) }
  }
  func testStopFindingKeepsClearsOrActivatesTheMatch() async throws {
    try await notApplicable { try await EngineContract.stopFindingKeepsClearsOrActivatesTheMatch(harness) }
  }
  func testHoveredLinkReportsItsTargetURL() async throws {
    try await notApplicable { try await EngineContract.hoveredLinkReportsItsTargetURL(harness) }
  }

  /// FakeEngine only: a tab that is not in a window has nothing to snapshot.
  func testPageImageOfAnUnshownTabIsNil() async throws {
    let engine = FakeEngine()
    let id = engine.createTab(url: try harness.pageURL("Unshown"))
    try await harness.settle(engine, id)
    let image = await engine.pageImage(of: id, .thumbnail)
    XCTAssertNil(image)
  }

  /// FakeEngine only (#404, BH-193): the page's selection is reported for Copy URL's text link, and a new document
  /// drops it.
  func testSelectedTextFollowsThePageSelection() async throws {
    let engine = FakeEngine()
    let findPage = try XCTUnwrap(harness.findPage)
    let id = engine.createTab(url: try findPage(1, try harness.pageURL("Target")))
    try await harness.settle(engine, id)
    XCTAssertNil(engine.selectedText(of: id), "nothing is selected yet")

    await engine.runScript("window.getSelection().selectAllChildren(document.querySelector('p'))", in: id)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.selectedText(of: id) != nil }
    XCTAssertEqual(engine.selectedText(of: id), EngineContract.findWord)

    await engine.runScript("window.getSelection().removeAllRanges()", in: id)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.selectedText(of: id) == nil }

    await engine.runScript("window.getSelection().selectAllChildren(document.querySelector('p'))", in: id)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.selectedText(of: id) != nil }

    // A load that does not commit (a 204) leaves the old page, and its selection, in place.
    let recorder = EventRecorder(engine)
    engine.navigate(id, to: try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/no-content")))
    try await EngineContract.waitUntil(timeout: .seconds(10)) {
      recorder.events(for: id).contains(.loadingChanged(id, isLoading: false))
    }
    await engine.runScript("void 0", in: id)
    XCTAssertEqual(engine.selectedText(of: id), EngineContract.findWord, "a cancelled load keeps the selection")

    // While the next page is still provisional the old page is live: its selection changes are its own, and the new
    // document starts with none.
    engine.navigate(id, to: try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/slow.html")))
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.isLoading == true }
    await engine.runScript("window.getSelection().selectAllChildren(document.getElementById('link'))", in: id)
    try await EngineContract.waitUntil(timeout: .seconds(10)) {
      engine.selectedText(of: id) == EngineContract.findLinkText
    }
    slowGate.open()
    try await harness.settle(engine, id)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.title == "Slow" }
    await engine.runScript("void 0", in: id)
    XCTAssertNil(engine.selectedText(of: id), "the old page's selection does not stick to the new page")
    engine.closeTab(id, mode: .skipUnloadHandlers)
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

  /// FakeEngine only (#675): an SVG favicon, which ImageIO cannot decode, reaches the shell as a PNG (the contract
  /// promises PNG or ICO), so the row shows the icon instead of the letter.
  func testAnSVGFaviconArrivesAsPNG() async throws {
    let engine = FakeEngine()
    let id = engine.createTab(url: URL(string: "http://127.0.0.1:\(server.port)/svg-icon.html")!)
    try await harness.settle(engine, id)
    await engine.waitForFaviconFetch(id)
    let data = try XCTUnwrap(engine.snapshot(of: id)?.faviconData)
    XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG bytes")
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    XCTAssertEqual(CGImageSourceGetCount(source), 1)
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
    "/svg-icon.html": .init(mime: "text/html",
                            body: Data("<!doctype html><title>SVG</title><link rel=icon href=/icon.svg><p>x".utf8)),
    "/icon.svg": .init(mime: "image/svg+xml", body: Data(
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><rect width='16' height='16' fill='#2a7'/></svg>".utf8)),
    "/no-content": .init(status: 204, mime: "text/plain", body: Data()),
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
      },
      findPage: { occurrences, link in
        let url = pages.appending(path: "Find\(occurrences).html")
        let words = Array(repeating: EngineContract.findWord, count: occurrences).joined(separator: " filler ")
        try ("<!doctype html><title>Find</title><body><p>\(words)</p>"
          + "<p><a id=link href=\"\(link.absoluteString)\">\(EngineContract.findLinkText)</a></p></body>")
          .write(to: url, atomically: true, encoding: .utf8)
        return url
      },
      selectedText: { engine, id in
        let fake = try XCTUnwrap(engine as? FakeEngine)
        return await fake.scriptString("window.getSelection().toString()", in: id) ?? ""
      },
      hoverLink: { engine, id in
        let fake = try XCTUnwrap(engine as? FakeEngine)
        await fake.runScript(
          "document.getElementById('link').dispatchEvent(new MouseEvent('mouseover', { bubbles: true }))", in: id)
      },
      leaveLink: { engine, id in
        let fake = try XCTUnwrap(engine as? FakeEngine)
        await fake.runScript(
          "document.getElementById('link').dispatchEvent(new MouseEvent('mouseout', { bubbles: true, relatedTarget: document.body }))",
          in: id)
      }
    )
  }
}
