import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Opt-in, synthetic screenshots of the real restore panel in its shell window.
@MainActor
final class RestorePagesScreenshotTests: XCTestCase {
  func testRestorePagesShots() throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_RESTORE_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_RESTORE_SHOTS_DIR to export restore panel screenshots")
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    for dark in [false, true] {
      let engine = InMemoryEngine()
      engine.crashedSession.simulateCrashedExit()
      let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
      controller.window?.isReleasedWhenClosed = false
      defer { controller.close() }
      let window = try XCTUnwrap(controller.window)
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      window.setFrame(NSRect(x: 80, y: 80, width: 1000, height: 700), display: true)
      controller.showWindow(nil)
      let titles = ["A very long synthetic page title that should truncate neatly inside the restore panel",
                    "Research notes", "A page in Little Arkt", "Another page", "Last page"]
      let pages = titles.enumerated().map { index, title in
        ShellRecoveryPage(title: title, url: URL(string: "https://example.invalid/fixture/\(index)")!, kind: index == 2 ? .littleArkt : .peek)
      }
      controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession, pages: pages) { _ in true })
      let panel = try XCTUnwrap(controller.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      panel.layer?.removeAllAnimations()
      panel.alphaValue = 1
      controller.rootView.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let file = folder.appendingPathComponent("restore-pages-\(dark ? "dark" : "light").png")
      let capture = Process()
      capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
      try capture.run()
      capture.waitUntilExit()
      XCTAssertEqual(capture.terminationStatus, 0)
      let imageData = try Data(contentsOf: file)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: imageData))
      XCTAssertGreaterThan(bitmap.pixelsWide, 0)
      XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
      var colors = Set<String>()
      for column in 0..<10 {
        let x = column * (bitmap.pixelsWide - 1) / 9
        for row in 0..<10 {
          let y = row * (bitmap.pixelsHigh - 1) / 9
          if let color = bitmap.colorAt(x: x, y: y) { colors.insert(color.description) }
        }
      }
      XCTAssertGreaterThan(colors.count, 1, "window capture must not be blank")
    }
  }
}
