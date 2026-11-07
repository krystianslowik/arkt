import AppKit
import XCTest
@testable import ShellUI

/// Light and dark screenshots of the four lifts #767 turned to cast down: the theme creator's slider knob, first
/// run's appearance thumb and Space preview, and the floating sidebar, each on a plain surface. Skipped unless
/// `ARKT_SHADOW_SHOTS_DIR` names a folder; writes `flipped-shadows-<light|dark>.png` there. Synthetic views only.
@MainActor
final class FlippedShadowScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_SHADOW_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_SHADOW_SHOTS_DIR to write the flipped shadow screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testShots() throws {
    for flavor in [ThemeFlavor.light, .dark] { try shot(flavor) }
  }

  private func shot(_ flavor: ThemeFlavor) throws {
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 340), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 340))
    content.wantsLayer = true
    content.layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    window.contentView = content

    let slider = ThemeSliderView(label: "Grain", identifier: "shot.slider")
    slider.frame = NSRect(x: 30, y: 270, width: 200, height: 24)
    slider.setValue(0.4)
    content.addSubview(slider)

    let segments = AppearanceSegmentView(appearance: OnboardingAppearance(flavor: flavor, reduceMotion: true))
    segments.frame = NSRect(origin: NSPoint(x: 30, y: 180), size: segments.intrinsicContentSize)
    content.addSubview(segments)

    let preview = SpacePreviewView(frame: NSRect(x: 280, y: 60, width: 320, height: 220))
    let family = SpaceThemeCatalog.defaultFamily
    preview.configure(theme: flavor == .dark ? family.dark : family.light, name: "Work", animated: false)
    content.addSubview(preview)

    let overlay = SidebarOverlayView(sidebar: SidebarContainerView(source: StubSidebar.sample()))
    overlay.frame = NSRect(x: 640, y: 40, width: 230, height: 270)
    overlay.reduceMotionForTesting = true
    // The window's Space theme shows through the floating sidebar, as the root mirrors it in the app.
    overlay.backdrop.themes = [flavor == .dark ? family.dark : family.light]
    content.addSubview(overlay)
    overlay.isDocked = false

    window.orderFront(nil)
    content.layoutSubtreeIfNeeded()
    overlay.reveal()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))

    let folder = try XCTUnwrap(folder)
    let data = try render(content)
    try data.write(to: folder.appendingPathComponent("flipped-shadows-\(flavor == .dark ? "dark" : "light").png"))
  }

  /// `content`'s layer tree drawn by Core Animation at 2x. `cacheDisplay` leaves out a view's own layer shadow when
  /// the layer has no content of its own (the floating sidebar's), so the tree is rendered directly.
  private func render(_ content: NSView) throws -> Data {
    let layer = try XCTUnwrap(content.layer)
    let scale: CGFloat = 2
    let width = Int(content.bounds.width * scale), height = Int(content.bounds.height * scale)
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
    context.cgContext.scaleBy(x: scale, y: scale)
    layer.render(in: context.cgContext)
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }
}
