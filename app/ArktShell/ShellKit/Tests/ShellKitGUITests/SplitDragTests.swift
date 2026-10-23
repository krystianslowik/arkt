import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Split View S7: dragging a sidebar tab onto the page splits it (GS-011, BH-117), with a drop preview (decision 11,
/// PARITY(NEEDS-RUNTIME-CHECK RT-32)). The drag session is not synthesized: the outline's pasteboard writer is asserted
/// directly, the drag start and end go through the outline's session hooks, and the drop overlay's dragging path is
/// driven through `preview(at:)` and `drop(node:at:)`.
@MainActor
final class SplitDragTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with Pinned `[folder(f0)]` and Today `[t0, t1, t2, split(s0 ... sN-1)]`.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var folder: UUID
    var folderTab: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitDragTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    var root: ShellRootView { controller.rootView }
    var split: SplitContainerView { root.split }
    var current: UUID? { controller.sidebarController.current }
    var overlay: SplitDropOverlayView? { controller.splitState.dropOverlay }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    /// What the outline writes to the pasteboard for `node`'s row (nil: the row cannot be dragged).
    func writer(_ node: UUID) throws -> NSPasteboardWriting? {
      let outline = try outline()
      return outline.outlineView(outline.outlineView, pasteboardWriterForItem: outline.item(for: node))
    }

    /// Starts a sidebar drag of `node` the way the outline's dragging session does, and returns the overlay.
    func beginDrag(_ node: UUID) throws -> SplitDropOverlayView {
      let outline = try outline()
      outline.draggingSessionWillBegin(items: [outline.item(for: node)])
      return try XCTUnwrap(overlay, "no drop overlay during a sidebar drag")
    }

    func endDrag() throws { try outline().draggingSessionEnded() }

    /// A point in `overlay` at fractions of its width and height (unflipped: 1 is the top).
    func point(_ overlay: SplitDropOverlayView, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: overlay.bounds.minX + overlay.bounds.width * x, y: overlay.bounds.minY + overlay.bounds.height * y)
    }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }

    func layout(of split: UUID) -> SplitLayoutInfo? {
      if case .split(_, let layout)? = source.node(split) { layout } else { nil }
    }

    /// The split that holds `node`, from the source.
    func split(holding node: UUID) -> UUID? {
      if case .split(let split)? = source.parent(of: node) { split } else { nil }
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(panes count: Int = 2) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    let folderTab = try sidebar.addTab(url: url("f0"), title: "F0", in: .folder(folder))
    let today = try (0..<3).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let factors = Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors, in: .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    return World(sidebar: sidebar, space: space, folder: folder, folderTab: folderTab, today: today, split: split,
                 panes: panes)
  }

  // MARK: Drag source

  /// Only tab rows (plain tabs, tabs in folders, panes) write the private node type, with the node's id.
  func testPasteboardWriterOnlyForTabs() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()

    for node in [world.today[0], world.folderTab, world.panes[1]] {
      let item = try XCTUnwrap(try harness.writer(node) as? NSPasteboardItem, "a tab row is a drag source")
      XCTAssertEqual(item.types, [.sidebarNode])
      XCTAssertEqual(item.string(forType: .sidebarNode), node.uuidString)
    }
    XCTAssertNil(try harness.writer(world.split), "a split row is not a drag source")
    XCTAssertNil(try harness.writer(world.folder), "a folder row is not a drag source")
    let divider = try XCTUnwrap(outline.outlineView.item(atRow: outline.dividerRow))
    XCTAssertNil(outline.outlineView(outline.outlineView, pasteboardWriterForItem: divider),
                 "the divider is not a drag source")
    harness.controller.close()
  }

  // MARK: Overlay life

  /// The overlay is in the view tree only between drag start and end, sits above the page, accepts only the private
  /// node type, and lets every click through to the page below it.
  func testOverlayAbsentOutsideDragAndPassesClicks() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let root = harness.root
    func overlayInTree() -> Bool { root.subviews.contains { $0 is SplitDropOverlayView } }
    XCTAssertFalse(overlayInTree(), "no overlay before a drag")

    let overlay = try harness.beginDrag(world.today[2])
    XCTAssertTrue(overlayInTree())
    XCTAssertEqual(overlay.frame, root.card.frame, "the overlay covers the content area")
    XCTAssertEqual(overlay.registeredDraggedTypes, [.sidebarNode])
    let cardIndex = try XCTUnwrap(root.subviews.firstIndex(of: root.card))
    let splitIndex = try XCTUnwrap(root.subviews.firstIndex(of: root.split))
    let overlayIndex = try XCTUnwrap(root.subviews.firstIndex(of: overlay))
    XCTAssertGreaterThan(overlayIndex, max(cardIndex, splitIndex), "the overlay is above the page")
    let center = NSPoint(x: root.card.frame.midX, y: root.card.frame.midY)
    XCTAssertNil(overlay.hitTest(overlay.convert(center, from: root)), "clicks pass through the overlay")
    let hit = try XCTUnwrap(root.hitTest(center))
    XCTAssertFalse(hit === overlay, "the window's hit test never lands on the overlay")

    try harness.endDrag()
    XCTAssertFalse(overlayInTree(), "the overlay leaves when the drag ends")
    harness.controller.close()
  }

  // MARK: Drops

  /// Right third: a side-by-side split takes the current tab's place, the dragged tab second; it gets focus.
  func testDropRightCreatesSideBySideSplitAtCurrentsPlace() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[2])

    XCTAssertTrue(overlay.drop(node: world.today[2], at: harness.point(overlay, 0.9, 0.5)))
    try harness.endDrag()

    let split = try XCTUnwrap(harness.split(holding: world.today[1]), "the current tab is now a pane")
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[0], split, world.split],
                   "the split takes the current tab's place; the dragged tab left Today")
    XCTAssertEqual(harness.children(.split(split)), [world.today[1], world.today[2]])
    XCTAssertEqual(harness.layout(of: split)?.orientation, .horizontal)
    waitUntil("the new split shown with the dropped pane focused") {
      harness.root.showsSplit && harness.split.paneCount == 2 && harness.current == world.today[2]
    }
    XCTAssertEqual(harness.split.axis, .sideBySide)
    XCTAssertEqual(harness.split.focusedIndex, 1)
    harness.controller.close()
  }

  /// Left third: the dragged tab goes first, side by side.
  func testDropLeftPutsTheDraggedTabFirst() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[0])

    XCTAssertTrue(overlay.drop(node: world.today[0], at: harness.point(overlay, 0.1, 0.5)))
    try harness.endDrag()

    let split = try XCTUnwrap(harness.split(holding: world.today[1]))
    XCTAssertEqual(harness.children(.split(split)), [world.today[0], world.today[1]])
    XCTAssertEqual(harness.layout(of: split)?.orientation, .horizontal)
    waitUntil("the new split shown with the dropped pane focused") {
      harness.split.paneCount == 2 && harness.current == world.today[0]
    }
    harness.controller.close()
  }

  /// Top quarter of the middle column: a stacked split, the dragged tab on top.
  func testDropTopCreatesStackedSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[2])

    XCTAssertTrue(overlay.drop(node: world.today[2], at: harness.point(overlay, 0.5, 0.95)))
    try harness.endDrag()

    let split = try XCTUnwrap(harness.split(holding: world.today[1]))
    XCTAssertEqual(harness.children(.split(split)), [world.today[2], world.today[1]])
    XCTAssertEqual(harness.layout(of: split)?.orientation, .vertical)
    waitUntil("the stacked split shown with the dropped pane focused") {
      harness.split.paneCount == 2 && harness.split.axis == .stacked && harness.current == world.today[2]
    }
    XCTAssertEqual(harness.split.focusedIndex, 0)
    harness.controller.close()
  }

  /// A tab dropped on a shown split joins it: the right side appends it, the split's orientation stays.
  func testDropOnShownSplitAddsAPane() throws {
    let world = try Self.makeWorld(panes: 2)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let overlay = try harness.beginDrag(world.today[0])

    XCTAssertTrue(overlay.drop(node: world.today[0], at: harness.point(overlay, 0.5, 0.05)),
                  "the bottom zone of a side-by-side split appends a pane side by side")
    try harness.endDrag()

    XCTAssertEqual(harness.children(.split(world.split)), world.panes + [world.today[0]])
    XCTAssertEqual(harness.layout(of: world.split)?.orientation, .horizontal)
    waitUntil("the split shown with three panes, the dropped one focused") {
      harness.split.paneCount == 3 && harness.current == world.today[0]
    }
    harness.controller.close()
  }

  /// BH-116: a tab dropped on a full split shows "Cannot Add New Pane" and changes nothing.
  func testDropOnFullSplitShowsToast() throws {
    let world = try Self.makeWorld(panes: SplitLayoutInfo.maximumPanes)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let overlay = try harness.beginDrag(world.today[0])

    XCTAssertEqual(overlay.preview(at: harness.point(overlay, 0.9, 0.5)), .full, "a full split takes the drop")
    XCTAssertTrue(overlay.previewLayer.isHidden, "no preview for a full split")
    XCTAssertFalse(overlay.drop(node: world.today[0], at: harness.point(overlay, 0.9, 0.5)))
    try harness.endDrag()

    XCTAssertEqual(harness.controller.toasts.current?.text, "Cannot Add New Pane")
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    XCTAssertEqual(harness.children(.today(world.space)), world.today + [world.split])
    XCTAssertEqual(harness.current, world.panes[1], "focus stays")
    harness.controller.close()
  }

  /// A pane of the shown split dropped on the left side moves to the front; factors follow it; it gets focus.
  func testDropPaneOfShownSplitReorders() throws {
    var world = try Self.makeWorld(panes: 3)
    try world.sidebar.setSplitWidthFactors(world.split, [0.5, 0.3, 0.2])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let overlay = try harness.beginDrag(world.panes[2])

    XCTAssertTrue(overlay.drop(node: world.panes[2], at: harness.point(overlay, 0.1, 0.5)))
    try harness.endDrag()

    XCTAssertEqual(harness.children(.split(world.split)), [world.panes[2], world.panes[0], world.panes[1]])
    let factors = try XCTUnwrap(harness.layout(of: world.split)?.widthFactors)
    XCTAssertEqual(factors, [0.2, 0.5, 0.3], "factors follow their panes")
    waitUntil("the reordered split shown with the moved pane focused") {
      harness.split.focusedIndex == 0 && harness.current == world.panes[2]
    }
    harness.controller.close()
  }

  /// Refused drops: the current tab onto itself, a split row's id, and a pane already where the zone puts it. None
  /// shows a preview or changes the source.
  func testRefusedDropsChangeNothing() throws {
    let world = try Self.makeWorld(panes: 2)
    let harness = Harness(world.sidebar)
    let before = harness.children(.today(world.space))
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[1])
    let right = harness.point(overlay, 0.9, 0.5)
    XCTAssertEqual(overlay.preview(at: right), SplitDropTarget.none, "the current tab onto itself")
    XCTAssertTrue(overlay.previewLayer.isHidden)
    XCTAssertFalse(overlay.drop(node: world.today[1], at: right))
    XCTAssertFalse(overlay.drop(node: world.split, at: right), "a split is not a tab")
    try harness.endDrag()
    XCTAssertEqual(harness.children(.today(world.space)), before)

    harness.controller.activate(node: world.panes[0])
    let paneOverlay = try harness.beginDrag(world.panes[1])
    XCTAssertEqual(paneOverlay.preview(at: right), SplitDropTarget.none, "the last pane dropped on the right stays")
    XCTAssertFalse(paneOverlay.drop(node: world.panes[1], at: right))
    try harness.endDrag()
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    harness.controller.close()
  }

  // MARK: Preview

  /// The preview sits exactly where the new pane lands: the frame `preview(at:)` reports, the preview layer's frame,
  /// and the pane card's frame after the drop all match.
  func testPreviewFrameMatchesFutureLayout() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[2])
    let right = harness.point(overlay, 0.9, 0.5)

    guard case .pane(let frame) = overlay.preview(at: right) else {
      return XCTFail("a drop on a plain tab previews the new pane")
    }
    XCTAssertFalse(overlay.previewLayer.isHidden)
    XCTAssertEqual(overlay.previewLayer.frame, frame)
    XCTAssertEqual(frame.maxX, overlay.bounds.maxX, "the new pane is the right half")
    XCTAssertEqual(frame.height, overlay.bounds.height)
    XCTAssertTrue(overlay.drop(node: world.today[2], at: right))
    try harness.endDrag()
    waitUntil("the new split shown") { harness.split.paneCount == 2 }
    XCTAssertEqual(harness.split.paneCards[1].frame, frame, "the preview matched the pane's frame")
    harness.controller.close()
  }

  /// On a shown split, the preview is the frame the pane gets after the drop, with all shares equal (RT-35).
  func testPreviewOnShownSplitMatchesTheAddedPane() throws {
    let world = try Self.makeWorld(panes: 2)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let overlay = try harness.beginDrag(world.today[0])
    let left = harness.point(overlay, 0.1, 0.5)

    guard case .pane(let frame) = overlay.preview(at: left) else {
      return XCTFail("a drop on a split with room previews the new pane")
    }
    XCTAssertEqual(frame.minX, overlay.bounds.minX, "the new pane is first")
    XCTAssertTrue(overlay.drop(node: world.today[0], at: left))
    try harness.endDrag()
    waitUntil("the split shown with three panes") { harness.split.paneCount == 3 }
    XCTAssertEqual(harness.split.paneCards[0].frame, frame)
    harness.controller.close()
  }

  /// Moving the pointer within one zone does not touch the preview layer again (no work per frame beyond the zone).
  func testPreviewMovesOnlyWhenTheZoneChanges() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let overlay = try harness.beginDrag(world.today[2])

    _ = overlay.preview(at: harness.point(overlay, 0.9, 0.5))
    let updates = overlay.previewUpdateCount
    for step in 0..<20 { _ = overlay.preview(at: harness.point(overlay, 0.7 + CGFloat(step) * 0.01, 0.5)) }
    XCTAssertEqual(overlay.previewUpdateCount, updates, "the same zone keeps the preview where it is")
    _ = overlay.preview(at: harness.point(overlay, 0.1, 0.5))
    XCTAssertEqual(overlay.previewUpdateCount, updates + 1)
    try harness.endDrag()
    harness.controller.close()
  }
}
