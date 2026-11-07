import AppKit
import Testing
@testable import ShellUI

/// The four lifts drawn on flipped views (#767) cast their shadow down on screen, not up. A literal offset cannot
/// show that: the sign that means "down" depends on the layer's flip. Each control's layer tree is hosted under a
/// plain unflipped layer (the window's own orientation) and drawn with Core Animation; the shadow must darken the band
/// just below the element more than the band just above it, in light and dark.
@MainActor
struct ShadowDirectionTests {
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theThemeSliderKnobCastsDown(appearance: NSAppearance.Name) throws {
    let slider = ThemeSliderView(label: "Grain", identifier: "test.slider")
    slider.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    slider.appearance = NSAppearance(named: appearance)
    slider.setValue(0.3)
    let host = Host(slider, dark: appearance == .darkAqua)
    slider.layout()
    let knob = try #require(host.layers().first { $0 is ShadowPathLayer }, "the knob")
    try host.expectCastsDown(knob, band: 3)
  }

  @Test(arguments: [ThemeFlavor.light, .dark])
  func theFirstRunAppearanceThumbCastsDown(flavor: ThemeFlavor) throws {
    let segments = AppearanceSegmentView(appearance: OnboardingAppearance(flavor: flavor, reduceMotion: true))
    segments.frame = NSRect(origin: .zero, size: segments.intrinsicContentSize)
    let host = Host(segments, dark: flavor == .dark)
    segments.layout()
    let thumb = try #require(host.layers().first { $0 is ShadowPathLayer }, "the thumb")
    try host.expectCastsDown(thumb, band: 2)
  }

  @Test(arguments: [false, true])
  func theFirstRunSpacePreviewCastsDown(dark: Bool) throws {
    let preview = SpacePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 220))
    let family = SpaceThemeCatalog.defaultFamily
    preview.configure(theme: dark ? family.dark : family.light, name: "Work", animated: false)
    preview.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)   // AppKit resets the layer's shadow here
    let host = Host(preview, dark: dark)
    preview.layout()
    try host.expectCastsDown(try #require(preview.layer), band: 16)
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theFloatingSidebarCastsDown(appearance: NSAppearance.Name) throws {
    let overlay = SidebarOverlayView(sidebar: SidebarContainerView(source: StubSidebar.sample()))
    overlay.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    overlay.appearance = NSAppearance(named: appearance)
    overlay.isDocked = false
    let host = Host(overlay, dark: appearance == .darkAqua)
    overlay.updateLayer()
    // The revealed rest state, without running the reveal spring: shown, no translation.
    overlay.isHidden = false
    let layer = try #require(overlay.layer)
    layer.setAffineTransform(.identity)
    // On screen the window joins the sidebar's views to this layer. The offscreen renderer draws no shadow for a
    // layer with no content of its own, so an opaque sublayer stands in for them.
    let content = CALayer()
    content.frame = layer.bounds
    content.backgroundColor = CGColor(gray: 0.5, alpha: 1)
    layer.addSublayer(content)
    try host.expectCastsDown(layer, band: 4)
  }

  /// The renderer keeps the window's orientation: a marker placed near the top of the host lands in the top rows of
  /// the bitmap. Without this a mirrored image would read "up" as "down".
  @Test func theRendererKeepsTheTopAtTheTop() throws {
    let plain = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    plain.wantsLayer = true
    let host = Host(plain, dark: false)
    let marker = CALayer()
    let height = host.root.bounds.height
    marker.frame = CGRect(x: 0, y: height - 8, width: 8, height: 4)   // y up: 4 to 8 points below the top
    marker.backgroundColor = CGColor(gray: 0, alpha: 1)
    host.root.addSublayer(marker)
    let image = try host.render()
    #expect(image.luminance(x: 4, yFromTop: 6) < 0.1, "the marker is in the top rows")
    #expect(image.luminance(x: 4, yFromTop: height - 6) > 0.9, "and not in the bottom rows")
  }
}

// MARK: - Rendering

