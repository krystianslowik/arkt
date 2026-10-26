import CoreGraphics
import EngineAPI
import Foundation
import ImageIO

// MARK: - Rule 18 (#370, #352)

extension EngineContract {
  /// The last thumbnail a rule 18 check made, with the time the call took: the in-app runner prints it as the engine
  /// smoke's size and timing (#370). Sizes only, never the page.
  public private(set) static var lastPageImageMeasurement: (image: PageImage, duration: Duration)?

  /// A loaded, shown tab gives a thumbnail within both caps that decodes to the size it reports, and a full frame at
  /// least as large.
  public static func pageImageFitsTheCaps(_ h: EngineHarness) async throws {
    let showPage = try driver(h.showPage, "showPage")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Thumbnail"))
    try await h.settle(engine, id)
    try await showPage(engine, id)
    let request = PageImageRequest.thumbnail
    let started = ContinuousClock.now
    let image = try requireValue(await engine.pageImage(of: id, request), "thumbnail of a loaded, shown tab")
    lastPageImageMeasurement = (image, started.duration(to: .now))
    let caps = try requireValue(request.maxPixelSize, "thumbnail pixel cap")
    try require(image.pixelWidth > 0 && image.pixelHeight > 0, "empty thumbnail: \(image)")
    try require(image.pixelWidth <= caps.width && image.pixelHeight <= caps.height,
                "thumbnail \(image.pixelWidth)x\(image.pixelHeight) exceeds \(caps.width)x\(caps.height)")
    try require(!image.data.isEmpty && image.data.count <= (request.maxBytes ?? .max),
                "thumbnail of \(image.data.count) bytes exceeds \(request.maxBytes ?? .max)")
    let decoded = try requireValue(decode(image.data), "a decodable thumbnail")
    try require(decoded.width == image.pixelWidth && decoded.height == image.pixelHeight,
                "thumbnail decodes to \(decoded.width)x\(decoded.height), reports \(image.pixelWidth)x\(image.pixelHeight)")
    try require(image.scale > 0, "thumbnail scale \(image.scale)")

    let full = try requireValue(await engine.pageImage(of: id, .fullFrame), "full frame of a loaded, shown tab")
    try require(full.pixelWidth >= image.pixelWidth && full.pixelHeight >= image.pixelHeight,
                "full frame \(full.pixelWidth)x\(full.pixelHeight) is smaller than the thumbnail")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  /// A closed or unknown tab gives nil.
  public static func pageImageOfAClosedTabIsNil(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    try require(await engine.pageImage(of: TabID(), .thumbnail) == nil, "an unknown tab must give nil")
    let id = engine.createTab(url: try h.pageURL("Closed"))
    try await h.settle(engine, id)
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try await waitUntil(timeout: .seconds(5)) { engine.snapshot(of: id) == nil }
    try require(await engine.pageImage(of: id, .thumbnail) == nil, "a closed tab must give nil")
  }

  private static func decode(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
