import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Window screenshots of the sidebar banner's three states (design/sidebar-banner) in light and dark, for the pull
/// request. Skipped unless `ARKT_BANNER_SHOTS_DIR` names a folder; writes `sidebar-banner-<state>-<light|dark>.png`
/// there. Synthetic sidebar only.
@MainActor
final class SidebarBannerScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_BANNER_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_BANNER_SHOTS_DIR to write the sidebar banner screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeWindow(dark: Bool, size: NSSize,
                          notice: SidebarNotice) -> (ShellWindowController, SidebarBannerCenter) {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Work", theme: AlertScreenshotTests.workTheme(dark: dark))
    for title in ["Field guide to lichens", "Release checklist", "Weekend recipes",
                  "Quarterly report draft, version 7 (final, really)", "Train times", "Gallery opening hours",
                  "Pull request 1482: sidebar banner", "Recipes for a rainy week", "Bird songs of the coast"] {
      _ = stub.addTab(url: URL(string: "https://example.com/\(title.count)")!, title: title, in: .today(space),
                      at: nil)
    }
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    let source = FakeSidebarNoticeSource(notices: [notice])
    let model = SidebarBannerModel(source: source, dismissals: .ephemeral()) { _, _ in }
    model.reduceMotion = { true }
    let center = SidebarBannerCenter(model: model)
    center.attach(to: controller)
    let window = controller.window
    window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window?.setFrame(NSRect(origin: NSPoint(x: 80, y: 80), size: size), display: true)
    if size.width <= 640 { controller.rootView.sidebarWidth = ShellMetrics.standard.sidebarMinWidth }
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    return (controller, center)
  }

  private func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  /// `window`'s content drawn offscreen (no screen recording needed); a child panel is saved as its own file.
  private func save(_ window: NSWindow, _ name: String) throws {
    let folder = try XCTUnwrap(folder)
    let view = try XCTUnwrap(window.contentView)
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try data.write(to: folder.appendingPathComponent("\(name).png"))
  }

  func testBannerShots() throws {
    let announcement = SidebarNotice.announcement(
      id: "archive-search",
      title: "Archived tabs can now be searched by what was on the page, not only by their title, at last",
      body: "Open the Archive and type a few words you remember. It works for tabs archived from today on; older "
        + "ones are indexed in the background over the next few days.",
      actionTitle: "Open Archive")
    for dark in [false, true] {
      let suffix = dark ? "dark" : "light"
      var (controller, center) = makeWindow(dark: dark, size: NSSize(width: 1080, height: 720),
                                            notice: .update(version: "1.4.2"))
      var window = try XCTUnwrap(controller.window)
      controller.sidebarController.view.banner.setHovered(true)
      settle()
      try save(window, "sidebar-banner-update-\(suffix)")
      controller.close()

      (controller, center) = makeWindow(dark: dark, size: NSSize(width: 1080, height: 720), notice: announcement)
      window = try XCTUnwrap(controller.window)
      center.attachment(of: controller)?.togglePopover()
      settle()
      try save(window, "sidebar-banner-announce-\(suffix)")
      try save(try XCTUnwrap(center.attachment(of: controller)?.popover.panel), "sidebar-banner-popover-\(suffix)")
      center.attachment(of: controller)?.popover.hide()
      controller.close()

      (controller, center) = makeWindow(dark: dark, size: NSSize(width: 640, height: 420),
                                        notice: .update(version: "1.4.2"))
      window = try XCTUnwrap(controller.window)
      settle()
      try save(window, "sidebar-banner-small-\(suffix)")
      controller.close()
      _ = center
    }
  }
}
