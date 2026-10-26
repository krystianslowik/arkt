import AppKit
import XCTest
@testable import ShellUI

/// Window screenshots of the quick lookup bar and its Settings row for the pull request (#354). Skipped unless
/// `ARKT_LOOKUP_SHOTS_DIR` names a folder; writes `lookup-<state>.png` there. Synthetic hosts only.
@MainActor
final class LittleArktLookupScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_LOOKUP_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_LOOKUP_SHOTS_DIR to write the lookup screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate()
  }

  private func settle(_ seconds: TimeInterval = 0.6) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  /// The window as on screen (no shadow margin), through `screencapture -l`.
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

  func testLookupBarShots() throws {
    let bar = LittleArktLookupController()
    bar.show(on: NSScreen.main)
    settle()
    try save(bar.panel, "lookup-empty")
    bar.setQueryForTesting("atlas.example/field-guide")
    settle()
    try save(bar.panel, "lookup-results")
    bar.hide()
  }

  /// The Settings > Links row, off, with the conflict line another app's combination produces.
  func testSettingsLinksShots() throws {
    let name = "dev.arkt.tests.lookupShots.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { UserDefaults().removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let controller = SettingsWindowController(settings: settings, services: SettingsServices())
    controller.show(pane: .general)
    settle()
    let window = try XCTUnwrap(controller.window)
    try save(window, "settings-links")
    settings.setLittleArktHotKeyTaken(true)
    settle()
    try save(window, "settings-links-conflict")
    controller.close()
  }
}
