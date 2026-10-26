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
    XCTAssertEqual(try harness.rowLayer(world.pinnedTab).transform.m42, below.offsetY,
                   "the frame reaches the row view as a layer transform, not a frame change")
    XCTAssertEqual(CGFloat(try harness.rowLayer(world.folderTabs[1]).opacity), child.alpha, accuracy: 0.001)

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
    let fade = try XCTUnwrap(try harness.rowLayer(world.folderTabs[0]).animation(forKey: SidebarOutlineController.folderFadeKey)
      as? CABasicAnimation)
    XCTAssertEqual(fade.keyPath, "opacity")
    XCTAssertEqual(fade.fromValue as? Float, 0)
    XCTAssertNil(try harness.rowLayer(world.pinnedTab).animation(forKey: SidebarOutlineController.folderFadeKey),
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

  // MARK: Peeking rows (BH-092, BH-105)

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
