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
        XCTAssertEqual(row.accessibilityRole(), .group, "the divider is a plain separator group, no splitter (#297)")
        XCTAssertFalse(row.isAccessibilityElement(), "VoiceOver skips the divider (#297)")
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
    // A built page realizes only the rows near its visible rect (#297), and a tab added afterwards lands at the
    // end of Today, about 12,700 pt below a page under 800 pt tall; either way its row gets no row view.
    let lastTitle = "Added Later"
    let lastNode = sidebar.addTab(url: URL(string: "https://example.com/added-later")!, title: lastTitle,
                                  in: .today(space))
    let last = fixture.outlineController.row(for: lastNode)
    XCTAssertEqual(last, outline.numberOfRows - 1)
    XCTAssertNil(outline.rowView(atRow: last, makeIfNecessary: false), "precondition: the added row has no row view")

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

  // MARK: #297

  /// A row reload (title, favicon, Closing) does not change which item a row shows: the proxy elements survive,
  /// so the element a VoiceOver user is on does not drop out of its parent's children.
  func testARowReloadKeepsTheProxyElements() throws {
    let fixture = try makeFixture()
    let tab = fixture.sidebar.children(of: .today(fixture.space))[0]
    let before = try proxyRows(fixture.element)
    fixture.outlineController.reload(node: tab)
    let after = try proxyRows(fixture.element)
    XCTAssertEqual(before.count, after.count)
    for (old, new) in zip(before, after) {
      XCTAssertTrue(old === new, "a row reload keeps the proxy element")
    }
  }

  /// Insert, remove, expand and collapse post rowCountChanged / rowExpanded / rowCollapsed; a row's reload posts
  /// titleChanged and valueChanged, so a client that caches the tree is told to refresh (#297).
  func testStructuralChangesAndRowReloadsPostNotifications() throws {
    let fixture = try makeFixture()
    let proxies = fixture.outline.axProxyRows
    proxies.postedNotificationsForTesting = []

    let folderID = try folder(fixture)
    let folderRow = fixture.outlineController.row(for: folderID)
    let folderItem = try XCTUnwrap(fixture.outline.item(atRow: folderRow))
    fixture.outline.collapseItem(folderItem)
    fixture.outline.expandItem(folderItem)
    let posted = proxies.postedNotificationsForTesting ?? []
    XCTAssertTrue(posted.contains { $0.0 == .rowCollapsed && $0.1 == folderRow },
                  "collapse posts rowCollapsed for the folder's row")
    XCTAssertTrue(posted.contains { $0.0 == .rowExpanded && $0.1 == folderRow },
                  "expand posts rowExpanded for the folder's row")

    _ = fixture.sidebar.addTab(url: URL(string: "https://example.com/synthetic-notify")!,
                               title: "Synthetic Notify", in: .today(fixture.space))
    XCTAssertTrue((proxies.postedNotificationsForTesting ?? []).contains { $0.0 == .rowCountChanged },
                  "an insert posts rowCountChanged")

    proxies.postedNotificationsForTesting = []
    let tab = fixture.sidebar.children(of: .today(fixture.space))[0]
    let tabRow = fixture.outlineController.row(for: tab)
    fixture.outlineController.reload(node: tab)
    let reloaded = (proxies.postedNotificationsForTesting ?? []).filter { $0.1 == tabRow }.map(\.0)
    XCTAssertTrue(reloaded.contains(.titleChanged), "a row reload posts titleChanged")
    XCTAssertTrue(reloaded.contains(.valueChanged), "a row reload posts valueChanged (Closing)")
  }

  /// #297: a built page realizes only the rows near its visible rect; the rest are realized as they scroll in.
  func testBuildingAPageRealizesOnlyRowsNearTheVisibleRect() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Big")
    for index in 0..<200 {
      _ = sidebar.addTab(url: URL(string: "https://example.com/\(index)")!, title: "Tab \(index)",
                         in: .today(space))
    }
    let fixture = try makeFixture(sidebar)
    XCTAssertNotNil(fixture.outline.rowView(atRow: 1, makeIfNecessary: false),
                    "a row near the visible rect is realized")
    XCTAssertNil(fixture.outline.rowView(atRow: 150, makeIfNecessary: false),
                 "a row far past the visible rect is not realized up front")
  }

  /// #297: pages realize their visible rows when they are laid out (window open, a new Space), while parked:
  /// a Space switch shows built rows instead of paying the realization cost in its showing frame.
  func testBuiltPagesConstructTheirVisibleRowsWhileParked() throws {
    let fixture = try makeFixture()
    let pager = fixture.controller.view.pager
    for (index, page) in pager.pages.enumerated() where index != pager.index {
      let page = try XCTUnwrap(page as? SpacePageView)
      XCTAssertTrue(page.isHidden, "page \(index) is parked")
      XCTAssertNotNil(page.outlineView.rowView(atRow: 1, makeIfNecessary: false),
                      "parked page \(index) has its visible rows built")
    }
  }

  // MARK: Press, show menu and value (#607)

  private static let press = #selector(NSAccessibilityProtocol.accessibilityPerformPress)
  private static let showMenu = #selector(NSAccessibilityProtocol.accessibilityPerformShowMenu)

  func testPressActivatesATabRowAndTogglesAFolderRow() throws {
    let fixture = try makeFixture()
    let element = fixture.element
    let today = fixture.sidebar.children(of: .today(fixture.space))
    var activated: [NodeID] = []
    fixture.outlineController.onActivate = { activated.append($0) }
    let rows = try proxyRows(element)
    let tabRow = rows[fixture.outlineController.row(for: today[1])]
    XCTAssertTrue(tabRow.isAccessibilitySelectorAllowed(Self.press))
    XCTAssertTrue(tabRow.accessibilityPerformPress())
    XCTAssertEqual(activated, [today[1]], "a press activates the row as a click does")

    let folderID = try folder(fixture)
    let folderRow = rows[fixture.outlineController.row(for: folderID)]
    XCTAssertTrue(folderRow.accessibilityPerformPress())
    XCTAssertEqual(shown(try proxyRows(element)), Self.personalExpanded.filter { $0.level == 0 },
                   "a press closes an open folder")
    let reopened = try proxyRows(element)[fixture.outlineController.row(for: folderID)]
    XCTAssertTrue(reopened.accessibilityPerformPress())
    XCTAssertEqual(shown(try proxyRows(element)), Self.personalExpanded, "and opens a closed one")
    XCTAssertEqual(activated, [today[1]], "a folder press activates nothing")

    let divider = try proxyRows(element)[fixture.outlineController.dividerRow]
    XCTAssertFalse(divider.isAccessibilitySelectorAllowed(Self.press))
    XCTAssertFalse(divider.isAccessibilitySelectorAllowed(Self.showMenu))
    XCTAssertFalse(divider.accessibilityPerformPress(), "the divider does nothing")
  }

  /// A press has no mouse-down, so it never reads the point of an earlier click (a drag that began on a pinned
  /// tab's favicon leaves one behind): it activates the row, never the favicon's reset path (GS-005).
  func testPressIgnoresAStaleClickPointInAPinnedFavicon() throws {
    let fixture = try makeFixture()
    let controller = fixture.outlineController
    let pinned = fixture.sidebar.children(of: .pinned(fixture.space))[0]
    let row = controller.row(for: pinned)
    var activated: [NodeID] = []
    var faviconClicks: [NodeID] = []
    controller.onActivate = { activated.append($0) }
    controller.onPinnedFaviconClick = { id, _ in faviconClicks.append(id) }
    let cell = try XCTUnwrap(fixture.outline.view(atColumn: 0, row: row, makeIfNecessary: false)
                             as? SidebarTabCellView)
    let favicon = cell.faviconView.frame
    fixture.outline.lastClickPoint = cell.convert(NSPoint(x: favicon.midX, y: favicon.midY), to: fixture.outline)

    XCTAssertTrue(try proxyRows(fixture.element)[row].accessibilityPerformPress())
    XCTAssertEqual(activated, [pinned], "the press activates the pinned tab")
    XCTAssertEqual(faviconClicks, [], "and does not reset it")
    XCTAssertNil(fixture.outline.lastClickPoint)
  }

  /// A drag that starts on a pinned favicon ends the click it began with: its point is not kept for later.
  func testADragForgetsTheClickPoint() throws {
    let fixture = try makeFixture()
    fixture.outline.lastClickPoint = NSPoint(x: 10, y: 10)
    let pinned = fixture.sidebar.children(of: .pinned(fixture.space))[0]
    fixture.outlineController.draggingSessionWillBegin(items: [fixture.outline.item(atRow:
      fixture.outlineController.row(for: pinned)) as Any])
    XCTAssertNil(fixture.outline.lastClickPoint)
    fixture.outlineController.draggingSessionEnded()
  }

  func testShowMenuPresentsTheRowsContextMenu() throws {
    let fixture = try makeFixture()
    let controller = fixture.outlineController
    var presented: [(titles: [String], row: Int)] = []
    controller.presentAccessibilityMenu = { menu, row in presented.append((menu.items.map(\.title), row)) }
    let rows = try proxyRows(fixture.element)
    let today = fixture.sidebar.children(of: .today(fixture.space))
    let tabRow = controller.row(for: today[0])
    let folderRow = controller.row(for: try folder(fixture))
    let expectedTab = try XCTUnwrap(controller.menu(forRow: tabRow)).items.map(\.title)
    let expectedFolder = try XCTUnwrap(controller.menu(forRow: folderRow)).items.map(\.title)

    XCTAssertTrue(rows[tabRow].isAccessibilitySelectorAllowed(Self.showMenu))
    XCTAssertTrue(rows[tabRow].accessibilityPerformShowMenu())
    XCTAssertTrue(rows[folderRow].accessibilityPerformShowMenu())
    XCTAssertFalse(rows[controller.dividerRow].accessibilityPerformShowMenu())
    XCTAssertEqual(presented.map(\.row), [tabRow, folderRow])
    XCTAssertEqual(presented.first?.titles, expectedTab, "the same menu a right-click on the row shows")
    XCTAssertEqual(presented.last?.titles, expectedFolder)
    XCTAssertFalse(expectedTab.isEmpty)
  }

  func testValueSaysTheSectionAndTheState() throws {
    let fixture = try makeFixture()
    let controller = fixture.outlineController
    let pinned = fixture.sidebar.children(of: .pinned(fixture.space))
    let today = fixture.sidebar.children(of: .today(fixture.space))
    let folderID = try folder(fixture)
    let inFolder = fixture.sidebar.children(of: .folder(folderID))[0]
    let sound = Box<[NodeID: TabAudio]>([pinned[0]: .playing, pinned[1]: .muted])
    let closing = Box<Set<NodeID>>([])
    controller.audioProvider = { sound.value[$0] ?? .silent }
    controller.closingProvider = { closing.value.contains($0) }
    fixture.controller.activate(node: today[0])

    func value(_ id: NodeID) throws -> String? {
      try proxyRows(fixture.element)[controller.row(for: id)].accessibilityValue() as? String
    }
    XCTAssertEqual(try value(pinned[0]), "Pinned, playing audio")
    XCTAssertEqual(try value(pinned[1]), "Pinned, muted")
    XCTAssertEqual(try value(folderID), "Pinned")
    XCTAssertEqual(try value(inFolder), "Pinned", "a row in a folder is in the folder's section")
    XCTAssertEqual(try value(today[0]), "Today, current")
    XCTAssertEqual(try value(today[1]), "Today")

    sound.value[today[0]] = .playing
    closing.value.insert(today[0])
    XCTAssertEqual(try value(today[0]), "Today, current, playing audio, closing")
    sound.value = [:]
    closing.value = []
    fixture.controller.activate(node: today[1])
    XCTAssertEqual(try value(today[0]), "Today")
    XCTAssertEqual(try value(today[1]), "Today, current")
  }

  func testStateAndSoundChangesPostAValueChange() throws {
    let fixture = try makeFixture()
    let controller = fixture.outlineController
    let proxies = fixture.outline.axProxyRows
    let today = fixture.sidebar.children(of: .today(fixture.space))
    _ = try proxyRows(fixture.element)
    proxies.postedNotificationsForTesting = []

    fixture.controller.activate(node: today[1])
    let row = controller.row(for: today[1])
    XCTAssertTrue(proxies.postedNotificationsForTesting?.contains { $0.0 == .valueChanged && $0.1 == row } ?? false,
                  "a row that became current tells clients its value changed")

    proxies.postedNotificationsForTesting = []
    controller.audioChanged(node: today[2])
    let audioRow = controller.row(for: today[2])
    XCTAssertTrue(proxies.postedNotificationsForTesting?.contains { $0.0 == .valueChanged && $0.1 == audioRow }
                  ?? false, "a sound change tells clients the value changed")
  }

  // MARK: Favorite tiles (#607)

  func testPressAndShowMenuOnAFavoriteTile() throws {
    let fixture = try makeFixture()
    let grid = fixture.controller.view.favorites
    grid.collectionView.layoutSubtreeIfNeeded()
    let favorites = fixture.sidebar.children(of: .favorites(profile: "default"))
    let id = try XCTUnwrap(favorites.first)
    let tile = try XCTUnwrap(grid.tile(for: id))
    var activated: [NodeID] = []
    grid.onActivate = { activated.append($0) }
    var presented: [(titles: [String], tile: NSView)] = []
    grid.presentAccessibilityMenu = { menu, view in presented.append((menu.items.map(\.title), view)) }

    XCTAssertTrue(tile.isAccessibilitySelectorAllowed(Self.press))
    XCTAssertTrue(tile.isAccessibilitySelectorAllowed(Self.showMenu))
    XCTAssertTrue(tile.accessibilityPerformPress())
    XCTAssertEqual(activated, [id], "a press activates the Favorite as a click does")

    XCTAssertTrue(tile.accessibilityPerformShowMenu())
    let expected = try XCTUnwrap(grid.contextMenu(for: id)).items.map(\.title)
    XCTAssertEqual(presented.first?.titles, expected, "the same menu a right-click on the tile shows")
    XCTAssertTrue(presented.first?.tile === tile)
    XCTAssertFalse(expected.isEmpty)
  }

  /// VoiceOver does not speak "selected" on a button, so the tile's value description says the section and state;
  /// the value itself stays the `loaded` / `unloaded` token the UI tests read.
  func testAFavoriteTileSpeaksItsState() throws {
    let fixture = try makeFixture()
    let grid = fixture.controller.view.favorites
    let favorites = fixture.sidebar.children(of: .favorites(profile: "default"))
    let loaded = Box<Set<NodeID>>([favorites[0], favorites[1]])
    grid.pageLoadedProvider = { loaded.value.contains($0) }
    fixture.controller.activate(node: favorites[1])
    grid.collectionView.layoutSubtreeIfNeeded()
    func tile(_ index: Int) throws -> FavoriteTileView { try XCTUnwrap(grid.tile(for: favorites[index])) }

    XCTAssertEqual(try tile(1).accessibilityValue() as? String, AXID.Favorites.loaded)
    XCTAssertEqual(try tile(1).accessibilityValueDescription(), "Favorites, current")
    XCTAssertEqual(try tile(0).accessibilityValueDescription(), "Favorites, loaded")
    XCTAssertEqual(try tile(2).accessibilityValue() as? String, AXID.Favorites.unloaded)
    XCTAssertEqual(try tile(2).accessibilityValueDescription(), "Favorites")

    loaded.value.remove(favorites[0])
    fixture.controller.activate(node: favorites[0])
    grid.collectionView.layoutSubtreeIfNeeded()
    XCTAssertEqual(try tile(0).accessibilityValueDescription(), "Favorites, current")
    XCTAssertEqual(try tile(1).accessibilityValueDescription(), "Favorites, loaded")
  }

  func testATileWhoseCurrentStateChangesPostsAValueChange() throws {
    let fixture = try makeFixture()
    let grid = fixture.controller.view.favorites
    let favorites = fixture.sidebar.children(of: .favorites(profile: "default"))
    grid.collectionView.layoutSubtreeIfNeeded()
    let tile = try XCTUnwrap(grid.tile(for: favorites[0]))
    var posted: [NSAccessibility.Notification] = []
    tile.postedNotificationsForTesting = { posted.append($0) }
    fixture.controller.activate(node: favorites[0])
    XCTAssertEqual(posted.filter { $0 == .valueChanged }.count, 1, "becoming current is announced once")
    posted = []
    fixture.controller.activate(node: favorites[1])
    XCTAssertEqual(posted.filter { $0 == .valueChanged }.count, 1, "and so is leaving it")
  }

  func testAFavoriteTileReportsItselfSelectedWhileCurrent() throws {
    let fixture = try makeFixture()
    let grid = fixture.controller.view.favorites
    let favorites = fixture.sidebar.children(of: .favorites(profile: "default"))
    fixture.controller.activate(node: favorites[1])
    grid.collectionView.layoutSubtreeIfNeeded()
    XCTAssertEqual(try XCTUnwrap(grid.tile(for: favorites[1])).isAccessibilitySelected(), true)
    XCTAssertEqual(try XCTUnwrap(grid.tile(for: favorites[0])).isAccessibilitySelected(), false)
    fixture.controller.activate(node: favorites[0])
    grid.collectionView.layoutSubtreeIfNeeded()
    XCTAssertEqual(try XCTUnwrap(grid.tile(for: favorites[1])).isAccessibilitySelected(), false)
    XCTAssertEqual(try XCTUnwrap(grid.tile(for: favorites[0])).isAccessibilitySelected(), true)
  }

  func testAReusedTileForgetsItsPressAndMenu() throws {
    let tile = FavoriteTileView(frame: NSRect(x: 0, y: 0, width: 52, height: 46))
    var calls = 0
    tile.onAccessibilityPress = { calls += 1 }
    tile.onAccessibilityShowMenu = { calls += 10 }
    tile.prepareForReuse()
    XCTAssertFalse(tile.accessibilityPerformPress())
    XCTAssertFalse(tile.accessibilityPerformShowMenu())
    XCTAssertEqual(calls, 0)
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

/// A value the providers read and the test changes between reads.
@MainActor
private final class Box<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
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
