import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

/// Window screenshots of the private pages states (design/private-pages) in light and dark, to compare with the
/// design's screens. Skipped unless `ARKT_PRIVATE_PAGES_SHOTS_DIR` names a folder; writes
/// `private-pages-<state>-<light|dark>.png` there. Synthetic titles only.
@MainActor
final class PrivatePagesScreenshotTests: XCTestCase {
  private var folder: URL?
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_PRIVATE_PAGES_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_PRIVATE_PAGES_SHOTS_DIR to write the private pages screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  static let titles = [
    "Your cart - Example Store",
    "Sign in to continue to the account settings and billing overview for this workspace",
    "Weekly radio stream, live from the harbour studio",
    "Search results for a very long query that keeps going past the end of the row",
    "x", "Order confirmation and delivery estimate", "Help centre: returns and refunds", "Compare plans",
    "Release notes for version 14.2", "Map of the old town walking route", "Recipe: slow-cooked bean stew",
    "Train times, weekday service", "Library catalogue search", "Forum thread: keyboard layouts on laptops",
    "Weather for the coming week", "Photo gallery, page 12 of 40", "Museum opening hours and tickets",
    "Translation of a long paragraph from the original text", "Parking near the station", "Q",
  ]

  /// The design's backdrop (`prototype.html`, `--theme-a` and `--theme-b`).
  static func neutralTheme(dark: Bool) -> SpaceThemeInfo {
    dark ? SpaceThemeInfo(baseColors: [.srgb(hex: 0x34343B), .srgb(hex: 0x222227)], isDark: true)
      : SpaceThemeInfo(baseColors: [.srgb(hex: 0xE7E6EA), .srgb(hex: 0xD6D5DB)], isDark: false)
  }

  static let hosts = ["checkout.example.org", "accounts.example.com", "radio.example.net", "search.example.org",
                      "x.example", "orders.example.com", "help.example.org", "plans.example.com"]

  private func makeWindow(dark: Bool, size: NSSize, pages: Int) throws -> (ShellWindowController, InMemoryEngine) {
    let engine = InMemoryEngine()
    // The window opens on a Space, as from a normal window; its theme is the design's neutral backdrop.
    let source = StubSidebar()
    _ = source.addSpace(title: "Work", theme: Self.neutralTheme(dark: dark))
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let controller = set.openWindow(opensFirstTab: false)
    controller.makeIncognito()
    let window = try XCTUnwrap(controller.window)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    controller.sidebarController.view.setFlavor(dark ? .dark : .light)
    controller.sidebarController.view.privatePages.reduceMotion = { true }
    controller.toasts.view?.reduceMotion = { true }
    window.setFrame(NSRect(origin: NSPoint(x: 80, y: 80), size: size), display: true)
    if size.width <= 640 { controller.rootView.sidebarWidth = ShellMetrics.standard.sidebarMinWidth }
    for index in 0..<pages {
      let host = Self.hosts[index % Self.hosts.count]
      controller.openPrivately(URL(string: "https://\(host)/page-\(index)")!, inNewPage: index > 0)
      if let tab = controller.currentTab { engine.setDocumentTitle(tab, Self.titles[index]) }
    }
    controller.selectPrivatePage(controller.privatePageOrder.pages[0])
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    return (controller, engine)
  }

  private func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  private func save(_ window: NSWindow, _ name: String) throws {
    let folder = try XCTUnwrap(folder)
    let view = try XCTUnwrap(window.contentView)
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try data.write(to: folder.appendingPathComponent("private-pages-\(name).png"))
  }

  func testPrivatePagesShots() throws {
    for dark in [false, true] {
      let suffix = dark ? "dark" : "light"
      var (controller, engine) = try makeWindow(dark: dark, size: NSSize(width: 960, height: 600), pages: 3)
      controller.sidebarController.view.privatePages.rows[1].setHovered(true)
      settle()
      try save(try XCTUnwrap(controller.window), "list-\(suffix)")
      controller.close()

      (controller, engine) = try makeWindow(dark: dark, size: NSSize(width: 960, height: 600), pages: 5)
      engine.setAudible(controller.privatePageOrder.pages[2], true)
      engine.setMuted(controller.privatePageOrder.pages[2], muted: true)
      settle()
      try save(try XCTUnwrap(controller.window), "audio-\(suffix)")
      controller.close()

      (controller, engine) = try makeWindow(dark: dark, size: NSSize(width: 960, height: 600), pages: 20)
      engine.setAudible(controller.privatePageOrder.pages[2], true)
      controller.openPrivately(URL(string: "https://example.org/refused")!, inNewPage: true)
      settle()
      try save(try XCTUnwrap(controller.window), "cap-\(suffix)")
      controller.close()

      (controller, engine) = try makeWindow(dark: dark, size: NSSize(width: 960, height: 600), pages: 20)
      for tab in controller.privatePageOrder.pages.dropFirst() { engine.setAudible(tab, true) }
      controller.openPrivately(URL(string: "https://example.org/refused")!, inNewPage: true)
      settle()
      try save(try XCTUnwrap(controller.window), "cap-none-\(suffix)")
      controller.close()

      (controller, engine) = try makeWindow(dark: dark, size: NSSize(width: 640, height: 420), pages: 20)
      engine.setAudible(controller.privatePageOrder.pages[2], true)
      controller.openPrivately(URL(string: "https://example.org/refused")!, inNewPage: true)
      settle()
      try save(try XCTUnwrap(controller.window), "small-\(suffix)")
      controller.close()
    }
  }
}
