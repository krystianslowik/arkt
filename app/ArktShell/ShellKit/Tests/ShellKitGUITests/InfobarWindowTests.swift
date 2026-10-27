import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A tab's infobars in the shell window (#400): the window's tab events reach the presenter, the strip sits over the tab
/// that is shown and follows the tab switching without losing either tab's list, a dialog points below it, an action
/// reaches the engine, and closing the window leaves nothing behind.
@MainActor
final class InfobarWindowTests: XCTestCase {
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
    controller.infobarStrips.reduceMotion = { true }
  }

  override func tearDown() async throws {
    controller.close()
  }

  func testTheShownTabsInfobarGetsAStripOverTheWindowAndAnActionReachesTheEngine() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)

    let id = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Hello"))

    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))
    XCTAssertTrue(controller.window?.childWindows?.contains(strip.panel) == true)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let anchor = try XCTUnwrap(page.window).convertToScreen(page.convert(page.bounds, to: nil))
    XCTAssertEqual(strip.panel.frame.maxY, anchor.maxY)
    XCTAssertEqual(strip.panel.frame.width, anchor.width)
    strip.rows[0].okButton?.performClick(nil)
    XCTAssertEqual(engine.infobarActions.map(\.id), [id])
    XCTAssertNil(controller.infobarStrips.strip(for: tab), "the engine removed it")
  }

  func testEachTabKeepsItsOwnListAcrossSwitches() throws {
    controller.activate(node: first)
    let firstTab = try XCTUnwrap(controller.currentTab)
    controller.activate(node: second)
    let secondTab = try XCTUnwrap(controller.currentTab)
    engine.raiseInfobar(in: firstTab, message: "For A")
    engine.raiseInfobar(in: secondTab, message: "For B")
    XCTAssertNil(controller.infobarStrips.strip(for: firstTab), "A is not shown")
    XCTAssertEqual(controller.infobarStrips.strip(for: secondTab)?.rows.map(\.infobar.message), ["For B"])

    controller.activate(node: first)
    XCTAssertEqual(controller.infobarStrips.strip(for: firstTab)?.rows.map(\.infobar.message), ["For A"])
    XCTAssertNil(controller.infobarStrips.strip(for: secondTab))

    controller.activate(node: second)
    XCTAssertEqual(controller.infobarStrips.strip(for: secondTab)?.rows.map(\.infobar.message), ["For B"])
  }

  func testAPageDialogPointsBelowTheStrip() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.javaScriptDialogs.reduceMotion = { true }
    engine.raiseInfobar(in: tab, message: "Hello")
    engine.raiseDialog(in: tab, kind: .alert, message: "Hi")

    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    XCTAssertLessThanOrEqual(panel.panel.frame.maxY, strip.panel.frame.minY - DialogPanel.anchorInset + 0.5,
                             "the dialog starts 12 pt under the strip, not over it")
  }

  func testAClosingWindowTakesItsStripsDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.raiseInfobar(in: tab, message: "Hello")
    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))

    controller.window?.close()

    XCTAssertNil(strip.panel.parent)
    XCTAssertNil(controller.infobarStrips.strip(for: tab))
  }
}
