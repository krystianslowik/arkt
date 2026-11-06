import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Window screenshots of the sidebar drop slot (#686, design/drag-hint-focus-ring) for the pull request: the slot and
/// its Reduce Motion variant, the boundary line, on a dark-text Space (Sand) and a light-text Space (Plum), in light
/// and dark. Skipped unless `ARKT_DROP_SLOT_SHOTS_DIR` names a folder; writes
/// `sidebar-drop-<slot|line>-<sand|plum>-<light|dark>.png` there. Synthetic sidebar only.
@MainActor
final class SidebarDropSlotScreenshotTests: XCTestCase {
  private var folder: URL?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_DROP_SLOT_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_DROP_SLOT_SHOTS_DIR to write the sidebar drop slot screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// The design's sample themes: Sand has dark text, Plum light text.
  private static func theme(_ name: String, dark: Bool) -> SpaceThemeInfo {
    switch (name, dark) {
    case ("sand", false): SpaceThemeInfo(baseColors: [.srgb(hex: 0xF3E9D2), .srgb(hex: 0xE4D3AE)], isDark: false)
    case ("sand", true): SpaceThemeInfo(baseColors: [.srgb(hex: 0x3F3628), .srgb(hex: 0x2B251B)], isDark: true)
    case (_, false): SpaceThemeInfo(baseColors: [.srgb(hex: 0x4A3460), .srgb(hex: 0x2F213F)], isDark: true)
    default: SpaceThemeInfo(baseColors: [.srgb(hex: 0x3A2848), .srgb(hex: 0x241830)], isDark: true)
    }
  }

  /// `window`'s content from its layer tree, so the rows show where their `sublayerTransform` moves them (offscreen
  /// `cacheDisplay` ignores it). No screen recording needed.
  private func save(_ window: NSWindow, _ name: String) throws {
    let view = try XCTUnwrap(window.contentView)
    let layer = try XCTUnwrap(view.layer)
    let scale = window.backingScaleFactor
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: nil, width: Int(view.bounds.width * scale),
                                          height: Int(view.bounds.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: scale, y: scale)
    if layer.isGeometryFlipped {
      context.translateBy(x: 0, y: view.bounds.height)
      context.scaleBy(x: 1, y: -1)
    }
    layer.render(in: context)
    let image = try XCTUnwrap(context.makeImage())
    let file = try XCTUnwrap(folder).appendingPathComponent("\(name).png")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  func testDropSlotShots() throws {
    for name in ["sand", "plum"] {
      for dark in [false, true] {
        for reduce in [false, true] {
          let stub = StubSidebar()
          let space = stub.addSpace(title: "Work", theme: Self.theme(name, dark: dark))
          var tabs: [NodeID] = []
          for title in ["Field guide to lichens", "Release checklist", "Weekend recipes", "Train times",
                        "Quarterly report draft, version 7 (final, really)", "Gallery opening hours"] {
            tabs.append(stub.addTab(url: URL(string: "https://example.com/\(title.count)")!, title: title,
                                    in: .today(space), at: nil))
          }
          let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
          let window = try XCTUnwrap(controller.window)
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          window.setFrame(NSRect(x: 80, y: 80, width: 900, height: 560), display: true)
          controller.showWindow(nil)
          controller.rootView.layoutSubtreeIfNeeded()
          let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
          let drop = outline.drop
          let start: CFTimeInterval = 100
          drop.reduceMotion = { reduce }
          drop.now = { start }
          let row = outline.row(for: tabs[2])
          let rect = outline.outlineView.rect(ofRow: row)
          drop.update(at: NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.1),
                      payload: SidebarDragPayload(nodes: [tabs[0]], isSingleTab: true))
          drop.preview.tick(at: start + 2)
          RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))   // the 0.12 s fade; screenshots only
          try save(window, "sidebar-drop-\(reduce ? "line" : "slot")-\(name)-\(dark ? "dark" : "light")")
          drop.exit()
          controller.close()
        }
      }
    }
  }
}
