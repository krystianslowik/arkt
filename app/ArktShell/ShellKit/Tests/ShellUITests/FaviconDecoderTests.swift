import AppKit
import Testing
@testable import ShellUI

/// A favicon decoder the test releases by hand: each call is recorded and waits until `release()`, so a test can set
/// newer bytes or drop a key while a decode is in flight. No clock anywhere.
actor GatedFaviconDecoder {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var calls: [[Data]] = []
  /// Calls whose task was cancelled by the time they were released.
  private(set) var cancelledCalls = 0

  nonisolated var decoder: FaviconDecoder { FaviconDecoder { await self.decode($0) } }

  func decode(_ batch: [Data]) async -> [CGImage?] {
    calls.append(batch)
    if !isOpen { await withCheckedContinuation { waiters.append($0) } }
    if Task.isCancelled { cancelledCalls += 1 }
    return batch.map { FaviconDecoder.decodeNow($0) }
  }

  /// Lets every waiting and later call through.
  func release() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

enum FaviconFixtures {
  /// A PNG of `pixels` square, its color picked by `index`, with some detail so it does not compress to nothing.
  static func png(_ index: Int, pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor(hue: CGFloat(index % 97) / 97, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    var seed = UInt64(index) &* 6_364_136_223_846_793_005 &+ 1
    for _ in 0..<max(1, pixels / 2) {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let x = CGFloat(seed >> 40 & 0xFF) / 255 * CGFloat(pixels)
      let y = CGFloat(seed >> 24 & 0xFF) / 255 * CGFloat(pixels)
      let r = CGFloat(seed >> 16 & 0x0F) / 15 * CGFloat(pixels) / 4 + 1
      let dot = NSColor(hue: CGFloat(seed & 0xFF) / 255, saturation: 0.8, brightness: 0.6, alpha: 0.8)
      context.setFillColor(dot.cgColor)
      context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }
}

/// #605: favicons decode off the main actor, newest bytes win, dropped keys cancel their decode.
@MainActor
struct FaviconDecoderTests {
  @Test func decodesToABitmapNoLargerThanTheMaximumAndKeepsSmallIcons() throws {
    let large = try #require(FaviconDecoder.decodeNow(FaviconFixtures.png(1, pixels: 256)))
    #expect(large.width == FaviconDecoder.maxPixelSize && large.height == FaviconDecoder.maxPixelSize)
    let small = try #require(FaviconDecoder.decodeNow(FaviconFixtures.png(2, pixels: 4)))
    #expect(small.width == 4 && small.height == 4)
    #expect(FaviconDecoder.image(small).size == NSSize(width: 4, height: 4), "sized like NSImage(data:) of the PNG")
    #expect(FaviconDecoder.decodeNow(Data("not an image".utf8)) == nil)
  }

  @Test func theNewestBytesForAKeyWinAndTheOlderDecodeIsCancelled() async throws {
    let gate = GatedFaviconDecoder()
    let loader = FaviconImageLoader<Int>(decoder: gate.decoder, cache: NSCache())
    var applied: [[Int: NSImage?]] = []
    loader.load([1: FaviconFixtures.png(1, pixels: 8)]) { applied.append($0) }
    loader.load([1: FaviconFixtures.png(2, pixels: 16)]) { applied.append($0) }
    await gate.release()
    await loader.settle()
    #expect(applied.count == 1)
    let image = try #require(applied.first?[1] ?? nil)
    #expect(image.size == NSSize(width: 16, height: 16), "the newer bytes")
    #expect(await gate.cancelledCalls == 1, "the older job was cancelled")
    #expect(loader.pendingCount == 0)
  }

  @Test func aCancelledKeyGetsNothingAndItsJobIsCancelled() async {
    let gate = GatedFaviconDecoder()
    let loader = FaviconImageLoader<Int>(decoder: gate.decoder, cache: NSCache())
    var applied: [[Int: NSImage?]] = []
    loader.load([1: FaviconFixtures.png(1, pixels: 8)]) { applied.append($0) }
    loader.cancel(1)
    await gate.release()
    await loader.settle()
    #expect(applied.isEmpty)
    #expect(await gate.cancelledCalls == 1)
  }

  @Test func aJobKeepsRunningForItsOtherKeysWhenOneIsDropped() async throws {
    let gate = GatedFaviconDecoder()
    let loader = FaviconImageLoader<Int>(decoder: gate.decoder, cache: NSCache())
    var applied: [[Int: NSImage?]] = []
    loader.load([1: FaviconFixtures.png(1, pixels: 8), 2: FaviconFixtures.png(2, pixels: 8)]) { applied.append($0) }
    loader.cancel(1)
    await gate.release()
    await loader.settle()
    #expect(applied.count == 1)
    #expect(applied.first.map { Array($0.keys) } == [2])
    #expect(await gate.cancelledCalls == 0)
  }

  @Test func aBatchDecodesEachDistinctImageOnceInOneJob() async {
    let gate = GatedFaviconDecoder()
    let loader = FaviconImageLoader<Int>(decoder: gate.decoder, cache: NSCache())
    let shared = FaviconFixtures.png(1, pixels: 8)
    var applied: [[Int: NSImage?]] = []
    loader.load([1: shared, 2: shared, 3: FaviconFixtures.png(3, pixels: 8), 4: Data("junk".utf8)]) {
      applied.append($0)
    }
    await gate.release()
    await loader.settle()
    let calls = await gate.calls
    #expect(calls.count == 1)
    #expect(calls.first?.count == 3, "shared bytes are decoded once")
    #expect(applied.count == 1, "one apply for the whole batch")
    let images = applied.first ?? [:]
    #expect(images.count == 4)
    #expect(images[1]! != nil && images[1]! === images[2]!, "one image for the shared bytes")
    #expect(images[4]! == nil, "bytes that are not an image")
  }

  @Test func decodedBytesAreShownAtOnceWithoutAnotherDecode() async {
    let gate = GatedFaviconDecoder()
    await gate.release()
    let loader = FaviconImageLoader<Int>(decoder: gate.decoder, cache: NSCache())
    let data = FaviconFixtures.png(1, pixels: 8)
    var first: NSImage?
    loader.load([1: data]) { first = $0[1] ?? nil }
    await loader.settle()
    var again: NSImage?
    loader.load([2: data]) { again = $0[2] ?? nil }
    #expect(again != nil, "applied before load returns")
    #expect(again === first)
    #expect(await gate.calls.count == 1)
  }

  /// The guarantee behind #605, without a clock (#699): the images the loader hands out, through the real off-main
  /// decoder, are realized bitmaps. An image read from its file (`NSImage(data:)`, `CGImageSourceCreateImageAtIndex`)
  /// stays tied to its image source and reports the file's type; ImageIO decodes it at first draw, on the main thread.
  /// A realized bitmap has no source type.
  ///
  /// Not covered here: dropping `kCGImageSourceShouldCacheImmediately` from `decodeNow`. The thumbnail is a realized
  /// bitmap without it on the macOS this was written on, so neither this check nor the `ARKT_FAVICON_GATE` timing run
  /// fails when it is removed; the option stays as a request ImageIO is free to need on a later release.
  @Test(arguments: [64, 256])
  func theLoaderHandsOutBitmapsThatDrawWithoutDecoding(pixels: Int) async throws {
    let data = FaviconFixtures.png(pixels, pixels: pixels)
    // Controls: both lazy paths stay tied to their source, so the check below tells them apart.
    let lazy = try #require(NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(lazy.utType != nil, "control: NSImage(data:) is decoded at first draw")
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let fromSource = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(fromSource.utType != nil, "control: CGImageSourceCreateImageAtIndex is decoded at first draw")
    let loader = FaviconImageLoader<Int>(decoder: .offMain, cache: NSCache())
    var applied: NSImage?
    loader.load([1: data]) { applied = $0[1] ?? nil }
    await loader.settle()
    let image = try #require(applied)
    let bitmap = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(bitmap.utType == nil, "a realized bitmap, not one decoded at first draw")
    #expect(max(bitmap.width, bitmap.height) == min(pixels, FaviconDecoder.maxPixelSize))
  }

  /// The measurement behind #605: main-thread CPU to draw a sidebar's worth of favicons for the first time, as
  /// `NSImage(data:)` (decoded lazily, inside the draw) and as decoded bitmaps. Always printed; the ratio is asserted
  /// only with `ARKT_FAVICON_GATE=1`, since at 64 px both sides are a few milliseconds and a busy runner erases the
  /// margin (#699). The required check is `theLoaderHandsOutBitmapsThatDrawWithoutDecoding`.
  @Test(arguments: [64, 256])
  func drawingDecodedFaviconsSkipsTheDecode(pixels: Int) throws {
    let count = 30                                   // rows a full-height sidebar shows at once
    let bytes = (0..<count).map { FaviconFixtures.png($0, pixels: pixels) }
    func firstDrawCPU(_ images: [NSImage]) -> Double {
      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
      let context = NSGraphicsContext(bitmapImageRep: rep)!
      let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      for image in images { image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16)) }
      NSGraphicsContext.restoreGraphicsState()
      return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }
    // Warm up the drawing path on images outside the measured set, so neither side pays its first-use cost.
    let warmUp = try #require(FaviconDecoder.decodeNow(FaviconFixtures.png(1001, pixels: pixels)))
    _ = firstDrawCPU([try #require(NSImage(data: FaviconFixtures.png(1000, pixels: pixels))),
                      FaviconDecoder.image(warmUp)])
    let lazy = firstDrawCPU(bytes.compactMap(NSImage.init(data:)))
    let decoded = firstDrawCPU(try bytes.map { FaviconDecoder.image(try #require(FaviconDecoder.decodeNow($0))) })
    print(String(format: "favicondecode.firstdraw pixels=%d count=%d lazyMs=%.2f decodedMs=%.2f",
                 pixels, count, lazy * 1000, decoded * 1000))
    if ProcessInfo.processInfo.environment["ARKT_FAVICON_GATE"] == "1" {
      #expect(decoded * 2 < lazy, "decoded favicons draw without decoding")
    }
  }
}
