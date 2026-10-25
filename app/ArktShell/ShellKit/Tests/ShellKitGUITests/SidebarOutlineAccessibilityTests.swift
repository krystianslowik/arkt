import AppKit
import XCTest
@testable import ShellUI

/// The sidebar outline's rows as an out-of-process accessibility client reaches them (#269): the Space page lists the
/// proxy outline (`sidebar.outline`, an `AXProxyTable`) in place of the scroll view, and the server reads it and its
/// `AXProxyRow`s through their protocol getters. In process the legacy `accessibilityAttributeValue` entry points
/// answer nil for these elements, so the tests read the getters; the out-of-process proof is the UI tests job.
@MainActor
final class SidebarOutlineAccessibilityTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    windows.forEach { $0.close() }
    windows = []
  }

  @MainActor
  private struct Fixture {
    let sidebar: StubSidebar
    let controller: SidebarController
    let page: SpacePageView
    let space: SpaceID
    var outline: SidebarOutlineView { page.outlineView }
    var outlineController: SidebarOutlineController { page.outlineController }
    var element: AXProxyTable { page.outlineView.axProxyRows.element }
  }

  /// The sidebar column alone in an 800 pt tall window, showing the first sample Space ("Personal").
  private func makeFixture(_ sidebar: StubSidebar = .sample()) throws -> Fixture {
    let controller = SidebarController(source: sidebar)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    window.setContentSize(NSSize(width: 190, height: 800))
    controller.view.layoutSubtreeIfNeeded()
    windows.append(window)
    let page = try XCTUnwrap(controller.currentPage)
    return Fixture(sidebar: sidebar, controller: controller, page: page, space: sidebar.spaceOrder[0])
  }

  private enum RowList { case children, rows, visibleRows, selectedRows }

  /// The proxy outline's rows as one of its getters lists them.
  private func proxyRows(_ element: AXProxyTable, _ list: RowList = .children,
                         file: StaticString = #filePath, line: UInt = #line) throws -> [AXProxyRow] {
    let value: [Any]?
    switch list {
    case .children: value = element.accessibilityChildren()
    case .rows: value = element.accessibilityRows()
    case .visibleRows: value = element.accessibilityVisibleRows()
    case .selectedRows: value = element.accessibilitySelectedRows()
    }
    let all = try XCTUnwrap(value, file: file, line: line)
    return try all.map { try XCTUnwrap($0 as? AXProxyRow, "not a proxy row: \($0)", file: file, line: line) }
  }

  private struct Shown: Equatable {
    var identifier: String?
    var label: String?
    var level: Int?
  }

  private func shown(_ rows: [AXProxyRow]) -> [Shown] {
    rows.map {
      Shown(identifier: $0.accessibilityIdentifier(),
            label: $0.accessibilityLabel().flatMap { $0.isEmpty ? nil : $0 },
            level: $0.accessibilityDisclosureLevel())
    }
  }

  private static let pinned = AXID.Sidebar.rowPinned
  private static let today = AXID.Sidebar.rowToday

  /// The sample's first Space with the Trips folder expanded.
  private static let personalExpanded = [
    Shown(identifier: pinned, label: "Family Calendar", level: 0),
    Shown(identifier: pinned, label: "Inbox", level: 0),
    Shown(identifier: AXID.Sidebar.rowFolder, label: "Trips", level: 0),
    Shown(identifier: pinned, label: "Lisbon Itinerary", level: 1),
    Shown(identifier: pinned, label: "Flight Options", level: 1),
    Shown(identifier: AXID.Sidebar.divider, label: nil, level: 0),
    Shown(identifier: today, label: "Weekend Recipes", level: 0),
    Shown(identifier: today, label: "Reading List", level: 0),
    Shown(identifier: today, label: "Swift Blog", level: 0),
  ]

  private func folder(_ fixture: Fixture) throws -> NodeID {
    try XCTUnwrap(fixture.sidebar.children(of: .pinned(fixture.space)).first {
      if case .folder? = fixture.sidebar.node($0) { return true } else { return false }
    })
  }

  // MARK: The proxy outline

  func testThePageListsTheProxyOutlineInPlaceOfTheScrollView() throws {
    let fixture = try makeFixture()
    let page = fixture.page
    let element = fixture.element
    let children = try XCTUnwrap(page.accessibilityChildren())
    XCTAssertEqual(children.filter { ($0 as? AXProxyTable) === element }.count, 1, "the page lists the proxy outline")
    XCTAssertFalse(children.contains { ($0 as? NSView)?.isDescendant(of: page.scrollView) ?? false },
                   "and not the scroll view or the real outline")
    XCTAssertEqual(element.accessibilityRole(), .outline)
    XCTAssertEqual(element.accessibilityIdentifier(), AXID.Sidebar.outline)
    XCTAssertTrue((element.accessibilityParent() as? SpacePageView) === page)
    let window = try XCTUnwrap(page.window)
    XCTAssertEqual(element.accessibilityFrame(),
                   window.convertToScreen(page.scrollView.convert(page.scrollView.bounds, to: nil)))
  }

  // MARK: Rows

  func testRowsAreTheDisplayedItemsInOrderWithRolesAndDisclosure() throws {
    let fixture = try makeFixture()
    let element = fixture.element
    let rows = try proxyRows(element)
    XCTAssertEqual(shown(rows), Self.personalExpanded)
    XCTAssertEqual(rows.count, fixture.outline.numberOfRows)
    XCTAssertTrue(try proxyRows(element, .rows).elementsEqual(rows) { $0 === $1 })

    let dividerRow = fixture.outlineController.dividerRow
    for (index, row) in rows.enumerated() {
      XCTAssertEqual(row.accessibilityIndex(), index)
      XCTAssertTrue((row.accessibilityParent() as? AXProxyTable) === element)
      if index == dividerRow {
        XCTAssertEqual(row.accessibilityRole(), .splitter, "the divider is not counted as a row")
        XCTAssertNil(row.accessibilitySubrole())
      } else {
        XCTAssertEqual(row.accessibilityRole(), .row)
        XCTAssertEqual(row.accessibilitySubrole(), .outlineRow, "XCUITest lists these as outlineRows")
      }
    }
    let folderRow = fixture.outlineController.row(for: try folder(fixture))
    XCTAssertEqual(rows[folderRow].isAccessibilityDisclosed(), true, "the folder starts expanded")
    XCTAssertEqual(rows[0].isAccessibilityDisclosed(), false, "a tab row discloses nothing")

    let firstTab = fixture.sidebar.children(of: .pinned(fixture.space))[0]
    let closeName = try XCTUnwrap(RowCloseAction.resolve(firstTab, in: fixture.sidebar)?.accessibilityName)
    XCTAssertEqual(rows[0].accessibilityCustomActions()?.map(\.name), [closeName], "the row's VoiceOver close")
    XCTAssertEqual(rows[folderRow].accessibilityCustomActions()?.count ?? 0, 0, "a folder has no close")
  }

  func testCustomActionRunsTheRowsClose() throws {
    let fixture = try makeFixture()
    let today = fixture.sidebar.children(of: .today(fixture.space))
    var closed: [NodeID] = []
    fixture.outlineController.onClose = { closed.append($0) }
    let rows = try proxyRows(fixture.element)
    let row = rows[fixture.outlineController.row(for: today[0])]
    let action = try XCTUnwrap(row.accessibilityCustomActions()?.first)
    XCTAssertTrue(action.performForTesting())
    XCTAssertEqual(closed, [today[0]], "performing the action closes the row's tab")
  }

  func testRowsFollowCollapseAndExpand() throws {
    let fixture = try makeFixture()
    let element = fixture.element
    let folderID = try folder(fixture)
    let before = try proxyRows(element)

    fixture.outlineController.handleClick(row: fixture.outlineController.row(for: folderID), modifiers: [])
    let collapsed = try proxyRows(element)
    XCTAssertEqual(shown(collapsed), Self.personalExpanded.filter { $0.level == 0 })
    XCTAssertEqual(collapsed[2].isAccessibilityDisclosed(), false, "the folder reports collapsed")
    XCTAssertFalse(collapsed[3] === before[3], "a collapse publishes fresh elements")

    fixture.outlineController.handleClick(row: fixture.outlineController.row(for: folderID), modifiers: [])
    let expanded = try proxyRows(element)
    XCTAssertEqual(shown(expanded), Self.personalExpanded)
    XCTAssertEqual(expanded[2].isAccessibilityDisclosed(), true)
  }

  func testRowsFollowModelChanges() throws {
    let fixture = try makeFixture()
    let element = fixture.element
    let sidebar = fixture.sidebar
    _ = try proxyRows(element)

    let added = sidebar.addTab(url: URL(string: "https://example.com/synthetic-added")!, title: "Synthetic Added",
                               in: .today(fixture.space))
    XCTAssertEqual(shown(try proxyRows(element)),
                   Self.personalExpanded + [Shown(identifier: Self.today, label: "Synthetic Added", level: 0)])

    sidebar.updateTab(added, url: nil, title: "Synthetic Renamed")
    XCTAssertEqual(try proxyRows(element).last?.accessibilityLabel(), "Synthetic Renamed")

    let moved = sidebar.children(of: .today(fixture.space))[0]
    sidebar.moveNode(moved, to: .pinned(fixture.space), at: 0)
    let afterMove = shown(try proxyRows(element))
    XCTAssertEqual(afterMove.first, Shown(identifier: Self.pinned, label: "Weekend Recipes", level: 0))
    XCTAssertEqual(afterMove.filter { $0.label == "Weekend Recipes" }.count, 1)

    sidebar.removeNode(added)
    let afterRemove = shown(try proxyRows(element))
    XCTAssertFalse(afterRemove.contains { $0.label == "Synthetic Renamed" })
    XCTAssertEqual(afterRemove.count, fixture.outline.numberOfRows)
  }

  // MARK: Selection

  func testSelectedRowsTrackTheCurrentTab() throws {
    let fixture = try makeFixture()
    let element = fixture.element
    let today = fixture.sidebar.children(of: .today(fixture.space))
    fixture.controller.activate(node: today[1])
    let rows = try proxyRows(element)
    let current = fixture.outlineController.row(for: today[1])
    XCTAssertEqual(rows.map { $0.isAccessibilitySelected() }, rows.indices.map { $0 == current })
    XCTAssertTrue(try proxyRows(element, .selectedRows).elementsEqual([rows[current]]) { $0 === $1 })
    XCTAssertTrue(fixture.outline.selectedRowIndexes.isEmpty, "outline selection stays off")

    fixture.controller.activate(node: today[2])
    let next = fixture.outlineController.row(for: today[2])
    XCTAssertEqual(rows[current].isAccessibilitySelected(), false)
    XCTAssertEqual(rows[next].isAccessibilitySelected(), true)
    XCTAssertEqual(try proxyRows(element, .selectedRows).map { $0.accessibilityLabel() }, ["Swift Blog"])
  }

  // MARK: Geometry and laziness

  func testAnsweringBuildsNoRowViewAndFramesFollowTheWindow() throws {
    let sidebar = StubSidebar.sample()
    let space = sidebar.spaceOrder[0]
    for index in 0..<300 {
      sidebar.addTab(url: URL(string: "https://example.com/synthetic-\(index)")!, title: "Synthetic \(index)",
                     in: .today(space))
    }
    let fixture = try makeFixture(sidebar)
    let outline = fixture.outline
    let element = fixture.element
    // 309 rows of 41 pt (about 12,700 pt) in a page under 800 pt tall. Only rows near the visible rect may have row
    // views; the test picks the last row without one, wherever AppKit put the realized ones.
    var realized: [Int] = []
    outline.enumerateAvailableRowViews { _, row in realized.append(row) }
    let visibleRange = outline.rows(in: outline.visibleRect)
    XCTAssertLessThan(realized.count, 60, "only rows near the visible rect \(visibleRange) have row views")
    let unrealized = (0..<outline.numberOfRows).filter { outline.rowView(atRow: $0, makeIfNecessary: false) == nil }
    let last = try XCTUnwrap(unrealized.last, "precondition: some row has no row view (\(realized.count) realized)")
    let lastNode = try XCTUnwrap((outline.item(atRow: last) as? OutlineItem)?.nodeID)
    guard case .tab(_, _, let lastTitle)? = sidebar.node(lastNode) else { return XCTFail("row \(last) is not a tab") }

    let rows = try proxyRows(element)
    XCTAssertEqual(rows.count, outline.numberOfRows)
    let row = rows[last]
    XCTAssertEqual(shown([row]), [Shown(identifier: Self.today, label: lastTitle, level: 0)])
    _ = row.isAccessibilitySelected()
    _ = row.isAccessibilityDisclosed()
    _ = row.accessibilityCustomActions()
    XCTAssertEqual(row.accessibilityChildren()?.count ?? 0, 0, "an unrealized row lists no cell")
    _ = try proxyRows(element, .visibleRows)
    _ = try proxyRows(element, .selectedRows)

    let window = try XCTUnwrap(outline.window)
    func expected(_ index: Int) -> NSRect {
      window.convertToScreen(outline.convert(outline.rect(ofRow: index), to: nil))
    }
    let before = row.accessibilityFrame()
    XCTAssertEqual(before, expected(last))
    XCTAssertEqual(before.height, SidebarMetrics.rowPitch, accuracy: 0.5)
    window.setFrameOrigin(NSPoint(x: window.frame.minX + 120, y: window.frame.minY + 60))
    let after = row.accessibilityFrame()
    XCTAssertEqual(after.minX - before.minX, 120, accuracy: 0.5)
    XCTAssertEqual(after.minY - before.minY, 60, accuracy: 0.5)
    XCTAssertEqual(after, expected(last))
    XCTAssertNil(outline.rowView(atRow: last, makeIfNecessary: false), "answering built no row view")

    let visible = try proxyRows(element, .visibleRows)
    let range = outline.rows(in: outline.visibleRect)
    XCTAssertEqual(visible.map { $0.accessibilityIndex() }, Array(range.location..<(range.location + range.length)))
  }

  /// Building a page realizes row views only for rows near what is visible, at every stage: the outline in its
  /// scroll view before any layout, the page, and the page in a window. An outline loaded before it had a superview
  /// used to realize every row (its visible rect is unbounded then).
  func testBuildingAPageRealizesOnlyRowsNearTheVisibleRect() throws {
    let sidebar = StubSidebar.sample()
    let space = sidebar.spaceOrder[0]
    for index in 0..<300 {
      sidebar.addTab(url: URL(string: "https://example.com/synthetic-\(index)")!, title: "Synthetic \(index)",
                     in: .today(space))
    }
    func realized(_ outline: NSOutlineView) -> Int {
      var count = 0
      outline.enumerateAvailableRowViews { _, _ in count += 1 }
      return count
    }

    let hosted = SidebarOutlineController(source: sidebar, spaceID: space, hostedIn: NSScrollView(frame: .zero))
    XCTAssertLessThan(realized(hosted.outlineView), 60, "outline in a scroll view, before layout")

    let page = SpacePageView(source: sidebar, spaceID: space)
    XCTAssertLessThan(realized(page.outlineView), 60, "page built")

    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    window.contentView = page
    page.layoutSubtreeIfNeeded()
    XCTAssertLessThan(realized(page.outlineView), 60, "page in a window")
    XCTAssertGreaterThan(realized(page.outlineView), 0, "the visible rows are realized")
  }

  // MARK: Cells

  func testTheCellHangsOffTheProxy() throws {
    let fixture = try makeFixture()
    let outline = fixture.outline
    let today = fixture.sidebar.children(of: .today(fixture.space))
    let index = fixture.outlineController.row(for: today[0])
    let rowView = try XCTUnwrap(outline.rowView(atRow: index, makeIfNecessary: false) as? SidebarRowView)
    let cell = try XCTUnwrap(outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? SidebarTabCellView)
    XCTAssertFalse(rowView.isAccessibilityElement(), "the proxy stands for the row view")
    let proxy = try proxyRows(fixture.element)[index]

    let children = try XCTUnwrap(proxy.accessibilityChildren())
    XCTAssertEqual(children.count, 1)
    XCTAssertTrue((children.first as? SidebarTabCellView) === cell)
    XCTAssertTrue((cell.accessibilityParent() as? AXProxyRow) === proxy)

    rowView.isHovered = true
    let below = descendants(of: proxy)
    XCTAssertEqual(below.filter { $0.accessibilityIdentifier() == AXID.Sidebar.rowClose }.count, 1,
                   "the hover close button is under the row's proxy")
    XCTAssertFalse(below.contains { $0 is AXProxyRow }, "no row lists another row")
    rowView.isHovered = false
  }

  /// Every unignored element below `root`, depth first.
  private func descendants(of root: Any) -> [NSAccessibilityProtocol] {
    guard let element = root as? NSAccessibilityProtocol else { return [] }
    let children = NSAccessibility.unignoredChildren(from: element.accessibilityChildren() ?? [])
      .compactMap { $0 as? NSAccessibilityProtocol }
    return children.flatMap { [$0] + descendants(of: $0) }
  }
}

extension NSAccessibilityCustomAction {
  /// What AppKit does when VoiceOver performs the action: run the handler, or send the selector to the target with
  /// the action.
  @MainActor
  func performForTesting() -> Bool {
    if let handler { return handler() }
    guard let target = target as? NSObject, let selector else { return false }
    typealias Perform = @convention(c) (NSObject, Selector, NSAccessibilityCustomAction) -> Bool
    return unsafeBitCast(target.method(for: selector), to: Perform.self)(target, selector, self)
  }
}
