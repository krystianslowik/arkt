import AppKit
import XCTest
@testable import ShellUI

/// The text AppKit draws in the sidebar banner's popover and the launch-failure alert lands on `primaryText` and
/// `secondaryText` over the dialog surface, in light and dark (#711). Each label is drawn through `cacheDisplay` at 2x
/// and its most saturated text pixel (the brightest in dark, the darkest in light) is compared with the token filled
/// over the surface in the same kind of bitmap, so color management treats both alike.
@MainActor
final class DialogLabelColorTests: XCTestCase {
  private static let announcement = SidebarNotice.announcement(
    id: "label-color", title: "Archived tabs can now be searched", body: "Open the Archive and type a few words.",
    actionTitle: "Open Archive")

  private var windows: [NSWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for window in windows { window.orderOut(nil) }
    windows = []
  }

  // MARK: - Popover

  func testThePopoversLabelsDrawTheirTokensInDark() throws {
    try assertPopoverLabels(.dark)
  }

  func testThePopoversLabelsDrawTheirTokensInLight() throws {
    try assertPopoverLabels(.light)
  }

  private func assertPopoverLabels(_ flavor: ThemeFlavor, file: StaticString = #filePath, line: UInt = #line) throws {
    let popover = SidebarBannerPopover()
    popover.reduceMotion = { true }
    let row = try anchorRow(flavor)
    popover.show(Self.announcement, beside: row, flavor: flavor, takesKey: false)
    defer { popover.hide() }
    let panel = try XCTUnwrap(popover.panel)
    let container = try XCTUnwrap(panel.contentView)
    let content = try XCTUnwrap(popover.contentView)
    panel.display()
    let shot = try Shot(container)
    try shot.assert(content.titleLabel, drawn: ShellTokens.primaryText, flavor: flavor, "title", file: file, line: line)
    try shot.assert(content.bodyLabel, drawn: ShellTokens.secondaryText, flavor: flavor, "body", file: file, line: line)
    try shot.assert(content.dismissButton, drawn: ShellTokens.secondaryText, flavor: flavor, "Dismiss", file: file,
                    line: line)
  }

  /// A window holding a plain row for the popover to open beside.
  private func anchorRow(_ flavor: ThemeFlavor) throws -> NSView {
    let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 640, height: 480), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = SidebarBannerPopoverView.appearance(for: flavor)
    let row = NSView(frame: NSRect(x: 0, y: 40, width: 220, height: 34))
    try XCTUnwrap(window.contentView).addSubview(row)
    window.orderFrontRegardless()
    windows.append(window)
    return row
  }

  // MARK: - Launch-failure alert

  func testTheLaunchFailureAlertsLabelsDrawTheirTokensInDark() throws {
    try assertAlertLabels(.dark)
  }

  func testTheLaunchFailureAlertsLabelsDrawTheirTokensInLight() throws {
    try assertAlertLabels(.light)
  }

  private func assertAlertLabels(_ flavor: ThemeFlavor, file: StaticString = #filePath, line: UInt = #line) throws {
    let alert = DialogAlert(content: .launchFailure(errorCode: "SQLiteError 11"))
    alert.panel.isReleasedWhenClosed = false
    alert.panel.appearance = SidebarBannerPopoverView.appearance(for: flavor)
    alert.panel.orderFrontRegardless()
    windows.append(alert.panel)
    alert.panel.display()
    let shot = try Shot(alert.container)
    let view = alert.view
    try shot.assert(view.titleField, drawn: ShellTokens.primaryText, flavor: flavor, "title", file: file, line: line)
    XCTAssertEqual(view.paragraphFields.count, 2, file: file, line: line)
    try shot.assert(view.paragraphFields[0], drawn: ShellTokens.primaryText, flavor: flavor, "paragraph", file: file,
                    line: line)
    try shot.assert(view.paragraphFields[1], drawn: ShellTokens.secondaryText, flavor: flavor, "error code",
                    file: file, line: line)
    try shot.assert(try XCTUnwrap(view.footerLinkButton), drawn: ShellTokens.secondaryText, flavor: flavor,
                    "footer link", file: file, line: line)
  }

  // MARK: - Screenshots

  /// 2x shots of both dialogs in light and dark for the pull request, written as `<dialog>-<flavor>.png`. Skipped
  /// unless `ARKT_LABEL_SHOTS_DIR` names a folder.
  func testShots() throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_LABEL_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_LABEL_SHOTS_DIR to write the label screenshots")
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for flavor in [ThemeFlavor.light, .dark] {
      let suffix = flavor == .dark ? "dark" : "light"
      let popover = SidebarBannerPopover()
      popover.reduceMotion = { true }
      popover.show(Self.announcement, beside: try anchorRow(flavor), flavor: flavor, takesKey: false)
      let panel = try XCTUnwrap(popover.panel)
      panel.display()
      try Shot(try XCTUnwrap(panel.contentView)).write(to: folder.appendingPathComponent("popover-\(suffix).png"))
      popover.hide()
      let alert = DialogAlert(content: .launchFailure(errorCode: "SQLiteError 11"))
      alert.panel.isReleasedWhenClosed = false
      alert.panel.appearance = SidebarBannerPopoverView.appearance(for: flavor)
      alert.panel.orderFrontRegardless()
      windows.append(alert.panel)
      alert.panel.display()
      try Shot(alert.container).write(to: folder.appendingPathComponent("launch-failure-\(suffix).png"))
    }
  }
}

