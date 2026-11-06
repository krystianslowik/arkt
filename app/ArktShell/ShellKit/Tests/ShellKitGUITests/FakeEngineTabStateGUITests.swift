import AppKit
import XCTest
import EngineAPI
@testable import FakeEngineKit
@testable import EngineAPITestSupport

/// FakeEngine's tab state against real WebKit loads (#576): a web content process that really exits is a crash and a
/// reload recovers it; rule 25 of the shared contract. Real loads and a killed process need the GUI lane, so these
/// stay out of the required non-GUI targets (InMemoryEngine runs rule 25 there). Skipped when WebKit no longer
/// publishes the web content process id.
@MainActor
final class FakeEngineTabStateGUITests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
  }

  /// Pages as data URLs (no files, no network) whose title is `title`; the crash driver kills the page's process.
  static let harness = EngineHarness(
    makeEngine: { FakeEngine() },
    pageURL: { title in
      try XCTUnwrap(URL(string: "data:text/html,%3Ctitle%3E\(title)%3C/title%3E%3Cp%3E\(title)%3C/p%3E"))
    },
    settle: { engine, id in
      try await EngineContract.waitUntil(timeout: .seconds(10)) {
        engine.snapshot(of: id).map { !$0.isLoading && !$0.title.isEmpty } ?? true
      }
    },
    retitle: { _, _, _ in },
    pagesOnTwoHosts: { (URL(string: "about:blank")!, URL(string: "about:blank")!) },
    crashTab: { engine, id in
      let fake = try XCTUnwrap(engine as? FakeEngine)
      let pid = try XCTUnwrap(fake.webContentProcessIdentifier(of: id), "the page has a web content process")
      XCTAssertEqual(kill(pid, SIGKILL), 0)
    }
  )

  private func requireProcessIdentifier() throws {
    guard FakeEngine.canReadWebContentProcessIdentifier else {
      throw XCTSkip("this WebKit does not publish the web content process id")
    }
  }

  func testWebContentProcessExitIsACrashAndReloadRecovers() async throws {
    try requireProcessIdentifier()
    let h = Self.harness
    let engine = FakeEngine()
    let tab = engine.createTab(url: try h.pageURL("Crash"), in: engine.createWindow(host: StubWindowHost()))
    try await h.settle(engine, tab)
    let recorder = EventRecorder(engine)

    let crash = try XCTUnwrap(h.crashTab)
    try await crash(engine, tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash != nil }
    XCTAssertEqual(engine.snapshot(of: tab)?.crash, .crashed)

    engine.reload(tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash == nil }
    try await h.settle(engine, tab)

    // The recovery comes with the reload's commit: after the crash, possibly after the reload's loadingChanged(true),
    // and before its loadingChanged(false).
    let events = recorder.events(for: tab)
    let crashed = try XCTUnwrap(events.firstIndex(of: .tabCrashed(tab, .crashed)))
    let recovered = try XCTUnwrap(events.firstIndex(of: .tabRecovered(tab)))
    let finished = try XCTUnwrap(events.lastIndex(of: .loadingChanged(tab, isLoading: false)))
    XCTAssertTrue(crashed < recovered && recovered < finished, "\(events)")
    XCTAssertEqual(events.filter { $0 == .tabRecovered(tab) }.count, 1)
    XCTAssertEqual(engine.snapshot(of: tab)?.title, "Crash")
    engine.closeTab(tab)
  }

  // Rule 25 of the shared contract.
  func testZoomStepIsReportedOnceAndNothingAtTheEnds() async throws {
    try await EngineContract.zoomStepIsReportedOnceAndNothingAtTheEnds(Self.harness)
  }

  func testCrashedTabStaysListed() async throws {
    try requireProcessIdentifier()
    try await EngineContract.crashedTabStaysListed(Self.harness)
  }

  func testReloadRecoversACrashedTabOnce() async throws {
    try requireProcessIdentifier()
    try await EngineContract.reloadRecoversACrashedTabOnce(Self.harness)
  }
}
