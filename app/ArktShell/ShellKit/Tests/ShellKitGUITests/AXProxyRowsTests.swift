import AppKit
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

/// The proxy-row accessibility bridge (`AXProxyRows`) as an out-of-process client reaches it: through the legacy
/// `accessibilityAttributeValue` / `accessibilityArrayAttribute*` entry points, which is how the accessibility server
/// queries a table. The test methods are marked deprecated because they call those deprecated entry points on
/// purpose.
@MainActor
final class AXProxyRowsTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// A model of synthetic titles. Each row view is a plain label; the proxies never read it.
  @MainActor
  private final class Source: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var titles: [String]
    init(_ titles: [String]) { self.titles = titles }
    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      NSTextField(labelWithString: titles[row])
    }
  }

  private struct Fixture {
    let window: NSWindow
    let table: CommandBarTableView
    let source: Source
  }

  private static let rowHeight: CGFloat = 50

  /// `rowCount` rows of 50 pt in a 200 pt tall scroll view, so only the first few rows can be on screen.
  private func makeFixture(rowCount: Int) -> Fixture {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 200), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let table = CommandBarTableView(frame: .zero)
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("synthetic"))
    column.width = 400
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = Self.rowHeight
    table.intercellSpacing = .zero
    let source = Source((0..<rowCount).map { "Synthetic Row \($0)" })
    table.dataSource = source
    table.delegate = source
    table.axProxyRows.content = { [source] row in
      guard source.titles.indices.contains(row) else { return nil }
      return AXProxyRowContent(identifier: "test.row", label: source.titles[row], value: "Caption \(row)")
    }
    scroll.documentView = table
    window.contentView = scroll
    table.reloadData()
    scroll.layoutSubtreeIfNeeded()
    return Fixture(window: window, table: table, source: source)
  }

  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  private func legacyRows(_ table: NSTableView, _ attribute: NSAccessibility.Attribute = .children,
                          file: StaticString = #filePath, line: UInt = #line) throws -> [AXProxyRow] {
    let value = try XCTUnwrap(table.accessibilityAttributeValue(attribute) as? [Any], file: file, line: line)
    return try value.map { try XCTUnwrap($0 as? AXProxyRow, file: file, line: line) }
  }

  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  func testRowsWithoutRowViewsReportTheModelsLabelAndValue() throws {
    let fixture = makeFixture(rowCount: 40)
    let table = fixture.table
    XCTAssertNil(table.rowView(atRow: 39, makeIfNecessary: false), "precondition: row 39 is beyond the visible rows")

    let rows = try legacyRows(table)
    XCTAssertEqual(rows.count, 40)
    XCTAssertEqual(table.accessibilityArrayAttributeCount(.children), 40)
    XCTAssertEqual((table.accessibilityAttributeValue(.rowCount) as? NSNumber)?.intValue, 40)
    for (index, row) in rows.enumerated() {
      XCTAssertEqual(row.accessibilityRole(), .row)
      XCTAssertEqual(row.accessibilityIdentifier(), "test.row")
      XCTAssertEqual(row.accessibilityLabel(), "Synthetic Row \(index)")
      XCTAssertEqual(row.accessibilityValue() as? String, "Caption \(index)")
      XCTAssertEqual(row.accessibilityIndex(), index)
      XCTAssertTrue(row.isAccessibilityElement())
    }
    for index in [20, 30, 39] {
      _ = rows[index].accessibilityFrame()
      XCTAssertNil(table.rowView(atRow: index, makeIfNecessary: false),
                   "answering for row \(index) builds no row view")
    }
    fixture.window.close()
  }

  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  func testFramesAreScreenRectsOfTheRowAndFollowAMovedWindow() throws {
    let fixture = makeFixture(rowCount: 40)
    let table = fixture.table
    let rows = try legacyRows(table)
    func expected(_ row: Int) -> NSRect {
      fixture.window.convertToScreen(table.convert(table.rect(ofRow: row), to: nil))
    }

    for index in [0, 30] {
      XCTAssertEqual(rows[index].accessibilityFrame(), expected(index))
      XCTAssertEqual(rows[index].accessibilityFrame().height, Self.rowHeight, accuracy: 0.5)
    }
    let before = rows[30].accessibilityFrame()
    let origin = fixture.window.frame.origin
    fixture.window.setFrameOrigin(NSPoint(x: origin.x + 120, y: origin.y + 80))

    let after = rows[30].accessibilityFrame()
    XCTAssertEqual(after.minX - before.minX, 120, accuracy: 0.5)
    XCTAssertEqual(after.minY - before.minY, 80, accuracy: 0.5)
    XCTAssertEqual(after, expected(30))
    fixture.window.close()
  }

  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  func testReloadDataReplacesTheProxiesWithTheNewRows() throws {
    let fixture = makeFixture(rowCount: 5)
    let table = fixture.table
    let old = try legacyRows(table)
    XCTAssertEqual(old.count, 5)
    XCTAssertTrue(try legacyRows(table)[0] === old[0], "unchanged rows keep their elements between queries")

    fixture.source.titles = ["Synthetic Other A", "Synthetic Other B", "Synthetic Other C", "Synthetic Other D",
                             "Synthetic Other E"]
    table.reloadData()
    let sameCount = try legacyRows(table)
    XCTAssertEqual(sameCount.map { $0.accessibilityLabel() }, fixture.source.titles)
    XCTAssertFalse(sameCount[0] === old[0], "a reload publishes fresh elements")

    fixture.source.titles = ["Synthetic Only"]
    table.reloadData()
    let shrunk = try legacyRows(table)
    XCTAssertEqual(shrunk.map { $0.accessibilityLabel() }, ["Synthetic Only"])
    XCTAssertNil(old[3].accessibilityLabel(), "an element for a row that is gone reports nothing")
    fixture.window.close()
  }

  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  func testChildrenAreFlatLeavesParentedToTheTableAndFollowSelection() throws {
    let fixture = makeFixture(rowCount: 40)
    let table = fixture.table
    let rows = try legacyRows(table)
    for row in rows {
      XCTAssertEqual(row.accessibilityChildren()?.count, 0, "a proxy row has no children")
      XCTAssertTrue((row.accessibilityParent() as? NSTableView) === table)
    }
    XCTAssertTrue(try legacyRows(table, .rows).elementsEqual(rows) { $0 === $1 })
    XCTAssertTrue(try legacyRows(table, NSAccessibility.Attribute(rawValue: "AXChildrenInNavigationOrder"))
      .elementsEqual(rows) { $0 === $1 })
    XCTAssertTrue((table.accessibilityChildren() ?? []).elementsEqual(rows) { $0 as AnyObject === $1 })

    let tail = table.accessibilityArrayAttributeValues(.children, index: 38, maxCount: 10)
    XCTAssertEqual(tail.count, 2)
    XCTAssertTrue((tail.first as? AXProxyRow) === rows[38])
    XCTAssertTrue(table.accessibilityArrayAttributeValues(.children, index: 40, maxCount: 1).isEmpty)

    table.selectRowIndexes([30], byExtendingSelection: false)
    XCTAssertTrue(try legacyRows(table, .selectedRows).elementsEqual([rows[30]]) { $0 === $1 })
    XCTAssertEqual(rows.map { $0.isAccessibilitySelected() }, (0..<40).map { $0 == 30 })
    table.selectRowIndexes([2], byExtendingSelection: false)
    XCTAssertTrue(rows[2].isAccessibilitySelected())
    XCTAssertFalse(rows[30].isAccessibilitySelected())
    fixture.window.close()
  }

  /// The real command bar: labels come from its results, frames follow the panel, a new query republishes.
  @available(macOS, deprecated: 10.10, message: "Calls the legacy accessibility entry points")
  func testCommandBarRowsFollowResultsAndThePanel() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample(),
                                           toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    let bar = controller.commandBar
    bar.prewarm()
    controller.newTab(nil)
    bar.setQueryForTesting("example.com")
    let table = bar.barView.table

    let rows = try legacyRows(table)
    XCTAssertGreaterThanOrEqual(rows.count, 2)
    XCTAssertEqual(rows.map { $0.accessibilityLabel() }, bar.results.map(\.title))
    XCTAssertEqual(rows.map { $0.accessibilityValue() as? String }, bar.results.map(\.accessibilityCaption))
    XCTAssertEqual(rows.map { $0.accessibilityIdentifier() }, Array(repeating: AXID.CommandBar.row, count: rows.count))

    let before = rows[0].accessibilityFrame()
    let origin = bar.panel.frame.origin
    bar.panel.setFrameOrigin(NSPoint(x: origin.x + 40, y: origin.y - 30))
    let after = rows[0].accessibilityFrame()
    XCTAssertEqual(after.minX - before.minX, 40, accuracy: 0.5)
    XCTAssertEqual(after.minY - before.minY, -30, accuracy: 0.5)

    bar.setQueryForTesting("example.org/synthetic")
    let requeried = try legacyRows(table)
    XCTAssertEqual(requeried.map { $0.accessibilityLabel() }, bar.results.map(\.title))
    XCTAssertEqual(requeried.first?.accessibilityLabel(), "example.org/synthetic")

    bar.hide(restoreFocus: false)
    controller.close()
  }
}