// MARK: - Measuring

/// A 2x `cacheDisplay` of a dialog's root view, and the surface the dialog draws on.
@MainActor
private struct Shot {
  let root: NSView
  let rep: NSBitmapImageRep
  let scale: CGFloat

  init(_ root: NSView) throws {
    self.root = root
    scale = 2
    rep = try XCTUnwrap(Self.rep(size: root.bounds.size, scale: scale))
    root.cacheDisplay(in: root.bounds, to: rep)
  }

  static func rep(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                               bitsPerPixel: 0)
    rep?.size = size
    return rep
  }

  /// The token filled over the dialog surface, drawn the way `cacheDisplay` draws: the level its text should reach.
  func expectedLevel(_ token: TokenPair, flavor: ThemeFlavor) throws -> Int {
    let swatch = try XCTUnwrap(Self.rep(size: NSSize(width: 4, height: 4), scale: scale))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: swatch))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    AlertTokens.dialogSurface.resolve(flavor).nsColor().setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    token.resolve(flavor).nsColor().setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill(using: .sourceOver)
    NSGraphicsContext.restoreGraphicsState()
    return try XCTUnwrap(Self.level(swatch, x: 4, y: 4))
  }

  /// The most saturated text level inside `view`: the brightest pixel in dark, the darkest in light.
  func drawnLevel(of view: NSView, flavor: ThemeFlavor) throws -> Int {
    let frame = view.convert(view.bounds, to: root)
    let top = root.isFlipped ? frame.minY : root.bounds.height - frame.maxY
    let minX = max(0, Int((frame.minX * scale).rounded(.down)))
    let maxX = min(rep.pixelsWide, Int((frame.maxX * scale).rounded(.up)))
    let minY = max(0, Int((top * scale).rounded(.down)))
    let maxY = min(rep.pixelsHigh, Int(((top + frame.height) * scale).rounded(.up)))
    XCTAssertLessThan(minX, maxX)
    XCTAssertLessThan(minY, maxY)
    var best = flavor == .dark ? 0 : 255
    for y in minY..<maxY {
      for x in minX..<maxX {
        guard let level = Self.level(rep, x: x, y: y) else { continue }
        best = flavor == .dark ? max(best, level) : min(best, level)
      }
    }
    return best
  }

  func assert(_ view: NSView, drawn token: TokenPair, flavor: ThemeFlavor, _ name: String, file: StaticString,
              line: UInt) throws {
    let expected = try expectedLevel(token, flavor: flavor)
    let drawn = try drawnLevel(of: view, flavor: flavor)
    XCTAssertLessThanOrEqual(abs(drawn - expected), DialogLabelColorTestsTolerance.levels,
                             "\(name) in \(flavor): drawn \(drawn), token \(expected)", file: file, line: line)
  }

  func write(to file: URL) throws {
    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: file)
  }

  /// The green level (the surfaces and text tokens are near-neutral, so one channel stands for the gray level).
  static func level(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Int? {
    guard x < rep.pixelsWide, y < rep.pixelsHigh, let color = rep.colorAt(x: x, y: y) else { return nil }
    return Int((color.greenComponent * 255).rounded())
  }
}

/// Levels (0 to 255) a label's text may differ from its token. The bug drew dark labels 30 to 40 levels brighter.
private enum DialogLabelColorTestsTolerance {
  static let levels = 4
}
