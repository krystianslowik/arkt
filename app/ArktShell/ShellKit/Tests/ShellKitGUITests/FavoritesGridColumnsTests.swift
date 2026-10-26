import AppKit
import XCTest
@testable import ShellUI

/// #337: the Favorites grid takes 1 to 4 columns by sidebar width with rows filled evenly; the keyboard cursor and
/// the drop band follow it, and a resize that changes the column count moves the tiles on a spring.
@MainActor
final class FavoritesGridColumnsTests: XCTestCase {
  private static let widths: [CGFloat] = [150, 190, 400]   // narrow, default, wide sidebar
  private var windows: [NSWindow] = []
  /// The column spring's clock; tests move it by hand.
  private var clock: CFTimeInterval = 1000

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    windows.forEach { $0.orderOut(nil); $0.close() }
    windows = []
  }

  private func makeSidebar(favorites count: Int, width: CGFloat) -> (SidebarController, [NodeID]) {
    let source = StubSidebar()
    _ = source.addSpace(title: "Work", theme: SpaceThemeInfo(baseColors: [.white(1)], isDark: false))
    let ids = (0..<count).map {
      source.addTab(url: URL(string: "https://example.com/f\($0)")!, title: "F\($0)",
                    in: .favorites(profile: "default"))
    }
    let controller = SidebarController(source: source)
    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: width, height: 700), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    resize(window, to: width)
    windows.append(window)
    return (controller, ids)
  }

  private func resize(_ window: NSWindow, to width: CGFloat) {
    window.setContentSize(NSSize(width: width, height: 700))
    window.contentView?.layoutSubtreeIfNeeded()
  }

  /// Shows the window and puts the column spring on this test's clock, frames presented by `advance`.
  private func animate(_ grid: FavoritesGridView) throws {
    let window = try XCTUnwrap(grid.window)
    window.orderFrontRegardless()
    grid.columnMotion.now = { [unowned self] in clock }
    grid.columnMotion.drivesFramesItself = false
    grid.columnMotion.reduceMotion = { false }
  }

  private func advance(_ grid: FavoritesGridView, by seconds: CFTimeInterval) {
    clock += seconds
    grid.columnMotion.presentFrame()
    grid.window?.contentView?.layoutSubtreeIfNeeded()
  }

  private func tileFrames(_ grid: FavoritesGridView, _ ids: [NodeID]) throws -> [CGRect] {
    grid.collectionView.layoutSubtreeIfNeeded()
    return try ids.map { try XCTUnwrap(grid.tile(for: $0), "no tile").frame }
  }

  // MARK: Layout

  /// 1 to 12 Favorites at the narrow, default and wide widths: every tile in its grid frame, the grid as tall as its
  /// rows, the Space page right below it, and the drop band over the whole grid.
  func testOneToTwelveFavoritesLayOutAtEveryWidth() throws {
    for count in 1...12 {
      let (controller, ids) = makeSidebar(favorites: count, width: Self.widths[0])
      let window = try XCTUnwrap(controller.view.window)
      for width in Self.widths {
        resize(window, to: width)
        let grid = controller.view.favorites
        let contentWidth = FavoritesLayout.contentWidth(sidebarWidth: width)
        let context = "\(count) Favorites at \(width) pt"
        XCTAssertFalse(grid.columnMotion.isRunning, context)
        XCTAssertEqual(grid.columns, FavoritesLayout.columns(itemCount: count, contentWidth: contentWidth), context)
        XCTAssertEqual(grid.frame.width, contentWidth, context)
        XCTAssertEqual(grid.frame.height, FavoritesLayout.height(itemCount: count, contentWidth: contentWidth),
                       context)
        XCTAssertEqual(controller.view.pager.frame.minY, grid.frame.maxY + SidebarMetrics.favoritesBottomGap,
                       context)
        let frames = try tileFrames(grid, ids)
        for (index, frame) in frames.enumerated() {
          XCTAssertEqual(frame, FavoritesLayout.frame(ofItem: index, itemCount: count, contentWidth: contentWidth),
                         "\(context), tile \(index)")
        }
        XCTAssertEqual(FavoritesDrop.band(favoritesFrame: grid.frame), grid.frame, context)
        let lastTile = try XCTUnwrap(frames.last)
        XCTAssertTrue(FavoritesDrop.band(favoritesFrame: grid.frame)
                        .contains(grid.convert(CGPoint(x: lastTile.midX, y: lastTile.midY), to: controller.view)),
                      "the band covers the last row: \(context)")
      }
    }
  }

  /// The maintainer's example: 4 Favorites in a wide sidebar make one row of 4, not 3 + 1.
  func testFourFavoritesInAWideSidebarMakeOneRow() throws {
    let (controller, ids) = makeSidebar(favorites: 4, width: 400)
    let grid = controller.view.favorites
    let frames = try tileFrames(grid, ids)
    XCTAssertEqual(Set(frames.map(\.minY)), [0])
    XCTAssertEqual(grid.frame.height, FavoritesLayout.tileHeight)
    XCTAssertEqual(frames.last?.maxX, grid.bounds.width, "the tiles grow to fill the row")

    resize(try XCTUnwrap(grid.window), to: 190)
    XCTAssertEqual(Set(try tileFrames(grid, ids).map(\.minY)).count, 2, "2 + 2 at the default width")
  }

  // MARK: Keyboard (#343)

  func testKeyboardFocusFollowsTheColumns() throws {
    let (controller, ids) = makeSidebar(favorites: 7, width: 400)   // 4 + 3
    let grid = controller.view.favorites
    XCTAssertEqual(grid.columns, 4)
    grid.focusKeyboard(on: ids[1])
    grid.collectionView.moveDown(nil)
    XCTAssertEqual(grid.keyboardFocusID, ids[5], "Down moves one row of 4")
    grid.collectionView.moveUp(nil)
    XCTAssertEqual(grid.keyboardFocusID, ids[1])
    grid.focusKeyboard(on: ids[3])
    grid.collectionView.moveDown(nil)
    XCTAssertEqual(grid.keyboardFocusID, ids[6], "Down over the short last row's gap takes its last tile")

    resize(try XCTUnwrap(grid.window), to: 150)                      // 2 columns
    XCTAssertEqual(grid.columns, 2)
    grid.focusKeyboard(on: ids[1])
    grid.collectionView.moveDown(nil)
    XCTAssertEqual(grid.keyboardFocusID, ids[3], "Down moves one row of 2")
    grid.collectionView.moveRight(nil)
    XCTAssertEqual(grid.keyboardFocusID, ids[4])

    var below = false
    grid.onKeyboardFocusBelow = { below = true }
    grid.focusKeyboard(on: ids[6])
    grid.collectionView.moveDown(nil)
    XCTAssertTrue(below, "Down from the last row leaves the grid")
  }

  // MARK: Column spring

  /// Widening across a threshold moves the tiles on a spring from their old slots; the grid height follows them, a
  /// resize back mid-flight reverses without a jump, and the motion settles exactly on the grid.
  func testColumnChangeRunsAnInterruptibleSpring() throws {
    let (controller, ids) = makeSidebar(favorites: 4, width: 190)    // 2 + 2
    let grid = controller.view.favorites
    let window = try XCTUnwrap(grid.window)
    try animate(grid)
    let before = try tileFrames(grid, ids)
    XCTAssertEqual(before[2].minY, FavoritesLayout.tileHeight + FavoritesLayout.gap)

    resize(window, to: 400)                                          // 1 x 4
    XCTAssertTrue(grid.columnMotion.isRunning)
    XCTAssertEqual(grid.columns, 4, "the keyboard already uses the new columns")
    let start = try tileFrames(grid, ids)
    XCTAssertEqual(start[2].minY, before[2].minY, "the third tile starts in its old row")
    XCTAssertEqual(grid.frame.height, FavoritesLayout.height(itemCount: 4, contentWidth: 174), "no height jump")

    advance(grid, by: 0.06)
    let mid = try tileFrames(grid, ids)
    XCTAssertLessThan(mid[2].minY, start[2].minY)
    XCTAssertGreaterThan(mid[2].minY, 0, "still on its way up")
    XCTAssertGreaterThan(mid[2].minX, start[2].minX)
    XCTAssertLessThan(grid.frame.height, FavoritesLayout.height(itemCount: 4, contentWidth: 174))
    XCTAssertGreaterThan(grid.frame.height, FavoritesLayout.tileHeight)
    XCTAssertEqual(controller.view.pager.frame.minY, grid.frame.maxY + SidebarMetrics.favoritesBottomGap,
                   "the Space page follows the animated height")

    resize(window, to: 190)                                          // back to 2 + 2 mid-flight
    XCTAssertTrue(grid.columnMotion.isRunning)
    let reversed = try tileFrames(grid, ids)
    XCTAssertEqual(reversed[2].minY, mid[2].minY, accuracy: 0.5, "the reversal starts where the tile is")


    for _ in 0..<60 { advance(grid, by: 1.0 / 60) }
    XCTAssertFalse(grid.columnMotion.isRunning)
    let settled = try tileFrames(grid, ids)
    for (index, frame) in settled.enumerated() {
      XCTAssertEqual(frame, FavoritesLayout.frame(ofItem: index, itemCount: 4, contentWidth: 174))
    }
    XCTAssertEqual(grid.frame.height, FavoritesLayout.height(itemCount: 4, contentWidth: 174))
  }

  /// Under Reduce Motion the columns switch at once, with no frame in between.
  func testReduceMotionSwitchesColumnsAtOnce() throws {
    let (controller, ids) = makeSidebar(favorites: 4, width: 190)
    let grid = controller.view.favorites
    try animate(grid)
    grid.columnMotion.reduceMotion = { true }
    resize(try XCTUnwrap(grid.window), to: 400)
    XCTAssertFalse(grid.columnMotion.isRunning)
    for (index, frame) in try tileFrames(grid, ids).enumerated() {
      XCTAssertEqual(frame, FavoritesLayout.frame(ofItem: index, itemCount: 4, contentWidth: 384))
    }
    XCTAssertEqual(grid.frame.height, FavoritesLayout.tileHeight)
  }

  /// A Favorite added or removed switches the columns at once (only a resize runs the spring), and the drop band
  /// keeps covering the grid.
  func testStructureChangeSwitchesColumnsAtOnce() throws {
    let (controller, ids) = makeSidebar(favorites: 3, width: 190)    // one row of 3
    let grid = controller.view.favorites
    try animate(grid)
    let source = try XCTUnwrap(grid.source as? StubSidebar)
    let added = source.addTab(url: URL(string: "https://example.com/added")!, title: "Added",
                              in: .favorites(profile: "default"))
    controller.view.layoutSubtreeIfNeeded()
    XCTAssertFalse(grid.columnMotion.isRunning)
    XCTAssertEqual(grid.columns, 2, "4 Favorites at the default width: 2 + 2")
    let frames = try tileFrames(grid, ids + [added])
    for (index, frame) in frames.enumerated() {
      XCTAssertEqual(frame, FavoritesLayout.frame(ofItem: index, itemCount: 4, contentWidth: 174))
    }
    XCTAssertEqual(FavoritesDrop.band(favoritesFrame: grid.frame).height, 46 * 2 + 9)
  }
}
