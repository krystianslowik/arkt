import Foundation

/// A size in device pixels.
public struct PixelSize: Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// What a page image may be: a pixel cap (the image is scaled down to fit it, never up) and a byte cap. Nil means
/// no cap.
public struct PageImageRequest: Hashable, Sendable {
  public var maxPixelSize: PixelSize?
  public var maxBytes: Int?

  public init(maxPixelSize: PixelSize?, maxBytes: Int?) {
    self.maxPixelSize = maxPixelSize
    self.maxBytes = maxBytes
  }

  /// The command bar's preview (#370): 600 x 360 px, 80 KB, for a 276 x 116 pt slot at 2x with room to crop.
  public static let thumbnail = PageImageRequest(maxPixelSize: PixelSize(width: 600, height: 360), maxBytes: 80_000)
  /// The full frame at the backing scale, lossless (#352, Little Arkt's Open in flight).
  public static let fullFrame = PageImageRequest(maxPixelSize: nil, maxBytes: nil)
}

/// An encoded image of a page's frame (#370, #352). Encoded bytes, not an `NSImage` or `CGImage`, so it stays a
/// `Sendable` value any layer can hold; decode it off the main thread (`CGImageSource`).
public struct PageImage: Hashable, Sendable {
  public enum Format: Hashable, Sendable {
    case png
    case jpeg
  }

  public var data: Data
  public var pixelWidth: Int
  public var pixelHeight: Int
  /// Pixels per point of the page: 2 for a full frame on a Retina screen, less for a thumbnail. A layer that shows
  /// the image at the page's size uses it as `contentsScale`.
  public var scale: Double
  public var format: Format

  public init(data: Data, pixelWidth: Int, pixelHeight: Int, scale: Double, format: Format) {
    self.data = data
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.scale = scale
    self.format = format
  }
}

extension PageImage: CustomStringConvertible {
  /// Sizes only, so logs never carry page content.
  public var description: String { "\(format) \(pixelWidth)x\(pixelHeight) px @\(scale), \(data.count) bytes" }
}
