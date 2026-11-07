import AppKit
import XCTest
@testable import ShellUI

/// The #767 lifts cast down inside the host chain they ship in: a flipped container (as `OnboardingStepView` and
/// `ShellRootView` are) in a window on screen, where AppKit itself joins the layers. `ShadowDirectionTests` covers the
/// same sites offscreen; this checks the window's own layer tree, drawn from its root.
@MainActor
final class ShadowDirectionInWindowTests: XCTestCase {
  private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
  }

  private var window: NSWindow!
  private var container: FlippedContainer!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 520, height: 360), styleMask: [.borderless],
                      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
    content.wantsLayer = true
    content.layer?.backgroundColor = CGColor(gray: 1, alpha: 1)
    window.contentView = content
    container = FlippedContainer(frame: content.bounds)
    container.wantsLayer = true
    content.addSubview(container)
  }

  override func tearDown() async throws { window.close() }

  func testTheSliderKnobAndTheSpacePreviewCastDownInAFlippedHost() throws {
    let slider = ThemeSliderView(label: "Grain", identifier: "test.slider")
    slider.frame = NSRect(x: 40, y: 40, width: 200, height: 24)   // flipped: 40 pt from the top
    slider.setValue(0.3)
    container.addSubview(slider)
    let preview = SpacePreviewView(frame: NSRect(x: 40, y: 120, width: 340, height: 196))
    preview.configure(theme: SpaceThemeCatalog.defaultFamily.light, name: "Work", animated: false)
    container.addSubview(preview)
    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let knob = try XCTUnwrap(layers(under: try XCTUnwrap(slider.layer)).first { $0 is ShadowPathLayer })
    let image = try render()
    try expectCastsDown(knob, in: image, band: 3)
    try expectCastsDown(try XCTUnwrap(preview.layer), in: image, band: 16)
  }

  // MARK: Helpers

  private func layers(under layer: CALayer) -> [CALayer] {
    [layer] + (layer.sublayers ?? []).flatMap { layers(under: $0) }
  }

  private func root() throws -> CALayer {
    var root = try XCTUnwrap(window.contentView?.layer)
    while let up = root.superlayer { root = up }
    return root
  }

  /// The window's layer tree from its unflipped root, at 2x, rows counted from the top.
  private func render() throws -> (pixels: [UInt8], width: Int, height: Int) {
    let root = try root()
    XCTAssertFalse(root.contentsAreFlipped(), "the root measures y upwards")
    let width = Int(root.bounds.width * 2), height = Int(root.bounds.height * 2)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: 2, y: 2)
    root.render(in: context)
    return (pixels, width, height)
  }

  /// Across the element's middle, the `band` points under its bottom edge are darker than those over its top edge.
  private func expectCastsDown(_ element: CALayer, in image: (pixels: [UInt8], width: Int, height: Int),
                               band: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
    let root = try root()
    let rect = element.convert(element.bounds, to: root)   // root points, y up
    let height = root.bounds.height
    func mean(_ rows: ClosedRange<CGFloat>) -> Double {
      var sum = 0.0, count = 0
      for x in stride(from: rect.minX + rect.width * 0.3, through: rect.maxX - rect.width * 0.3, by: 1) {
        for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 0.5) {
          let px = min(max(Int(x * 2), 0), image.width - 1), py = min(max(Int(y * 2), 0), image.height - 1)
          let i = (py * image.width + px) * 4
          sum += (0.2126 * Double(image.pixels[i]) + 0.7152 * Double(image.pixels[i + 1])
                  + 0.0722 * Double(image.pixels[i + 2])) / 255
          count += 1
        }
      }
      return sum / Double(max(count, 1))
    }
    let under = mean((height - rect.minY + 0.5)...(height - rect.minY + band))
    let over = mean((height - rect.maxY - band)...(height - rect.maxY - 0.5))
    XCTAssertLessThan(under, over - 0.003, "the band under \(type(of: element)) is darker than the band over it",
                      file: file, line: line)
  }
}
