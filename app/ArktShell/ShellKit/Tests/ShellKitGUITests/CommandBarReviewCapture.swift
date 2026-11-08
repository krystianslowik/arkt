import AppKit
import XCTest

/// Opt-in synthetic evidence; the ordinary activation and Settings tests remain the behavioral gates.
@MainActor
func commandBarReviewCaptureDirectory() throws -> URL {
  guard let path = ProcessInfo.processInfo.environment["ARKT_COMMAND_BAR_SHOTS_DIR"], !path.isEmpty else {
    throw XCTSkip("set ARKT_COMMAND_BAR_SHOTS_DIR to export command bar review captures")
  }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

@MainActor
func saveCommandBarReviewCapture(_ window: NSWindow, directory: URL, name: String) throws {
  let view = try XCTUnwrap(window.contentView)
  view.layoutSubtreeIfNeeded()
  window.displayIfNeeded()
  let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: bitmap)
  let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: directory.appendingPathComponent("\(name).png"))
  XCTAssertGreaterThan(bitmap.pixelsWide, 0)
  XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
  var colors = Set<String>()
  for x in 0..<10 {
    for y in 0..<10 {
      if let color = bitmap.colorAt(x: x * (bitmap.pixelsWide - 1) / 9, y: y * (bitmap.pixelsHigh - 1) / 9) {
        colors.insert(color.description)
      }
    }
  }
  XCTAssertGreaterThan(colors.count, 1, "review capture must not be blank")
}
