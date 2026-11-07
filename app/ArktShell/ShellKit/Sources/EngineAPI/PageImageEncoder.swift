import CoreGraphics
import Foundation
import ImageIO

/// Encodes a page frame within a `PageImageRequest`'s caps (#370, #352). Every engine goes through it, so the caps
/// hold the same way for all of them. Runs on the concurrent pool: the scale and the encode never touch the main
/// thread.
public enum PageImageEncoder {
  /// JPEG qualities tried in order until the byte cap holds.
  static let qualities: [Double] = [0.8, 0.65, 0.5, 0.35, 0.2]
  /// Halvings of the pixel size tried when no quality meets the byte cap.
  static let maxHalvings = 3

  /// `frame` scaled down to fit the pixel cap and encoded: PNG without a byte cap, else the best JPEG under it. `scale`
  /// is the frame's pixels per point; the result's is adjusted for the scaling. Nil when no encoding meets the caps.
  @concurrent
  public static func encode(_ frame: CGImage, scale: Double, _ request: PageImageRequest) async -> PageImage? {
    encodeNow(frame, scale: scale, request)
  }

  /// An already encoded frame (the engine facade's PNG): kept as it is when it fits both caps, else decoded and
  /// encoded again by `encode`. Nil for data that is not an image.
  @concurrent
  public static func fit(_ data: Data, scale: Double, _ request: PageImageRequest) async -> PageImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
          let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let fitsPixels = request.maxPixelSize.map { frame.width <= $0.width && frame.height <= $0.height } ?? true
    let fitsBytes = request.maxBytes.map { data.count <= $0 } ?? true
    if fitsPixels, fitsBytes, let format = format(of: source) {
      return PageImage(data: data, pixelWidth: frame.width, pixelHeight: frame.height, scale: scale, format: format)
    }
    return encodeNow(frame, scale: scale, request)
  }

  // MARK: - Steps

  private static func encodeNow(_ frame: CGImage, scale: Double, _ request: PageImageRequest) -> PageImage? {
    guard frame.width > 0, frame.height > 0 else { return nil }
    var size = fitted(PixelSize(width: frame.width, height: frame.height), within: request.maxPixelSize)
    guard let maxBytes = request.maxBytes else {
      guard let image = resized(frame, to: size), let data = write(image, type: "public.png", quality: nil) else {
        return nil
      }
      return made(data, size, frame: frame, scale: scale, format: .png)
    }
    for _ in 0...maxHalvings {
      guard let image = resized(frame, to: size) else { return nil }
      for quality in qualities {
        if let data = write(image, type: "public.jpeg", quality: quality), data.count <= maxBytes {
          return made(data, size, frame: frame, scale: scale, format: .jpeg)
        }
      }
      guard size.width > 1, size.height > 1 else { break }
      size = PixelSize(width: max(1, size.width / 2), height: max(1, size.height / 2))
    }
    return nil
  }

  /// The largest size with the frame's aspect that fits `cap`, never larger than the frame.
  static func fitted(_ size: PixelSize, within cap: PixelSize?) -> PixelSize {
    guard let cap, cap.width > 0, cap.height > 0 else { return size }
    let factor = min(1, Double(cap.width) / Double(size.width), Double(cap.height) / Double(size.height))
    guard factor < 1 else { return size }
    return PixelSize(width: max(1, Int((Double(size.width) * factor).rounded(.down))),
                     height: max(1, Int((Double(size.height) * factor).rounded(.down))))
  }

  private static func made(_ data: Data, _ size: PixelSize, frame: CGImage, scale: Double,
                           format: PageImage.Format) -> PageImage {
    PageImage(data: data, pixelWidth: size.width, pixelHeight: size.height,
              scale: scale * Double(size.width) / Double(frame.width), format: format)
  }

  private static func resized(_ frame: CGImage, to size: PixelSize) -> CGImage? {
    if size.width == frame.width, size.height == frame.height { return frame }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(frame, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    return context.makeImage()
  }

  private static func write(_ image: CGImage, type: String, quality: Double?) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
    let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, options)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  private static func format(of source: CGImageSource) -> PageImage.Format? {
    switch CGImageSourceGetType(source).map({ $0 as String }) {
    case "public.png": .png
    case "public.jpeg": .jpeg
    default: nil
    }
  }
}
