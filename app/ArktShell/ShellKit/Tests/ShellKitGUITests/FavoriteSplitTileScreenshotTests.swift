import AppKit
import XCTest
@testable import ShellUI

/// Screenshots of a Favorite split's tile (#788, design/favorite-split-tile) for the pull request: every state of the
/// design's States table, for 2, 3 and 4 panes, in light and dark, at 2x. Skipped unless
/// `ARKT_FAVORITE_SPLIT_SHOTS_DIR` names a folder; writes `favorite-split-<state>-<light|dark>.png` there. Synthetic
/// favicons only.
@MainActor
final class FavoriteSplitTileScreenshotTests: XCTestCase {
  private var folder: URL?
  private var host: FavoriteSplitTileHost?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_FAVORITE_SPLIT_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_FAVORITE_SPLIT_SHOTS_DIR to write the Favorite split tile screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    host?.close()
    host = nil
    try await super.tearDown()
  }

  /// The design's states. `loading`: the second pane has no favicon yet and draws its letter tile.
  private enum Shot: String, CaseIterable {
    case resting, hover, selected, focusMoved = "focus-moved", loading, unloaded = "unloaded-hover"
  }

  private func tile(panes: Int, shot: Shot, dark: Bool) -> FavoriteTileView {
    let tile = FavoriteTileView(frame: .zero)
    let ids = (0..<panes).map { _ in NodeID() }
    let focused = shot == .focusMoved ? ids[1] : nil
    let order = FavoriteSplitStack.order(panes: ids, focused: focused)
    var images = [NSColor.systemOrange, .systemBlue, .systemGreen, .systemPink].map(FavoriteSplitTileHost.favicon)
    if shot == .focusMoved { images = Array(images[1...]) + [images[0]] }
    if shot == .loading {
      images[1] = SidebarGlyphs.letter(for: "", url: URL(string: "https://mail.example.com"),
                                       flavor: dark ? .dark : .light, size: FavoriteSplitStack.layerSizes[1], scale: 2)
    }
    tile.setSplitStack(.init(panes: ids, order: order, images: Array(images.prefix(order.count))))
    return tile
  }

  func testFavoriteSplitTileShots() throws {
    for shot in Shot.allCases {
      for dark in [false, true] {
        let tiles = [2, 3, 4].map { tile(panes: $0, shot: shot, dark: dark) }
        let background = dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                              : NSColor(srgbRed: 0.93, green: 0.92, blue: 0.91, alpha: 1)
        host?.close()
        let made = FavoriteSplitTileHost(tiles, background: background, dark: dark, inset: 12, gap: 12)
        host = made
        for tile in tiles {
          if shot != .unloaded { tile.setCloseAction(.closeFavorite) }
          tile.isHovered = shot == .hover || shot == .unloaded
          tile.isCurrent = shot == .selected || shot == .focusMoved
        }
        let rep = try made.render()
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: try XCTUnwrap(folder).appendingPathComponent(
          "favorite-split-\(shot.rawValue)-\(dark ? "dark" : "light").png"))
      }
    }
  }
}
