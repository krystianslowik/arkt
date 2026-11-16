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
    // Fits below the rows, and centered its top would be over them, whatever size the screen lets the window keep.
    let sheet = makeSheet(height: try pageTop(of: tab) - 3 * InfobarMetrics.rowHeight - 40)

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
    let sheet = makeSheet(height: try pageTop(of: tab) - 3 * InfobarMetrics.rowHeight - 60)   // fits after the resize
    window.beginSheet(sheet)
    defer { end(sheet, on: window) }
    let begun = sheet.frame
    XCTAssertLessThanOrEqual(begun.maxY, window.convertToScreen(NSRect(x: 0, y: try pageTop(of: tab), width: 0,
                                                                      height: 0)).minY + 0.5,
                             "fixture: the sheet starts below the page's top")

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

  // MARK: Every page at the top of the content, and the window's bottom (#947 review)

  /// A sheet the cap would push past the window's bottom starts higher, as low as it can while it fits.
  func testASheetTooTallForTheCapStaysInsideTheWindow() throws {
    let tab = try shownTab(rows: 3)
    let window = try XCTUnwrap(controller.window)
    let sheet = makeSheet(height: try pageTop(of: tab) - 3 * InfobarMetrics.rowHeight + 60)

    window.beginSheet(sheet)
    defer { end(sheet, on: window) }

    XCTAssertLessThan(try pageTop(of: tab) - 3 * InfobarMetrics.rowHeight, sheet.frame.height,
                      "fixture: below the rows it would not fit")
    XCTAssertGreaterThanOrEqual(sheet.frame.minY, window.frame.minY - 0.5, "the sheet's bottom inside the window")
    XCTAssertLessThanOrEqual(sheet.frame.maxY, window.frame.maxY + 0.5)
  }

  /// The rect AppKit itself passes (recorded from a real `beginSheet`): the cap is never above it.
  func testTheCapIsNeverAboveTheRectAppKitPasses() throws {
    let tab = try shownTab(rows: 1)
    let window = try XCTUnwrap(controller.window)
    let recorder = RecordingSheetDelegate(forwardingTo: controller)
    window.delegate = recorder
    defer { window.delegate = controller }
    let sheet = makeSheet(height: 100)
    window.beginSheet(sheet)
    defer { end(sheet, on: window) }
    let appKitRect = try XCTUnwrap(recorder.passed.first, "AppKit asked the delegate")
    let returned = try XCTUnwrap(recorder.returned.first)

    XCTAssertLessThanOrEqual(returned.maxY, appKitRect.maxY)
    XCTAssertEqual(returned.maxY, try pageTop(of: tab) - InfobarMetrics.rowHeight, accuracy: 0.5)
    XCTAssertEqual(returned.minX, appKitRect.minX)
    XCTAssertEqual(returned.width, appKitRect.width)
  }

  private func makeSplitWindow(orientation: SidebarModel.Orientation, focus: Int) throws -> (ShellWindowController,
                                                                                      InMemoryEngine, [TabID]) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: orientation, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["a", "b"].map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: $0, in: .split(split))
    }
    let engine = InMemoryEngine()
    let shell = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    shell.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    shell.showWindow(nil)
    shell.infobarStrips.reduceMotion = { true }
    shell.activate(node: panes[focus])
    shell.window?.contentView?.layoutSubtreeIfNeeded()
    let tabs = try panes.map { try XCTUnwrap(shell.engineTab(of: $0)) }
    XCTAssertEqual(shell.currentTab, tabs[focus], "fixture: the focused pane")
    return (shell, engine, tabs)
  }

  /// Stacked panes with the lower one focused: the sheet starts at the top pane's page, not mid-window, and stays
  /// inside the window.
  func testInAStackedSplitASheetStartsAtTheTopPaneNotTheFocusedLowerOne() throws {
    let (shell, engine, tabs) = try makeSplitWindow(orientation: .vertical, focus: 1)
    defer { shell.close() }
    let window = try XCTUnwrap(shell.window)
    let top = try XCTUnwrap(engine.contentView(for: tabs[0])).convert(
      try XCTUnwrap(engine.contentView(for: tabs[0])).bounds, to: nil).maxY
    let lower = try XCTUnwrap(engine.contentView(for: tabs[1])).convert(
      try XCTUnwrap(engine.contentView(for: tabs[1])).bounds, to: nil).maxY
    XCTAssertLessThan(lower, top - 100, "fixture: the panes are stacked")

    let probe = makeSheet(height: 100)
    defer { probe.close() }
    let rect = try XCTUnwrap(window.delegate?.window?(window, willPositionSheet: probe, using: defaultRect))
    XCTAssertEqual(rect.maxY, top, accuracy: 0.5, "the top pane's page top")

    let sheet = makeSheet(height: top - 40)                             // taller than the lower pane's top
    window.beginSheet(sheet)
    defer { end(sheet, on: window) }
    XCTAssertGreaterThanOrEqual(sheet.frame.minY, window.frame.minY - 0.5, "the sheet's bottom inside the window")
  }

  /// Side by side, the focused pane without rows and the other with 3: the cap is below the other pane's rows.
  func testSideBySideTheCapIsBelowTheTallestStripOfThePanes() throws {
    let (shell, engine, tabs) = try makeSplitWindow(orientation: .horizontal, focus: 0)
    defer { shell.close() }
    let window = try XCTUnwrap(shell.window)
    for index in 0..<3 { engine.raiseInfobar(in: tabs[1], message: "Row \(index + 1)") }
    let strip = try XCTUnwrap(shell.infobarStrips.strip(for: tabs[1]))

    let probe = makeSheet(height: 100)
    defer { probe.close() }
    let rect = try XCTUnwrap(window.delegate?.window?(window, willPositionSheet: probe, using: defaultRect))
    XCTAssertEqual(rect.maxY, window.convertFromScreen(strip.panel.frame).minY, accuracy: 0.5,
                   "below the unfocused pane's rows")

    let sheet = makeSheet(height: rect.maxY - 40)
    window.beginSheet(sheet)
    defer { end(sheet, on: window) }
    XCTAssertFalse(sheet.frame.intersects(strip.panel.frame), "the sheet covers none of the other pane's rows")
  }

  /// Ends the sheet and waits until the window has let it go, so no window outlives the class (#805).
  private func end(_ sheet: NSWindow, on window: NSWindow) {
    window.endSheet(sheet)
    waitUntil("the sheet ended") { window.sheets.isEmpty }
    sheet.close()
  }
}

/// Stands in as the window's delegate to record the rect AppKit passes and what the shell window's controller returns.
@MainActor
private final class RecordingSheetDelegate: NSObject, NSWindowDelegate {
  let target: ShellWindowController
  var passed: [NSRect] = []
  var returned: [NSRect] = []

  init(forwardingTo target: ShellWindowController) { self.target = target }

  func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
    passed.append(rect)
    let result = target.window(window, willPositionSheet: sheet, using: rect)
    returned.append(result)
    return result
  }
}
