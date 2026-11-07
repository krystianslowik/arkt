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
    for window in windows { window.close() }
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

  // MARK: - Checkbox, subtitle and list

  /// A dialog with every kind of text the sheet draws: subtitle, paragraph, a list with its heading, and a checkbox.
  private static let fullContent = DialogContent(
    title: "Remove Quiet Reader?", subtitle: "Added from the Chrome Web Store",
    paragraphs: [.init("Its settings on this Mac are removed too.")], listHeading: "It could read",
    listItems: ["Pages you open", "Your downloads"], primaryTitle: "Remove", cancelTitle: "Cancel",
    isDestructive: true, checkbox: .init("Report abuse"))

  func testASheetsSubtitleListAndCheckboxDrawTheirTokensInDark() throws {
    try assertFullSheet(.dark)
  }

  func testASheetsSubtitleListAndCheckboxDrawTheirTokensInLight() throws {
    try assertFullSheet(.light)
  }

  private func makeAlert(_ content: DialogContent, _ flavor: ThemeFlavor) -> DialogAlert {
    let alert = DialogAlert(content: content)
    alert.panel.isReleasedWhenClosed = false
    alert.panel.appearance = SidebarBannerPopoverView.appearance(for: flavor)
    alert.panel.orderFrontRegardless()
    windows.append(alert.panel)
    alert.panel.display()
    return alert
  }

  private func assertFullSheet(_ flavor: ThemeFlavor, file: StaticString = #filePath, line: UInt = #line) throws {
    let alert = makeAlert(Self.fullContent, flavor)
    let shot = try Shot(alert.container)
    let view = alert.view
    let list = try XCTUnwrap(view.listField, file: file, line: line)
    try shot.assert(try XCTUnwrap(view.subtitleField), drawn: ShellTokens.secondaryText, flavor: flavor, "subtitle",
                    file: file, line: line)
    try shot.assert(try XCTUnwrap(list.headingField), drawn: ShellTokens.secondaryText, flavor: flavor,
                    "list heading", over: ArchiveTokens.listField, file: file, line: line)
    for (index, item) in list.itemFields.enumerated() {
      try shot.assert(item, drawn: ShellTokens.primaryText, flavor: flavor, "list item \(index)",
                      over: ArchiveTokens.listField, file: file, line: line)
    }
    let label = try XCTUnwrap(view.checkboxTitleLabel, file: file, line: line)
    XCTAssertEqual(label.stringValue, "Report abuse", file: file, line: line)
    try shot.assert(label, drawn: ShellTokens.primaryText, flavor: flavor, "checkbox title", file: file, line: line)
  }

  /// The checkbox keeps AppKit's own box, accent and focus ring: only its title moved to a `TokenLabel`. Its box is
  /// drawn pixel for pixel like a plain checkbox's, off and on (the accent fill), and its title still toggles it.
  func testTheCheckboxKeepsAppKitsBoxAccentAndFocusRing() throws {
    for flavor in [ThemeFlavor.light, .dark] {
      for isOn in [false, true] {
        var content = Self.fullContent
        content.checkbox = .init("Report abuse", isOn: isOn)
        let alert = makeAlert(content, flavor)
        let checkbox = try XCTUnwrap(alert.view.checkboxButton)
        XCTAssertTrue(type(of: checkbox) == NSButton.self, "AppKit's checkbox, not a subclass that redraws it")
        XCTAssertEqual(checkbox.title, "Report abuse", "VoiceOver and the click target keep the title")
        XCTAssertEqual(checkbox.accessibilityLabel(), "Report abuse")
        XCTAssertNotEqual(checkbox.focusRingType, .none)
        XCTAssertFalse(try XCTUnwrap(alert.view.checkboxTitleLabel).isAccessibilityElement())

        let reference = NSButton(checkboxWithTitle: "Report abuse", target: nil, action: nil)
        reference.font = .systemFont(ofSize: 13)
        reference.state = isOn ? .on : .off
        reference.frame = checkbox.frame
        let host = try XCTUnwrap(alert.panel.contentView)
        host.addSubview(reference, positioned: .below, relativeTo: nil)
        defer { reference.removeFromSuperview() }
        XCTAssertEqual(checkbox.focusRingMaskBounds, reference.focusRingMaskBounds, "the same focus ring")
        let box = NSRect(x: 0, y: 0, width: checkbox.frame.height, height: checkbox.frame.height)
        let drawn = try Shot(checkbox)
        let plain = try Shot(reference)
        let difference = drawn.largestDifference(from: plain, in: box)
        XCTAssertLessThanOrEqual(difference, 2, "\(flavor) \(isOn ? "on" : "off"): the box as AppKit draws it")

        // The title's text starts where the plain checkbox draws its own, within a point.
        let labelInk = try XCTUnwrap(try Shot(title(alert)).inkOrigin(after: 0))
        let plainInk = try XCTUnwrap(plain.inkOrigin(after: box.width))
        let labelOffset = NSPoint(x: try title(alert).frame.minX - checkbox.frame.minX,
                                  y: try title(alert).frame.minY - checkbox.frame.minY)
        XCTAssertEqual(labelInk.x + labelOffset.x, plainInk.x, accuracy: 1, "\(flavor): the title's leading edge")
        XCTAssertEqual(labelInk.y + labelOffset.y, plainInk.y, accuracy: 1, "\(flavor): the title's top")
        let labelEnd = try XCTUnwrap(try Shot(title(alert)).inkEnd()) + labelOffset.x
        let plainEnd = try XCTUnwrap(plain.inkEnd())
        XCTAssertEqual(labelEnd, plainEnd, accuracy: 0.5, "\(flavor): the whole title shows, not clipped")

        // A click on the title lands on the checkbox, as before.
        let title = try XCTUnwrap(alert.view.checkboxTitleLabel)
        let point = alert.view.convert(NSPoint(x: title.frame.midX, y: title.frame.midY), to: alert.view.superview)
        XCTAssertTrue(alert.view.hitTest(point) === checkbox, "a click on the title toggles the box")
        XCTAssertTrue(alert.panel.makeFirstResponder(checkbox), "the box takes keyboard focus")
      }
    }
  }

  private func title(_ alert: DialogAlert) throws -> TokenLabel {
    try XCTUnwrap(alert.view.checkboxTitleLabel)
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
      let full = makeAlert(Self.fullContent, flavor)
      try Shot(full.container).write(to: folder.appendingPathComponent("checkbox-list-\(suffix).png"))
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
  func expectedLevel(_ token: TokenPair, flavor: ThemeFlavor, over underlay: TokenPair? = nil) throws -> Int {
    let swatch = try XCTUnwrap(Self.rep(size: NSSize(width: 4, height: 4), scale: scale))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: swatch))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    AlertTokens.dialogSurface.resolve(flavor).nsColor().setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    if let underlay {
      underlay.resolve(flavor).nsColor().setFill()
      NSRect(x: 0, y: 0, width: 4, height: 4).fill(using: .sourceOver)
    }
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

  func assert(_ view: NSView, drawn token: TokenPair, flavor: ThemeFlavor, _ name: String, over underlay: TokenPair? = nil,
              file: StaticString, line: UInt) throws {
    let expected = try expectedLevel(token, flavor: flavor, over: underlay)
    let drawn = try drawnLevel(of: view, flavor: flavor)
    XCTAssertLessThanOrEqual(abs(drawn - expected), DialogLabelColorTestsTolerance.levels,
                             "\(name) in \(flavor): drawn \(drawn), token \(expected)", file: file, line: line)
  }

  /// The largest per-channel difference (0 to 255) from `other` inside `rect` (points, top-left origin).
  func largestDifference(from other: Shot, in rect: NSRect) -> Int {
    var largest = 0
    let minX = Int(rect.minX * scale), maxX = min(rep.pixelsWide, other.rep.pixelsWide, Int(rect.maxX * scale))
    let minY = Int(rect.minY * scale), maxY = min(rep.pixelsHigh, other.rep.pixelsHigh, Int(rect.maxY * scale))
    for y in minY..<maxY {
      for x in minX..<maxX {
        guard let a = rep.colorAt(x: x, y: y), let b = other.rep.colorAt(x: x, y: y) else { continue }
        for (p, q) in [(a.redComponent, b.redComponent), (a.greenComponent, b.greenComponent),
                       (a.blueComponent, b.blueComponent), (a.alphaComponent, b.alphaComponent)] {
          largest = max(largest, Int((abs(p - q) * 255).rounded()))
        }
      }
    }
    return largest
  }

  /// The top-left of the opaque pixels (text) right of `minX` points, in points from the view's top-left.
  func inkOrigin(after minX: CGFloat) -> NSPoint? {
    var left = Int.max, top = Int.max
    for y in 0..<rep.pixelsHigh {
      for x in Int(minX * scale)..<rep.pixelsWide {
        guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
        left = min(left, x)
        top = min(top, y)
      }
    }
    guard left != .max else { return nil }
    return NSPoint(x: CGFloat(left) / scale, y: CGFloat(top) / scale)
  }

  /// The right edge of the opaque pixels, in points from the view's leading edge.
  func inkEnd() -> CGFloat? {
    var right = -1
    for y in 0..<rep.pixelsHigh {
      for x in 0..<rep.pixelsWide {
        guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
        right = max(right, x)
      }
    }
    return right < 0 ? nil : CGFloat(right + 1) / scale
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
