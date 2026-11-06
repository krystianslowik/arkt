import AppKit
import ImageIO
import Testing
@testable import FakeEngineKit

/// #675: FakeEngine hands the shell favicons the way the engine contract promises them, PNG or ICO. Other formats
/// (SVG, which ImageIO cannot decode, JPEG, GIF) are drawn to a PNG; bytes that are no image are dropped. No page
/// loads, so the required lane stays deterministic.
@MainActor
struct FakeEngineFaviconTests {
  init() { _ = NSApplication.shared }

  static let svg = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="#2a7"/></svg>
    """.utf8)

  /// A 4 px image in `type` (a UTType identifier), written with ImageIO.
  static func image(_ type: String, pixels: Int = 4) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  private func imageIOType(_ data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
      return nil
    }
    return CGImageSourceGetType(source) as String?
  }

  @Test func pngAndIcoPassThroughUnchanged() {
    let png = Self.image("public.png")
    let ico = Self.image("com.microsoft.ico", pixels: 16)
    #expect(imageIOType(ico) == "com.microsoft.ico", "control: the fixture is an ICO")
    #expect(FakeEngine.contractFavicon(png) == png)
    #expect(FakeEngine.contractFavicon(ico) == ico)
  }

  @Test func anSVGFaviconIsDrawnToAPNGImageIOCanDecode() throws {
    #expect(imageIOType(Self.svg) == nil, "control: ImageIO cannot decode SVG")
    let png = try #require(FakeEngine.contractFavicon(Self.svg))
    #expect(imageIOType(png) == "public.png")
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(bitmap.width == FakeEngine.rasterFaviconPixels && bitmap.height == FakeEngine.rasterFaviconPixels)
  }

  @Test func otherImageFormatsBecomePNG() throws {
    for type in ["public.jpeg", "com.compuserve.gif", "public.tiff"] {
      let png = try #require(FakeEngine.contractFavicon(Self.image(type)), "\(type)")
      #expect(imageIOType(png) == "public.png", "\(type)")
    }
  }

  @Test func bytesThatAreNoImageAreDropped() {
    #expect(FakeEngine.contractFavicon(Data("nope".utf8)) == nil)
    #expect(FakeEngine.contractFavicon(Data()) == nil)
    #expect(FakeEngine.contractFavicon(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"".utf8)) == nil, "broken SVG")
  }
}
