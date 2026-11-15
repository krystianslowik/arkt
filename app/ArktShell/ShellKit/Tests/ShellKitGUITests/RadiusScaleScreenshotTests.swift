import AppKit
import XCTest
@testable import ShellUI

/// Light and dark screenshots of the surfaces with the most corner radii (#620): three Settings panes (General,
/// Appearance, Shortcuts) and the Archive window. Rendered at both sides of a radius change and compared pixel by
/// pixel to show the change moved nothing. Skipped unless `ARKT_RADIUS_SHOTS_DIR` names a folder; writes
/// `radius-<surface>-<light|dark>.png` there. Stub settings in a private defaults suite and stub Archive rows; no
/// engine, no clipboard.
@MainActor
final class RadiusScaleScreenshotTests: XCTestCase {
  private var folder: URL?
  private var suiteName = ""

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_RADIUS_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_RADIUS_SHOTS_DIR to write the radius scale screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    suiteName = "dev.arkt.tests.radiusShots.\(UUID().uuidString)"
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    if !suiteName.isEmpty { UserDefaults().removePersistentDomain(forName: suiteName) }
  }

  func testSettingsShots() throws {
    for flavor in [ThemeFlavor.light, .dark] {
      for pane in [SettingsPane.general, .appearance, .shortcuts] { try settingsShot(pane, flavor) }
    }
  }

  func testArchiveShots() async throws {
    for flavor in [ThemeFlavor.light, .dark] { try await archiveShot(flavor) }
  }

  private func settingsShot(_ pane: SettingsPane, _ flavor: ThemeFlavor) throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    var services = SettingsServices()
    let shortcuts = MainMenu.make(commands: AppCommands()).menu
    services.shortcutsMenu = { shortcuts }
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    controller.show(pane: pane)
    controller.select(pane, animated: false)
    try write(window, name: "settings-\(pane.rawValue)", flavor)
  }

  private func archiveShot(_ flavor: ThemeFlavor) async throws {
    let controller = ArchiveWindowController(dataSource: ArchiveRowsStub(count: 3))
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    await controller.reload()
    window.orderFront(nil)
    try write(window, name: "archive", flavor)
  }

  private func write(_ window: NSWindow, name: String, _ flavor: ThemeFlavor) throws {
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    var root = try XCTUnwrap(window.contentView?.layer)
    while let up = root.superlayer { root = up }
    let folder = try XCTUnwrap(folder)
    let data = try render(root, size: root.bounds.size)
    try data.write(to: folder.appendingPathComponent("radius-\(name)-\(flavor == .dark ? "dark" : "light").png"))
  }

  /// `layer`'s tree drawn by Core Animation at 2x.
  private func render(_ layer: CALayer, size: CGSize) throws -> Data {
    let scale: CGFloat = 2
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
    context.cgContext.scaleBy(x: scale, y: scale)
    layer.render(in: context.cgContext)
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }
}
