import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// BH-049: only recently used Favorites stay loaded. Loading more than the limit unloads the least recently used
/// ones: the page closes (so its playback stops with it, BH-053) and the Favorite row stays, unloaded.
@MainActor
final class FavoritesUnloadTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// One Space "Work" with one Today tab and `favorites` Favorites.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var today: UUID
    var favorites: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { FavoritesUnloadTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func activate(_ node: UUID) { controller.activate(node: node) }
    func tab(of node: UUID) -> TabID? { controller.engineTab(of: node) }
    func favoritesChildren() -> [UUID] { source.children(of: .favorites(profile: "default")) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func makeWorld(favorites count: Int) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let today = try sidebar.addTab(url: URL(string: "https://example.com/t")!, title: "T", in: .today(space))
    let favorites = try (0..<count).map {
      try sidebar.addTab(url: URL(string: "https://example.com/f\($0)")!, title: "F\($0)",
                         in: .favorites(profile: "default"))
    }
    return World(sidebar: sidebar, space: space, today: today, favorites: favorites)
  }

  /// Loading more Favorites than the limit unloads the least recently used; the rows stay (the page goes, not the
  /// Favorite, so its playback stops with the page, BH-053).
  func testLoadingBeyondTheLimitUnloadsTheLeastRecentlyUsedFavorites() throws {
    let limit = FavoritesUnloadPolicy.maximumLoadedFavorites
    let world = try Self.makeWorld(favorites: limit + 2)
    let harness = Harness(world.sidebar)
    for favorite in world.favorites { harness.activate(favorite) }
    for favorite in world.favorites.prefix(world.favorites.count - limit) {
      XCTAssertNil(harness.tab(of: favorite), "the least recently used Favorite unloads")
    }
    for favorite in world.favorites.suffix(limit) {
      XCTAssertNotNil(harness.tab(of: favorite))
    }
    XCTAssertEqual(harness.favoritesChildren(), world.favorites)
    harness.controller.close()
  }

  /// Re-activating a Favorite makes it the most recently used: the next eviction skips it.
  func testReactivatingRefreshesRecency() throws {
    let limit = FavoritesUnloadPolicy.maximumLoadedFavorites
    let world = try Self.makeWorld(favorites: limit + 1)
    let harness = Harness(world.sidebar)
    for favorite in world.favorites.prefix(limit) { harness.activate(favorite) }
    harness.activate(world.favorites[0])      // f0 is now the most recently used
    harness.activate(world.favorites[limit])  // the ninth load: one eviction past the limit
    XCTAssertNotNil(harness.tab(of: world.favorites[0]))
    XCTAssertNil(harness.tab(of: world.favorites[1]))
    harness.controller.close()
  }

  /// A loaded Favorite that moved to Pinned leaves the recency order: later evictions never close it.
  func testAFavoriteMovedToPinnedIsNeverUnloaded() throws {
    let limit = FavoritesUnloadPolicy.maximumLoadedFavorites
    let world = try Self.makeWorld(favorites: limit + 2)
    let harness = Harness(world.sidebar)
    harness.activate(world.favorites[0])
    try harness.source.moveNode(world.favorites[0], to: .pinned(world.space), at: 0)
    for favorite in world.favorites.dropFirst() { harness.activate(favorite) }
    XCTAssertNotNil(harness.tab(of: world.favorites[0]), "a Pinned tab is not a Favorite to unload")
    XCTAssertNil(harness.tab(of: world.favorites[1]), "the least recently used Favorite still unloads")
    harness.controller.close()
  }

  /// Pinned and Today tabs are never unloaded by the Favorites limit.
  func testTodayTabsStayLoaded() throws {
    let world = try Self.makeWorld(favorites: FavoritesUnloadPolicy.maximumLoadedFavorites + 1)
    let harness = Harness(world.sidebar)
    harness.activate(world.today)
    for favorite in world.favorites { harness.activate(favorite) }
    XCTAssertNotNil(harness.tab(of: world.today))
    harness.controller.close()
  }
}
