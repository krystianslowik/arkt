import CoreGraphics
import Foundation
import ImageIO
import Testing
import EngineAPI

/// The pixel and byte caps of a page image (#370): the encoder never upscales, keeps the aspect ratio, fits the
/// pixel cap, steps the JPEG quality down (and then the size) until the byte cap holds, and reports the pixel size
/// and the scale it wrote.
struct PageImageEncoderTests {
  @Test func thumbnailFitsThePixelCapAndKeepsTheAspect() async throws {
    let frame = try #require(TestImages.gradient(width: 2400, height: 1600))
    let image = try #require(await PageImageEncoder.encode(frame, scale: 2, .thumbnail))
    #expect(image.pixelWidth == 540)
    #expect(image.pixelHeight == 360)
    let decoded = try #require(TestImages.decode(image.data))
    #expect(decoded.width == image.pixelWidth && decoded.height == image.pixelHeight)
    // 540 px for a 1200 pt wide page.
    #expect(abs(image.scale - 0.45) < 0.0001)
  }

  @Test func wideFrameIsCappedByWidth() async throws {
    let frame = try #require(TestImages.gradient(width: 3000, height: 600))
    let image = try #require(await PageImageEncoder.encode(frame, scale: 2, .thumbnail))
    #expect(image.pixelWidth == 600)
    #expect(image.pixelHeight == 120)
  }

  @Test func smallFrameIsNeverUpscaled() async throws {
    let frame = try #require(TestImages.gradient(width: 300, height: 200))
    let image = try #require(await PageImageEncoder.encode(frame, scale: 1, .thumbnail))
    #expect(image.pixelWidth == 300)
    #expect(image.pixelHeight == 200)
    #expect(image.scale == 1)
  }

  @Test func noisyFrameStaysUnderTheByteCap() async throws {
    let frame = try #require(TestImages.noise(width: 600, height: 360))
    let request = PageImageRequest(maxPixelSize: PixelSize(width: 600, height: 360), maxBytes: 80_000)
    let image = try #require(await PageImageEncoder.encode(frame, scale: 2, request))
    #expect(image.data.count <= 80_000)
    #expect(image.data.count > 0)
    #expect(image.format == .jpeg)
    #expect(image.pixelWidth <= 600 && image.pixelHeight <= 360)
  }

  /// A cap that no quality meets at full size halves the size until it holds.
  @Test func tightByteCapShrinksThePixels() async throws {
    let frame = try #require(TestImages.noise(width: 600, height: 360))
    let request = PageImageRequest(maxPixelSize: PixelSize(width: 600, height: 360), maxBytes: 6_000)
    let image = try #require(await PageImageEncoder.encode(frame, scale: 2, request))
    #expect(image.data.count <= 6_000)
    #expect(image.pixelWidth < 600)
    let decoded = try #require(TestImages.decode(image.data))
    #expect(decoded.width == image.pixelWidth && decoded.height == image.pixelHeight)
  }

  @Test func impossibleByteCapGivesNil() async throws {
    let frame = try #require(TestImages.noise(width: 600, height: 360))
    let request = PageImageRequest(maxPixelSize: PixelSize(width: 600, height: 360), maxBytes: 10)
    #expect(await PageImageEncoder.encode(frame, scale: 2, request) == nil)
  }

  /// The full frame (#352) keeps every pixel and is lossless.
  @Test func fullFrameKeepsTheSizeAsPNG() async throws {
    let frame = try #require(TestImages.gradient(width: 1000, height: 700))
    let image = try #require(await PageImageEncoder.encode(frame, scale: 2, .fullFrame))
    #expect(image.pixelWidth == 1000 && image.pixelHeight == 700)
    #expect(image.format == .png)
    #expect(image.scale == 2)
  }

  /// The facade's PNG passes through untouched when it already fits both caps.
  @Test func fittingPNGPassesThrough() async throws {
    let frame = try #require(TestImages.gradient(width: 400, height: 240))
    let png = try #require(TestImages.png(frame))
    let image = try #require(await PageImageEncoder.fit(png, scale: 1, .thumbnail))
    #expect(image.data == png)
    #expect(image.format == .png)
    #expect(image.pixelWidth == 400 && image.pixelHeight == 240)
  }

  @Test func oversizedPNGIsReencodedWithinTheCaps() async throws {
    let frame = try #require(TestImages.noise(width: 1200, height: 720))
    let png = try #require(TestImages.png(frame))
    let image = try #require(await PageImageEncoder.fit(png, scale: 2, .thumbnail))
    #expect(image.pixelWidth == 600 && image.pixelHeight == 360)
    #expect(image.data.count <= 80_000)
  }

  @Test func unreadableDataGivesNil() async {
    #expect(await PageImageEncoder.fit(Data("not an image".utf8), scale: 1, .thumbnail) == nil)
  }

  @Test func requestPresetsMatchTheIssue() {
    #expect(PageImageRequest.thumbnail.maxPixelSize == PixelSize(width: 600, height: 360))
    #expect(PageImageRequest.thumbnail.maxBytes == 80_000)
    #expect(PageImageRequest.fullFrame.maxPixelSize == nil)
    #expect(PageImageRequest.fullFrame.maxBytes == nil)
  }
}

/// Synthetic frames for the image tests: no page content.
enum TestImages {
  static func context(width: Int, height: Int) -> CGContext? {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
  }

  static func gradient(width: Int, height: Int) -> CGImage? {
    guard let context = context(width: width, height: height) else { return nil }
    for x in stride(from: 0, to: width, by: 8) {
      context.setFillColor(red: Double(x) / Double(width), green: 0.5, blue: 0.8, alpha: 1)
      context.fill(CGRect(x: x, y: 0, width: 8, height: height))
    }
    return context.makeImage()
  }

  /// Seeded noise, which JPEG compresses badly: the byte cap has to work for it.
  static func noise(width: Int, height: Int) -> CGImage? {
    guard let context = context(width: width, height: height), let data = context.data else { return nil }
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
    for row in 0..<height {
      for column in 0..<width {
        let offset = row * context.bytesPerRow + column * 4
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        bytes[offset] = UInt8(truncatingIfNeeded: state >> 24)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: state >> 32)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: state >> 40)
        bytes[offset + 3] = 255
      }
    }
    return context.makeImage()
  }

  static func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  static func decode(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
