import AppKit
import XCTest
@testable import ShellUI

/// Light and dark 2x shots of the Toolbar strip with a long URL, the text in its own `ShellType.toolbarURL` token
/// (#623). Skipped unless `ARKT_TYPE_SHOTS_DIR` names a folder; writes `toolbar-url-<light|dark>.png` there. Synthetic
/// views only: no page loads, no engine.
@MainActor
final class ToolbarTypeScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_TYPE_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_TYPE_SHOTS_DIR to write the Toolbar type screenshots")
    }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    folder = url
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testToolbarShots() throws {
    for flavor in [ThemeFlavor.light, .dark] { try shot(flavor) }
  }

  private func shot(_ flavor: ThemeFlavor) throws {
    let size = NSSize(width: 640, height: ContentToolbarView.height)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    content.wantsLayer = true
    content.layer?.backgroundColor = ShellTokens.toolbarSurface.resolve(flavor).cgColor
    window.contentView = content
    let toolbar = ContentToolbarView(frame: content.bounds)
    content.addSubview(toolbar)
    toolbar.urlBar.url = try XCTUnwrap(URL(string: "https://developer.example.org/documentation/appkit/nsfont"))
    toolbar.setHistory(canGoBack: true, canGoForward: false)
    window.orderFront(nil)
    content.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let scale: CGFloat = 2
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                             pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = size
    content.cacheDisplay(in: content.bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    let folder = try XCTUnwrap(folder)
    try data.write(to: folder.appendingPathComponent("toolbar-url-\(flavor == .dark ? "dark" : "light").png"))
  }
}
