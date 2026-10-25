import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import FakeEngineKit
import ShellUI

/// W3-7 part D step 3, FakeEngine build: the page commands WKWebView can run are enabled and run on the window's
/// active tab; the rest (Find, Print, Developer Tools, History, Downloads) stay disabled.
@MainActor
final class FakeEnginePageCommandTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
  }

  func testSupportedCommandsAreEnabledAndTheRestDisabled() throws {
    let engine = FakeEngine()
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let forward = try XCTUnwrap(host.forward)
    XCTAssertFalse(forward.validate(.reload), "no active tab yet")

    let tab = engine.createTab(url: nil, in: window)
    engine.activateTab(tab)

    XCTAssertTrue(forward.validate(.reload))
    XCTAssertTrue(forward.validate(PendingEngineCommands.reloadBypassingCache), "Force Reload")
    XCTAssertTrue(forward.validate(.zoomIn))
    XCTAssertTrue(forward.validate(.zoomOut))
    XCTAssertFalse(forward.validate(.zoomReset), "already at actual size")
    XCTAssertFalse(forward.validate(.back), "no history")
    XCTAssertFalse(forward.validate(.forward))
    for command in [EngineCommand.find, .print, .savePage, .viewSource, .devTools, .history, .downloads,
                    PendingEngineCommands.findNext, PendingEngineCommands.inspect] {
      XCTAssertFalse(forward.validate(command), "\(command)")
    }
  }

  /// FakeEngine's copies of the #272 ids are the menu's (one source of truth until #272 names them in EngineAPI).
  func testFakeEnginesPendingIdsMatchTheMenus() {
    XCTAssertEqual(FakeEngine.stopCommand, PendingEngineCommands.stop)
    XCTAssertEqual(FakeEngine.reloadBypassingCacheCommand, PendingEngineCommands.reloadBypassingCache)
  }

  func testZoomRunsOnTheActiveTab() throws {
    let engine = FakeEngine()
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: nil, in: window)
    engine.activateTab(tab)
    let forward = try XCTUnwrap(host.forward)

    forward.execute(.zoomIn, .currentTab)
    XCTAssertTrue(forward.validate(.zoomReset), "zoomed in")
    forward.execute(.zoomReset, .currentTab)
    XCTAssertFalse(forward.validate(.zoomReset))
    engine.closeWindow(window)
    XCTAssertNil(host.forward)
  }
}
