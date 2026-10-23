import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Split View S6: split row and pane row interactions in the sidebar. Context menus (BH-120, BH-121, BH-126), Opt-click
/// on a split row (GS-033) and on the current tab (GS-032), VoiceOver actions, and the closed state of a pane whose
/// page closes while its split is off screen (decision 6).
@MainActor
final class SplitSidebarTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with Today `[t0, split(s0 ... sN-1), t1]`.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [UUID] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitSidebarTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        archived += ids
        _ = source.archive(ids, reason: .manual, at: SplitSidebarTests.now)
      }
    }

    var split: SplitContainerView { controller.rootView.split }
    var current: UUID? { controller.sidebarController.current }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }

    func menuTitles(_ node: UUID) throws -> [String]? {
      try outline().menu(forRow: row(node))?.items.map(\.title)
    }

    /// Chooses the context menu item titled `title` on `node`'s row.
    func choose(_ title: String, on node: UUID) throws {
      let menu = try XCTUnwrap(try outline().menu(forRow: row(node)), "the row has no context menu")
      let index = menu.indexOfItem(withTitle: title)
      XCTAssertGreaterThanOrEqual(index, 0, "no menu item \(title)")
      menu.performActionForItem(at: index)
    }

    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
    func page(_ node: UUID) -> NSView? { tab(node).flatMap { engine.contentView(for: $0) } }
    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(panes count: Int = 2) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let t0 = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let factors = Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors, in: .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let t1 = try sidebar.addTab(url: url("t1"), title: "T1", in: .today(space))
    return World(sidebar: sidebar, space: space, today: [t0, t1], split: split, panes: panes)
  }

  // MARK: Context menus (BH-120, BH-121, BH-126)

  func testSplitRowMenuHasSeparateConvertDuplicate() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    XCTAssertEqual(try harness.menuTitles(world.split),
                   ["Separate All Tabs", "Convert to Vertical Split View", "Duplicate Split View"])
    XCTAssertNil(try harness.menuTitles(world.today[0]), "a plain tab row has no split menu")
    harness.controller.close()
  }

  /// The real right-click path: `menu(for:)` sets `clickedRow`, and `menuNeedsUpdate` fills the outline's menu for it.
  func testRightClickFillsTheMenuForTheClickedRow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    let view = outline.outlineView
    func rightClick(_ node: UUID) throws -> [String] {
      let rect = view.rect(ofRow: try harness.row(node))
      let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                                   timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      let menu = try XCTUnwrap(view.menu(for: event))
      menu.delegate?.menuNeedsUpdate?(menu)
      return menu.items.map(\.title)
    }

    XCTAssertEqual(try rightClick(world.split),
                   ["Separate All Tabs", "Convert to Vertical Split View", "Duplicate Split View"])
    XCTAssertEqual(try rightClick(world.panes[0]), ["Remove Tab from Split View"])
    XCTAssertEqual(try rightClick(world.today[0]), [], "a plain tab row gets an empty menu, which does not open")
    harness.controller.close()
  }

  func testPaneRowMenuHasRemoveFromSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    XCTAssertEqual(try harness.menuTitles(world.panes[1]), ["Remove Tab from Split View"])
    harness.controller.close()
  }

  /// Remove Tab from Split View on the focused pane: the pane lands after the split with its page, nothing is
  /// archived, and focus goes to the pane next to it (decision 9).
  func testRemoveTabFromSplitViewSeparatesThePaneAndFocusesItsNeighbor() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let tabs = harness.engine.tabIDs

    try harness.choose("Remove Tab from Split View", on: world.panes[1])

    XCTAssertEqual(harness.children(.split(world.split)), [world.panes[0], world.panes[2]])
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[0], world.split, world.panes[1], world.today[1]])
    XCTAssertEqual(harness.archived, [])
    XCTAssertEqual(harness.engine.tabIDs, tabs, "the separated pane keeps its page")
    XCTAssertEqual(harness.current, world.panes[2])
    waitUntil("the shown split to shrink to 2 panes") { harness.split.paneCount == 2 }
    XCTAssertEqual(harness.controller.currentTab, harness.tab(world.panes[2]))
    harness.controller.close()
  }

  /// Separate All Tabs puts the panes in the split's place as plain rows: the outline inserts and removes exactly those
  /// rows (no `reloadData`), and the focused pane stays focused, now shown alone.
  func testSeparateAllTabsRestoresPlainRowsInPlace() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let outline = try harness.outline()
    let reloads = outline.outlineView.reloadDataCount
    let configured = outline.rowConfigureCount

    try harness.choose("Separate All Tabs", on: world.split)

    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.panes[0], world.panes[1], world.today[1]])
    XCTAssertEqual(outline.outlineView.reloadDataCount, reloads, "no reloadData")
    XCTAssertLessThanOrEqual(outline.rowConfigureCount - configured, world.panes.count,
                             "only the separated panes' rows are configured")
    let first = try harness.row(world.today[0])
    XCTAssertEqual(try harness.row(world.panes[0]), first + 1, "in the split's place, right after t0")
    XCTAssertEqual(try harness.row(world.panes[1]), first + 2)
    XCTAssertEqual(try harness.row(world.today[1]), first + 3)
    XCTAssertEqual(outline.outlineView.level(forRow: try harness.row(world.panes[0])), 0, "a top-level row again")
    XCTAssertLessThan(outline.row(for: world.split), 0, "the split row is gone")
    waitUntil("the card to show pane 1's page alone") {
      harness.split.isHidden && harness.controller.rootView.card.contentView === harness.page(world.panes[1])
    }
    XCTAssertEqual(harness.current, world.panes[1])
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[1]])
    harness.controller.close()
  }

  func testConvertFromMenuFlipsTheShownLayout() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    XCTAssertEqual(harness.split.axis, .sideBySide)

    try harness.choose("Convert to Vertical Split View", on: world.split)

    waitUntil("the shown split's axis to become .stacked") { harness.split.axis == .stacked }
    XCTAssertEqual(try harness.menuTitles(world.split)?[1], "Convert to Horizontal Split View")
    try harness.choose("Convert to Horizontal Split View", on: world.split)
    waitUntil("the shown split's axis to become .sideBySide again") { harness.split.axis == .sideBySide }
    harness.controller.close()
  }

  func testDuplicateSplitInsertsACopyAfterIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.choose("Duplicate Split View", on: world.split)

    let today = harness.children(.today(world.space))
    XCTAssertEqual(today.count, 4)
    XCTAssertEqual([today[0], today[1], today[3]], [world.today[0], world.split, world.today[1]])
    let copy = today[2]
    guard case .split? = harness.source.node(copy) else { return XCTFail("the copy is not a split") }
    let copied = harness.children(.split(copy))
    XCTAssertEqual(copied.count, 2)
    XCTAssertTrue(Set(copied).isDisjoint(with: world.panes), "the copy has new ids")
    XCTAssertEqual(copied.compactMap { id -> URL? in
      if case .tab(_, let url, _)? = harness.source.node(id) { url } else { nil }
    }, [Self.url("s0"), Self.url("s1")])
    XCTAssertGreaterThanOrEqual(try harness.row(copy), 0, "the copy has a row")
    XCTAssertEqual(harness.current, world.today[0], "focus does not move")
    harness.controller.close()
  }

  // MARK: Opt-click (GS-032, GS-033)

  func testOptClickOnASplitRowSeparatesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    try harness.outline().handleClick(row: try harness.row(world.split), modifiers: .option)

    XCTAssertNil(harness.source.node(world.split))
    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.panes[0], world.panes[1], world.today[1]])
    waitUntil("the card to show pane 0's page alone") {
      harness.split.isHidden && harness.controller.rootView.card.contentView === harness.page(world.panes[0])
    }
    XCTAssertEqual(harness.current, world.panes[0])
    harness.controller.close()
  }

  func testPlainClickOnASplitRowActivatesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    try harness.outline().handleClick(row: try harness.row(world.split), modifiers: [])

    XCTAssertNotNil(harness.source.node(world.split))
    XCTAssertEqual(harness.current, world.panes[0])
    XCTAssertFalse(harness.split.isHidden)
    harness.controller.close()
  }

  /// Opt-click on the current plain tab duplicates it into a split: the tab and a copy of its page side by side in
  /// the tab's place, with the copy focused.
  func testOptClickOnTheCurrentTabDuplicatesItIntoASplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.outline().handleClick(row: try harness.row(world.today[0]), modifiers: .option)

    let today = harness.children(.today(world.space))
    XCTAssertEqual(Array(today[1...]), [world.split, world.today[1]])
    guard case .split(let split, let layout)? = harness.source.node(today[0]) else { return XCTFail("no split") }
    XCTAssertEqual(layout.orientation, .horizontal)
    let panes = harness.children(.split(split))
    XCTAssertEqual(panes.count, 2)
    XCTAssertEqual(panes[0], world.today[0])
    guard case .tab(_, let url, let title)? = harness.source.node(panes[1]) else { return XCTFail("no copy") }
    XCTAssertEqual(url, Self.url("t0"))
    XCTAssertEqual(title, "T0")
    XCTAssertEqual(harness.current, panes[1])
    XCTAssertEqual(harness.controller.currentTab, harness.tab(panes[1]))
    XCTAssertEqual(harness.split.paneCount, 2)
    XCTAssertEqual(harness.split.focusedIndex, 1)
    harness.controller.close()
  }

  /// Opt-click on a tab that is not current, or on a pane, activates it like a plain click [I].
  func testOptClickOnAnotherTabOrAPaneOnlyActivatesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.outline().handleClick(row: try harness.row(world.today[1]), modifiers: .option)
    XCTAssertEqual(harness.current, world.today[1])
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[0], world.split, world.today[1]])

    try harness.outline().handleClick(row: try harness.row(world.panes[1]), modifiers: .option)
    XCTAssertEqual(harness.current, world.panes[1])
    try harness.outline().handleClick(row: try harness.row(world.panes[1]), modifiers: .option)
    XCTAssertEqual(harness.children(.split(world.split)), world.panes, "a pane is not duplicated")
    harness.controller.close()
  }

  // MARK: Accessibility

  func testRowsOfferTheSplitEditsAsVoiceOverActions() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let outline = try harness.outline()

    XCTAssertEqual(outline.accessibilityActions(for: world.split).map(\.name), ["Archive", "Separate All Tabs"])
    let paneActions = outline.accessibilityActions(for: world.panes[1])
    XCTAssertEqual(paneActions.map(\.name), ["Archive", "Remove Tab from Split View"])
    XCTAssertEqual(outline.accessibilityActions(for: world.today[0]).map(\.name), ["Archive"])

    XCTAssertTrue(try XCTUnwrap(paneActions.last?.handler)())
    XCTAssertEqual(harness.children(.split(world.split)), [], "the split collapsed")
    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.panes[0], world.panes[1], world.today[1]])
    XCTAssertEqual(harness.archived, [])
    harness.controller.close()
  }

  // MARK: Pages closed while their split is off screen (decision 6, #56 follow-up from #183)

  /// A Space with a Pinned split `(l, r)` and a Today tab `o`.
  private static func makePinnedSplitWorld() throws -> (SidebarModel.Sidebar, split: UUID, panes: [UUID], other: UUID) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    let other = try sidebar.addTab(url: url("o"), title: "O", in: .today(space))
    return (sidebar, split, panes, other)
  }

  /// The X on a Pinned pane while a plain tab is shown closes its page; showing the split again keeps it closed (a
  /// placeholder, no engine tab) instead of reopening it.
  func testPinnedPaneClosedWhileItsSplitIsOffScreenStaysClosed() throws {
    let world = try Self.makePinnedSplitWorld()
    let harness = Harness(world.0)
    harness.controller.activate(node: world.panes[0])
    XCTAssertNotNil(harness.tab(world.panes[1]))
    harness.controller.activate(node: world.other)
    XCTAssertTrue(harness.split.isHidden)

    harness.controller.sidebarController.onClose?(world.panes[1])          // the pane row's hover X
    XCTAssertNil(harness.tab(world.panes[1]))

    harness.controller.activate(node: world.panes[0])
    XCTAssertNil(harness.tab(world.panes[1]), "showing the split does not reopen the closed pane")
    XCTAssertTrue(harness.split.paneCards[1].emptyStateView is SplitPanePlaceholderView)
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0]])
    harness.controller.close()
  }

  /// The same holds when the page closes itself (an engine-side close, such as `window.close()`).
  func testPinnedPanePageClosedByTheEngineWhileOffScreenStaysClosed() throws {
    let world = try Self.makePinnedSplitWorld()
    let harness = Harness(world.0)
    harness.controller.activate(node: world.panes[0])
    harness.controller.activate(node: world.other)

    harness.engine.closeTab(try XCTUnwrap(harness.tab(world.panes[1])))

    harness.controller.activate(node: world.split)
    XCTAssertEqual(harness.current, world.panes[0])
    XCTAssertNil(harness.tab(world.panes[1]))
    XCTAssertTrue(harness.split.paneCards[1].emptyStateView is SplitPanePlaceholderView)
    harness.controller.close()
  }

  /// With every pane of an off-screen split closed, the split forgets its closed panes and opens afresh.
  func testEveryPaneClosedWhileOffScreenOpensTheSplitAfresh() throws {
    let world = try Self.makePinnedSplitWorld()
    let harness = Harness(world.0)
    harness.controller.activate(node: world.panes[1])
    harness.controller.activate(node: world.other)

    harness.controller.sidebarController.onClose?(world.split)               // the split row's hover X
    XCTAssertNil(harness.tab(world.panes[0]))
    XCTAssertNil(harness.tab(world.panes[1]))

    harness.controller.activate(node: world.split)
    XCTAssertNotNil(harness.tab(world.panes[0]))
    XCTAssertNotNil(harness.tab(world.panes[1]))
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes))
    harness.controller.close()
  }
}
