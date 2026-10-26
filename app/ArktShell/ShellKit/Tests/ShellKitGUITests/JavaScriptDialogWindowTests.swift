import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A page's dialog in the shell window (#400): the window's tab events reach the presenter, the panel sits over the
/// tab that is shown and follows the tab switching, and an answer reaches the engine.
@MainActor
final class JavaScriptDialogWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var first: NodeID!
  private var second: NodeID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    first = try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .today(space))
    second = try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine,
                                       sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.javaScriptDialogs.reduceMotion = { true }
  }

  override func tearDown() async throws {
    controller.close()
  }

  func testTheShownTabsDialogGetsAPanelOverTheWindow() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)

    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Delete it?"))

    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    XCTAssertTrue(controller.window?.childWindows?.contains(panel.panel) == true)
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testSwitchingTabsHidesTheDialogWithoutAnsweringAndShowingTheTabBringsItBack() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Saved")
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))

    controller.activate(node: second)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab), "the page is off screen: no panel")
    XCTAssertNotNil(controller.javaScriptDialogs.pending[tab], "still pending: the page may be waiting")
    XCTAssertTrue(engine.dialogAnswers.isEmpty)

    controller.activate(node: first)
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testAClosingWindowTakesItsPanelsDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Bye")
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))

    controller.window?.close()

    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }
}
