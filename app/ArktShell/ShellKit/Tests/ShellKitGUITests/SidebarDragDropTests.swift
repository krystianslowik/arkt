import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Sidebar drag and drop (#104) in a real window over the model source: reorder, pin and unpin across the divider
/// (GS-007), Favorites leaving for the page (BH-047), onto a folder (GS-009), onto a tab (GS-010, BH-118), the
/// Space edge (GS-012), out to a new window (GS-013), Opt-drag (GS-014), text (GS-015), the selected set (#105), the
/// spring preview and its Reduce Motion variant, and the four bug classes of earlier sidebar work.
///
/// Drag sessions are not synthesized (the `SplitDragTests` pattern): the outline's session hooks start them and the
/// drop helper's `update(at:payload:)` / `perform(...)` drive the destination, so every test is deterministic.
@MainActor
final class SidebarDragDropTests: XCTestCase {
  private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
  /// Long before `start`: older than any auto-archive threshold.
  private static let ancient = Date(timeIntervalSinceReferenceDate: 700_000_000)

  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var other: UUID
    var pinned: [UUID]
    var folder: UUID
    var foldered: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
    var favorite: UUID
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  /// Space "Work": Pinned `[p0, p1, Folder [f0]]`, Today `[t0, t1, t2, Split [l, r]]`; Space "Home" with one Today
  /// tab; one Favorite. Every tab was last active long ago.
  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let other = sidebar.addSpace(title: "Home")
    let old = ancient
    let pinned = try (0..<2).map {
      try sidebar.addTab(url: url("p\($0)"), title: "P\($0)", lastActiveAt: old, in: .pinned(space))
    }
    let folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    let foldered = try sidebar.addTab(url: url("f0"), title: "F0", lastActiveAt: old, in: .folder(folder))
    let today = try (0..<3).map {
      try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", lastActiveAt: old, in: .today(space))
    }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["l", "r"].map {
      try sidebar.addTab(url: url($0), title: $0, lastActiveAt: old, in: .split(split))
    }
    _ = try sidebar.addTab(url: url("h0"), title: "H0", lastActiveAt: old, in: .today(other))
    let favorite = try sidebar.addTab(url: url("fav"), title: "Fav", lastActiveAt: old,
                                      in: .favorites(profile: "default"))
    return World(sidebar: sidebar, space: space, other: other, pinned: pinned, folder: folder, foldered: foldered,
                 today: today, split: split, panes: panes, favorite: favorite)
  }

  @MainActor
  private final class Clock {
    var date = SidebarDragDropTests.start
  }

  @MainActor
  private final class Harness {
    let clock = Clock()
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var errors: [SidebarMutation] = []
    var haptics = 0
    var motionTime: CFTimeInterval = 100

    init(_ sidebar: SidebarModel.Sidebar, reduceMotion: Bool = false) {
      let clock = self.clock
      let source = ModelSidebarSource(sidebar: sidebar, now: { clock.date })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onError = { [unowned self] mutation, _ in errors.append(mutation) }
      controller.onTabHidden = { id in source.markInactive([id], at: clock.date) }   // as the app does
      configure(reduceMotion: reduceMotion)
    }

    func configure(reduceMotion: Bool) {
      for page in pages {
        page.outlineController.drop.reduceMotion = { reduceMotion }
        page.outlineController.drop.now = { [unowned self] in motionTime }
        page.outlineController.drop.haptic = { [unowned self] in haptics += 1 }
      }
    }

    var pages: [SpacePageView] {
      controller.sidebarController.view.pager.pages.compactMap { $0 as? SpacePageView }
    }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func drop() throws -> SidebarOutlineDrop { try outline().drop }

    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }

    /// A point in `node`'s row (outline coordinates) at `y` of its height (0: top) and `x` of its width.
    func point(_ node: UUID, y: CGFloat, x: CGFloat = 0.3) throws -> NSPoint {
      try point(row: row(node), y: y, x: x)
    }

    func point(row: Int, y: CGFloat, x: CGFloat = 0.3) throws -> NSPoint {
      let rect = try outline().outlineView.rect(ofRow: row)
      return NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    func payload(_ nodes: [UUID]) -> SidebarDragPayload {
      let single = nodes.count == 1 && { if case .tab? = source.node(nodes[0]) { true } else { false } }()
      return SidebarDragPayload(nodes: nodes, isSingleTab: single)
    }

    /// Previews then drops `nodes` at `point` of the current page.
    @discardableResult
    func drag(_ nodes: [UUID], to point: NSPoint, duplicate: Bool = false) throws -> Bool {
      let drop = try drop()
      drop.update(at: point, payload: payload(nodes))
      return drop.perform(payload: payload(nodes), at: point, duplicate: duplicate, fromOtherWindow: false)
    }

    func tab(_ id: UUID) -> SidebarModel.TabItem? {
      if case .tab(let tab)? = source.sidebar.nodes[id]?.kind { tab } else { nil }
    }

    /// Loads `node`'s page and navigates it to `path`.
    func navigate(_ node: UUID, to path: String) throws {
      controller.activate(node: node)
      let tab = try XCTUnwrap(controller.engineTab(of: node))
      engine.navigate(tab, to: SidebarDragDropTests.url(path))
    }

    /// What auto-archive would close now with a 12 hour threshold and this window's exemptions.
    func autoArchived() -> [UUID] {
      AutoArchivePolicy.itemsToArchive(
        in: source.sidebar,
        AutoArchiveInput(now: clock.date, startedAt: SidebarDragDropTests.ancient,
                         exempt: controller.sidebarController.resolver.visible, threshold: { _ in .twelveHours }))
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: Source

  func testATabRowWritesItselfAndTheSetToThePasteboard() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    let writer = try XCTUnwrap(outline.outlineView(outline.outlineView, pasteboardWriterForItem:
      outline.item(for: world.today[0])) as? NSPasteboardItem)
    XCTAssertEqual(writer.string(forType: .sidebarNode), world.today[0].uuidString)
    XCTAssertEqual(writer.string(forType: .sidebarNodes), world.today[0].uuidString)
  }

  func testFoldersAndSplitsAreDraggableNow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    for node in [world.folder, world.split] {
      XCTAssertNotNil(outline.outlineView(outline.outlineView, pasteboardWriterForItem: outline.item(for: node)))
    }
  }

  func testDraggingARowOfTheSelectionCarriesTheWholeSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    outline.handleClick(row: try harness.row(world.today[0]), modifiers: .command)
    outline.handleClick(row: try harness.row(world.today[2]), modifiers: .command)
    let writer = try XCTUnwrap(outline.outlineView(outline.outlineView, pasteboardWriterForItem:
      outline.item(for: world.today[2])) as? NSPasteboardItem)
    XCTAssertEqual(writer.string(forType: .sidebarNode), world.today[2].uuidString)
    let carried = writer.string(forType: .sidebarNodes).flatMap(SidebarDragPayload.nodes(fromPasteboardString:))
    XCTAssertEqual(carried, outline.selectedNodes, "the selection in display order (it starts from the current row)")
    XCTAssertTrue(carried?.contains(world.today[0]) ?? false)
    XCTAssertTrue(carried?.contains(world.today[2]) ?? false)
  }

  func testTheOutlineTakesSidebarDragsAndText() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let types = try harness.outline().outlineView.registeredDraggedTypes
    for type in [NSPasteboard.PasteboardType.sidebarNode, .sidebarNodes, .string, .URL] {
      XCTAssertTrue(types.contains(type), "\(type.rawValue)")
    }
  }

  func testTheFavoritesOverlayCoversOnlyTheBand() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.outline().draggingSessionWillBegin(items: [harness.outline().item(for: world.today[0])])
    let overlay = try XCTUnwrap(harness.controller.sidebarController.dropOverlay)
    let view = harness.controller.sidebarController.view
    XCTAssertEqual(overlay.frame.height, FavoritesDrop.band(favoritesFrame: view.favorites.frame).height,
                   accuracy: 0.5, "the rows below are the outline's to take")
    try harness.outline().draggingSessionEnded()
  }

  // MARK: Reorder and sections

  func testDroppingBetweenTodayRowsReorders() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.today[0]], to: harness.point(world.today[2], y: 0.9)))
    XCTAssertEqual(harness.source.children(of: .today(world.space)),
                   [world.today[1], world.today[2], world.today[0], world.split])
  }

  /// GS-007: above the divider pins.
  func testDroppingATodayTabAboveTheDividerPinsIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let divider = try harness.outline().dividerRow
    XCTAssertTrue(try harness.drag([world.today[1]], to: harness.point(row: divider, y: 0.3)))
    XCTAssertEqual(harness.source.children(of: .pinned(world.space)).last, world.today[1])
  }

  /// GS-007 and the stale-URL bug class: a navigated pinned tab unpinned by a drag keeps the page it shows, and its
  /// idle clock restarts, so the next auto-archive pass does not close it.
  func testUnpinningANavigatedPinByDragTakesTheLiveURLAndRestartsItsClock() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.pinned[0], to: "p0/elsewhere")
    harness.controller.activate(node: world.today[0])          // the pin is no longer shown
    harness.clock.date = Self.start.addingTimeInterval(60)
    let divider = try harness.outline().dividerRow
    XCTAssertTrue(try harness.drag([world.pinned[0]], to: harness.point(row: divider, y: 0.8)))
    XCTAssertEqual(harness.source.children(of: .today(world.space)).first, world.pinned[0])
    XCTAssertEqual(harness.tab(world.pinned[0])?.url, Self.url("p0/elsewhere"), "no stale pinned URL saved")
    XCTAssertEqual(harness.tab(world.pinned[0])?.lastActiveAt, harness.clock.date)
    XCTAssertFalse(harness.autoArchived().contains(world.pinned[0]))
  }

  /// BH-047 and the auto-archive bug class: a Favorite dragged onto the page lands where the indicator was, and
  /// arriving in Today does not let auto-archive close it on the next pass.
  func testAFavoriteDroppedInTodayLandsThereAndIsNotAutoArchived() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.favorite], to: harness.point(world.today[1], y: 0.1)))
    XCTAssertEqual(harness.source.children(of: .today(world.space))[1], world.favorite)
    XCTAssertFalse(harness.autoArchived().contains(world.favorite))
  }

  /// The visible-tab bug class: the shown tab dragged to the other Space stays shown there, so no automatic pass
  /// can take it for a hidden, idle tab.
  func testTheShownTabDraggedToAnotherSpaceStaysShown() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.sidebarController.showSpace(world.other)
    harness.configure(reduceMotion: false)
    let home = harness.source.children(of: .today(world.other))[0]
    XCTAssertTrue(try harness.drag([world.today[0]], to: harness.point(home, y: 0.1)))
    XCTAssertEqual(harness.source.children(of: .today(world.other)), [world.today[0], home])
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0])
    XCTAssertTrue(harness.controller.sidebarController.resolver.visible.contains(world.today[0]))
    XCTAssertFalse(harness.autoArchived().contains(world.today[0]))
  }

  /// The idle-clock bug class: a reorder never resets or drops `lastActiveAt`.
  func testAReorderKeepsTheIdleClock() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.today[2]], to: harness.point(world.today[0], y: 0.1)))
    XCTAssertEqual(harness.tab(world.today[2])?.lastActiveAt, Self.ancient)
  }

  // MARK: Folders (GS-009)

  func testATabDroppedOnAClosedFolderJoinsItAndTheFolderStaysClosed() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)                     // close it
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    XCTAssertTrue(try harness.drag([world.today[0]], to: harness.point(world.folder, y: 0.5)))
    XCTAssertEqual(harness.source.children(of: .folder(world.folder)), [world.foldered, world.today[0]])
    XCTAssertFalse(outline.isFolderOpen(world.folder), "the folder stays closed")
  }

  /// A drag resting on a closed folder opens it on the folder spring, so the drop can land between its rows.
  func testRestingOnAClosedFolderOpensIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)
    XCTAssertFalse(outline.isFolderOpen(world.folder))
    let drop = try harness.drop()
    let point = try harness.point(world.folder, y: 0.5)
    drop.update(at: point, payload: harness.payload([world.today[0]]))
    harness.motionTime += FolderSpringLoad.dwell + 0.01
    drop.update(at: point, payload: harness.payload([world.today[0]]))
    XCTAssertTrue(outline.isFolderOpen(world.folder))
  }

  func testAMovedFolderKeepsItsClosedState() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    outline.toggleFolder(world.folder, animated: false)
    let divider = outline.dividerRow
    XCTAssertTrue(try harness.drag([world.folder], to: harness.point(row: divider, y: 0.8)))
    XCTAssertEqual(harness.source.parent(of: world.folder), .today(world.space))
    XCTAssertFalse(outline.isFolderOpen(world.folder))
  }

  // MARK: Split View (GS-010, BH-118, and the broken-split bug class)

  func testATabDroppedOnTheLeftHalfOfATabMakesASplitWithItFirst() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.today[2]], to: harness.point(world.today[0], y: 0.5, x: 0.2)))
    guard case .split(let split)? = harness.source.parent(of: world.today[2]) else {
      return XCTFail("no split")
    }
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.today[2], world.today[0]])
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[2], "the dropped tab is shown")
  }

  func testAPaneDraggedOutLeavesNoOnePaneSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.panes[1]], to: harness.point(world.today[0], y: 0.1)))
    XCTAssertNil(harness.source.node(world.split), "the split dissolved into its last pane")
    XCTAssertEqual(harness.source.children(of: .today(world.space)),
                   [world.panes[1], world.today[0], world.today[1], world.today[2], world.panes[0]])
  }

  func testAPaneDroppedBetweenItsSplitsPanesReordersThem() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.panes[1]], to: harness.point(world.panes[0], y: 0.1)))
    XCTAssertEqual(harness.source.children(of: .split(world.split)), [world.panes[1], world.panes[0]])
  }

  func testASplitDraggedIntoAFolderKeepsItsPanes() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drag([world.split], to: harness.point(world.folder, y: 0.5)))
    XCTAssertEqual(harness.source.parent(of: world.split), .folder(world.folder))
    XCTAssertEqual(harness.source.children(of: .split(world.split)), world.panes)
  }

  // MARK: The selected set (#105), Opt-drag (GS-014), text (GS-015)

  func testTheSelectedSetMovesTogetherInOrder() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let divider = try harness.outline().dividerRow
    XCTAssertTrue(try harness.drag([world.today[0], world.today[2]], to: harness.point(row: divider, y: 0.3)))
    XCTAssertEqual(Array(harness.source.children(of: .pinned(world.space)).suffix(2)),
                   [world.today[0], world.today[2]])
  }

  func testAnOptionDragDuplicatesAndLeavesTheOriginal() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let divider = try harness.outline().dividerRow
    XCTAssertTrue(try harness.drag([world.today[0]], to: harness.point(row: divider, y: 0.3), duplicate: true))
    XCTAssertEqual(harness.source.children(of: .today(world.space)).first, world.today[0], "the original stays")
    let copy = try XCTUnwrap(harness.source.children(of: .pinned(world.space)).last)
    XCTAssertNotEqual(copy, world.today[0])
    XCTAssertEqual(harness.tab(copy)?.url, Self.url("t0"))
  }

  func testDroppedTextOpensASearchTabWhereTheIndicatorIs() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.drop().performText("spring physics", at: harness.point(world.today[1], y: 0.1)))
    let added = harness.source.children(of: .today(world.space))[1]
    XCTAssertEqual(harness.tab(added)?.url, URLInputParser.searchURL(for: "spring physics"))
    XCTAssertEqual(harness.controller.sidebarController.current, added)
  }

  func testAFullFavoritesBandRefusalStillToastsForADraggedSet() throws {
    var world = try Self.makeWorld()
    for index in 1..<SidebarModel.Sidebar.maximumFavorites {
      _ = try world.sidebar.addTab(url: Self.url("fav\(index)"), title: "F", in: .favorites(profile: "default"))
    }
    let harness = Harness(world.sidebar)
    try harness.outline().draggingSessionWillBegin(items: [harness.outline().item(for: world.today[0])])
    let overlay = try XCTUnwrap(harness.controller.sidebarController.dropOverlay)
    XCTAssertFalse(overlay.drop(node: world.today[0], at: CGPoint(x: 20, y: 10)))
    XCTAssertEqual(harness.errors, [.moveNode])
    try harness.outline().draggingSessionEnded()
  }

  // MARK: GS-012 Space edge

  func testRestingAtThePageEdgeTurnsToTheNextSpace() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let width = try harness.outline().outlineView.bounds.width
    let edge = NSPoint(x: width - 2, y: try harness.point(world.today[0], y: 0.5).y)
    drop.update(at: edge, payload: harness.payload([world.today[0]]))
    harness.motionTime += SpaceEdgeDwell.dwell + 0.01
    drop.update(at: edge, payload: harness.payload([world.today[0]]))
    XCTAssertEqual(harness.controller.sidebarController.view.pager.targetIndex, 1, "the pager heads to Home")
  }

  // MARK: Motion

  func testRowsBelowTheDropPointMakeRoomOnASpringAndSnapBackOnExit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let gapRow = try harness.row(world.today[1])
    drop.update(at: try harness.point(world.today[1], y: 0.1), payload: harness.payload([world.today[0]]))
    XCTAssertEqual(harness.haptics, 1, "BH-024: a tick when the drop point settles on a new place")
    let preview = drop.preview
    XCTAssertEqual(preview.offset(ofRow: gapRow, at: harness.motionTime), 0, "starts where the row is")
    let mid = preview.offset(ofRow: gapRow, at: harness.motionTime + 0.05)
    XCTAssertGreaterThan(mid, 0)
    XCTAssertLessThan(mid, SidebarMetrics.rowPitch)
    XCTAssertEqual(preview.offset(ofRow: gapRow, at: harness.motionTime + 2), SidebarMetrics.rowPitch)
    XCTAssertEqual(preview.offset(ofRow: gapRow - 1, at: harness.motionTime + 2), 0, "rows above stay")
    XCTAssertTrue(preview.isIndicatorShown)

    harness.motionTime += 0.05
    drop.exit()
    XCTAssertEqual(preview.offset(ofRow: gapRow, at: harness.motionTime), mid, accuracy: 0.001,
                   "the snap back starts from where the row is")
    XCTAssertEqual(preview.offset(ofRow: gapRow, at: harness.motionTime + 2), 0)
  }

  func testTheRowTransformFollowsTheSpring() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let gapRow = try harness.row(world.today[1])
    drop.update(at: try harness.point(world.today[1], y: 0.1), payload: harness.payload([world.today[0]]))
    drop.preview.tick(at: harness.motionTime + 2)
    let rowView = try XCTUnwrap(harness.outline().outlineView.rowView(atRow: gapRow, makeIfNecessary: false))
    let shift = try XCTUnwrap(rowView.layer).sublayerTransform.m42
    XCTAssertEqual(abs(shift), SidebarMetrics.rowPitch, accuracy: 0.01)
    XCTAssertTrue(drop.preview.isSettled(at: harness.motionTime + 2))
    _ = drop.perform(payload: harness.payload([world.today[0]]), at: try harness.point(world.today[1], y: 0.1),
                     duplicate: false, fromOtherWindow: false)
    try harness.outline().outlineView.enumerateAvailableRowViews { rowView, _ in
      XCTAssertEqual(rowView.layer?.sublayerTransform.m42 ?? 0, 0, "a drop clears every shift at once")
    }
  }

  /// The shift moves a row's content down on screen, measured in the window's root layer.
  func testRowsMakeRoomDownwardOnScreen() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let gapRow = try harness.row(world.today[1])
    let outline = try harness.outline().outlineView
    let rowView = try XCTUnwrap(outline.rowView(atRow: gapRow, makeIfNecessary: false))
    let cellView = try XCTUnwrap(outline.view(atColumn: 0, row: gapRow, makeIfNecessary: false))
    cellView.wantsLayer = true
    let cell = try XCTUnwrap(cellView.layer)
    var root = cell
    while let parent = root.superlayer { root = parent }                // the window's root layer
    let before = cell.convert(cell.bounds, to: root)
    drop.update(at: try harness.point(world.today[1], y: 0.1), payload: harness.payload([world.today[0]]))
    drop.preview.tick(at: harness.motionTime + 2)
    let after = cell.convert(cell.bounds, to: root)
    let down = root.isGeometryFlipped ? after.minY - before.minY : before.minY - after.minY
    XCTAssertEqual(down, SidebarMetrics.rowPitch, accuracy: 0.5)

    rowView.prepareForReuse()
    XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(rowView.layer).sublayerTransform),
                  "a reused row starts without a shift")
  }

  /// Rows realized under a steady gap (scrolled into view) get their shift on the next update.
  func testAnUnchangedTargetStillPresentsTheCurrentFrame() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let gapRow = try harness.row(world.today[1])
    let point = try harness.point(world.today[1], y: 0.1)
    drop.update(at: point, payload: harness.payload([world.today[0]]))
    let rowView = try XCTUnwrap(harness.outline().outlineView.rowView(atRow: gapRow, makeIfNecessary: false))
    rowView.layer?.sublayerTransform = CATransform3DIdentity        // as a freshly realized row
    harness.motionTime += 2
    drop.update(at: point, payload: harness.payload([world.today[0]]))
    XCTAssertEqual(abs(try XCTUnwrap(rowView.layer).sublayerTransform.m42), SidebarMetrics.rowPitch, accuracy: 0.01)
  }

  func testReduceMotionShowsTheIndicatorWithoutMovingRows() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar, reduceMotion: true)
    let drop = try harness.drop()
    let gapRow = try harness.row(world.today[1])
    drop.update(at: try harness.point(world.today[1], y: 0.1), payload: harness.payload([world.today[0]]))
    XCTAssertEqual(drop.preview.offset(ofRow: gapRow, at: harness.motionTime + 0.05), 0)
    XCTAssertTrue(drop.preview.isIndicatorShown)
    let rect = try harness.outline().outlineView.rect(ofRow: gapRow)
    XCTAssertEqual(drop.preview.indicatorY, rect.minY, accuracy: 0.5, "the line sits on the row boundary")
  }

  func testAFolderOrTabTargetHighlightsTheRowWithoutAGap() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    drop.update(at: try harness.point(world.folder, y: 0.5), payload: harness.payload([world.today[0]]))
    XCTAssertTrue(drop.preview.isHighlightShown)
    XCTAssertFalse(drop.preview.isIndicatorShown)
    XCTAssertEqual(drop.preview.offset(ofRow: try harness.row(world.today[0]), at: harness.motionTime + 2), 0)
  }

  /// Design section 5's frame budget: one preview frame (target, springs, row transforms) stays far under a 120 Hz
  /// refresh of main-thread CPU while the pointer sweeps every row.
  func testAPreviewSweepStaysUnderOneFrameOfMainThreadCPU() throws {
    let fps = harnessScreenFPS()
    if fps < 120 { throw XCTSkip("NOT-MEASURABLE (screen \(fps) Hz)") }
    var world = try Self.makeWorld()
    for index in 0..<30 {
      _ = try world.sidebar.addTab(url: Self.url("x\(index)"), title: "X\(index)", in: .today(world.space))
    }
    let harness = Harness(world.sidebar)
    let drop = try harness.drop()
    let outline = try harness.outline().outlineView
    var worst = 0.0
    for pass in 0..<3 {
      for row in 0..<outline.numberOfRows {
        for y in [0.1, 0.5, 0.9] as [CGFloat] {
          harness.motionTime += 1.0 / 120
          let start = threadCPU()
          drop.update(at: try harness.point(row: row, y: y), payload: harness.payload([world.today[0]]))
          drop.preview.tick(at: harness.motionTime)
          CATransaction.flush()
          if pass > 0 { worst = max(worst, threadCPU() - start) }
        }
      }
    }
    print(String(format: "sidebardrop.cost worstMs=%.3f", worst * 1000))
    XCTAssertLessThan(worst, FrameStats().designBudget)
  }

  private func harnessScreenFPS() -> Int { NSScreen.main?.maximumFramesPerSecond ?? 0 }

  private func threadCPU() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
  }
}
