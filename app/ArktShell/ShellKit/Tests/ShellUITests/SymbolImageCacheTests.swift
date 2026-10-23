import AppKit
import Testing
@testable import ShellUI

/// C7: symbol icons are bitmaps rendered once, so drawing them never reaches AppKit's symbol LRU.
@MainActor
struct SymbolImageCacheTests {
  private let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)

  /// The pixel tagged with the bitmap's own color space (`colorAt` reports calibrated RGB for a CGImage-backed
  /// rep, which would misread Display P3 components).
  private func color(_ rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
    var raw = [Int](repeating: 0, count: rep.samplesPerPixel)
    rep.getPixel(&raw, atX: x, y: y)
    let max = CGFloat((1 << rep.bitsPerSample) - 1)
    var components = raw.map { CGFloat($0) / max }
    if rep.hasAlpha, let alpha = components.last, alpha > 0 {      // premultiplied: undo it for the color part
      for i in 0..<(components.count - 1) { components[i] /= alpha }
    }
    return NSColor(colorSpace: rep.colorSpace, components: components, count: components.count)
  }

  @Test func sameKeyReturnsTheSameImageWithoutRerendering() {
    let cache = SymbolImageCache()
    let a = cache.symbol("folder", box: 16, color: red, scale: 2)
    let renders = cache.renderCount
    let b = cache.symbol("folder", box: 16, color: red, scale: 2)
    #expect(a === b)
    #expect(cache.renderCount == renders)
  }

  @Test func eachKeyPartMakesADistinctImage() {
    let cache = SymbolImageCache()
    let base = cache.symbol("folder", box: 16, color: red, scale: 2)
    #expect(cache.symbol("folder", box: 16, color: red, scale: 1) !== base)
    #expect(cache.symbol("folder", box: 20, color: red, scale: 2) !== base)
    #expect(cache.symbol("folder", box: 16, weight: .bold, color: red, scale: 2) !== base)
    #expect(cache.symbol("folder", box: 16, color: .white(0.8), scale: 2) !== base)
    #expect(cache.symbol("plus", box: 16, color: red, scale: 2) !== base)
    #expect(cache.count == 6)
  }

  @Test func imageIsOneBitmapAtTheBackingScale() throws {
    let cache = SymbolImageCache()
    let image = cache.symbol("archivebox", box: 16, color: red, scale: 2)
    #expect(image.size == NSSize(width: 16, height: 16))
    #expect(!image.isTemplate)
    #expect(image.representations.count == 1)
    let rep = try #require(image.representations.first as? NSBitmapImageRep)
    #expect(rep.pixelsWide == 32 && rep.pixelsHigh == 32)
  }

  @Test func glyphIsDrawnInTheRequestedColor() throws {
    let cache = SymbolImageCache()
    let image = cache.symbol("square.fill", box: 16, color: red, scale: 2)
    let rep = try #require(image.representations.first as? NSBitmapImageRep)
    let center = try #require(color(rep, x: 16, y: 16)?.usingColorSpace(.sRGB))
    #expect(center.alphaComponent > 0.9)
    #expect(center.redComponent > 0.9 && center.greenComponent < 0.1 && center.blueComponent < 0.1)
  }

  // Pre-merge review: tokens are mostly Display P3, so bitmaps are rendered in Display P3 (not device RGB),
  // which holds sRGB tokens exactly too.
  @Test func bitmapsAreDisplayP3AndKeepAP3TokenExact() throws {
    let cache = SymbolImageCache()
    let token = RGBA(red: 1, green: 0, blue: 0, alpha: 1, space: .displayP3)
    let image = cache.bitmap(key: "p3-fill", size: 4, scale: 2) { rect in token.nsColor().setFill(); rect.fill() }
    let rep = try #require(image.representations.first as? NSBitmapImageRep)
    #expect(rep.colorSpace.cgColorSpace?.name == CGColorSpace.displayP3)
    let pixel = try #require(color(rep, x: 4, y: 4)?.usingColorSpace(.displayP3))
    #expect(pixel.redComponent > 0.99 && pixel.greenComponent < 0.01 && pixel.blueComponent < 0.01)
    let symbol = cache.symbol("square.fill", box: 16, color: token, scale: 2)
    let symbolRep = try #require(symbol.representations.first as? NSBitmapImageRep)
    #expect(symbolRep.colorSpace.cgColorSpace?.name == CGColorSpace.displayP3)
  }

  @Test func unknownSymbolStillReturnsAnImage() {
    let cache = SymbolImageCache()
    #expect(cache.symbol("no.such.symbol.arkt", box: 16, color: red, scale: 2).size.width == 16)
  }

  @Test func bitmapHelperCachesDrawnImages() throws {
    let cache = SymbolImageCache()
    var draws = 0
    let a = cache.bitmap(key: "letter-E", size: 16, scale: 2) { rect in draws += 1; NSColor.red.setFill(); rect.fill() }
    let b = cache.bitmap(key: "letter-E", size: 16, scale: 2) { _ in draws += 1 }
    #expect(a === b)
    #expect(draws == 1)
    let rep = try #require(a.representations.first as? NSBitmapImageRep)
    #expect(rep.pixelsWide == 32)
  }

  /// #153: the letter tile is filled with `ShellTokens.letterTileFill` of its flavor (dark darkens), and the two
  /// flavors are separate cache entries, so a flavor switch never shows the other flavor's fill.
  @Test(arguments: [ThemeFlavor.light, .dark])
  func letterTileIsFilledWithItsFlavorsTileToken(flavor: ThemeFlavor) throws {
    let cache = SymbolImageCache()
    let image = SidebarGlyphs.letter(for: "Example", url: nil, flavor: flavor, size: 16, scale: 2, cache: cache)
    let other = SidebarGlyphs.letter(for: "Example", url: nil, flavor: flavor == .dark ? .light : .dark, size: 16,
                                     scale: 2, cache: cache)
    #expect(image !== other)
    let rep = try #require(image.representations.first as? NSBitmapImageRep)
    // Middle of the left edge: inside the rounded rect, clear of the centered letter.
    let pixel = try #require(color(rep, x: 2, y: 16))
    let alpha = pixel.alphaComponent
    let fill = ShellTokens.letterTileFill.resolve(flavor)
    #expect(abs(alpha - fill.alpha) < 0.02, "\(flavor) alpha \(alpha)")
    let p3 = try #require(pixel.usingColorSpace(.displayP3))
    #expect(max(p3.redComponent, p3.greenComponent, p3.blueComponent) < 0.15, "\(flavor) \(p3)")
  }

  @Test func prewarmRendersEveryShellSymbolForBothFlavors() {
    let cache = SymbolImageCache()
    cache.prewarm(scale: 2)
    let warmed = cache.renderCount
    #expect(warmed > 0)
    _ = SidebarGlyphs.symbol("folder", flavor: .dark, scale: 2, cache: cache)
    _ = SidebarGlyphs.symbol("folder", flavor: .light, scale: 2, cache: cache)
    _ = SidebarGlyphs.close(flavor: .dark, scale: 2, cache: cache)
    _ = SidebarGlyphs.close(flavor: .light, scale: 2, cache: cache)
    #expect(cache.renderCount == warmed, "prewarm covered the sidebar's symbols")
  }
}
