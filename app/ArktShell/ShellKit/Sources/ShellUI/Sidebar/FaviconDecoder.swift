import AppKit
import ImageIO

/// Turns stored favicon bytes into bitmaps that draw without decoding (#605). `NSImage(data:)` only parses the
/// header: the pixels are decoded at first draw, on the main thread, inside whatever frame first shows the row (the
/// first swipe into a Space of imported tabs draws every visible favicon at once). The decode runs off the main
/// actor instead, and the main actor only wraps the finished bitmap.
///
/// A value type holding the decode function, so tests can hand the sidebar one they hold and release by hand.
public struct FaviconDecoder: Sendable {
  /// Decodes a batch, one result per input in order; nil for bytes that are not an image. Runs off the main actor.
  public var decode: @Sendable ([Data]) async -> [CGImage?]

  public init(decode: @escaping @Sendable ([Data]) async -> [CGImage?]) { self.decode = decode }

  /// Decodes on the concurrent pool (`decodeOffMain`).
  public static let offMain = FaviconDecoder { await decodeOffMain($0) }

  /// The largest side kept, in pixels: the 20 pt Favorites tile at 3x. Larger icons (imported touch icons are often
  /// 180 or 256 px) are scaled down, which also bounds memory: 300 decoded 256 px icons would hold about 78 MB.
  public static let maxPixelSize = 64

  /// Decodes `batch` in order, stopping early (nil for the rest) once the calling task is cancelled.
  @concurrent
  static func decodeOffMain(_ batch: [Data]) async -> [CGImage?] {
    let state = ShellSignposts.signposter.beginInterval("favicon.decode", "\(batch.count) images")
    defer { ShellSignposts.signposter.endInterval("favicon.decode", state) }
    var images: [CGImage?] = []
    images.reserveCapacity(batch.count)
    for data in batch {
      images.append(Task.isCancelled ? nil : decodeNow(data))
    }
    return images
  }

  /// A fully decoded bitmap of `data`, at most `maxPixelSize` on its longer side (smaller images keep their size).
  /// A thumbnail is always a realized bitmap, unlike `CGImageSourceCreateImageAtIndex`, whose result decodes lazily
  /// at first draw. Any thread.
  public nonisolated static func decodeNow(_ data: Data, maxPixelSize: Int = maxPixelSize) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) > 0
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// Decoded favicons by their bytes, shared by every sidebar and the Archive: an icon decoded for one window shows at
  /// once in another. Bounded by count; NSCache also drops entries under memory pressure.
  @MainActor
  static let sharedImages: NSCache<NSData, NSImage> = {
    let cache = NSCache<NSData, NSImage>()
    cache.countLimit = 512
    return cache
  }()

  /// The image views take: sized in points as the bitmap's pixels, like `NSImage(data:)` of a 72 dpi PNG. Main actor
  /// only, never off it.
  @MainActor
  public static func image(_ bitmap: CGImage) -> NSImage {
    NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
  }
}
