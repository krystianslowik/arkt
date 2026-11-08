import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A Split View made on a Favorite stays a Favorite (BH-115: a split can be favorited; the split takes the target
/// tab's place, as BH-119 has it for Pinned) and is the Favorites tile of the split's node. Until the split draws its
/// own tile (#788), that tile must still close and leave the Favorites like any other Favorite: the X while a pane
/// has a page, a drag below the Space title, and a menu without the tab-only items. Events are delivered in-process;
/// nothing goes through the OS.
@MainActor
final class FavoriteSplitTileTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let profile = "default"

  /// One Space with a pinned tab and Today `[t0, t1]`, and one Favorite.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
    var favorite: UUID
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [[UUID]] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { FavoriteSplitTileTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.rootView.split.reduceMotion = { true }
      controller.rootView.reduceMotion = { true }
      controller.onArchive = { [unowned self] ids in
        archived.append(ids)
        _ = source.archive(ids, reason: .manual, at: FavoriteSplitTileTests.now)
      }
    }

    var grid: FavoritesGridView { controller.sidebarController.view.favorites }
    var favorites: [UUID] { source.children(of: .favorites(profile: FavoriteSplitTileTests.profile)) }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func tile(_ id: UUID) throws -> FavoriteTileView {
      grid.collectionView.layoutSubtreeIfNeeded()
      return try XCTUnwrap(grid.tile(for: id), "no tile for the node")
    }

    /// Hovers the tile, checks that a click at the X's center lands on the X, then clicks it in-process.
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

    /// What the grid writes to the pasteboard for `id`'s tile (nil: the tile cannot be dragged).
    func writer(_ id: UUID) throws -> NSPasteboardWriting? {
      let index = try XCTUnwrap(grid.nodeIDs.firstIndex(of: id), "no tile for the node")
      return grid.collectionView(grid.collectionView, pasteboardWriterForItemAt: IndexPath(item: index, section: 0))
    }

    func menuTitles(_ id: UUID) -> [String]? { grid.contextMenu(for: id)?.items.map(\.title) }

    /// Makes the split the way Add Split (Ctrl-Shift-=) does on the shown tab: Enter in the bar opens `url` as the
    /// new pane right of it.
    func addSplit(on node: UUID, url: URL) throws -> (split: UUID, pane: UUID) {
      controller.activate(node: node)
      controller.openInNewSplitPane(url)
      let pane = try XCTUnwrap(controller.currentNode, "the new pane is shown")
      let split: UUID? = if case .split(let split)? = source.parent(of: pane) { split } else { nil }
      return (try XCTUnwrap(split, "the new tab is a pane"), pane)
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
    let pinned = try sidebar.addTab(url: url("p0"), title: "P0", in: .pinned(space))
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let favorite = try sidebar.addTab(url: url("f0"), title: "F0", in: .favorites(profile: profile))
    return World(sidebar: sidebar, space: space, pinned: pinned, today: today, favorite: favorite)
  }

  // MARK: Where the split lands

  /// Add Split on a shown Favorite: the split takes the Favorite's place in the Favorites and is drawn as one tile.
  func testAddSplitOnAShownFavoriteMakesAFavoriteSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    XCTAssertEqual(harness.favorites, [split])
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    XCTAssertEqual(harness.grid.nodeIDs, [split])
    harness.controller.close()
  }

  /// A Today tab dragged onto the page of a shown Favorite: the same Favorite split, the Today tab now its pane.
  func testDraggingATabOntoAShownFavoriteMakesAFavoriteSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorite)
    let outline = try harness.outline()
    outline.draggingSessionWillBegin(items: [outline.item(for: world.today[0])])
    let overlay = try XCTUnwrap(harness.controller.splitState.dropOverlay)

    XCTAssertTrue(overlay.drop(node: world.today[0],
                               at: CGPoint(x: overlay.bounds.width * 0.9, y: overlay.bounds.midY)))
    outline.draggingSessionEnded()

    let split = try XCTUnwrap(harness.favorites.first)
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, world.today[0]])
    XCTAssertEqual(harness.source.children(of: .today(world.space)), [world.today[1]])
    harness.controller.close()
  }

  // MARK: Close (the tile's X)

  /// The tile of a Favorite split shows the X while one of its panes has a page, as a Favorite tab's tile does (#82)
  /// and as the outline's pinned split row does (#601). Its click is Close and Keep Favorite for every pane: the pages
  /// close, the split stays a Favorite, nothing is archived.
  func testFavoriteSplitTileXClosesItsPagesAndKeepsTheFavorite() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    XCTAssertNotNil(harness.controller.engineTab(of: world.favorite))
    XCTAssertNotNil(harness.controller.engineTab(of: pane))
    XCTAssertEqual(try harness.tile(split).closeAction, .closeFavorite)

    try harness.clickClose(split)

    XCTAssertNil(harness.controller.engineTab(of: world.favorite))
    XCTAssertNil(harness.controller.engineTab(of: pane))
    XCTAssertEqual(harness.favorites, [split], "Close and Keep Favorite")
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    XCTAssertEqual(harness.archived, [])
    XCTAssertNil(try harness.tile(split).closeAction, "no page left: no X")
    harness.controller.close()
  }

  /// The tile follows its panes' pages: the X goes when the last page closes by Cmd-W and comes back when a pane is
  /// shown again.
  func testFavoriteSplitTileXFollowsItsPanesPages() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    harness.controller.closeTab(nil)                          // Cmd-W: the new pane's page closes
    XCTAssertEqual(try harness.tile(split).closeAction, .closeFavorite, "the Favorite pane still has its page")
    harness.controller.closeTab(nil)                          // Cmd-W: the Favorite pane's page closes
    XCTAssertNil(harness.controller.currentNode)
    XCTAssertEqual(harness.favorites, [split])
    XCTAssertNil(try harness.tile(split).closeAction)

    harness.controller.activate(node: split)

    XCTAssertNotNil(harness.controller.currentNode)
    XCTAssertEqual(try harness.tile(split).closeAction, .closeFavorite)
    harness.controller.close()
  }

  /// A Favorite split that is not on screen: its X closes the pages in the background, and the tile drops its X then,
  /// although neither pane is the current or the previous tab (the grid refreshes a pane's split tile).
  func testBackgroundFavoriteSplitTileDropsItsXWhenItsPagesClose() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    harness.controller.activate(node: world.today[1])
    harness.controller.activate(node: world.pinned)
    XCTAssertNotNil(harness.controller.engineTab(of: pane), "the hidden split keeps its pages")
    XCTAssertEqual(try harness.tile(split).closeAction, .closeFavorite)

    try harness.clickClose(split)

    XCTAssertNil(harness.controller.engineTab(of: world.favorite))
    XCTAssertNil(harness.controller.engineTab(of: pane))
    XCTAssertEqual(harness.controller.currentNode, world.pinned, "the shown tab stays")
    XCTAssertNil(try harness.tile(split).closeAction, "no page left: no X")
    harness.controller.close()
  }

  // MARK: Leaving the Favorites

  /// BH-047: dragging a Favorite below the Space title un-favorites it. The split's tile is a drag source carrying
  /// the split, and the page outline takes it whole into Today.
  func testFavoriteSplitTileDragsOutOfTheFavorites() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let item = try XCTUnwrap(try harness.writer(split) as? NSPasteboardItem, "the split's tile is a drag source")
    XCTAssertEqual(item.string(forType: .sidebarNode), split.uuidString)
    let index = try XCTUnwrap(harness.grid.nodeIDs.firstIndex(of: split))
    harness.grid.draggingSessionWillBegin(indexPaths: [IndexPath(item: index, section: 0)])
    let outline = try harness.outline()
    let row = outline.outlineView.rect(ofRow: outline.row(for: world.today[0]))
    let point = NSPoint(x: row.midX, y: row.minY + row.height * 0.2)
    let payload = SidebarDragPayload(nodes: [split], isSingleTab: false)

    XCTAssertTrue(outline.drop.perform(payload: payload, at: point, duplicate: false, fromOtherWindow: false))
    harness.grid.draggingSessionEnded()

    XCTAssertEqual(harness.favorites, [])
    XCTAssertEqual(harness.source.children(of: .today(world.space)), [split, world.today[0], world.today[1]])
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    harness.controller.close()
  }

  /// Remove from Favorites on the split's tile: the split goes on top of Today whole, with its pages.
  func testRemoveFromFavoritesOnTheSplitTileMovesTheSplitToToday() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))
    let index = menu.indexOfItem(withTitle: "Remove from Favorites")
    XCTAssertGreaterThanOrEqual(index, 0)

    menu.performActionForItem(at: index)

    XCTAssertEqual(harness.favorites, [])
    XCTAssertEqual(harness.source.children(of: .today(world.space)).first, split)
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    XCTAssertNotNil(harness.controller.engineTab(of: pane), "the pages stay open")
    harness.controller.close()
  }

  // MARK: Menu and labels

  /// The split's tile offers only the Favorite items that act on a split: the links of its panes, Remove from
  /// Favorites and Close and Keep Favorite. Rename..., Change Icon, Back to Pinned URL and Edit Pinned URL... edit one
  /// tab's pin and did nothing on a split.
  func testFavoriteSplitTileMenuHasNoTabOnlyItems() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    XCTAssertEqual(harness.menuTitles(split), ["Copy Links", "Copy Links as Markdown", "",
                                               "Remove from Favorites", "Close and Keep Favorite"])
    harness.controller.close()
  }

  /// The split's tile is named after its panes, as its outline row is: tooltip and VoiceOver label.
  func testFavoriteSplitTileIsLabelledWithItsPaneTitles() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorite)
    let split = try harness.source.addToSplit(.existing(world.today[0]), target: world.favorite, at: 1,
                                              orientation: .horizontal).split

    let tile = try harness.tile(split)
    XCTAssertEqual(tile.toolTip, "F0 | T0")
    XCTAssertEqual(tile.accessibilityLabel(), "F0 | T0")
    harness.controller.close()
  }

  /// The split's tile takes the strongest state of its panes, as its outline row does: current while one of its panes
  /// is shown (selected for VoiceOver), not current once another tab is.
  func testFavoriteSplitTileIsCurrentWhileAPaneIsShown() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    let tile = try harness.tile(split)
    XCTAssertTrue(tile.isCurrent)
    XCTAssertTrue(tile.isAccessibilitySelected())

    harness.controller.activate(node: world.pinned)

    XCTAssertFalse(try harness.tile(split).isCurrent)
    XCTAssertFalse(try harness.tile(split).isAccessibilitySelected())
    harness.controller.close()
  }

  // MARK: Menu actions

  /// Close and Keep Favorite from the split's menu: every pane's page closes, the split stays a Favorite, and nothing
  /// goes to the Archive.
  func testCloseAndKeepFavoriteFromTheSplitMenuArchivesNothing() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))
    let index = menu.indexOfItem(withTitle: "Close and Keep Favorite")
    XCTAssertGreaterThanOrEqual(index, 0)

    menu.performActionForItem(at: index)

    XCTAssertEqual(harness.archived, [])
    XCTAssertNil(harness.controller.engineTab(of: world.favorite))
    XCTAssertNil(harness.controller.engineTab(of: pane))
    XCTAssertEqual(harness.favorites, [split])
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    harness.controller.close()
  }

  /// Copy Links on the split's tile copies the link of every pane, to the window's link pasteboard (a private one
  /// here, never the system clipboard).
  func testCopyLinksOnTheSplitTileCopiesEveryPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let board = NSPasteboard(name: .init("FavoriteSplitTileTests.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    harness.controller.linkPasteboard = board
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))
    let index = menu.indexOfItem(withTitle: "Copy Links")
    XCTAssertGreaterThanOrEqual(index, 0)

    menu.performActionForItem(at: index)

    let copied = try XCTUnwrap(board.string(forType: .string))
    XCTAssertTrue(copied.contains(Self.url("f0").absoluteString), copied)
    XCTAssertTrue(copied.contains(Self.url("new").absoluteString), copied)
    harness.controller.close()
  }
}
