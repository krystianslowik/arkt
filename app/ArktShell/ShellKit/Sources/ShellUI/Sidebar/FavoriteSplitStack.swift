import AppKit

/// The look of a Split View in the Favorites (#788, design/favorite-split-tile, direction B): up to three pane
/// favicons, layered, in a 52 x 47 pt box at the tile's center. The front favicon, and the second when a third is
/// behind it, carry a 2 pt ring drawn as a cut-out: the layers below are cleared under the ring's shape, so the tile's
/// own fill shows there in every state and on every theme. Pure geometry plus one bitmap render; the tile shows it.
@MainActor
enum FavoriteSplitStack {
  /// The box the offsets are measured in: the narrowest tile.
  static let boxSize = CGSize(width: FavoritesLayout.minimumTileWidth, height: FavoritesLayout.tileHeight)
  /// Front, second and third layer: size and offset from the box's top leading corner. The third ends at y 42.
  static let layerSizes: [CGFloat] = [SidebarMetrics.favoriteFaviconSize, 16, 14]
  static let layerOffsets: [CGPoint] = [CGPoint(x: 9, y: 7), CGPoint(x: 25, y: 21), CGPoint(x: 32, y: 28)]
  /// A 4th pane is not drawn; the tooltip and the VoiceOver label name it.
  static var maximumLayers: Int { layerSizes.count }
  /// The ring around a layer that has another one behind it.
  static let ringWidth: CGFloat = 2
  /// A layer's shape: the letter tile's rounded square (`SidebarGlyphs.letter`), 25 % of its side.
  static let layerCornerRatio: CGFloat = 0.25

  // MARK: Order

  /// The panes drawn, front first: the focused pane (else the first), then the next panes in order after it,
  /// wrapping, at most `maximumLayers`.
  static func order(panes: [NodeID], focused: NodeID?) -> [NodeID] {
    guard !panes.isEmpty else { return [] }
    let start = focused.flatMap { panes.firstIndex(of: $0) } ?? 0
    let count = min(panes.count, maximumLayers)
    return (0..<count).map { panes[(start + $0) % panes.count] }
  }

  // MARK: Geometry

  /// The layers' frames in the box (top-left origin), front first.
  static func frames(layerCount: Int) -> [CGRect] {
    (0..<min(max(layerCount, 0), maximumLayers)).map {
      CGRect(origin: layerOffsets[$0], size: CGSize(width: layerSizes[$0], height: layerSizes[$0]))
    }
  }

  /// Where the box sits in a tile of `size`, from the tile's top leading corner: centered, on whole points, as a
  /// plain Favorite's favicon is.
  static func boxOrigin(in size: CGSize) -> CGPoint {
    CGPoint(x: ((size.width - boxSize.width) / 2).rounded(), y: ((size.height - boxSize.height) / 2).rounded())
  }

  /// A layer's shape, grown by `outset` (the ring is the shape grown by `ringWidth`).
  static func shape(of frame: CGRect, outset: CGFloat = 0) -> CGPath {
    let rect = frame.insetBy(dx: -outset, dy: -outset)
    let radius = frame.width * layerCornerRatio + outset
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  // MARK: Rendering

  /// The stack as one bitmap of the box at `scale`, `images` front first. Drawn back to front; before each layer
  /// that has one behind it, its ring shape is cleared, which also clears the layer below under a translucent letter
  /// tile. Nil when nothing is to be drawn.
  static func render(_ images: [NSImage], scale: CGFloat) -> CGImage? {
    let frames = frames(layerCount: images.count)
    guard !frames.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: Int((boxSize.width * scale).rounded()),
                                  height: Int((boxSize.height * scale).rounded()), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: boxSize.height)    // top-left origin, as the offsets are written
    context.scaleBy(x: 1, y: -1)
    let graphics = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    for index in frames.indices.reversed() {
      if index < frames.count - 1 {
        context.saveGState()
        context.setBlendMode(.clear)
        context.addPath(shape(of: frames[index], outset: ringWidth))
        context.fillPath()
        context.restoreGState()
      }
      images[index].draw(in: frames[index], from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                         hints: nil)
    }
    return context.makeImage()
  }
}
