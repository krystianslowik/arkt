import AppKit
import Testing
@testable import ShellUI

/// The stack a Favorite split draws on its tile (#788, design/favorite-split-tile, direction B): which pane is in
/// front, where each layer sits, and the cut-out ring.
@MainActor
struct FavoriteSplitStackTests {
  private static let a = NodeID(), b = NodeID(), c = NodeID(), d = NodeID()

  // MARK: Order

  @Test func theFirstPaneIsInFrontWhenNoPaneIsFocused() {
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b], focused: nil) == [Self.a, Self.b])
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b, Self.c], focused: NodeID()) == [Self.a, Self.b, Self.c])
  }

  /// The focused pane comes to the front; the second is the next pane after it in order, the third the one after.
  @Test func theFocusedPaneIsInFrontAndTheOthersFollowIt() {
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b], focused: Self.b) == [Self.b, Self.a])
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b, Self.c], focused: Self.b) == [Self.b, Self.c, Self.a])
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b, Self.c, Self.d], focused: Self.d)
            == [Self.d, Self.a, Self.b])
  }

  @Test func aFourthPaneIsNotDrawn() {
    #expect(FavoriteSplitStack.order(panes: [Self.a, Self.b, Self.c, Self.d], focused: nil)
            == [Self.a, Self.b, Self.c])
    #expect(FavoriteSplitStack.order(panes: [], focused: nil) == [])
  }

  // MARK: Geometry

  /// Front 20 pt at (9, 7), second 16 pt at (25, 21), third 14 pt at (32, 28), from the top leading corner of the
  /// 52 x 47 box.
  @Test func layersSitAtTheDesignOffsets() {
    #expect(FavoriteSplitStack.frames(layerCount: 3) == [
      CGRect(x: 9, y: 7, width: 20, height: 20),
      CGRect(x: 25, y: 21, width: 16, height: 16),
      CGRect(x: 32, y: 28, width: 14, height: 14),
    ])
    #expect(FavoriteSplitStack.frames(layerCount: 2).count == 2)
    #expect(FavoriteSplitStack.frames(layerCount: 5).count == 3)
    #expect(FavoriteSplitStack.boxSize == CGSize(width: 52, height: 47))
    #expect(FavoriteSplitStack.frames(layerCount: 3).allSatisfy { $0.maxY <= 47 && $0.maxX <= 52 })
  }

  /// On a wider tile the box is centered and its origin rounded to whole points, as a plain Favorite's favicon is.
  @Test func theBoxIsCenteredOnWholePoints() {
    #expect(FavoriteSplitStack.boxOrigin(in: CGSize(width: 52, height: 47)) == .zero)
    #expect(FavoriteSplitStack.boxOrigin(in: CGSize(width: 52.7, height: 47)) == .zero)
    #expect(FavoriteSplitStack.boxOrigin(in: CGSize(width: 61, height: 47)) == CGPoint(x: 5, y: 0))
    #expect(FavoriteSplitStack.boxOrigin(in: CGSize(width: 185, height: 47)) == CGPoint(x: 67, y: 0))
  }

  // MARK: Rendering

  private static func solid(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
      color.setFill()
      rect.fill()
      return true
    }
  }

  /// Reads the pixel at a point of the box (top-left origin) from the rendered stack.
  private static func pixel(_ image: CGImage, at point: CGPoint, scale: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8,
                                                                                     a: UInt8) {
    let rep = NSBitmapImageRep(cgImage: image)
    let color = rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
    func byte(_ value: CGFloat?) -> UInt8 { UInt8(((value ?? 0) * 255).rounded()) }
    return (byte(color?.redComponent), byte(color?.greenComponent), byte(color?.blueComponent),
            byte(color?.alphaComponent))
  }

  /// The ring is a cut-out: in the 2 pt band around the front favicon the second layer is cleared, so the tile's fill
  /// shows there in every state and on every theme.
  @Test func theRingAroundTheFrontLayerIsCleared() throws {
    let images = [Self.solid(.systemRed), Self.solid(.systemBlue), Self.solid(.systemGreen)]
    let image = try #require(FavoriteSplitStack.render(images, scale: 2))
    // Inside the front layer: red.
    #expect(Self.pixel(image, at: CGPoint(x: 19, y: 17), scale: 2).a == 255)
    #expect(Self.pixel(image, at: CGPoint(x: 19, y: 17), scale: 2).r > 200)
    // The second layer spans x 25...41, y 21...37. The front ends at x 29; its ring reaches x 31, and its straight
    // right edge runs down to y 22, where the corner starts.
    let ring = Self.pixel(image, at: CGPoint(x: 30, y: 21.5), scale: 2)
    #expect(ring.a == 0, "the ring band is cleared, not painted: \(ring)")
    let second = Self.pixel(image, at: CGPoint(x: 36, y: 23), scale: 2)
    #expect(second.a == 255 && second.b > 200, "the second layer outside the ring: \(second)")
    // The second carries a ring too when a third is behind it: the third is cleared next to the second's edge.
    let secondRing = Self.pixel(image, at: CGPoint(x: 42, y: 30), scale: 2)
    #expect(secondRing.a == 0, "the ring around the second layer: \(secondRing)")
    let third = Self.pixel(image, at: CGPoint(x: 44, y: 40), scale: 2)
    #expect(third.a == 255 && third.g > 100, "the third layer outside the rings: \(third)")
  }

  /// A translucent layer (the letter tile) in front hides what is behind it: the layer below is cleared under its
  /// shape too.
  @Test func nothingShowsThroughATranslucentFrontLayer() throws {
    let clear = Self.solid(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.1))
    let images = [clear, Self.solid(.systemBlue)]
    let image = try #require(FavoriteSplitStack.render(images, scale: 2))
    // (27, 25) lies inside both the front (9...29, 7...27) and the second (25...41, 21...37).
    let overlap = Self.pixel(image, at: CGPoint(x: 27, y: 25), scale: 2)
    #expect(overlap.b < 50, "no blue under the translucent front layer: \(overlap)")
  }
}
