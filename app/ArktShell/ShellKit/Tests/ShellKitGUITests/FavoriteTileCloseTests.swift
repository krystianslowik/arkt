import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The hover close (X) on Favorite tiles (#82). A loaded Favorite shows the X while hovered; a click or the VoiceOver
/// action runs the same close as Cmd-W (`ShellWindowController.close(node:)`): the page closes and the Favorite stays
/// (BH-048 [I]); nothing is archived. Events are delivered in-process; nothing goes through the OS.
@MainActor
final class FavoriteTileCloseTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// One Space with two Today tabs and three Favorites.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var today: [UUID]
    var favorites: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [[UUID]] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { FavoriteTileCloseTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        archived.append(ids)
        _ = source.archive(ids, reason: .manual, at: FavoriteTileCloseTests.now)
      }
    }

    var grid: FavoritesGridView { controller.sidebarController.view.favorites }

    func tile(_ id: UUID) throws -> FavoriteTileView {
      grid.collectionView.layoutSubtreeIfNeeded()
      return try XCTUnwrap(grid.tile(for: id))
    }

    /// Hovers the tile, checks that a click at the X's center lands on the X (not on the tile, which would select and
    /// activate it), then clicks it in-process.
    func clickClose(_ id: UUID) throws {
      let tile = try tile(id)
      tile.isHovered = true
      let button = tile.closeButton
      XCTAssertFalse(button.isHidden, "the X is clickable while a loaded tile is hovered")
      let content = try XCTUnwrap(button.window?.contentView)
      let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
      let hit = content.hitTest(content.superview?.convert(center, from: nil) ?? center)
      XCTAssertTrue(hit === button, "a click on the X goes to the X")
      button.performClick(nil)
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let favorites = try (0..<3).map {
      try sidebar.addTab(url: url("f\($0)"), title: "F\($0)", in: .favorites(profile: "default"))
    }
    return World(sidebar: sidebar, today: today, favorites: favorites)
  }

  // MARK: Visibility

  /// A Favorite without a loaded page has nothing to close: no X on hover and no VoiceOver action.
  func testUnloadedFavoriteShowsNoCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let tile = try harness.tile(world.favorites[1])

    tile.isHovered = true

    XCTAssertNil(tile.closeAction)
    XCTAssertFalse(tile.isCloseButtonShown)
    XCTAssertTrue(tile.closeButton.isHidden)
    XCTAssertEqual(tile.accessibilityCustomActions() ?? [], [])
    harness.controller.close()
  }

  func testLoadedFavoriteShowsCloseButtonOnlyWhileHovered() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    XCTAssertEqual(tile.closeAction, .closeFavorite)
    XCTAssertFalse(tile.isCloseButtonShown)
    XCTAssertTrue(tile.closeButton.isHidden)

    tile.isHovered = true
    XCTAssertTrue(tile.isCloseButtonShown)
    XCTAssertFalse(tile.closeButton.isHidden)

    tile.isHovered = false
    XCTAssertFalse(tile.isCloseButtonShown)
    harness.controller.close()
  }

  /// [I] "Close this tab" on the X; the tile keeps its title as its own tooltip and VoiceOver label.
  func testTooltipAndLabels() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    XCTAssertEqual(tile.closeButton.toolTip, "Close this tab")
    XCTAssertEqual(tile.closeButton.accessibilityLabel(), "Close this tab")
    XCTAssertEqual(tile.toolTip, "F0")
    XCTAssertEqual(tile.accessibilityLabel(), "F0")
    harness.controller.close()
  }

  /// The X sits inside the tile's top trailing corner, frames set directly; the favicon stays centered.
  func testCloseButtonSitsInTheTopTrailingCorner() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    tile.isHovered = true
    tile.layoutSubtreeIfNeeded()

    let box = SidebarMetrics.favoriteCloseButtonSize
    let inset = SidebarMetrics.favoriteCloseButtonInset
    let button = tile.closeButton.frame
    XCTAssertEqual(button.width, box)
    XCTAssertEqual(button.height, box)
    XCTAssertEqual(button.maxX, tile.bounds.width - inset, accuracy: 0.5)
    XCTAssertEqual(button.maxY, tile.bounds.height - inset, accuracy: 0.5, "top edge (the tile is not flipped)")
    XCTAssertTrue(tile.bounds.contains(button))
    XCTAssertEqual(tile.faviconView.frame.midX, tile.bounds.midX, accuracy: 1)
    harness.controller.close()
  }

  /// A tile that becomes loaded under the pointer shows its X at once, without a mouse move.
  func testTileLoadedWhileHoveredShowsCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let tile = try harness.tile(world.favorites[2])
    tile.isHovered = true
    XCTAssertFalse(tile.isCloseButtonShown)

    harness.controller.activate(node: world.favorites[2])

    XCTAssertTrue(try harness.tile(world.favorites[2]).isCloseButtonShown)
    harness.controller.close()
  }

  /// A tile reloaded under the pointer (title change) keeps its X.
  func testReloadedTileUnderThePointerKeepsCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    tile.isHovered = true

    harness.source.updateTab(world.favorites[0], url: nil, title: "Renamed")

    let reloaded = try harness.tile(world.favorites[0])
    XCTAssertEqual(reloaded.accessibilityLabel(), "Renamed")
    XCTAssertTrue(reloaded.isCloseButtonShown)
    harness.controller.close()
  }

  /// A reused tile starts without the X, its action or its VoiceOver action.
  func testReuseClearsCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    harness.grid.collectionView.layoutSubtreeIfNeeded()
    let item = try XCTUnwrap(harness.grid.collectionView.item(at: IndexPath(item: 0, section: 0)) as? FavoriteTileItem)
    item.tileView.isHovered = true
    XCTAssertTrue(item.tileView.isCloseButtonShown)

    item.prepareForReuse()

    XCTAssertFalse(item.tileView.isCloseButtonShown)
    XCTAssertTrue(item.tileView.closeButton.isHidden)
    XCTAssertNil(item.tileView.closeAction)
    XCTAssertNil(item.tileView.nodeID)
    XCTAssertEqual(item.tileView.accessibilityCustomActions() ?? [], [])
    harness.controller.close()
  }

  /// Tiles shifted or reused under a still pointer resync their hover state when tracking areas update.
  func testHoverResyncsFromThePointerLocation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    let inside = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)

    tile.syncHover(pointerInWindow: inside)
    XCTAssertTrue(tile.isHovered)
    XCTAssertTrue(tile.isCloseButtonShown)

    tile.syncHover(pointerInWindow: NSPoint(x: inside.x, y: inside.y - 10 * FavoritesLayout.tileHeight))
    XCTAssertFalse(tile.isHovered)
    XCTAssertFalse(tile.isCloseButtonShown)

    tile.isHovered = true
    tile.syncHover(pointerInWindow: nil)
    XCTAssertFalse(tile.isHovered, "no pointer in the window means no hover")
    harness.controller.close()
  }

  /// The grid reads the pointer once for all its tiles, in any visible window (key or not), and a tile under another
  /// window (a child panel such as the command bar) drops its hover.
  func testResyncHoversTheTileUnderThePointerUnlessAnotherWindowCoversIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    let other = try harness.tile(world.favorites[1])
    other.isHovered = true
    let window = try XCTUnwrap(tile.window)
    let pointer = HoverPointerStub(window: window)
    pointer.move(toCenterOf: tile)
    harness.grid.hoverPointerLookup = pointer.lookup
    XCTAssertFalse(window.isKeyWindow)

    harness.grid.resyncHoverWithPointer()

    XCTAssertTrue(tile.isHovered)
    XCTAssertTrue(tile.isCloseButtonShown)
    XCTAssertFalse(other.isHovered)
    XCTAssertEqual(pointer.windowServerQueries, 1)

    pointer.coveringWindowNumber = window.windowNumber + 1
    harness.grid.resyncHoverWithPointer()
    XCTAssertFalse(tile.isHovered)
    XCTAssertFalse(tile.isCloseButtonShown)
    harness.controller.close()
  }

  /// A Favorite removed before the hovered tile shifts the tiles under a still pointer: after the change the tile now
  /// under the pointer is hovered and the shifted one is not (no stale X).
  func testTilesShiftedByARemovedFavoriteResyncTheirHover() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let last = try harness.tile(world.favorites[2])
    let middle = try harness.tile(world.favorites[1])
    let pointer = HoverPointerStub(window: try XCTUnwrap(last.window))
    // Near the middle tile's trailing edge: with two Favorites left the grid takes two wider columns (#337), and
    // this point falls on the second one.
    pointer.pointInWindow = middle.convert(NSPoint(x: middle.bounds.maxX - 6, y: middle.bounds.midY), to: nil)
    harness.grid.hoverPointerLookup = pointer.lookup
    harness.grid.resyncHoverWithPointer()
    XCTAssertTrue(middle.isHovered)

    harness.source.mutate { $0.remove(world.favorites[0]) }
    harness.grid.collectionView.layoutSubtreeIfNeeded()
    drainMainQueue()

    XCTAssertEqual(harness.grid.nodeIDs, [world.favorites[1], world.favorites[2]])
    XCTAssertFalse(try harness.tile(world.favorites[1]).isHovered, "moved out from under the pointer")
    XCTAssertTrue(try harness.tile(world.favorites[2]).isHovered, "moved under the pointer")
    harness.controller.close()
  }

  /// Reduce Motion: the tile's X appears and hides at once, without a fade.
  func testReduceMotionShowsAndHidesTheTileCloseButtonWithoutAFade() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tile = try harness.tile(world.favorites[0])
    tile.closeButton.reducesMotion = { true }

    tile.isHovered = true
    XCTAssertEqual(tile.closeButton.alphaValue, 1)
    XCTAssertFalse(tile.closeButton.isHidden)

    tile.isHovered = false
    XCTAssertEqual(tile.closeButton.alphaValue, 0)
    XCTAssertTrue(tile.closeButton.isHidden)
    XCTAssertNil(tile.closeButton.layer?.animation(forKey: "opacity"))
    harness.controller.close()
  }

  // MARK: Loaded state

  /// A loaded Favorite removed from the source leaves the loaded set like it leaves the favicon cache, also for a
  /// sidebar without a window to report the closed page.
  func testRemovedFavoriteLeavesTheLoadedSet() throws {
    let world = try Self.makeWorld()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { FavoriteTileCloseTests.now })
    let sidebar = SidebarController(source: source)
    sidebar.activate(node: world.favorites[0])
    sidebar.activate(node: world.favorites[1])
    XCTAssertEqual(sidebar.loadedNodes, [world.favorites[0], world.favorites[1]])

    source.mutate { $0.remove(world.favorites[0]) }

    XCTAssertEqual(sidebar.loadedNodes, [world.favorites[1]])
  }

  /// Closing the current Favorite's page refreshes its tile once (the row-state refresh covers it).
  func testDeactivatingTheCurrentFavoriteConfiguresItsTileOnce() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    _ = try harness.tile(world.favorites[0])
    var configured = 0
    let favicons = harness.grid.faviconProvider
    harness.grid.faviconProvider = { id in
      if id == world.favorites[0] { configured += 1 }
      return favicons?(id)
    }

    harness.controller.sidebarController.deactivate(node: world.favorites[0])

    XCTAssertEqual(configured, 1)
    XCTAssertNil(try harness.tile(world.favorites[0]).closeAction)
    harness.controller.close()
  }

  // MARK: Click

  /// BH-048 [I]: the X on the current Favorite closes its page and keeps the Favorite; nothing is archived, and the
  /// X hides because nothing is loaded any more, although the pointer is still on the tile.
  func testClosingTheCurrentFavoriteClosesItsPageAndKeepsTheFavorite() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tab = try XCTUnwrap(harness.controller.currentTab)

    try harness.clickClose(world.favorites[0])

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(tab))
    XCTAssertNotNil(harness.source.node(world.favorites[0]))
    XCTAssertEqual(harness.source.children(of: .favorites(profile: "default")), world.favorites)
    XCTAssertNil(harness.controller.currentTab)
    let tile = try harness.tile(world.favorites[0])
    XCTAssertTrue(tile.isHovered)
    XCTAssertFalse(tile.isCloseButtonShown)
    XCTAssertEqual(tile.accessibilityCustomActions() ?? [], [])
    harness.controller.close()
  }

  /// A Favorite loaded in the background closes only its page: the current tab stays and the click never activates
  /// the tile. Its X hides at once (the close reaches the grid even though the Favorite is not current).
  func testClosingABackgroundFavoriteClosesOnlyItsPage() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[1])
    let favoriteTab = try XCTUnwrap(harness.controller.currentTab)
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.today[1])
    let current = try XCTUnwrap(harness.controller.currentTab)

    try harness.clickClose(world.favorites[1])

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(favoriteTab))
    XCTAssertEqual(harness.controller.currentTab, current)
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[1])
    XCTAssertNotNil(harness.source.node(world.favorites[1]))
    let tile = try harness.tile(world.favorites[1])
    XCTAssertTrue(tile.isHovered)
    XCTAssertFalse(tile.isCloseButtonShown)
    XCTAssertNil(tile.closeAction)
    harness.controller.close()
  }

  // MARK: Accessibility

  /// VoiceOver: a loaded Favorite tile carries one custom action, "Close", running the same close.
  func testLoadedTileCarriesACloseAccessibilityAction() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorites[0])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    harness.controller.activate(node: world.today[0])
    let actions = try XCTUnwrap(harness.tile(world.favorites[0]).accessibilityCustomActions())
    XCTAssertEqual(actions.map(\.name), ["Close"])

    XCTAssertTrue(actions[0].handler?() ?? false)

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(tab))
    XCTAssertNotNil(harness.source.node(world.favorites[0]))
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0])
    XCTAssertEqual(try harness.tile(world.favorites[0]).accessibilityCustomActions() ?? [], [])
    harness.controller.close()
  }
}
