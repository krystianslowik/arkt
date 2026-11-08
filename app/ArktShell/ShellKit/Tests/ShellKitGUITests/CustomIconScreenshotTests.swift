import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Synthetic Favorite and folder icon renders for review. Set ARKT_CUSTOM_ICON_SHOTS_DIR to write PNGs.
@MainActor
final class CustomIconScreenshotTests: XCTestCase {
  func testCustomIconShots() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_CUSTOM_ICON_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_CUSTOM_ICON_SHOTS_DIR to write synthetic custom icon screenshots")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    for dark in [false, true] {
      try await capture(directory: directory, dark: dark)
    }
  }

  private func capture(directory: URL, dark: Bool) async throws {
    let source = StubSidebar()
    let space = source.addSpace(title: "Synthetic Space", theme: AlertScreenshotTests.workTheme(dark: dark))
    let url = URL(string: "https://example.com/synthetic")!
    let symbol = source.addTab(url: url, title: "Symbol Favorite", in: .favorites(profile: "default"))
    let emoji = source.addTab(url: url, title: "Emoji Favorite", in: .favorites(profile: "default"))
    _ = source.addTab(url: url, title: "Normal Favorite", in: .favorites(profile: "default"))
    let reset = source.addTab(url: url, title: "Reset Favorite", in: .favorites(profile: "default"))
    let folder = source.addFolder(title: "A very long synthetic folder title for the minimum window width",
                                  in: .pinned(space))
    let child = source.addTab(url: url, title: "Synthetic folder child", in: .folder(folder))
    source.setNodeIcon(symbol, to: .symbol("star"))
    source.setNodeIcon(emoji, to: .emoji("\u{1F680}"))
    source.setNodeIcon(reset, to: .symbol("heart"))
    source.setNodeIcon(folder, to: .symbol("star"))

    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    defer { controller.close() }
    let window = try XCTUnwrap(controller.window)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.setFrame(NSRect(x: 80, y: 80, width: 640, height: 420), display: true)
    controller.rootView.sidebarWidth = ShellMetrics.standard.sidebarMinWidth
    controller.showWindow(nil)
    // The launch selection is the folder child; keep the current-tab peek out of closed-state captures.
    controller.activate(node: symbol)
    let sidebar = controller.sidebarController
    let favicon = try XCTUnwrap(NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?.tiffRepresentation)
    sidebar.setFavicon(favicon, for: reset)
    await sidebar.settleFaviconDecodes()
    let outline = try XCTUnwrap(sidebar.currentPage?.outlineController)
    let suffix = dark ? "dark" : "light"
    XCTAssertEqual(sidebar.current, symbol)
    func saveState(open: Bool, name: String) throws {
      XCTAssertEqual(outline.isFolderOpen(folder), open)
      XCTAssertEqual(outline.row(for: child) >= 0, open, "closed capture must not contain a current-tab peek")
      try save(window, directory: directory, name: name)
    }

    if !outline.isFolderOpen(folder) { outline.toggleFolder(folder, animated: false) }
    try saveState(open: true, name: "custom-icons-open-\(suffix)")
    outline.toggleFolder(folder, animated: false)
    try saveState(open: false, name: "custom-icons-closed-\(suffix)")
    source.setNodeIcon(reset, to: nil)
    source.setNodeIcon(folder, to: nil)
    try saveState(open: false, name: "custom-icons-reset-closed-\(suffix)")
    outline.toggleFolder(folder, animated: false)
    try saveState(open: true, name: "custom-icons-reset-open-\(suffix)")
  }

  private func save(_ window: NSWindow, directory: URL, name: String) throws {
    let view = try XCTUnwrap(window.contentView)
    view.layoutSubtreeIfNeeded()
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try data.write(to: directory.appendingPathComponent("\(name).png"))
  }
}
