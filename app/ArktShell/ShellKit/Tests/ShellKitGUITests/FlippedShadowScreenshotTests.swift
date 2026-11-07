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

  /// #773: the Settings switch (off and on), segmented control and pane items, a current sidebar row and a selected
  /// Archive row, in a flipped container as the Settings content views and the tables host them. Writes
  /// `flipped-shadows-settings-rows-<light|dark>.png`. In dark only the off knob draws a lift (the plate and row
  /// lifts are light only).
  func testSettingsAndRowShots() throws {
    for flavor in [ThemeFlavor.light, .dark] { try settingsAndRowShot(flavor) }
  }

  private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
  }

  private func settingsAndRowShot(_ flavor: ThemeFlavor) throws {
    let size = NSSize(width: 560, height: 200)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    content.wantsLayer = true
    content.layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    window.contentView = content
    let container = FlippedContainer(frame: content.bounds)
    container.wantsLayer = true
    content.addSubview(container)

    let off = SettingsSwitch(frame: NSRect(x: 30, y: 36, width: 32, height: 20))
    container.addSubview(off)
    let on = SettingsSwitch(frame: NSRect(x: 80, y: 36, width: 32, height: 20))
    on.setOn(true, animated: false)
    container.addSubview(on)
    let segments = SettingsSegmentedControl(segments: ["Light", "Dark", "Auto"], selected: 0)
    segments.frame = NSRect(origin: NSPoint(x: 140, y: 32), size: segments.intrinsicContentSize)
    container.addSubview(segments)
    for (index, pane) in [SettingsPane.general, .spaces].enumerated() {
      let item = SettingsPaneItemView(pane: pane)
      item.frame.origin = NSPoint(x: 400 + CGFloat(index) * 86, y: 24)
      container.addSubview(item)
      item.setSelected(index == 0, animated: false)
    }
    let sidebarRow = SidebarRowView(frame: NSRect(x: 30, y: 110, width: 230, height: 41))
    sidebarRow.flavor = flavor
    sidebarRow.state = .current
    container.addSubview(sidebarRow)
    let archiveRow = ArchiveRowView(frame: NSRect(x: 300, y: 112, width: 230, height: 37))
    // Outside a table AppKit paints its own selection over a selected row; off, so the fill and its lift are drawn.
    archiveRow.selectionHighlightStyle = .none
    container.addSubview(archiveRow)
    archiveRow.isSelected = true

    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let folder = try XCTUnwrap(folder)
    let data = try render(content)
    let name = "flipped-shadows-settings-rows-\(flavor == .dark ? "dark" : "light").png"
    try data.write(to: folder.appendingPathComponent(name))
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
