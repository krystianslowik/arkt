import AppKit

/// The Arkt mark as the first run shows it: taken from the approved artwork (`01-mustard-on-white.png`, a copy in
/// this module's resources), never redrawn. The plate is removed with the website's rule: a pixel is part of the
/// mark when its alpha is above 200 and its saturation above 70 (0...255). Cached for the session.
@MainActor
public enum BrandMarkArtwork {
  public struct Sample: Equatable, Sendable {
    /// Centred on the mark, scaled to a height of 1 (x grows right, y grows down).
    public var x: Float
    public var y: Float
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
  }

  private static var cachedImage: CGImage??

  /// The mark's pixels on a transparent background, cropped to the mark. Nil when the resource is missing.
  public static var image: CGImage? {
    if let cachedImage { return cachedImage }
    let made = makeImage()
    cachedImage = .some(made)
    return made
  }

  /// Width over height of the cropped mark.
  public static var aspectRatio: CGFloat {
    guard let image else { return 1 }
    return CGFloat(image.width) / CGFloat(image.height)
  }

  static func source() -> CGImage? {
    guard let url = Bundle.module.url(forResource: "01-mustard-on-white", withExtension: "png"),
          let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { return nil }
    return rep.cgImage
  }

  /// Whether a pixel belongs to the mark (the website's rule).
  public nonisolated static func isMark(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> Bool {
    guard alpha > 200 else { return false }
    let high = max(red, green, blue), low = min(red, green, blue)
    guard high > 0 else { return false }
    let saturation = Int(high - low) * 255 / Int(high)
    return saturation > 70
  }

  /// RGBA8 pixels of `image` at `width` x proportional height.
  static func pixels(of image: CGImage, width: Int) -> (data: [UInt8], width: Int, height: Int)? {
    let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = data.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? (data, width, height) : nil
  }

  private static func makeImage() -> CGImage? {
    guard let source = source(), let (data, width, height) = pixels(of: source, width: source.width) else {
      return nil
    }
    var out = [UInt8](repeating: 0, count: data.count)
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
      for x in 0..<width {
        let i = (y * width + x) * 4
        guard isMark(red: data[i], green: data[i + 1], blue: data[i + 2], alpha: data[i + 3]) else { continue }
        out[i] = data[i]; out[i + 1] = data[i + 1]; out[i + 2] = data[i + 2]; out[i + 3] = data[i + 3]
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let cropWidth = maxX - minX + 1, cropHeight = maxY - minY + 1
    var cropped = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)
    for y in 0..<cropHeight {
      let from = ((minY + y) * width + minX) * 4
      cropped.replaceSubrange((y * cropWidth * 4)..<((y + 1) * cropWidth * 4), with: out[from..<(from + cropWidth * 4)])
    }
    let provider = CGDataProvider(data: Data(cropped) as CFData)
    return provider.flatMap {
      CGImage(width: cropWidth, height: cropHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cropWidth * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0,
              decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
  }

  /// One sample per mark pixel of the artwork at `width` px (the particle layer uses 140), centred and scaled to a
  /// height of 1.
  public static func samples(width: Int = 140) -> [Sample] {
    guard let source = source(), let (data, w, h) = pixels(of: source, width: width) else { return [] }
    var kept: [(Int, Int, Int)] = []
    for y in 0..<h {
      for x in 0..<w {
        let i = (y * w + x) * 4
        if isMark(red: data[i], green: data[i + 1], blue: data[i + 2], alpha: data[i + 3]) { kept.append((x, y, i)) }
      }
    }
    guard let minY = kept.map(\.1).min(), let maxY = kept.map(\.1).max(),
          let minX = kept.map(\.0).min(), let maxX = kept.map(\.0).max() else { return [] }
    // The bitmap's first row is the image's top row, so y already grows down.
    let height = Float(maxY - minY + 1)
    let cx = Float(minX + maxX) / 2, cy = Float(minY + maxY) / 2
    return kept.map { x, y, i in
      Sample(x: (Float(x) - cx) / height, y: (Float(y) - cy) / height, red: data[i], green: data[i + 1],
             blue: data[i + 2])
    }
  }
}
