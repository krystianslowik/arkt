import AppKit
import XCTest
@testable import ShellUI

/// The same synthetic overlay is rendered on both revisions by the opt-in evidence job.
@MainActor
final class ThemeOverlayScreenshotTests: XCTestCase {
  func testOverlayShots() throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_THEME_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_THEME_SHOTS_DIR to write overlay screenshots")
    }
    let prefix = ProcessInfo.processInfo.environment["ARKT_THEME_SHOTS_PREFIX"] ?? "overlay"
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    for dark in [false, true] {
      let frame = NSRect(x: 80, y: 80, width: 800, height: 600)
      let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      let view = ThemeBackgroundView(frame: NSRect(origin: .zero, size: frame.size))
      view.themes = [SpaceThemeInfo(baseColors: [.p3(hex: 0x224466, alpha: 1), .p3(hex: 0xAACCEE, alpha: 1)],
                                    overlayColors: [.p3(hex: 0xFF5533, alpha: 0.4), .p3(hex: 0x44CC99, alpha: 0.2),
                                                    .p3(hex: 0x5544FF, alpha: 0.3)], isDark: dark)]
      view.setPosition(0)
      window.contentView = view
      window.makeKeyAndOrderFront(nil)
      view.layoutSubtreeIfNeeded()
      CATransaction.flush()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
      let file = folder.appendingPathComponent("\(prefix)-\(dark ? "dark" : "light").png")
      let capture = Process()
      capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
      try capture.run()
      capture.waitUntilExit()
      XCTAssertEqual(capture.terminationStatus, 0)
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
      window.close()
    }
  }
}
