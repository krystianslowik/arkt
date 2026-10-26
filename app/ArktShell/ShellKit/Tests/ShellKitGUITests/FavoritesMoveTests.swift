import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Favorites add, remove, limit and unloading (BH-046, BH-047, BH-049): the "Move To > Favorites" context menu
/// item, dragging a tab onto the Favorites band above the Space title, dragging a Favorite onto the Space page to
/// pin it, the 12-Favorite refusal toast, and the limit that unloads the least recently used Favorites.
/// Drag sessions are not synthesized: the outline's and grid's session hooks start them, and the overlay's
/// `preview(at:)` / `drop(node:at:)` drive the drop (the `SplitDragTests` pattern).
@MainActor
final class FavoritesMoveTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// One Space "Work" with Pinned `[p0]`, Today tabs and `favorites` Favorites.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
    var split: UUID
    var pane: UUID
    var favorites: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var errors: [(SidebarMutation, String)] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { FavoritesMoveTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onError = { [unowned self] mutation, error in
        errors.append((mutation, String(describing: error)))
      }
    }

    var sidebarController: SidebarController { controller.sidebarController }
    var favorites: FavoritesGridView { controller.sidebarController.view.favorites }
    var overlay: FavoritesDropOverlayView? { controller.sidebarController.dropOverlay }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }

    /// The "Move To" submenu's item titles on `node`'s row (nil: the row has no menu or no Move To).
    func moveToTitles(_ node: UUID) throws -> [String]? {
      let menu = try outline().menu(forRow: row(node))
      return menu?.items.first { $0.title == "Move To" }?.submenu?.items.map(\.title)
    }

    /// Chooses "Move To > Favorites" on `node`'s row.
    func chooseMoveToFavorites(_ node: UUID) throws {
      let menu = try XCTUnwrap(try outline().menu(forRow: row(node)), "the row has no context menu")
      let moveTo = try XCTUnwrap(menu.items.first { $0.title == "Move To" }, "no Move To item")
      let submenu = try XCTUnwrap(moveTo.submenu)
      let index = submenu.indexOfItem(withTitle: "Favorites")
      XCTAssertGreaterThanOrEqual(index, 0, "no Favorites item in Move To")
      submenu.performActionForItem(at: index)
    }

    /// Starts a drag of `node`'s outline row through the outline's session hook.
    func beginOutlineDrag(_ node: UUID) throws {
      try outline().draggingSessionWillBegin(items: [outline().item(for: node)])
    }

    /// Starts a drag of `node`'s Favorite tile through the grid's session hook.
    func beginTileDrag(_ node: UUID) throws {
      let index = try XCTUnwrap(favorites.nodeIDs.firstIndex(of: node), "no tile for the node")
      favorites.draggingSessionWillBegin(indexPaths: [IndexPath(item: index, section: 0)])
    }

    func endOutlineDrag() throws { try outline().draggingSessionEnded() }
    func endTileDrag() { favorites.draggingSessionEnded() }

    /// A point inside the Favorites band, in overlay coordinates (the band starts at the overlay's top).
    func bandPoint() -> CGPoint { CGPoint(x: 20, y: 5) }
    /// A point over the Space page, in overlay coordinates.
    func pagePoint() throws -> CGPoint {
      let overlay = try XCTUnwrap(self.overlay)
      return CGPoint(x: 20, y: overlay.bounds.height - 20)
    }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(favorites count: Int) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: url("p0"), title: "P0", in: .pinned(space))
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try (0..<2).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let favorites = try (0..<count).map {
      try sidebar.addTab(url: url("f\($0)"), title: "F\($0)", in: .favorites(profile: "default"))
    }
    return World(sidebar: sidebar, space: space, pinned: pinned, today: today, split: split,
                 pane: panes[0], favorites: favorites)
  }

  // MARK: Move To > Favorites (BH-047)

  func testTodayAndPinnedRowsOfferMoveToFavorites() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    // Favorites, then the Spaces (#105); the only Space is the row's own, so it is listed disabled.
    XCTAssertEqual(try harness.moveToTitles(world.today[0]), ["Favorites", "", "Work"])
    XCTAssertEqual(try harness.moveToTitles(world.pinned), ["Favorites", "", "Work"])
    harness.controller.close()
  }

  /// A split row moves whole (BH-115, design 3.5); a pane row has no Move To, so a pane never leaves its split
  /// this way.
  func testSplitRowsMoveWholeAndPaneRowsHaveNoMoveTo() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    XCTAssertEqual(try harness.moveToTitles(world.split), ["Favorites", "", "Work"])
    XCTAssertNil(try harness.moveToTitles(world.pane))
    harness.controller.close()
  }

  func testMoveToFavoritesMovesATodayTab() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.chooseMoveToFavorites(world.today[0])
    XCTAssertEqual(harness.children(.favorites(profile: "default")), world.favorites + [world.today[0]])
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[1], world.split])
    XCTAssertTrue(harness.errors.isEmpty)
    harness.controller.close()
  }

  /// BH-046: the 13th Favorite is refused; the tab stays and the failure reports `.moveNode`.
  func testMoveToFavoritesIntoFullFavoritesIsRefused() throws {
    let world = try Self.makeWorld(favorites: 12)
    let harness = Harness(world.sidebar)
    try harness.chooseMoveToFavorites(world.today[0])
    XCTAssertEqual(harness.children(.today(world.space)), world.today + [world.split])
    XCTAssertEqual(harness.children(.favorites(profile: "default")).count, 12)
    XCTAssertEqual(harness.errors.map(\.0), [.moveNode])
    harness.controller.close()
  }

  // MARK: Drag above the Space title (BH-047)

  func testBeginningAnOutlineDragShowsTheOverlayAndEndingHidesIt() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    XCTAssertNil(harness.overlay)
    try harness.beginOutlineDrag(world.today[0])
    XCTAssertNotNil(harness.overlay)
    try harness.endOutlineDrag()
    XCTAssertNil(harness.overlay)
    harness.controller.close()
  }

  func testDropOnTheBandFavoritesATodayTab() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.beginOutlineDrag(world.today[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertEqual(overlay.preview(at: harness.bandPoint()), .favorites(profile: "default"))
    XCTAssertTrue(overlay.drop(node: world.today[0], at: harness.bandPoint()))
    XCTAssertEqual(harness.children(.favorites(profile: "default")), world.favorites + [world.today[0]])
    try harness.endOutlineDrag()
    harness.controller.close()
  }

  /// Zero Favorites is allowed (BH-046): the band still takes the drop when the grid is empty.
  func testDropOnTheEmptyBandFavoritesATodayTab() throws {
    let world = try Self.makeWorld(favorites: 0)
    let harness = Harness(world.sidebar)
    try harness.beginOutlineDrag(world.today[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertEqual(overlay.preview(at: harness.bandPoint()), .favorites(profile: "default"))
    XCTAssertTrue(overlay.drop(node: world.today[0], at: harness.bandPoint()))
    XCTAssertEqual(harness.children(.favorites(profile: "default")), [world.today[0]])
    try harness.endOutlineDrag()
    harness.controller.close()
  }

  func testDropOnTheBandIntoFullFavoritesIsRefused() throws {
    let world = try Self.makeWorld(favorites: 12)
    let harness = Harness(world.sidebar)
    try harness.beginOutlineDrag(world.today[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertFalse(overlay.drop(node: world.today[0], at: harness.bandPoint()))
    XCTAssertEqual(harness.children(.today(world.space)), world.today + [world.split])
    XCTAssertEqual(harness.errors.map(\.0), [.moveNode])
    try harness.endOutlineDrag()
    harness.controller.close()
  }

  func testDraggingAFavoriteOverTheBandIsRefused() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.beginTileDrag(world.favorites[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertNil(overlay.preview(at: harness.bandPoint()))
    harness.endTileDrag()
    harness.controller.close()
  }

  /// A pane cannot be favorited by a drop: the move would leave its split with one pane.
  func testDropOfAPaneOnTheBandIsRefused() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.beginOutlineDrag(world.pane)
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertNil(overlay.preview(at: harness.bandPoint()))
    XCTAssertFalse(overlay.drop(node: world.pane, at: harness.bandPoint()))
    XCTAssertEqual(harness.children(.split(world.split)).count, 2)
    XCTAssertEqual(harness.children(.favorites(profile: "default")), world.favorites)
    try harness.endOutlineDrag()
    harness.controller.close()
  }

  // MARK: Drag below the Space title (BH-047)

  func testDropOfAFavoriteOnThePagePinsItInTheCurrentSpace() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.beginTileDrag(world.favorites[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertEqual(overlay.preview(at: try harness.pagePoint()), .pinned(world.space))
    XCTAssertTrue(overlay.drop(node: world.favorites[0], at: try harness.pagePoint()))
    XCTAssertEqual(harness.children(.favorites(profile: "default")), [world.favorites[1]])
    XCTAssertEqual(harness.children(.pinned(world.space)), [world.pinned, world.favorites[0]])
    harness.endTileDrag()
    harness.controller.close()
  }

  func testDropOfATodayTabOnThePageIsRefused() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    try harness.beginOutlineDrag(world.today[0])
    let overlay = try XCTUnwrap(harness.overlay)
    XCTAssertNil(overlay.preview(at: try harness.pagePoint()))
    XCTAssertFalse(overlay.drop(node: world.today[0], at: try harness.pagePoint()))
    try harness.endOutlineDrag()
    harness.controller.close()
  }

}
