import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A Split View made on a Favorite stays a Favorite (BH-115: a split can be favorited; the split takes the target
/// tab's place, as BH-119 has it for Pinned) and is the Favorites tile of the split's node. That tile closes and
/// leaves the Favorites like any other Favorite: the X while a pane has a page, a drag below the Space title, and a
/// menu without the tab-only items. It draws the stack of its panes and offers the split items (#788). Events
/// are delivered in-process; nothing goes through the OS.
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

  /// The harness of the running test; `tearDown` closes its window and lets it go.
  private var harness: Harness?

  private func makeHarness(_ sidebar: SidebarModel.Sidebar) -> Harness {
    let made = Harness(sidebar)
    harness = made
    return made
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    harness?.controller.close()
    harness = nil
    try await super.tearDown()
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
    let harness = makeHarness(world.sidebar)

    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    XCTAssertEqual(harness.favorites, [split])
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    XCTAssertEqual(harness.grid.nodeIDs, [split])
  }

  /// A Today tab dragged onto the page of a shown Favorite: the same Favorite split, the Today tab now its pane.
  func testDraggingATabOntoAShownFavoriteMakesAFavoriteSplit() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  // MARK: Close (the tile's X)

  /// The tile of a Favorite split shows the X while one of its panes has a page, as a Favorite tab's tile does (#82)
  /// and as the outline's pinned split row does (#601). Its click is Close and Keep Favorite for every pane: the pages
  /// close, the split stays a Favorite, nothing is archived.
  func testFavoriteSplitTileXClosesItsPagesAndKeepsTheFavorite() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  /// The tile follows its panes' pages: the X goes when the last page closes by Cmd-W and comes back when a pane is
  /// shown again.
  func testFavoriteSplitTileXFollowsItsPanesPages() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  /// A Favorite split that is not on screen: its X closes the pages in the background, and the tile drops its X then,
  /// although neither pane is the current or the previous tab (the grid refreshes a pane's split tile).
  func testBackgroundFavoriteSplitTileDropsItsXWhenItsPagesClose() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  // MARK: Leaving the Favorites

  /// BH-047: dragging a Favorite below the Space title un-favorites it. The split's tile is a drag source carrying
  /// the split, and the page outline takes it whole into Today.
  func testFavoriteSplitTileDragsOutOfTheFavorites() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  /// Remove from Favorites on the split's tile: the split goes on top of Today whole, with its pages.
  func testRemoveFromFavoritesOnTheSplitTileMovesTheSplitToToday() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))
    let index = menu.indexOfItem(withTitle: "Remove from Favorites")
    XCTAssertGreaterThanOrEqual(index, 0)

    menu.performActionForItem(at: index)

    XCTAssertEqual(harness.favorites, [])
    XCTAssertEqual(harness.source.children(of: .today(world.space)).first, split)
    XCTAssertEqual(harness.source.children(of: .split(split)), [world.favorite, pane])
    XCTAssertNotNil(harness.controller.engineTab(of: pane), "the pages stay open")
  }

  // MARK: Menu and labels

  /// The split's tile menu is design/favorite-split-tile's table (#788): Separate All Tabs and Convert, then the
  /// Favorite items that act on a split. Rename... waits for #847; Change Icon, Back to Pinned URL and Edit Pinned
  /// URL... edit one tab's pin and do nothing on a split.
  func testFavoriteSplitTileMenuHasNoTabOnlyItems() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    XCTAssertEqual(harness.menuTitles(split), ["Separate All Tabs", "Convert to Vertical Split View", "",
                                               "Copy Links", "Copy Links as Markdown", "",
                                               "Remove from Favorites", "Close and Keep Favorite"])
  }

  /// The split's tile is named after its panes, as its outline row is: tooltip and VoiceOver label.
  func testFavoriteSplitTileIsLabelledWithItsPaneTitles() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    harness.controller.activate(node: world.favorite)
    let split = try harness.source.addToSplit(.existing(world.today[0]), target: world.favorite, at: 1,
                                              orientation: .horizontal).split

    let tile = try harness.tile(split)
    XCTAssertEqual(tile.toolTip, "F0 | T0")
    XCTAssertEqual(tile.accessibilityLabel(), "F0 | T0")
  }

  /// The split's tile takes the strongest state of its panes, as its outline row does: current while one of its panes
  /// is shown (selected for VoiceOver), not current once another tab is.
  func testFavoriteSplitTileIsCurrentWhileAPaneIsShown() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    let tile = try harness.tile(split)
    XCTAssertTrue(tile.isCurrent)
    XCTAssertTrue(tile.isAccessibilitySelected())

    harness.controller.activate(node: world.pinned)

    XCTAssertFalse(try harness.tile(split).isCurrent)
    XCTAssertFalse(try harness.tile(split).isAccessibilitySelected())
  }

  // MARK: Menu actions

  /// Close and Keep Favorite from the split's menu: every pane's page closes, the split stays a Favorite, and nothing
  /// goes to the Archive.
  func testCloseAndKeepFavoriteFromTheSplitMenuArchivesNothing() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  /// Copy Links on the split's tile copies the link of every pane, to the window's link pasteboard (a private one
  /// here, never the system clipboard).
  func testCopyLinksOnTheSplitTileCopiesEveryPane() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
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
  }

  // MARK: The stack (#788, design/favorite-split-tile)

  /// The split's tile draws the stack, not one favicon: the focused pane in front while the split is shown, the
  /// next pane behind it; the first pane in front once another tab is shown.
  func testFavoriteSplitTileStacksItsPanesFocusedFirst() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    var tile = try harness.tile(split)
    XCTAssertTrue(tile.faviconView.isHidden, "a split tile shows the stack, not one favicon")
    XCTAssertFalse(tile.stackLayer.isHidden)
    XCTAssertNotNil(tile.stackLayer.contents)
    XCTAssertEqual(tile.splitStack?.order, [pane, world.favorite], "the focused (new) pane is in front")

    harness.controller.activate(node: world.favorite)
    XCTAssertEqual(try harness.tile(split).splitStack?.order, [world.favorite, pane])

    harness.controller.activate(node: world.pinned)
    tile = try harness.tile(split)
    XCTAssertEqual(tile.splitStack?.order, [world.favorite, pane], "not shown: the first pane in front")
  }

  /// 3 panes draw 3 layers; a 4th pane is not drawn (the label still names it).
  func testFourPanesDrawThreeLayers() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    try harness.source.addToSplit(.existing(world.today[0]), target: split, at: 2, orientation: .horizontal)
    XCTAssertEqual(try harness.tile(split).splitStack?.images.count, 3)

    try harness.source.addToSplit(.existing(world.today[1]), target: split, at: 3, orientation: .horizontal)
    harness.controller.activate(node: world.pinned)

    let tile = try harness.tile(split)
    XCTAssertEqual(tile.splitStack?.order, [world.favorite, pane, world.today[0]])
    XCTAssertEqual(tile.splitStack?.images.count, 3)
    XCTAssertEqual(tile.toolTip, "F0 | example.com | T0 | T1")
  }

  /// A pane without a favicon (loading, or none) draws the letter tile at its layer's size; a pane with one draws it.
  func testAPaneWithoutAFaviconDrawsItsLetterTile() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let icon = NSImage(size: NSSize(width: 32, height: 32))
    harness.grid.faviconProvider = { $0 == world.favorite ? icon : nil }
    harness.controller.activate(node: world.favorite)

    let stack = try XCTUnwrap(try harness.tile(split).splitStack)
    XCTAssertEqual(stack.order, [world.favorite, pane])
    XCTAssertTrue(stack.images[0] === icon)
    let letter = SidebarGlyphs.letter(for: "", url: Self.url("new"), flavor: harness.grid.flavor,
                                      size: FavoriteSplitStack.layerSizes[1],
                                      scale: harness.grid.collectionView.shellBackingScale)
    XCTAssertTrue(stack.images[1] === letter, "the second layer is the pane's 16 pt letter tile")
  }

  /// Focus moving to another pane cross-fades the layers in `focusCrossFadeDuration` (0.15 s), ease-out.
  func testFocusChangeCrossFadesTheStack() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    harness.grid.reduceMotion = { false }
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let tile = try harness.tile(split)
    tile.stackLayer.removeAllAnimations()

    harness.controller.activate(node: world.favorite)

    let fade = try XCTUnwrap(tile.stackLayer.animation(forKey: kCATransition) as? CATransition,
                             "the front layer cross-fades")
    XCTAssertEqual(fade.type, .fade)
    XCTAssertEqual(fade.duration, 0.15)
    XCTAssertEqual(fade.duration, FavoritesLayout.focusCrossFadeDuration)
    XCTAssertEqual(fade.timingFunction, CAMediaTimingFunction(name: .easeOut))
  }

  /// With Reduce Motion the front layer switches at once.
  func testFocusChangeSwitchesAtOnceWithReduceMotion() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    harness.grid.reduceMotion = { true }
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let tile = try harness.tile(split)
    tile.stackLayer.removeAllAnimations()

    harness.controller.activate(node: world.favorite)

    XCTAssertNil(tile.stackLayer.animation(forKey: kCATransition))
    XCTAssertEqual(tile.splitStack?.order, [world.favorite, pane])
  }

  /// A favicon arriving, or another tab being shown, redraws the stack without a cross-fade: only focus moving
  /// between the split's panes animates.
  func testOnlyAFocusChangeCrossFades() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    harness.grid.reduceMotion = { false }
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let tile = try harness.tile(split)
    tile.stackLayer.removeAllAnimations()

    harness.grid.reload(node: pane)

    XCTAssertNil(tile.stackLayer.animation(forKey: kCATransition))
  }

  // MARK: Selected state and accessibility (#788)

  /// The tile is selected and its accessibility value says "current" while any of its panes is current, whichever
  /// pane that is.
  func testFavoriteSplitTileIsSelectedAndCurrentForAnyPane() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))

    for shown in [pane, world.favorite] {
      harness.controller.activate(node: shown)
      let tile = try harness.tile(split)
      XCTAssertEqual(harness.grid.resolver.current, shown)
      XCTAssertTrue(tile.isCurrent)
      XCTAssertEqual(tile.displayedFill, ShellTokens.tabCurrent.resolve(tile.flavor))
      XCTAssertEqual(tile.accessibilityValueDescription(), "Favorites, current")
    }

    harness.controller.activate(node: world.pinned)
    let tile = try harness.tile(split)
    XCTAssertEqual(tile.accessibilityValueDescription(), "Favorites, loaded")
  }

  /// VoiceOver reaches Separate All Tabs without the menu, next to the X's close (Close and Keep Favorite); with no
  /// page loaded there is no close, and Separate All Tabs stays.
  func testFavoriteSplitTileOffersSeparateAllTabsToVoiceOver() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    XCTAssertEqual(try harness.tile(split).accessibilityCustomActions()?.map(\.name),
                   ["Close", "Separate All Tabs"])

    try harness.clickClose(split)
    let tile = try harness.tile(split)
    XCTAssertEqual(tile.accessibilityCustomActions()?.map(\.name), ["Separate All Tabs"])

    let separate = try XCTUnwrap(tile.accessibilityCustomActions()?.first)
    XCTAssertTrue(separate.handler?() ?? false)
    XCTAssertEqual(harness.favorites, [world.favorite, pane])
  }

  /// A plain Favorite's tile has no Separate All Tabs action and shows its favicon.
  func testAPlainFavoriteTileHasNoStack() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    harness.controller.activate(node: world.favorite)

    let tile = try harness.tile(world.favorite)
    XCTAssertNil(tile.splitStack)
    XCTAssertTrue(tile.stackLayer.isHidden)
    XCTAssertFalse(tile.faviconView.isHidden)
    XCTAssertFalse(tile.accessibilityCustomActions()?.map(\.name).contains("Separate All Tabs") ?? false)
  }

  // MARK: The X and its plate

  /// The X sits on its round plate while hovered: the plate is a hole in the stack's mask, so the hovered fill covers
  /// any favicon under it. A tile with no loaded pane shows no X and no plate.
  func testTheXSitsOnItsPlateWhileHovered() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    var tile = try harness.tile(split)
    XCTAssertEqual(tile.plateLayer.opacity, 1, "no plate at rest")

    tile.isHovered = true
    XCTAssertFalse(tile.closeButton.isHidden)
    XCTAssertEqual(tile.plateLayer.opacity, 0, "the plate shows the fill")
    XCTAssertEqual(tile.plateLayer.path?.boundingBox.size, CGSize(width: 16, height: 16))
    tile.isHovered = false
    XCTAssertEqual(tile.plateLayer.opacity, 1)

    try harness.clickClose(split)
    tile = try harness.tile(split)
    tile.isHovered = false
    tile.isHovered = true
    XCTAssertTrue(tile.closeButton.isHidden, "no loaded pane: no X")
    XCTAssertEqual(tile.plateLayer.opacity, 1, "and no plate")
  }

  /// Increase Contrast draws the 1 pt edge on a split's tile, as on every Favorite tile.
  func testIncreaseContrastEdgesTheSplitTile() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let tile = try harness.tile(split)

    tile.increaseContrast = { true }
    tile.updateLayer()
    XCTAssertEqual(tile.fillLayer.borderWidth, ShellTokens.increasedContrastEdgeWidth)
    tile.increaseContrast = { false }
    tile.updateLayer()
    XCTAssertEqual(tile.fillLayer.borderWidth, 0)
  }

  // MARK: Split items in the menu (#788)

  /// Separate All Tabs on a Favorite split: each pane becomes its own Favorite, in pane order, at the split's place;
  /// the pages stay open.
  func testSeparateAllTabsMakesEachPaneAFavoriteInPlace() throws {
    var world = try Self.makeWorld()
    let after = try world.sidebar.addTab(url: Self.url("f1"), title: "F1", in: .favorites(profile: Self.profile))
    let harness = makeHarness(world.sidebar)
    let (split, pane) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    XCTAssertEqual(harness.favorites, [split, after])
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))
    let index = menu.indexOfItem(withTitle: "Separate All Tabs")
    XCTAssertEqual(index, 0)

    menu.performActionForItem(at: index)

    XCTAssertEqual(harness.favorites, [world.favorite, pane, after])
    XCTAssertEqual(harness.grid.nodeIDs, [world.favorite, pane, after])
    XCTAssertNotNil(harness.controller.engineTab(of: world.favorite), "the pages stay open")
    XCTAssertNotNil(harness.controller.engineTab(of: pane))
    XCTAssertNil(harness.source.node(split))
  }

  /// Convert to Vertical Split View works on a Favorite split, retitles itself, and does not change the tile.
  func testConvertFlipsAFavoriteSplitAndKeepsTheTile() throws {
    let world = try Self.makeWorld()
    let harness = makeHarness(world.sidebar)
    let (split, _) = try harness.addSplit(on: world.favorite, url: Self.url("new"))
    let before = try harness.tile(split).splitStack
    let menu = try XCTUnwrap(harness.grid.contextMenu(for: split))

    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Convert to Vertical Split View"))

    guard case .split(_, let layout)? = harness.source.node(split) else { return XCTFail("the split is gone") }
    XCTAssertEqual(layout.orientation, .vertical)
    XCTAssertEqual(harness.favorites, [split])
    XCTAssertEqual(try harness.tile(split).splitStack?.order, before?.order)
    XCTAssertEqual(harness.menuTitles(split)?[1], "Convert to Horizontal Split View")
  }
}
