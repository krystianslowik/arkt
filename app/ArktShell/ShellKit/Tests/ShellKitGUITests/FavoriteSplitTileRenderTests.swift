import AppKit
import XCTest
@testable import ShellUI

/// A Favorite split's tile as drawn (#788, design/favorite-split-tile): the stack's ring is a cut-out, so the pixels in
/// the ring are the tile's own fill over whatever is behind the sidebar, in every state, in light and dark, on a
/// theme. Rendered in process into a 2x bitmap; nothing is captured from the screen.
@MainActor
final class FavoriteSplitTileRenderTests: XCTestCase {
  private var host: FavoriteSplitTileHost?

  /// Two Space themes: Sand behind dark text, Plum behind light text (as `SidebarDropSlotScreenshotTests`).
  static let sand = NSColor(srgbRed: 0xF3 / 255, green: 0xE9 / 255, blue: 0xD2 / 255, alpha: 1)
  static let plum = NSColor(srgbRed: 0x4A / 255, green: 0x34 / 255, blue: 0x60 / 255, alpha: 1)

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    host?.close()
    host = nil
    try await super.tearDown()
  }

  private func makeHost(_ tiles: [FavoriteTileView], background: NSColor, dark: Bool) -> FavoriteSplitTileHost {
    host?.close()
    let made = FavoriteSplitTileHost(tiles, background: background, dark: dark)
    host = made
    return made
  }

  private func stackTile(panes: Int) -> FavoriteTileView {
    let tile = FavoriteTileView(frame: .zero)
    let panes = (0..<panes).map { _ in NodeID() }
    let order = FavoriteSplitStack.order(panes: panes, focused: nil)
    tile.setSplitStack(.init(panes: panes, order: order,
                             images: Array(FavoriteSplitTileHost.favicons.prefix(order.count))))
    return tile
  }

  // MARK: The cut-out ring

  /// In the ring around the front favicon, where the second favicon lies below, the tile shows its own fill: the
  /// same pixels as a bare part of the tile. Resting, hovered and selected; light and dark; on two themes.
  func testTheRingMatchesTheTileFillInEveryState() throws {
    let ring = CGPoint(x: 30, y: 21.5)            // in the front's ring, over the second favicon
    let secondRing = CGPoint(x: 42, y: 30)        // in the second's ring, over the third favicon
    let bare = CGPoint(x: 4, y: 30)               // the tile's fill, nothing drawn on it
    for theme in [Self.sand, Self.plum] {
      for dark in [false, true] {
        for state in ["resting", "hovered", "selected"] {
          let tile = stackTile(panes: 3)
          let host = makeHost([tile], background: theme, dark: dark)
          tile.isHovered = state == "hovered"
          tile.isCurrent = state == "selected"
          let rep = try host.render()
          let fill = host.pixel(rep, tile, bare)
          let label = "\(state), \(dark ? "dark" : "light"), \(theme == Self.sand ? "sand" : "plum")"
          for point in [ring, secondRing] {
            let shown = host.pixel(rep, tile, point)
            XCTAssertTrue(zip(shown, fill).allSatisfy { abs($0 - $1) <= 2 },
                          "ring \(point) is \(shown), the fill is \(fill): \(label)")
          }
          XCTAssertNotEqual(host.pixel(rep, tile, CGPoint(x: 36, y: 25)), fill,
                            "the second favicon is drawn: \(label)")
        }
      }
    }
  }

  /// The stack sits at the design's offsets in the tile: the front favicon's center is red, the second's blue.
  func testTheStackIsDrawnAtItsOffsets() throws {
    let tile = stackTile(panes: 2)
    let host = makeHost([tile], background: Self.sand, dark: false)
    let rep = try host.render()

    let front = host.pixel(rep, tile, CGPoint(x: 19, y: 17))
    let second = host.pixel(rep, tile, CGPoint(x: 36, y: 32))
    XCTAssertGreaterThan(front[0], 180, "red front at (9, 7, 20, 20): \(front)")
    XCTAssertLessThan(front[2], 120, "\(front)")
    XCTAssertGreaterThan(second[2], 180, "blue second at (25, 21, 16, 16): \(second)")
    XCTAssertLessThan(second[0], 120, "\(second)")
  }
}

/// A borderless test window holding Favorite tiles side by side on a flat background, and its 2x render. The test
/// that makes one closes it in `tearDown`.
@MainActor
final class FavoriteSplitTileHost {
  let window: NSWindow
  let view: NSView

  /// A synthetic favicon: a rounded square in one color.
  static func favicon(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
      color.setFill()
      NSBezierPath(roundedRect: rect, xRadius: rect.width * FavoriteSplitStack.layerCornerRatio,
                   yRadius: rect.height * FavoriteSplitStack.layerCornerRatio).fill()
      return true
    }
  }

  static let favicons = [favicon(.systemRed), favicon(.systemBlue), favicon(.systemGreen)]

  /// A borderless window holding `tiles` side by side on `background`, at `inset` from the edges.
  init(_ tiles: [FavoriteTileView], background: NSColor, dark: Bool, inset: CGFloat = 8,
       gap: CGFloat = FavoritesLayout.gap) {
    let size = FavoriteSplitStack.boxSize
    let width = 2 * inset + CGFloat(tiles.count) * size.width + CGFloat(max(tiles.count - 1, 0)) * gap
    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: size.height + 2 * inset))
    content.wantsLayer = true
    content.layer?.backgroundColor = background.cgColor
    let made = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
    made.isReleasedWhenClosed = false
    made.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    made.contentView = content
    window = made
    view = content
    for (index, tile) in tiles.enumerated() {
      tile.frame = NSRect(x: inset + CGFloat(index) * (size.width + gap), y: inset, width: size.width,
                          height: size.height)
      tile.flavor = dark ? .dark : .light
      tile.reduceMotion = { true }
      tile.closeButton.reducesMotion = { true }
      content.addSubview(tile)
    }
    content.layoutSubtreeIfNeeded()
  }

  func close() { window.close() }

  /// `view` at 2x, from its layer tree.
  func render() throws -> NSBitmapImageRep {
    view.displayIfNeeded()
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                             pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
  }

  /// The pixel at `point` of the tile's box (top-left origin, points), as 0...255 sRGB components.
  func pixel(_ rep: NSBitmapImageRep, _ tile: FavoriteTileView, _ point: CGPoint) -> [Int] {
    let hostHeight = rep.size.height
    let x = (tile.frame.minX + point.x) * 2
    let y = (hostHeight - tile.frame.maxY + point.y) * 2
    let color = rep.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB)
    return [color?.redComponent, color?.greenComponent, color?.blueComponent].map { Int((($0 ?? 0) * 255).rounded()) }
  }
}