/// An unflipped, opaque layer around one control's layer tree, with room for its shadow on every side: the window's
/// own orientation. Without a window on screen AppKit does not join a subview's layer to its superview's, so the
/// control's layer goes under a plain root layer directly, keeping the flip AppKit gave it (`isFlipped`).
@MainActor
private struct Host {
  static let margin: CGFloat = 40
  static let scale: CGFloat = 2
  let root = CALayer()
  private let content: NSView

  init(_ content: NSView, dark: Bool) {
    self.content = content
    let size = content.frame.size
    root.bounds = CGRect(x: 0, y: 0, width: size.width + 2 * Self.margin, height: size.height + 2 * Self.margin)
    root.backgroundColor = CGColor(gray: dark ? 0.35 : 1, alpha: 1)
  }

  /// Joins the control's layer to the root; call after the control laid itself out.
  private func attach() throws {
    let layer = try #require(content.layer, "the control is layer-backed")
    if layer.superlayer !== root { root.addSublayer(layer) }
    layer.frame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: content.frame.size)
  }

  func layers() -> [CALayer] {
    var found: [CALayer] = []
    func walk(_ layer: CALayer) {
      found.append(layer)
      layer.sublayers?.forEach(walk)
    }
    if let layer = content.layer { walk(layer) }
    return found
  }

  /// The host's layer tree, drawn by Core Animation at `scale` into an sRGB bitmap.
  func render() throws -> Bitmap {
    try attach()
    let width = Int(root.bounds.width * Self.scale), height = Int(root.bounds.height * Self.scale)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: Self.scale, y: Self.scale)
    root.render(in: context)
    let image = try #require(context.makeImage())
    return Bitmap(image: image, scale: Self.scale)
  }

  /// `element`'s shadow falls below it on screen: across its middle, the `band` points under its bottom edge are
  /// darker than the `band` points over its top edge. Every control here has the same surroundings above and below
  /// the element, so without a shadow, or with one cast straight up, this fails.
  func expectCastsDown(_ element: CALayer, band: CGFloat,
                       sourceLocation: SourceLocation = #_sourceLocation) throws {
    let image = try render()
    let rect = element.convert(element.bounds, to: root)   // root points, y up; joined by `render()`
    let height = root.bounds.height
    let xs = stride(from: rect.minX + rect.width * 0.3, through: rect.maxX - rect.width * 0.3, by: 1)
    // Bitmap rows count from the top: a height y up is the row (height - y).
    let under = image.mean(xs: xs, yFromTop: (height - rect.minY + 0.5)...(height - rect.minY + band))
    let over = image.mean(xs: xs, yFromTop: (height - rect.maxY - band)...(height - rect.maxY - 0.5))
    #expect(under < over - 0.003, "the band under the element (\(under)) is darker than the band over it (\(over))",
            sourceLocation: sourceLocation)
  }
}

/// Luminance reads of a rendered image, in points.
private struct Bitmap {
  let width: Int
  let height: Int
  let scale: CGFloat
  let bytes: [UInt8]

  init(image: CGImage, scale: CGFloat) {
    width = image.width
    height = image.height
    self.scale = scale
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    self.bytes = bytes
  }

  /// Rec. 709 luminance of the pixel at (`x`, `yFromTop`) points, 0 to 1. Row 0 of the buffer is the image's top.
  func luminance(x: CGFloat, yFromTop: CGFloat) -> Double {
    let px = min(max(Int(x * scale), 0), width - 1)
    let py = min(max(Int(yFromTop * scale), 0), height - 1)
    let i = (py * width + px) * 4
    return (0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])) / 255
  }

  func mean(xs: StrideThrough<CGFloat>, yFromTop rows: ClosedRange<CGFloat>) -> Double {
    var sum = 0.0
    var count = 0
    for x in xs {
      for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 1 / scale) {
        sum += luminance(x: x, yFromTop: y)
        count += 1
      }
    }
    return count == 0 ? .nan : sum / Double(count)
  }
}
