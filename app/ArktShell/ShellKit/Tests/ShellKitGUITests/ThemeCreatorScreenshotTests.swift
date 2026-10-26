import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Window screenshots of the Space theme creator in light and dark (#410), the three states of
/// design/theme-creator/screens/: two colours with Sand at 40 % and opacity 80 %, one colour, and Texture None.
/// Skipped unless `ARKT_THEME_SHOTS_DIR` names a folder; writes `<state>-<light|dark>.png` there. Synthetic sidebar
/// only.
@MainActor
final class ThemeCreatorScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_THEME_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_THEME_SHOTS_DIR to write the theme creator screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// The design's theme: a deep blue and a copper from the pad, Sand at 40 %, opacity 80 %.
  static let studio = SpaceThemeInfo(
    baseColors: [ThemePad.color(ThemePadPoint(hue: 216, tone: 0.74)), ThemePad.color(ThemePadPoint(hue: 27, tone: 0.34))],
    texture: "sand", noiseFactor: 0.4, opacity: 0.8, isDark: true)

  private func makeWindow(dark: Bool, theme: SpaceThemeInfo) -> ShellWindowController {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Studio", theme: theme)
    for title in ["Field guide to lichens", "Research notes", "Expense report template", "Moodboard, winter issue",
                  "Flights to Lisbon", "Miso aubergine"] {
      _ = stub.addTab(url: URL(string: "https://example.com/\(title.count)")!, title: title, in: .today(space),
                      at: nil)
    }
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    controller.sidebarController.themeCreatorReducesMotion = { true }
    let window = controller.window
    window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 760), display: true)
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  /// The window as on screen, shadows included, through `screencapture -l`.
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

  func testThemeCreatorShots() async throws {
    await ThemeCreatorImages.prepare(scale: NSScreen.main?.backingScaleFactor ?? 2).value
    var single = Self.studio
    single.baseColors = [Self.studio.baseColors[0]]
    var none = Self.studio
    none.texture = nil
    for (state, theme) in [("pad", Self.studio), ("single-colour", single), ("texture-none", none)] {
      for dark in [false, true] {
        let controller = makeWindow(dark: dark, theme: theme)
        let window = try XCTUnwrap(controller.window)
        let space = try XCTUnwrap(controller.currentSpace)
        controller.sidebarController.openThemeCreator(for: space)
        XCTAssertNotNil(controller.themeCreatorView)
        settle()
        try save(window, "\(state)-\(dark ? "dark" : "light")")
        controller.sidebarController.closeThemeCreator(animated: false)
        controller.close()
      }
    }
  }
}
