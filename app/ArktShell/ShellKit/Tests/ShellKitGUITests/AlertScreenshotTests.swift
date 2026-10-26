import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Window screenshots of the toasts and the Delete Space sheet in light and dark, for the pull request. Skipped unless
/// `ARKT_ALERT_SHOTS_DIR` names a folder; writes `<name>-<light|dark>.png` there. Synthetic sidebar only.
@MainActor
final class AlertScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_ALERT_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_ALERT_SHOTS_DIR to write the alert screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// The prototype's blue Work theme, light and dark.
  static func workTheme(dark: Bool) -> SpaceThemeInfo {
    dark ? SpaceThemeInfo(baseColors: [.srgb(hex: 0x1E3A5F), .srgb(hex: 0x24304A)], isDark: true)
      : SpaceThemeInfo(baseColors: [.srgb(hex: 0xC9DBF5), .srgb(hex: 0xDCE7F7)], isDark: false)
  }

  private func makeWindow(dark: Bool) -> ShellWindowController {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Work", theme: Self.workTheme(dark: dark))
    stub.setIcon(space, to: .symbol("diamond.fill"))
    for title in ["Field guide to lichens", "Release checklist", "Weekend recipes"] {
      _ = stub.addTab(url: URL(string: "https://example.com/\(title.count)")!, title: title, in: .today(space),
                      at: nil)
    }
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    let window = controller.window
    window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window?.setFrame(NSRect(x: 80, y: 80, width: 1080, height: 720), display: true)
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  /// The window as on screen, shadows and an attached sheet included, through `screencapture -l` (window only, no
  /// shadow margin).
  private func save(_ window: NSWindow, _ name: String) throws {
    let folder = try XCTUnwrap(folder)
    let file = folder.appendingPathComponent("\(name).png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
    try capture.run()
    capture.waitUntilExit()
    XCTAssertEqual(capture.terminationStatus, 0)
  }

  func testToastShots() throws {
    for dark in [false, true] {
      let suffix = dark ? "dark" : "light"
      let controller = makeWindow(dark: dark)
      let window = try XCTUnwrap(controller.window)
      controller.toasts.show(Toast(text: "Tab restored to Work", glyph: "arrow.counterclockwise",
                                   actionTitle: "View"))
      settle()
      try save(window, "toast-restored-\(suffix)")
      controller.toasts.show(Toast(text: "Archived 3 tabs", kind: .undo, actionTitle: "Undo"))
      settle()
      try save(window, "toast-undo-\(suffix)")
      controller.toasts.show(Toast(text: "Arkt couldn't read its saved sidebar and restored it from a backup. "
                                   + "Recent changes may be missing.", kind: .persistent, actionTitle: "Show Files"))
      settle()
      try save(window, "toast-recovery-\(suffix)")
      controller.close()
    }
  }

  func testDeleteSpaceShots() throws {
    for dark in [false, true] {
      let controller = makeWindow(dark: dark)
      let window = try XCTUnwrap(controller.window)
      controller.onRemoveSpace = { _ in }
      controller.deleteSpace(nil)
      settle(1.2)
      try save(window, "delete-space-\(dark ? "dark" : "light")")
      if let sheet = window.attachedSheet { window.endSheet(sheet) }
      controller.close()
    }
  }
}
