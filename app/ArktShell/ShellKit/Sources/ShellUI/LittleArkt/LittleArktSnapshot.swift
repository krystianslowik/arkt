import CoreGraphics
import EngineAPI
import ImageIO

/// The page's frame for the Open in flight (#352): a decoded image and its pixels per point, so its layer draws it at
/// the page's size (`contentsScale`), not stretched.
public struct LittleArktSnapshot: Sendable {
  public let image: CGImage
  public let scale: Double

  public init(image: CGImage, scale: Double) {
    self.image = image
    self.scale = max(scale, 0.01)
  }

  /// The image's size in points.
  public var pointSize: CGSize {
    CGSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
  }

  /// Decodes `page` off the main actor, fully (not lazily on the first draw); nil for bytes that are not an image.
  @concurrent
  public static func decode(_ page: PageImage) async -> LittleArktSnapshot? {
    guard let source = CGImageSourceCreateWithData(page.data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary) else { return nil }
    return LittleArktSnapshot(image: image, scale: page.scale)
  }
}
