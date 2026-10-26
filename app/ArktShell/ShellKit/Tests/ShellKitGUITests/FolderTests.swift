import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Folders (#109): the spring that opens and closes a folder (interruptible, with a Reduce Motion variant), rows
/// peeking out of a closed folder (BH-092, BH-105), Collapse All / Expand All Folders (BH-097), each window's own
/// open folders (BH-098), New Folder inside a folder (BH-094) and from the Tabs menu (KB-040), and rename commit on
/// focus loss (BH-096).
@MainActor
final class FolderTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// Work: Pinned `[folder [f0, f1, inner [g0]], p0]`, Today `[t0, t1]`.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var work: UUID
    var folder: UUID
    var inner: UUID
    var folderTabs: [UUID]
    var innerTab: UUID
    var pinnedTab: UUID
    var today: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    /// The folder springs' clock; tests move it by hand.
    var clock: CFTimeInterval = 1000

    init(_ sidebar: SidebarModel.Sidebar, source shared: ModelSidebarSource? = nil) {
      let source = shared ?? ModelSidebarSource(sidebar: sidebar, now: { FolderTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: FolderTests.now) }
    }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    /// Shows the window and puts the folder springs on this harness's clock, frames driven by `advance`.
    func show(current: UUID) throws {
      controller.showWindow(nil)
      controller.activate(node: current)
      let motion = try outline().folderMotion
      motion.now = { [unowned self] in self.clock }
      motion.drivesFramesItself = false
      motion.reduceMotion = { false }
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func advance(by seconds: CFTimeInterval) throws {
      clock += seconds
      try outline().folderMotion.presentFrame()
    }

    func row(_ node: UUID) throws -> Int { try outline().row(for: node) }

    func click(_ node: UUID) throws {
      let row = try row(node)
      XCTAssertGreaterThanOrEqual(row, 0, "no row for the node")
      try outline().handleClick(row: row, modifiers: [])
    }

    func style(_ node: UUID) throws -> FolderMotionLayout.RowStyle {
      try outline().rowStyle(for: node)
    }

    /// The realized row view's layer, as Core Animation draws it.
    func rowLayer(_ node: UUID) throws -> CALayer {
      let view = try outline().outlineView
      return try XCTUnwrap(view.rowView(atRow: try row(node), makeIfNecessary: false)?.layer)
    }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Folder", in: .pinned(work))
    let folderTabs = try (0..<2).map { try sidebar.addTab(url: url("f\($0)"), title: "F\($0)", in: .folder(folder)) }
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(folder))
    let innerTab = try sidebar.addTab(url: url("g0"), title: "G0", in: .folder(inner))
    let pinnedTab = try sidebar.addTab(url: url("p0"), title: "P0", in: .pinned(work))
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(work)) }
    return World(sidebar: sidebar, work: work, folder: folder, inner: inner, folderTabs: folderTabs,
                 innerTab: innerTab, pinnedTab: pinnedTab, today: today)
  }

  // MARK: Open and close spring

  /// A click closes the folder at once (its glyph and state), the rows slide under it and fade on a spring, and they
  /// leave the outline only when the spring settles.
  func testAClickClosesOnASpringAndTheRowsLeaveWhenItSettles() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])

    try harness.click(world.folder)
    let outline = try harness.outline()
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    XCTAssertGreaterThanOrEqual(try harness.row(world.folderTabs[1]), 0, "the rows stay while the spring runs")
    XCTAssertEqual(try harness.style(world.folderTabs[1]), .rest, "the first frame is the open layout")

    try harness.advance(by: 0.06)
    let child = try harness.style(world.folderTabs[1])
    let below = try harness.style(world.pinnedTab)
    XCTAssertTrue((0.01..<0.99).contains(child.alpha), "the child fades: \(child.alpha)")
    XCTAssertLessThan(below.offsetY, 0, "the row below rises")
    XCTAssertEqual(below.alpha, 1)
    let outlineController = try harness.outline()
    XCTAssertEqual(outlineController.rowStyle(atRow: outlineController.dividerRow).offsetY, below.offsetY,
                   "the Pinned / Today divider moves with the rows around it")
    XCTAssertEqual(try harness.rowLayer(world.pinnedTab).transform.m42, below.offsetY,
                   "the frame reaches the row view as a layer transform, not a frame change")
    XCTAssertEqual(CGFloat(try harness.rowLayer(world.folderTabs[1]).opacity), child.alpha, accuracy: 0.001)
    // Whatever way the layers are flipped, the row below draws closer to the folder row by the offset.
    let folderLayer = try harness.rowLayer(world.folder)
    let belowLayer = try harness.rowLayer(world.pinnedTab)
    let common = try XCTUnwrap(harness.controller.window?.contentView?.layer)
    func drawnGap() -> CGFloat {
      abs(belowLayer.convert(CGPoint(x: belowLayer.bounds.midX, y: belowLayer.bounds.midY), to: common).y
          - folderLayer.convert(CGPoint(x: folderLayer.bounds.midX, y: folderLayer.bounds.midY), to: common).y)
    }
    let layoutGap = try harness.outline().outlineView.rect(ofRow: try harness.row(world.pinnedTab)).midY
      - (try harness.outline().outlineView.rect(ofRow: try harness.row(world.folder)).midY)
    XCTAssertEqual(drawnGap(), layoutGap + below.offsetY, accuracy: 0.5, "the row below draws closer to the folder")

    try harness.advance(by: 2)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1, "settled: the children left the outline")
    XCTAssertEqual(try harness.row(world.pinnedTab), try harness.row(world.folder) + 1)
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest)
    XCTAssertEqual(try harness.rowLayer(world.pinnedTab).transform.m42, 0)
    XCTAssertFalse(outline.folderMotion.isRunning)
  }

  /// A second click mid-close reverses from where the rows are: no jump, no row removed, and the open settles.
  func testAClickMidCloseReversesFromWhereTheRowsAre() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let rowsBefore = try harness.outline().outlineView.numberOfRows

    try harness.click(world.folder)
    try harness.advance(by: 0.06)
    let mid = try harness.style(world.pinnedTab)
    try harness.click(world.folder)
    XCTAssertTrue(try harness.outline().isFolderOpen(world.folder))
    try harness.outline().folderMotion.presentFrame()
    XCTAssertEqual(try harness.style(world.pinnedTab).offsetY, mid.offsetY, accuracy: 0.001,
                   "the reversal starts from the presented offset")
    try harness.advance(by: 0.02)
    XCTAssertLessThan(try harness.style(world.pinnedTab).offsetY, mid.offsetY,
                      "the rows still move up for a moment: the spring carries its velocity into the reversal")

    try harness.advance(by: 2)
    XCTAssertEqual(try harness.outline().outlineView.numberOfRows, rowsBefore, "no row left and none came twice")
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest)
  }

  /// An open reverses a close the same way: the rows come back with the spring and stay.
  func testOpeningInsertsTheRowsAndSpringsThemOutFromUnderTheFolder() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    try harness.outline().toggleFolder(world.folder, animated: false)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1)

    try harness.click(world.folder)
    XCTAssertGreaterThanOrEqual(try harness.row(world.folderTabs[0]), 0, "the rows are inserted at once")
    let start = try harness.style(world.folderTabs[1])
    XCTAssertEqual(start.alpha, 0, "they start hidden under the folder row")
    XCTAssertLessThan(try harness.style(world.pinnedTab).offsetY, 0, "the row below starts where it was")
    try harness.advance(by: 2)
    XCTAssertEqual(try harness.style(world.folderTabs[1]), .rest)
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest)
  }

  /// Reduce Motion: no movement. A close applies at once; an open shows the rows in place and fades them in.
  func testReduceMotionAppliesAtOnceAndFadesNewRowsIn() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    try harness.outline().folderMotion.reduceMotion = { true }

    try harness.click(world.folder)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1, "closed at once")
    XCTAssertFalse(try harness.outline().folderMotion.isRunning)

    try harness.click(world.folder)
    XCTAssertGreaterThanOrEqual(try harness.row(world.folderTabs[0]), 0)
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest, "nothing moves")
    let key = SidebarOutlineController.folderFadeKey
    let fade = try XCTUnwrap(try harness.rowLayer(world.folderTabs[0]).animation(forKey: key) as? CABasicAnimation)
    XCTAssertEqual(fade.keyPath, "opacity")
    XCTAssertEqual(fade.fromValue as? Float, 0)
    XCTAssertNil(try harness.rowLayer(world.pinnedTab).animation(forKey: key),
                 "rows that were there already do not fade")
  }

  /// Return on a focused folder toggles it with no motion: keyboard actions never animate.
  func testKeyboardReturnTogglesWithoutMotion() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let outline = try harness.outline()
    outline.focusKeyboard(on: try harness.row(world.folder))
    outline.outlineView.onKeyboardReturn?(try harness.row(world.folder))
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1)
    XCTAssertFalse(outline.folderMotion.isRunning)
  }

  // MARK: Review fixes

  /// A keyboard toggle mid-spring applies at once and stops the spring.
  func testAKeyboardToggleMidSpringStopsIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    try harness.click(world.folder)
    try harness.advance(by: 0.06)
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)
    XCTAssertTrue(outline.isFolderOpen(world.folder))
    XCTAssertFalse(outline.folderMotion.isRunning)
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest)
    XCTAssertEqual(try harness.style(world.folderTabs[0]), .rest)
    try harness.advance(by: 2)
    XCTAssertGreaterThanOrEqual(try harness.row(world.folderTabs[0]), 0, "the rows stay")
  }

  /// Archiving a folder mid-close leaves no row offset behind.
  func testRemovingAFolderMidSpringRestsTheRowsBelow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    try harness.click(world.folder)
    try harness.advance(by: 0.06)
    XCTAssertLessThan(try harness.style(world.pinnedTab).offsetY, 0)
    _ = harness.source.archive([world.folder], reason: .manual, at: Self.now)
    XCTAssertFalse(try harness.outline().folderMotion.isRunning)
    XCTAssertEqual(try harness.style(world.pinnedTab), .rest)
    XCTAssertEqual(try harness.rowLayer(world.pinnedTab).transform.m42, 0)
  }

  // MARK: Peeking rows (BH-092, BH-105)

  /// A tab moved into a folder nested in a closed folder shows with the path to it.
  func testATabMovedIntoANestedFolderOfAClosedFolderPeeksWithItsPath() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    try harness.outline().toggleFolder(world.folder, animated: false)
    try harness.source.moveNode(world.today[1], to: .folder(world.inner), at: 0)
    XCTAssertEqual(try harness.row(world.inner), try harness.row(world.folder) + 1)
    XCTAssertEqual(try harness.row(world.today[1]), try harness.row(world.folder) + 2)
    XCTAssertEqual(try harness.row(world.innerTab), -1)

    try harness.source.moveNode(world.today[1], to: .today(world.work), at: 0)
    XCTAssertEqual(try harness.row(world.inner), -1, "the path goes with the last peeking row")
  }

  /// A folder moved into a closed folder does not peek itself; the current tab inside it does.
  func testAFolderMovedIntoAClosedFolderShowsOnlyTheCurrentTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let moved = try harness.source.addFolder(title: "Moved", in: .today(world.work), at: nil)
    let current = try harness.source.addTab(url: Self.url("m0"), title: "M0", in: .folder(moved), at: nil)
    let other = try harness.source.addTab(url: Self.url("m1"), title: "M1", in: .folder(moved), at: nil)
    try harness.show(current: current)
    try harness.outline().toggleFolder(world.folder, animated: false)

    try harness.source.moveNode(moved, to: .folder(world.folder), at: 0)
    XCTAssertEqual(try harness.row(moved), try harness.row(world.folder) + 1)
    XCTAssertEqual(try harness.row(current), try harness.row(world.folder) + 2)
    XCTAssertEqual(try harness.row(other), -1)
  }

  /// Opening a folder takes its peeking rows back; closing it again leaves only the current tab out.
  func testOpeningAFolderEndsItsMovedInPeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)
    try harness.source.moveNode(world.today[1], to: .folder(world.folder), at: 0)
    XCTAssertGreaterThanOrEqual(try harness.row(world.today[1]), 0)
    outline.toggleFolder(world.folder, animated: false)
    outline.toggleFolder(world.folder, animated: false)
    XCTAssertEqual(try harness.row(world.today[1]), -1)
  }


  /// Switching to a tab inside a closed folder shows that tab alone under the folder, which stays closed; switching
  /// to another tab puts it back.
  func testATabActivatedInAClosedFolderPeeksOut() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)

    harness.controller.activate(node: world.innerTab)
    XCTAssertFalse(outline.isFolderOpen(world.folder), "the folder stays closed")
    XCTAssertEqual(try harness.row(world.inner), try harness.row(world.folder) + 1, "the path to the tab shows")
    XCTAssertEqual(try harness.row(world.innerTab), try harness.row(world.folder) + 2)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1, "its siblings stay hidden")
    XCTAssertEqual(try harness.row(world.pinnedTab), try harness.row(world.folder) + 3)

    harness.controller.activate(node: world.today[1])
    XCTAssertEqual(try harness.row(world.innerTab), -1, "the peek ends when another tab is current")
    XCTAssertEqual(try harness.row(world.pinnedTab), try harness.row(world.folder) + 1)
  }

  /// BH-092, BH-091 (the model side; the drag itself is #104): a tab moved into a closed folder peeks out under it
  /// and the folder stays closed.
  func testATabMovedIntoAClosedFolderPeeksAndTheFolderStaysClosed() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)

    try harness.source.moveNode(world.today[1], to: .folder(world.folder), at: 0)
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    XCTAssertEqual(try harness.row(world.today[1]), try harness.row(world.folder) + 1)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1)
  }

  /// Closing the folder of the current tab keeps the current tab in view under it [I].
  func testClosingTheFolderOfTheCurrentTabLeavesItPeeking() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.folderTabs[1])

    try harness.click(world.folder)
    try harness.advance(by: 0.06)
    XCTAssertEqual(try harness.style(world.folderTabs[1]).alpha, 1, "the current row does not fade")
    try harness.advance(by: 2)
    XCTAssertEqual(try harness.row(world.folderTabs[1]), try harness.row(world.folder) + 1)
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1)
    XCTAssertEqual(try harness.style(world.folderTabs[1]), .rest)
  }

  // MARK: Collapse All / Expand All (BH-097)

  func testCollapseAllAndExpandAllFoldersFromTheTabsMenu() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let outline = try harness.outline()
    let items = TabsMenu.items()
    let collapse = try XCTUnwrap(items.first { $0.action == #selector(ShellWindowController.collapseAllFolders(_:)) })
    let expand = try XCTUnwrap(items.first { $0.action == #selector(ShellWindowController.expandAllFolders(_:)) })
    XCTAssertEqual(collapse.title, "Collapse All Folders")
    XCTAssertEqual(expand.title, "Expand All Folders")
    XCTAssertTrue(harness.controller.validateMenuItem(collapse))

    harness.controller.collapseAllFolders(nil)
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    XCTAssertFalse(outline.isFolderOpen(world.inner), "nested folders close too")
    try harness.advance(by: 0.06)
    XCTAssertLessThan(try harness.style(world.pinnedTab).offsetY, 0, "Collapse All moves on the same spring")
    try harness.advance(by: 2)
    XCTAssertEqual(try harness.row(world.pinnedTab), try harness.row(world.folder) + 1)

    harness.controller.expandAllFolders(nil)
    XCTAssertTrue(outline.isFolderOpen(world.folder))
    XCTAssertTrue(outline.isFolderOpen(world.inner))
    try harness.advance(by: 2)
    XCTAssertEqual(try harness.row(world.innerTab), try harness.row(world.inner) + 1, "nested rows are back")
    XCTAssertEqual(try harness.style(world.innerTab), .rest)
  }

  func testTheFolderItemsAreDisabledInASpaceWithoutFolders() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: Self.url("t"), title: "T", in: .today(work))
    let harness = Harness(sidebar)
    defer { harness.controller.close() }
    harness.controller.activate(node: tab)
    let collapse = NSMenuItem(title: "", action: #selector(ShellWindowController.collapseAllFolders(_:)),
                              keyEquivalent: "")
    XCTAssertFalse(harness.controller.validateMenuItem(collapse))
  }

  // MARK: Per window (BH-098)

  /// Two windows on one sidebar: closing a folder in one leaves it open in the other.
  func testEachWindowKeepsItsOwnOpenFolders() throws {
    let world = try Self.makeWorld()
    let first = Harness(world.sidebar)
    let second = Harness(world.sidebar, source: first.source)
    defer {
      first.controller.close()
      second.controller.close()
    }
    try first.outline().toggleFolder(world.folder, animated: false)
    XCTAssertFalse(try first.outline().isFolderOpen(world.folder))
    XCTAssertTrue(try second.outline().isFolderOpen(world.folder))
    XCTAssertGreaterThanOrEqual(try second.row(world.folderTabs[0]), 0)

    second.controller.collapseAllFolders(nil)
    try second.outline().folderMotion.settleNow()
    first.controller.expandAllFolders(nil)
    try first.outline().folderMotion.settleNow()
    XCTAssertTrue(try first.outline().isFolderOpen(world.inner))
    XCTAssertFalse(try second.outline().isFolderOpen(world.inner))
  }

  // MARK: New Folder (BH-094, KB-040)

  /// Shift-selected tabs inside a folder form a folder nested at their place in it (BH-094).
  func testNewFolderOnTabsInsideAFolderNestsIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    harness.controller.activate(node: world.folderTabs[0])
    try harness.outline().handleClick(row: try harness.row(world.folderTabs[1]), modifiers: .shift)
    XCTAssertEqual(try harness.outline().selectedNodes, world.folderTabs)

    harness.controller.perform(.newFolder(world.folderTabs))

    let children = harness.children(.folder(world.folder))
    XCTAssertEqual(children.count, 2, "the new folder and Inner")
    let made = try XCTUnwrap(children.first)
    XCTAssertEqual(children.last, world.inner)
    XCTAssertEqual(harness.children(.folder(made)), world.folderTabs)
    XCTAssertEqual(harness.children(.pinned(world.work)), [world.folder, world.pinnedTab], "nothing left the folder")
    XCTAssertEqual(try harness.outline().renamingNode, made)
  }

  /// Tabs from different places still go to a new pinned folder, as #105 shipped.
  func testNewFolderOnTabsFromSeveralPlacesPinsIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    harness.controller.perform(.newFolder([world.folderTabs[0], world.today[0]]))
    let pinned = harness.children(.pinned(world.work))
    XCTAssertEqual(pinned.count, 3)
    let made = try XCTUnwrap(pinned.first { !([world.folder, world.pinnedTab]).contains($0) })
    XCTAssertEqual(harness.children(.folder(made)), [world.folderTabs[0], world.today[0]])
  }

  /// New Folder in the Tabs menu (KB-040, unbound until RT-04): the selection when there is one, else an
  /// empty pinned folder, open for naming.
  func testNewFolderFromTheTabsMenu() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let item = try XCTUnwrap(TabsMenu.items().first { $0.action == #selector(ShellWindowController.newFolder(_:)) })
    XCTAssertEqual(item.title, "New Folder")
    XCTAssertEqual(item.keyEquivalent, "", "unbound: Cmd-Shift-N stays New Incognito Window (CF-02)")
    harness.controller.activate(node: world.today[0])

    harness.controller.newFolder(nil)

    let pinned = harness.children(.pinned(world.work))
    XCTAssertEqual(pinned.count, 3)
    let made = try XCTUnwrap(pinned.last)
    XCTAssertTrue(harness.children(.folder(made)).isEmpty)
    XCTAssertEqual(try harness.outline().renamingNode, made)
  }

  // MARK: Folder Preview (BH-093, GS-019)

  /// Shows the window with the folder closed and hovers its row the way the pointer does (the row view's hover).
  private func hoverClosedFolder(_ harness: Harness, _ world: World) throws -> FolderPreviewController {
    try harness.show(current: world.today[0])
    try harness.outline().toggleFolder(world.folder, animated: false)
    let rowView = try XCTUnwrap(try harness.outline().outlineView.rowView(
      atRow: try harness.row(world.folder), makeIfNecessary: false) as? SidebarRowView)
    rowView.isHovered = true
    return harness.controller.sidebarController.folderPreview
  }

  func testHoveringAClosedFolderShowsItsPreviewWithTheSearchFieldFocused() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    XCTAssertNil(preview.shownFolder, "the preview waits for the hover delay")

    preview.firePendingTimer()

    XCTAssertEqual(preview.shownFolder, world.folder)
    XCTAssertEqual(preview.view.rowViews.prefix(preview.view.rowCount).map(\.titleField.stringValue),
                   ["F0", "F1", "G0"], "every tab of the folder, nested ones included")
    XCTAssertEqual(preview.view.highlightedRow, 0)
    let window = try XCTUnwrap(harness.controller.window)
    XCTAssertTrue((window.firstResponder as? NSTextView)?.delegate === preview.view.searchField,
                  "typing goes to the search field")
    XCTAssertTrue(preview.view.isDescendant(of: try XCTUnwrap(window.contentView)))
    let sidebarRight = harness.controller.sidebarController.view.convert(
      harness.controller.sidebarController.view.bounds, to: nil).maxX
    XCTAssertGreaterThanOrEqual(preview.view.convert(preview.view.bounds, to: nil).minX, sidebarRight,
                                "it opens beside the sidebar")
    XCTAssertEqual(preview.view.accessibilityIdentifier(), AXID.FolderPreview.panel)
  }

  /// Typing selects the first match; Return activates it, the folder stays closed and the tab peeks out under it.
  func testTypingSelectsTheFirstMatchAndReturnActivatesItPeekingOut() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    preview.firePendingTimer()
    let window = try XCTUnwrap(harness.controller.window)
    let editor = try XCTUnwrap(window.firstResponder as? NSTextView)

    editor.insertText("g", replacementRange: editor.selectedRange())
    XCTAssertEqual(preview.view.rowViews.prefix(preview.view.rowCount).map(\.titleField.stringValue), ["G0"])
    XCTAssertEqual(preview.view.highlightedRow, 0)
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

    XCTAssertEqual(harness.controller.sidebarController.current, world.innerTab)
    XCTAssertNil(preview.shownFolder)
    let outline = try harness.outline()
    XCTAssertFalse(outline.isFolderOpen(world.folder), "the folder stays closed")
    XCTAssertGreaterThanOrEqual(try harness.row(world.innerTab), 0, "the chosen tab peeks out")
    XCTAssertEqual(try harness.row(world.folderTabs[0]), -1)
    XCTAssertFalse((window.firstResponder as? NSTextView)?.delegate === preview.view.searchField,
                   "the field gave focus back")
  }

  func testArrowsMoveTheHighlightAndAClickChoosesARow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    preview.firePendingTimer()
    let editor = try XCTUnwrap(harness.controller.window?.firstResponder as? NSTextView)
    editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
    XCTAssertEqual(preview.view.highlightedRow, 1)
    preview.view.rowViews[0].onClick?()
    XCTAssertEqual(harness.controller.sidebarController.current, world.folderTabs[0])
    XCTAssertNil(preview.shownFolder)
  }

  func testEscapeClosesThePreviewAndGivesFocusBack() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    preview.firePendingTimer()
    let editor = try XCTUnwrap(harness.controller.window?.firstResponder as? NSTextView)
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertNil(preview.shownFolder)
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0], "nothing was chosen")
  }

  /// Moving from one closed folder to the next keeps the preview up and the keyboard in its field.
  func testMovingToAnotherClosedFolderSwitchesThePreview() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let second = try harness.source.addFolder(title: "Second", in: .pinned(world.work), at: nil)
    try harness.source.addTab(url: Self.url("s0"), title: "S0", in: .folder(second), at: nil)
    let preview = try hoverClosedFolder(harness, world)
    try harness.outline().toggleFolder(second, animated: false)
    preview.firePendingTimer()

    preview.folderHoverChanged(world.folder, hovered: false)
    preview.folderHoverChanged(second, hovered: true)
    preview.firePendingTimer()

    XCTAssertEqual(preview.shownFolder, second)
    XCTAssertEqual(preview.view.rowViews.prefix(preview.view.rowCount).map(\.titleField.stringValue), ["S0"])
    XCTAssertTrue((harness.controller.window?.firstResponder as? NSTextView)?.delegate === preview.view.searchField)
  }

  /// An open folder shows its tabs already: no preview.
  func testAnOpenFolderShowsNoPreview() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    try harness.show(current: world.today[0])
    let rowView = try XCTUnwrap(try harness.outline().outlineView.rowView(
      atRow: try harness.row(world.folder), makeIfNecessary: false) as? SidebarRowView)
    rowView.isHovered = true
    let preview = harness.controller.sidebarController.folderPreview
    preview.firePendingTimer()
    XCTAssertNil(preview.shownFolder)
  }

  /// Leaving the folder row hides the preview after a short grace, unless the pointer went into the preview.
  func testLeavingTheRowHidesThePreviewUnlessThePointerIsInIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    preview.firePendingTimer()

    preview.folderHoverChanged(world.folder, hovered: false)
    preview.pointerInPreviewChanged(true)
    preview.firePendingTimer()
    XCTAssertEqual(preview.shownFolder, world.folder, "the pointer moved into the preview")

    preview.pointerInPreviewChanged(false)
    preview.firePendingTimer()
    XCTAssertNil(preview.shownFolder)
  }

  /// The preview scales in from its leading edge and fades; Reduce Motion keeps only the fade.
  func testThePreviewFadesInAndReduceMotionDropsTheScale() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let preview = try hoverClosedFolder(harness, world)
    preview.reduceMotion = { false }
    preview.firePendingTimer()
    let layer = try XCTUnwrap(preview.view.layer)
    XCTAssertNotNil(layer.animation(forKey: FolderPreviewView.enterOpacityKey))
    let scale = try XCTUnwrap(layer.animation(forKey: FolderPreviewView.enterScaleKey) as? CABasicAnimation)
    XCTAssertLessThanOrEqual(scale.duration, 0.2)
    preview.hide(animated: false)

    preview.reduceMotion = { true }
    preview.show(folder: world.folder)
    XCTAssertNotNil(layer.animation(forKey: FolderPreviewView.enterOpacityKey))
    XCTAssertNil(layer.animation(forKey: FolderPreviewView.enterScaleKey), "Reduce Motion: no scale")
  }

  // MARK: Rename (BH-096)

  /// The folder rename field saves the typed name when focus leaves it for anything outside the sidebar.
  func testFolderRenameSavesWhenFocusLeaves() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    harness.controller.showWindow(nil)
    XCTAssertTrue(try harness.outline().beginRename(world.folder))
    let cell = try XCTUnwrap(try harness.outline().outlineView.view(
      atColumn: 0, row: try harness.row(world.folder), makeIfNecessary: false) as? SidebarTabCellView)
    let editor = try XCTUnwrap(cell.renameField?.currentEditor() as? NSTextView)
    editor.insertText("Reading", replacementRange: editor.selectedRange())

    harness.controller.window?.makeFirstResponder(nil)

    guard case .folder(_, let title)? = harness.source.node(world.folder) else { return XCTFail("no folder") }
    XCTAssertEqual(title, "Reading")
  }
}
