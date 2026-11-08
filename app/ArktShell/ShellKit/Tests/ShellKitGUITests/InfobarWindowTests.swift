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

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    controller.close()
    controller = nil
    engine = nil
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
    XCTAssertEqual(panel.panel.frame.maxY, strip.panel.frame.minY, accuracy: 0.5,
                   "the dialog hangs from the page's top edge under the strip, not over it")
    let dim = try XCTUnwrap(panel.pageDim)
    let dimFrame = try XCTUnwrap(dim.window).convertToScreen(dim.convert(dim.bounds, to: nil))
    XCTAssertLessThanOrEqual(dimFrame.maxY, strip.panel.frame.minY + 0.5, "the dim leaves the rows clear")
  }

  // MARK: Panels below the rows (#581)

  private func pageTop(of tab: TabID) throws -> CGFloat {
    let page = try XCTUnwrap(engine.contentView(for: tab))
    return try XCTUnwrap(page.window).convertToScreen(page.convert(page.bounds, to: nil)).maxY
  }

  /// The panel's top sits on the rows' bottom edge (a page dialog, #693) or `anchorInset` below it (a permission
  /// prompt), at the page's top without any rows; it never overlaps a row. A page dialog's dim starts there too.
  private func assertBelowRows(_ panel: DialogPanel, of tab: TabID, rows: Int, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
    let rowsBottom = try pageTop(of: tab) - CGFloat(rows) * InfobarMetrics.rowHeight
    let inset = panel.attachment == .topEdge ? 0 : DialogPanel.anchorInset
    XCTAssertEqual(panel.panel.frame.maxY, rowsBottom - inset, accuracy: 0.5, message, file: file, line: line)
    if let strip = controller.infobarStrips.strip(for: tab) {
      XCTAssertFalse(panel.panel.frame.intersects(strip.panel.frame), "\(message): it overlaps a row", file: file,
                     line: line)
      XCTAssertEqual(strip.panel.frame.minY, rowsBottom, accuracy: 0.5, "\(message): the strip", file: file,
                     line: line)
    }
    if let dim = panel.pageDim {
      let dimFrame = try XCTUnwrap(dim.window).convertToScreen(dim.convert(dim.bounds, to: nil))
      XCTAssertEqual(dimFrame.maxY, rowsBottom, accuracy: 0.5, "\(message): the dim's top", file: file, line: line)
    }
  }

  func testAPageDialogUpFirstMovesBelowZeroOneAndThreeRowsAndBackUp() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.javaScriptDialogs.reduceMotion = { true }
    engine.raiseDialog(in: tab, kind: .alert, message: "Hi")
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    try assertBelowRows(panel, of: tab, rows: 0, "no infobar")

    let firstBar = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "One"))
    try assertBelowRows(panel, of: tab, rows: 1, "an infobar arrived while the dialog was up")

    engine.raiseInfobar(in: tab, message: "Two")
    engine.raiseInfobar(in: tab, message: "Three")
    XCTAssertEqual(controller.infobarStrips.strip(for: tab)?.rows.count, 3)
    try assertBelowRows(panel, of: tab, rows: 3, "three infobars")

    engine.removeInfobar(firstBar)
    try assertBelowRows(panel, of: tab, rows: 2, "one infobar left")
    for infobar in controller.infobarStrips.infobars[tab] ?? [] { engine.removeInfobar(infobar.id) }
    try assertBelowRows(panel, of: tab, rows: 0, "every infobar left: back at the page's top")
  }

  func testAPermissionPanelUpFirstMovesBelowZeroOneAndThreeRows() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.permissionPrompts.reduceMotion = { true }
    controller.permissionPrompts.isOnScreen = { true }
    _ = engine.askPermission(in: tab, kinds: [.notifications])
    let panel = try XCTUnwrap(controller.permissionPrompts.panel(for: tab))
    try assertBelowRows(panel, of: tab, rows: 0, "no infobar")

    engine.raiseInfobar(in: tab, message: "One")
    try assertBelowRows(panel, of: tab, rows: 1, "an infobar arrived while the prompt was up")

    engine.raiseInfobar(in: tab, message: "Two")
    engine.raiseInfobar(in: tab, message: "Three")
    try assertBelowRows(panel, of: tab, rows: 3, "three infobars")
  }

  func testAPanelRaisedUnderThreeRowsStartsBelowThem() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.javaScriptDialogs.reduceMotion = { true }
    for message in ["One", "Two", "Three"] { engine.raiseInfobar(in: tab, message: message) }
    engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?")
    try assertBelowRows(try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab)), of: tab, rows: 3, "three rows")
  }

  func testHTMLFullscreenHidesTheRowsAndLeavingItBringsThemBack() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.javaScriptDialogs.reduceMotion = { true }
    engine.raiseInfobar(in: tab, message: "One")
    engine.raiseInfobar(in: tab, message: "Two")
    engine.raiseDialog(in: tab, kind: .alert, message: "Hi")
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))

    engine.setTabFullscreen(tab, true)
    XCTAssertNil(controller.infobarStrips.strip(for: tab), "no row over a fullscreen element")
    XCTAssertEqual(controller.infobarStrips.height(of: tab), 0)
    XCTAssertEqual(controller.infobarStrips.infobars[tab]?.count, 2, "the tab keeps its list")
    try assertBelowRows(panel, of: tab, rows: 0, "the dialog moves up to the page's top")

    engine.setTabFullscreen(tab, false)
    XCTAssertEqual(controller.infobarStrips.strip(for: tab)?.rows.map(\.infobar.message), ["One", "Two"])
    try assertBelowRows(panel, of: tab, rows: 2, "the dialog goes back below the rows")
  }

  func testAnInfobarArrivingInHTMLFullscreenWaitsForTheTabToLeaveIt() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.setTabFullscreen(tab, true)
    engine.raiseInfobar(in: tab, message: "Later")
    XCTAssertNil(controller.infobarStrips.strip(for: tab))

    engine.setTabFullscreen(tab, false)
    XCTAssertEqual(controller.infobarStrips.strip(for: tab)?.rows.map(\.infobar.message), ["Later"])
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
