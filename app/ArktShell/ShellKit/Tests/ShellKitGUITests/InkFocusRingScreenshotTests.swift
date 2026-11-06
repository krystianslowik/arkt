import AppKit
import XCTest
@testable import ShellUI

/// Light and dark screenshots of the ink focus ring on the controls #687 moved to it, for
/// design/drag-hint-focus-ring/screens/: each control drawn focused on its own surface. Skipped unless
/// `ARKT_FOCUS_SHOTS_DIR` names a folder; writes `drag-hint-focus-ring-controls-<light|dark>.png` there. Synthetic
/// views only.
@MainActor
final class InkFocusRingScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_FOCUS_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_FOCUS_SHOTS_DIR to write the focus ring screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
  }

  /// A window that reports key, so the rings draw without the test runner being the active app.
  private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
  }

  /// A tile of `color` holding `views`, laid out left to right with a caption above.
  private func tile(_ title: String, _ color: RGBA, flavor: ThemeFlavor, _ views: [NSView]) -> NSView {
    let width = views.reduce(CGFloat(24)) { $0 + $1.frame.width + 24 }
    let tile = NSView(frame: NSRect(x: 0, y: 0, width: max(width, 150), height: 96))
    tile.wantsLayer = true
    tile.layer?.backgroundColor = color.cgColor
    tile.layer?.cornerRadius = 12
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    label.frame = NSRect(x: 12, y: 72, width: tile.frame.width - 24, height: 16)
    tile.addSubview(label)
    var x: CGFloat = 24
    for view in views {
      view.setFrameOrigin(NSPoint(x: x, y: ((64 - view.frame.height) / 2).rounded()))
      tile.addSubview(view)
      x += view.frame.width + 24
    }
    return tile
  }

  private func shot(_ flavor: ThemeFlavor) throws {
    let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 260), styleMask: [.borderless],
                           backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let content = NSView(frame: window.contentLayoutRect)
    content.wantsLayer = true
    content.layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    window.contentView = content
    var rings: [KeyboardFocusRingView] = []

    // Theme creator: the colour-count button, a slider knob and the selected swatch on the popover surface.
    let count = ThemeColourCountButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
    count.update(colors: [.srgb(hex: 0x3366CC), .srgb(hex: 0xC8743A)], flavor: flavor,
                 surface: ShellTokens.themePopoverSurface.resolve(flavor), animated: false)
    let slider = ThemeSliderView(label: "Opacity", identifier: "shot.slider")
    slider.frame = NSRect(x: 0, y: 0, width: 140, height: ThemeCreatorMetrics.sliderHeight)
    slider.applyColors(flavor)
    slider.setValue(0.6)
    let swatches = ThemeTextureSwatchesView(frame: NSRect(x: 0, y: 0, width: ThemeTextureSwatchesView.width,
                                                          height: ThemeCreatorMetrics.labelRow))
    swatches.update(selected: .sand, flavor: flavor)
    for control in [count, slider, swatches] as [ThemeFocusableView] {
      control.applyFocusRingFlavor(flavor)
      rings.append(control.keyboardFocusRing)
    }
    let unfocusedSwatches = ThemeTextureSwatchesView(frame: swatches.frame)
    unfocusedSwatches.update(selected: .grain, flavor: flavor)
    let theme = tile("Theme creator", ShellTokens.themePopoverSurface.resolve(flavor), flavor: flavor,
                     [count, slider, swatches, unfocusedSwatches])

    // Peek: a control beside the card, over the scrim on the page.
    let page = flavor == .light ? RGBA.white(1) : RGBA.srgb(hex: 0x1C1C20)
    let peek = PeekControlButton(symbol: "xmark", label: "Close", help: "", toolTip: "", identifier: "shot.peek")
    peek.frame = NSRect(x: 0, y: 0, width: PeekLayout.controlSize, height: PeekLayout.controlSize)
    peek.flavor = flavor
    rings.append(peek.keyboardFocusRing)
    let peekTile = tile("Peek", ShellTokens.peekScrim.resolve(flavor).composited(over: page), flavor: flavor, [peek])

    // Little Arkt: Copy Link and the mustard split's segment.
    let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 420, height: 40))
    bar.configure(host: "example.com", fullURL: "https://example.com/", secure: true, openLabel: "Open in Studio",
                  openHelp: "", accent: true, swatch: [.srgb(hex: 0x3366CC)])
    rings += [bar.copyButton.keyboardFocusRing, bar.openButton.keyboardFocusRing]
    let little = tile("Little Arkt", BrandTokens.surfaceBrand.resolve(flavor), flavor: flavor, [bar])

    // Find bar, Library and import.
    let find = FindBarButton(symbol: "chevron.down", pointSize: 11, label: "Next", identifier: "shot.find")
    find.frame = NSRect(x: 0, y: 0, width: FindBarLayout.buttonSize, height: FindBarLayout.buttonSize)
    let rail = LibraryRailItem(section: .downloads)
    rail.frame = NSRect(x: 0, y: 0, width: 140, height: DownloadsMetrics.railRow)
    rail.isCurrent = true
    let download = DownloadIconButton(symbol: "folder", label: "Show in Finder")
    let checkbox = ImportCheckbox(style: .hero(OnboardingAppearance(flavor: flavor), compact: false))
    checkbox.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
    checkbox.set(isOn: true, isEnabled: true, animated: false)
    rings += [find.keyboardFocusRing, rail.keyboardFocusRing, download.keyboardFocusRing,
              checkbox.keyboardFocusRing]
    let other = tile("Find bar, Library, import", BrandTokens.surfaceBrand.resolve(flavor), flavor: flavor,
                     [find, rail, download, checkbox])

    var x: CGFloat = 16
    var y: CGFloat = 140
    for view in [theme, peekTile, little, other] {
      if x + view.frame.width > content.bounds.width - 16 {
        x = 16
        y -= 112
      }
      view.setFrameOrigin(NSPoint(x: x, y: y))
      content.addSubview(view)
      x += view.frame.width + 16
    }
    for ring in rings { ring.setFocused(true) }
    content.layoutSubtreeIfNeeded()
    content.displayIfNeeded()
    for ring in rings { ring.updateLayer() }

    let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    let folder = try XCTUnwrap(folder)
    let name = "drag-hint-focus-ring-controls-\(flavor == .dark ? "dark" : "light").png"
    try data.write(to: folder.appendingPathComponent(name))
  }

  func testInkFocusRingShots() throws {
    try shot(.light)
    try shot(.dark)
  }
}

private extension RGBA {
  /// Source-over on an opaque color, for the scrim over the page.
  func composited(over bottom: RGBA) -> RGBA {
    let a = alpha
    return RGBA(red: red * a + bottom.red * (1 - a), green: green * a + bottom.green * (1 - a),
                blue: blue * a + bottom.blue * (1 - a), alpha: 1, space: space)
  }
}
