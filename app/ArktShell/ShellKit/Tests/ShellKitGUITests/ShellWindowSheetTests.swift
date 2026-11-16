import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Window-modal sheets on the shell window start below the current tab's infobar rows (#924): the window's delegate
/// answers `window(_:willPositionSheet:using:)` with the page's top less the strip's height, the card's top in HTML
/// fullscreen or without a page. A real sheet lands there, and one that is up when the rows change stays where it began
/// until the window resizes.
@MainActor
final class ShellWindowSheetTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var node: NodeID!
  /// The rect AppKit passes in on this window: the full width at the content's top, no height.
  private let defaultRect = NSRect(x: 0, y: 800, width: 1200, height: 0)

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    node = try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
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

  private func makeSheet(height: CGFloat) -> NSWindow {
    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: height), styleMask: [.titled],
                         backing: .buffered, defer: true)
    sheet.isReleasedWhenClosed = false
    return sheet
  }

  /// Asks the window's delegate, as AppKit does, so the test also proves the selector reaches the controller.
  private func positionedRect() throws -> NSRect {
    let window = try XCTUnwrap(controller.window)
    let sheet = makeSheet(height: 100)
    defer { sheet.close() }
    return try XCTUnwrap(window.delegate?.window?(window, willPositionSheet: sheet, using: defaultRect),
                         "the shell window's delegate positions sheets")
  }

  /// The top of `tab`'s page in the window's coordinates.
  private func pageTop(of tab: TabID) throws -> CGFloat {
    let page = try XCTUnwrap(engine.contentView(for: tab))
    return page.convert(page.bounds, to: nil).maxY
  }

  private var cardTop: CGFloat {
    let card = controller.rootView.card
    return card.convert(card.bounds, to: nil).maxY
  }

  private func shownTab(rows: Int) throws -> TabID {
    controller.activate(node: node)
    let tab = try XCTUnwrap(controller.currentTab)
    for index in 0..<rows { engine.raiseInfobar(in: tab, message: "Row \(index + 1)") }
    XCTAssertEqual(controller.infobarStrips.strip(for: tab)?.rows.count ?? 0, rows, "fixture: the strip's rows")
    return tab
  }

  private func assertRect(belowRows rows: Int, _ message: String, file: StaticString = #filePath,
                          line: UInt = #line) throws {
    let tab = try shownTab(rows: rows)
    let rect = try positionedRect()
    let expected = try pageTop(of: tab) - CGFloat(rows) * InfobarMetrics.rowHeight
    XCTAssertEqual(rect.maxY, expected, accuracy: 0.5, message, file: file, line: line)
    XCTAssertEqual(rect.height, 0, message, file: file, line: line)
    XCTAssertEqual(rect.minX, defaultRect.minX, "\(message): the horizontal place stays AppKit's", file: file,
                   line: line)
    XCTAssertEqual(rect.width, defaultRect.width, "\(message): the horizontal place stays AppKit's", file: file,
                   line: line)
    if let strip = controller.infobarStrips.strip(for: tab), let window = controller.window {
      let rowsBottom = window.convertFromScreen(strip.panel.frame).minY
      XCTAssertEqual(rect.maxY, rowsBottom, accuracy: 0.5, "\(message): the strip's bottom", file: file, line: line)
    }
  }

  // MARK: The rect the delegate returns

  func testWithoutRowsASheetStartsAtThePagesTop() throws {
    try assertRect(belowRows: 0, "no row")
    XCTAssertLessThan(try positionedRect().maxY, defaultRect.maxY, "the page's top, below the window's top edge")
  }

  func testWithOneRowASheetStartsBelowIt() throws {
    try assertRect(belowRows: 1, "one row")
  }

  func testWithThreeRowsASheetStartsBelowThem() throws {
    try assertRect(belowRows: 3, "three rows")
  }

  func testInHTMLFullscreenASheetStartsAtTheCardsTop() throws {
    let tab = try shownTab(rows: 2)
    engine.setTabFullscreen(tab, true)
    XCTAssertEqual(controller.infobarStrips.infobars[tab]?.count, 2, "fixture: the tab keeps its rows")

    XCTAssertEqual(try positionedRect().maxY, cardTop, accuracy: 0.5)

    engine.setTabFullscreen(tab, false)
    XCTAssertEqual(try positionedRect().maxY, try pageTop(of: tab) - 2 * InfobarMetrics.rowHeight, accuracy: 0.5,
                   "back below the rows once the page leaves fullscreen")
  }

  func testWithoutAPageASheetStartsAtTheCardsTop() throws {
    let empty = ShellWindowController(engine: InMemoryEngine(),
                                      sidebar: ModelSidebarSource(sidebar: SidebarModel.Sidebar(), now: { .now }))
    defer { empty.close() }
    empty.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    empty.showWindow(nil)
    let window = try XCTUnwrap(empty.window)
    XCTAssertNil(empty.currentTab, "fixture: no Space, no page")
    let sheet = makeSheet(height: 100)
    defer { sheet.close() }

    let rect = try XCTUnwrap(window.delegate?.window?(window, willPositionSheet: sheet, using: defaultRect))

    let card = empty.rootView.card
    XCTAssertEqual(rect.maxY, card.convert(card.bounds, to: nil).maxY, accuracy: 0.5)
  }

  // MARK: A real sheet

  /// AppKit centers a sheet in the window and takes the delegate's rect as the highest its top may sit: a sheet tall
  /// enough to reach the rows when centered starts below them.
  func testATallSheetBegunUnderThreeRowsStartsBelowThem() throws {
    let tab = try shownTab(rows: 3)
    let window = try XCTUnwrap(controller.window)
    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))
    let sheet = makeSheet(height: 700)

    window.beginSheet(sheet)
    defer { end(sheet, on: window) }

    XCTAssertEqual(sheet.frame.maxY, strip.panel.frame.minY, accuracy: 0.5, "the sheet's top at the rows' bottom")
    XCTAssertFalse(sheet.frame.intersects(strip.panel.frame), "the sheet covers no row")
  }

  /// Recorded for the results (#924): AppKit places a sheet when it begins and again when the window resizes, not when
  /// the rows change. A sheet begun without rows stays over the rows that arrive; the next resize moves it below them.
  func testASheetUpWhenRowsArriveStaysUntilTheWindowResizes() throws {
    let tab = try shownTab(rows: 0)
    let window = try XCTUnwrap(controller.window)
    let sheet = makeSheet(height: 790)                                  // centered, its top would be above the page
    window.beginSheet(sheet)
    defer { end(sheet, on: window) }
    let begun = sheet.frame
    XCTAssertEqual(begun.maxY, window.convertToScreen(NSRect(x: 0, y: try pageTop(of: tab), width: 0, height: 0)).minY,
                   accuracy: 0.5, "fixture: the sheet starts at the page's top")

    for index in 0..<3 { engine.raiseInfobar(in: tab, message: "Row \(index + 1)") }
    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))
    XCTAssertEqual(sheet.frame, begun, "AppKit does not ask again when the rows change")
    XCTAssertTrue(sheet.frame.intersects(strip.panel.frame), "the sheet that was up covers the new rows")

    var frame = window.frame
    frame.size.height -= 20
    frame.origin.y += 20
    window.setFrame(frame, display: true)

    XCTAssertEqual(sheet.frame.maxY, strip.panel.frame.minY, accuracy: 0.5, "a resize places it below the rows")
  }

  /// Ends the sheet and waits until the window has let it go, so no window outlives the class (#805).
  private func end(_ sheet: NSWindow, on window: NSWindow) {
    window.endSheet(sheet)
    waitUntil("the sheet ended") { window.sheets.isEmpty }
    sheet.close()
  }
}
