import AppKit

/// Bitmaps for SF Symbols (and other small drawn glyphs), rendered once per (name, box, weight, color,
/// backing scale). An `NSImageView` showing a symbol `NSImage` draws it through AppKit's symbol
/// representation cache, a small LRU that the shell's variants overflow; a miss re-rasterizes the vector
/// glyph inside the frame's Core Animation commit (C7 idle profile: 14-21 ms frames during Space swipes).
/// Images from here hold a single `NSBitmapImageRep`, so displaying them is a `CGImage` lookup.
@MainActor
public final class SymbolImageCache {
  public static let shared = SymbolImageCache()

  /// Symbols the shell shows, prewarmed per flavor at launch.
  static let sidebarSymbols = ["folder", "folder.fill", "rectangle.split.2x1", "questionmark.square"]
  static let bottomBarSymbols = ["archivebox", "plus"]
  static let commandBarSymbols = ["globe", "square.on.square", "magnifyingglass"]

  private struct Key: Hashable {
    var name: String
    var box: Double
    var weight: Double
    var color: [Double]
    var scale: Double
  }

  private var images: [Key: NSImage] = [:]
  private var drawn: [String: NSImage] = [:]
  /// Bitmaps rendered so far (tests check that hits do not render).
  public private(set) var renderCount = 0
  public var count: Int { images.count + drawn.count }

  public init() {}

  /// `name` drawn in `color`, aspect-fit and centered in a `box` x `box` pt bitmap at `scale` pixels per pt.
  public func symbol(_ name: String, box: CGFloat, weight: NSFont.Weight = .regular, color: RGBA,
                     scale: CGFloat) -> NSImage {
    let key = Key(name: name, box: Double(box), weight: Double(weight.rawValue),
                  color: [color.red, color.green, color.blue, color.alpha, color.space == .displayP3 ? 1 : 0],
                  scale: Double(scale))
    if let image = images[key] { return image }
    let configuration = NSImage.SymbolConfiguration(pointSize: box, weight: weight)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color.nsColor()]))
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    let image = render(size: box, scale: scale) { rect in
      guard let symbol, symbol.size.width > 0, symbol.size.height > 0 else { return }
      let fit = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
      let size = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
      symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                             width: size.width, height: size.height))
    }
    images[key] = image
    return image
  }

  /// A `size` x `size` pt bitmap drawn once by `draw` and cached under `key` plus the scale.
  public func bitmap(key: String, size: CGFloat, scale: CGFloat, draw: (NSRect) -> Void) -> NSImage {
    let fullKey = "\(key)@\(size)x\(scale)"
    if let image = drawn[fullKey] { return image }
    let image = render(size: size, scale: scale, draw: draw)
    drawn[fullKey] = image
    return image
  }

  /// Renders every symbol the sidebar, bottom bar and command bar use, for both flavors, at `scale`.
  public func prewarm(scale: CGFloat) {
    for flavor in [ThemeFlavor.light, .dark] {
      for name in Self.sidebarSymbols { _ = SidebarGlyphs.symbol(name, flavor: flavor, scale: scale, cache: self) }
      _ = SidebarGlyphs.close(flavor: flavor, scale: scale, cache: self)
      for name in Self.bottomBarSymbols {
        _ = symbol(name, box: SidebarMetrics.bottomBarIconSize, color: ShellTokens.sidebarForeground.resolve(flavor),
                   scale: scale)
      }
    }
    for name in Self.commandBarSymbols {
      _ = symbol(name, box: CommandBarCellView.iconSize, color: ShellTokens.commandBarText, scale: scale)
    }
  }

  /// Bitmaps are Display P3, the space of most shell tokens; sRGB tokens convert into it exactly (P3 holds
  /// sRGB), so one space serves every key and the cache keys need no color-space part beyond the token's.
  private static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

  private func render(size: CGFloat, scale: CGFloat, draw: (NSRect) -> Void) -> NSImage {
    renderCount += 1
    let pixels = max(Int((size * scale).rounded(.up)), 1)
    let image = NSImage(size: NSSize(width: size, height: size))
    guard let cgContext = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: Self.colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    cgContext.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)   // points map to scale pixels
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: false)
    draw(NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let cgImage = cgContext.makeImage() else { return image }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: size, height: size)
    image.addRepresentation(rep)
    return image
  }
}

extension NSView {
  /// Pixels per point for bitmaps drawn for this view: its window's, else the main screen's, else 2.
  var shellBackingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
}
