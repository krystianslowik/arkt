import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The command bar's "Favorite Tab" and "Move To Favorites" actions (BH-047, #340): both favorite the current tab
/// through `move(_:to:)`, a current pane takes its whole split, and a full Favorites section shows
/// "Favorites are full.".
@MainActor
final class CommandBarFavoriteTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let actionIDs = ["favoriteTab", "moveToFavorites"]

  /// One Space with Pinned `[pinned]`, Today `[today..., split]` and `favorites` Favorites.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
    var favorites: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let controller: ShellWindowController

    init(_ sidebar: SidebarModel.Sidebar) {
      source = ModelSidebarSource(sidebar: sidebar, now: { CommandBarFavoriteTests.now })
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    var favorites: [UUID] { source.children(of: .favorites(profile: "default")) }
    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }

    /// The action search's ids for the favorite actions, in the order the bar lists them.
    func favoriteActions() -> [String] {
      controller.commandBar.actionsProvider().map(\.id).filter(CommandBarFavoriteTests.actionIDs.contains)
    }

    func titles() -> [String] { controller.commandBar.actionsProvider().map(\.title) }

    func run(_ id: String) { controller.commandBar.onAction?(id) }
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
    return World(sidebar: sidebar, space: space, pinned: pinned, today: today, split: split, panes: panes,
                 favorites: favorites)
  }

  func testTheActionSearchListsBothFavoriteActionsForATodayTab() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    harness.controller.show(node: world.today[0])
    XCTAssertEqual(harness.favoriteActions(), Self.actionIDs)
    XCTAssertTrue(harness.titles().contains("Favorite Tab"))
    XCTAssertTrue(harness.titles().contains("Move To Favorites"))
    harness.controller.close()
  }

  func testFavoriteTabAppendsTheCurrentTodayTabToFavorites() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    harness.controller.show(node: world.today[0])
    harness.run("favoriteTab")
    XCTAssertEqual(harness.favorites, world.favorites + [world.today[0]])
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[1], world.split])
    XCTAssertNil(harness.controller.toasts.current)
    harness.controller.close()
  }

  func testMoveToFavoritesAppendsTheCurrentPinnedTabToFavorites() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    harness.controller.show(node: world.pinned)
    harness.run("moveToFavorites")
    XCTAssertEqual(harness.favorites, world.favorites + [world.pinned])
    XCTAssertEqual(harness.children(.pinned(world.space)), [])
    harness.controller.close()
  }

  /// A pane never leaves its split this way (as the row menu has no Move To on a pane): the whole split moves.
  func testACurrentPaneFavoritesItsWholeSplit() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    harness.controller.show(node: world.panes[1])
    XCTAssertEqual(harness.favoriteActions(), Self.actionIDs)
    harness.run("favoriteTab")
    XCTAssertEqual(harness.favorites, world.favorites + [world.split])
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    harness.controller.close()
  }

  /// BH-046: the 13th Favorite is refused; the tab stays and the toast names the full section.
  func testAFullFavoritesSectionShowsFavoritesAreFull() throws {
    let world = try Self.makeWorld(favorites: 12)
    for id in Self.actionIDs {
      let harness = Harness(world.sidebar)
      harness.controller.show(node: world.today[0])
      harness.run(id)
      XCTAssertEqual(harness.favorites, world.favorites, id)
      XCTAssertEqual(harness.children(.today(world.space)), world.today + [world.split], id)
      XCTAssertEqual(harness.controller.toasts.current?.text, "Favorites are full.", id)
      harness.controller.close()
    }
  }

  func testACurrentFavoriteGetsNeitherAction() throws {
    let world = try Self.makeWorld(favorites: 2)
    let harness = Harness(world.sidebar)
    harness.controller.show(node: world.favorites[0])
    XCTAssertEqual(harness.favoriteActions(), [])
    harness.run("favoriteTab")
    XCTAssertEqual(harness.favorites, world.favorites)
    harness.controller.close()
  }
}
