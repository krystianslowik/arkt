import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// The hybrid command bar's window-level behavior (#371, design/command-bar/README.md): the scrim, light and dark,
/// Reduce Transparency, the selection indicator, the pills, the hint strip, the Esc key cap and the accessibility
/// tree. Nothing here waits on a clock.
@MainActor
final class CommandBarHybridTests: XCTestCase {
  var shell: ShellWindowController!
  var bar: CommandBarController!
  var window: NSWindow!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
    bar.settings.dismissSearchSuggestionNotice()
    bar.prewarm()
  }

  override func tearDown() async throws {
    bar.invalidate()
    shell.close()
  }

  private func tabs(_ count: Int) -> [CommandBarResults.OpenTab] {
    (1...count).map { .init(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).example/path")!) }
  }

  private func showWithTabs(_ count: Int = 3, query: String = "") {
    bar.openTabsProvider = { [self] in tabs(count) }
    bar.toggle(.newTab)
    if !query.isEmpty { bar.setQueryForTesting(query) }
    bar.barView.layoutSubtreeIfNeeded()
  }

  private func cell(_ row: Int) throws -> CommandBarCellView {
    try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? CommandBarCellView)
  }

  // MARK: Scrim

  func testTheScrimDimsTheParentWhileTheBarIsOpen() throws {
    let content = try XCTUnwrap(window.contentView)
    XCTAssertTrue(bar.scrim.superview === content, "laid over the window's content")
    XCTAssertFalse(bar.scrim.isPresented, "hidden until the bar shows")
    XCTAssertNil(bar.scrim.hitTest(NSPoint(x: 100, y: 100)), "clicks reach the window behind it")
    showWithTabs()
    XCTAssertTrue(bar.scrim.isPresented)
    XCTAssertEqual(bar.scrim.frame, content.bounds)
    XCTAssertTrue(content.subviews.last === bar.scrim, "above everything else")
    bar.hide()
    XCTAssertFalse(bar.scrim.isPresented)
  }

  func testTheScrimAddsNoChildWindow() throws {
    showWithTabs()
    XCTAssertEqual(window.childWindows?.count ?? 0, 0, "dialogs and strips own the child windows")
  }

  func testTheScrimFollowsTheParentWhenItResizes() throws {
    showWithTabs()
    window.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 700), display: true)
    XCTAssertEqual(bar.scrim.frame, try XCTUnwrap(window.contentView).bounds)
  }

  func testTheScrimStaysOnTopOfViewsAddedAfterItsPrewarm() throws {
    let content = try XCTUnwrap(window.contentView)
    let late = NSView(frame: content.bounds)
    content.addSubview(late)
    showWithTabs()
    XCTAssertTrue(content.subviews.last === bar.scrim)
    late.removeFromSuperview()
  }

  func testTheScrimIsInvisibleToAccessibility() {
    XCTAssertFalse(bar.scrim.isAccessibilityElement())
    XCTAssertEqual(bar.scrim.accessibilityChildren()?.count, 0)
  }

  // MARK: Light and dark

  func testTheBarFollowsTheWindowIntoLightAndDark() throws {
    for (appearance, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      window.appearance = NSAppearance(named: appearance)
      showWithTabs()
      XCTAssertEqual(bar.flavor, flavor)
      XCTAssertEqual(bar.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), appearance)
      XCTAssertEqual(bar.scrim.fillFlavor, flavor)
      XCTAssertEqual(bar.barView.field.textColor, ShellTokens.commandBarText.resolve(flavor).nsColor())
      let cell = try cell(0)
      XCTAssertEqual(cell.subtitle.textColor, ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor())
      bar.hide()
    }
  }

  func testAppearanceChangeWhileClosedIsPickedUpByTheNextShow() throws {
    window.appearance = NSAppearance(named: .darkAqua)
    showWithTabs()
    bar.hide()
    window.appearance = NSAppearance(named: .aqua)
    showWithTabs()
    XCTAssertEqual(bar.flavor, .light)
    XCTAssertEqual(try cell(0).title.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                   ShellTokens.commandBarText.resolve(.light).nsColor(), "the selected row's title is the strong color")
  }

  // MARK: Reduce Transparency

  func testReduceTransparencyDrawsAnOpaqueSurface() throws {
    bar.barView.reduceTransparency = { true }
    window.appearance = NSAppearance(named: .darkAqua)
    showWithTabs()
    let tintColors = bar.barView.subviews.compactMap { $0.layer?.backgroundColor }
    XCTAssertTrue(tintColors.contains(ShellTokens.commandBarSurfaceOpaque.dark.cgColor),
                  "the opaque surface fill replaces the glass")
    XCTAssertTrue(bar.barView.subviews.contains { ($0 as? NSVisualEffectView)?.isHidden == true },
                  "the blur is dropped")
    bar.hide()
    bar.barView.reduceTransparency = { false }
    showWithTabs()
    XCTAssertTrue(bar.barView.subviews.contains { ($0 as? NSVisualEffectView)?.isHidden == false })
  }

  // MARK: Layout

  func testRowsFieldsAndStripFollowTheReadme() throws {
    showWithTabs(3)
    let v = bar.barView
    XCTAssertEqual(bar.panel.frame.width, 680)
    XCTAssertEqual(v.magnifier.frame.minX, 18)
    XCTAssertEqual(v.magnifier.frame.width, 18)
    XCTAssertEqual(v.field.font?.pointSize, 22)
    XCTAssertEqual(v.table.rowHeight, 40)
    XCTAssertEqual(v.scrollView.frame.minX, 6, "list padding")
    XCTAssertEqual(v.scrollView.frame.width, 680 - 12)
    XCTAssertEqual(v.hintStrip.frame.height, 34)
    XCTAssertEqual(v.hintStrip.frame.maxY, v.bounds.height)
    XCTAssertEqual(v.layer?.cornerRadius, 16)
    XCTAssertEqual(v.pills.frame.height, 26)
    XCTAssertEqual(v.pills.pillFrames.map(\.height), [22, 22, 22, 22])
    XCTAssertEqual(v.escapeKey.frame.height, 18)
    XCTAssertEqual(v.escapeKey.frame.maxX, v.bounds.width - 14, accuracy: 0.5, "Esc is at the right end of the field row")
    XCTAssertLessThan(v.pills.frame.maxX, v.escapeKey.frame.minX)
    XCTAssertLessThanOrEqual(v.field.frame.maxX, v.pills.frame.minX)
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(
      rowCount: bar.results.count, headerCount: 1, maxRows: CommandBarGeometry.maxEmptyStateRows),
      "three recent tabs under one header")
  }

  func testAtMostFiveRowsShowWithoutScrolling() throws {
    showWithTabs(8, query: "Tab")
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: 5))
    XCTAssertGreaterThan(bar.results.count, 5)
  }

  func testTheTopEdgeStaysFixedWhenRowsAreAdded() throws {
    showWithTabs(1)
    let top = bar.panel.frame.maxY
    bar.openTabsProvider = { [self] in tabs(4) }
    bar.setQueryForTesting("Tab")
    XCTAssertEqual(bar.panel.frame.maxY, top, accuracy: 0.5)
  }

  func testWorstCaseTitlesAndURLsNeverOverlapTheTrailingGroup() throws {
    let long = String(repeating: "A very long page title that never ends ", count: 8)
    bar.openTabsProvider = {
      [.init(node: UUID(), title: long, url: URL(string: "https://example.com/" + String(repeating: "segment/", count: 40))!),
       .init(node: UUID(), title: "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{30BF}\u{30A4}\u{30C8}\u{30EB} \u{1F600}",
             url: URL(string: "https://xn--wgv71a.example")!)]
    }
    bar.toggle(.newTab)
    bar.barView.layoutSubtreeIfNeeded()
    for row in 0..<2 {
      let cell = try cell(row)
      cell.layoutSubtreeIfNeeded()
      XCTAssertLessThanOrEqual(cell.title.frame.maxX, cell.hint.frame.minX, "row \(row)")
      XCTAssertLessThanOrEqual(cell.subtitle.frame.maxX, cell.hint.frame.minX, "row \(row)")
      XCTAssertLessThanOrEqual(cell.hint.frame.maxX, cell.bounds.width - 12 + 0.5)
    }
  }

  // MARK: Selection indicator

  func testTheIndicatorSitsOnTheSelectedRowAndMovesWithIt() throws {
    showWithTabs(3)
    let table = bar.barView.table
    let indicator = bar.barView.selectionIndicator
    XCTAssertFalse(indicator.isHidden)
    XCTAssertEqual(indicator.frame, bar.barView.selectionRect(ofRow: 0))
    XCTAssertEqual(indicator.frame.height, 40)
    table.selectRowIndexes([2], byExtendingSelection: false)
    XCTAssertEqual(indicator.frame, table.rect(ofRow: 2))
  }

  func testTheIndicatorSitsBehindTheRowsAndIsNotAHitTarget() throws {
    showWithTabs(3)
    let table = bar.barView.table
    XCTAssertEqual(table.subviews.first, bar.barView.selectionIndicator, "behind every row")
    let point = NSPoint(x: 100, y: table.rect(ofRow: 0).midY)
    XCTAssertTrue(table.hitTest(table.convert(point, to: table.superview)) !== bar.barView.selectionIndicator)
  }

  func testTheIndicatorHidesWithNoResults() throws {
    bar.toggle(.currentTab(nil))
    XCTAssertTrue(bar.results.isEmpty)
    XCTAssertTrue(bar.barView.selectionIndicator.isHidden)
  }

  func testTheTickIsAThreePointMustardFillInsetTenFromTopAndBottom() {
    let frames = CommandBarSelectionIndicator.layerFrames(rowSize: NSSize(width: 668, height: 40))
    XCTAssertEqual(frames.tick, NSRect(x: 0, y: 10, width: 3, height: 20))
    XCTAssertEqual(frames.fill, NSRect(x: 0, y: 0, width: 668, height: 40))
    XCTAssertEqual(ShellTokens.commandBarTick.light, BrandTokens.Palette.mustard)
    XCTAssertEqual(ShellTokens.commandBarTick.dark, BrandTokens.Palette.mustard)
  }

  func testTheSelectedRowShowsReturnAndTheOthersDoNot() throws {
    showWithTabs(3)
    XCTAssertEqual(try cell(0).visibleKeyCaps, [CommandBarKeyCaps.return])
    XCTAssertEqual(try cell(1).visibleKeyCaps, [])
    bar.barView.table.selectRowIndexes([1], byExtendingSelection: false)
    XCTAssertEqual(try cell(0).visibleKeyCaps, [])
    XCTAssertEqual(try cell(1).visibleKeyCaps, [CommandBarKeyCaps.return])
  }

  // MARK: Pills and hint strip

  func testPillsShowCountsForAQueryAndHideThemForAnEmptyOne() throws {
    showWithTabs(3)
    XCTAssertFalse(bar.barView.pills.showsCounts, "empty query: counts hidden")
    XCTAssertEqual(bar.barView.pills.selected, .all, "All is the default on every open")
    bar.setQueryForTesting("Tab")
    XCTAssertTrue(bar.barView.pills.showsCounts)
    XCTAssertEqual(bar.barView.pills.counts[.tabs], 3)
    XCTAssertEqual(bar.barView.pills.counts[.all], bar.results.count)
    XCTAssertEqual(bar.barView.pills.counts[.actions], 0)
  }

  func testTheHintStripShowsTheEmptyStateLineOnlyForAnEmptyQuery() throws {
    showWithTabs(3)
    XCTAssertEqual(bar.barView.hintStrip.hints.trailing?.text, "Type a URL, a search, or a command")
    XCTAssertEqual(bar.barView.hintStrip.hints.items.map(\.caption), ["Move", "Open", "Filter", "Actions"],
                   "an empty new-tab bar: Tab enters action search")
    bar.setQueryForTesting("Tab")
    XCTAssertEqual(bar.barView.hintStrip.hints.trailing?.text, "Paste and Go")
    XCTAssertEqual(bar.barView.hintStrip.hints.items.map(\.caption), ["Move", "Filter"])
  }

  func testTheEscKeyCapClosesTheBar() throws {
    showWithTabs(3)
    bar.barView.escapeKey.onClick?()
    XCTAssertFalse(bar.isVisible)
  }

  func testTheFieldPlaceholderIsTheDesignsCopy() {
    XCTAssertEqual(bar.barView.field.placeholderAttributedString?.string, "Search or enter address")
  }

  // MARK: Accessibility

  func testTheBarIsADialogGroupLabelledCommandBar() {
    XCTAssertEqual(bar.barView.accessibilityLabel(), "Command bar")
    XCTAssertEqual(bar.barView.accessibilityRole(), .group)
    XCTAssertEqual(bar.barView.accessibilityIdentifier(), AXID.CommandBar.root)
  }

  func testRowsReadTitleHostKindAndPosition() throws {
    showWithTabs(3)
    let content = try XCTUnwrap(bar.barView.table.axProxyRows.content?(1))
    XCTAssertEqual(content.label, "Tab 2, t2.example, open tab, 2 of 3")
    XCTAssertEqual(content.value, "Switch to Tab")
    XCTAssertEqual(try cell(2).accessibilityLabel(), "Tab 3, t3.example, open tab, 3 of 3")
  }

  func testPillsAnnounceNameAndCount() throws {
    showWithTabs(3, query: "Tab")
    let pills = bar.barView.pills
    XCTAssertEqual(pills.accessibilityRole(), .tabGroup)
    XCTAssertEqual(pills.accessibilityIdentifier(), AXID.CommandBar.filters)
    let labels = pills.subviews.map { $0.accessibilityLabel() ?? "" }
    XCTAssertEqual(labels, ["All, 4 results, selected", "Tabs, 3 results", "History, 0 results", "Actions, 0 results"])
    XCTAssertEqual(pills.subviews.map { $0.accessibilityIdentifier() },
                   ["commandBar.filter.all", "commandBar.filter.tabs", "commandBar.filter.history",
                    "commandBar.filter.actions"])
    bar.setQueryForTesting("")
    XCTAssertEqual(pills.subviews.first?.accessibilityLabel(), "All, selected", "no counts for an empty query")
  }

  func testHintStripAndEscKeyHaveIdentifiers() throws {
    showWithTabs(3)
    XCTAssertEqual(bar.barView.hintStrip.accessibilityIdentifier(), AXID.CommandBar.hints)
    XCTAssertEqual(bar.barView.escapeKey.accessibilityIdentifier(), AXID.CommandBar.escape)
    XCTAssertEqual(bar.barView.escapeKey.accessibilityLabel(), "Close")
    XCTAssertTrue(bar.barView.escapeKey.isAccessibilityElement())
  }

  func testNoAccessibilityStringSaysArc() throws {
    showWithTabs(3)
    var strings: [String] = [bar.barView.accessibilityLabel() ?? "", bar.barView.hintStrip.spokenText]
    strings += bar.barView.pills.subviews.compactMap { $0.accessibilityLabel() }
    for string in strings { XCTAssertFalse(string.localizedCaseInsensitiveContains("arc "), string) }
  }

  // MARK: Rendering

  /// The tick is drawn in mustard (a fill), in both appearances.
  func testTheTickRendersInMustardInLightAndDark() throws {
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = NSAppearance(named: name)
      showWithTabs(3)
      let view = bar.barView
      view.layoutSubtreeIfNeeded()
      view.displayIfNeeded()
      let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: rep)
      let row = view.convert(view.selectionRect(ofRow: 0), from: view.table)
      let scale = CGFloat(rep.pixelsWide) / view.bounds.width
      let x = Int((row.minX + 1) * scale)
      let y = Int(row.midY * scale)
      Self.writeSnapshot(rep, named: "bar-\(name == .aqua ? "light" : "dark")")
      let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
      // Mustard (#E9B520) as the offscreen render reads it: the color-managed copy is a little lighter in blue, so
      // the check is the hue, not the exact value.
      XCTAssertGreaterThan(color.redComponent, 0.8, "\(name)")
      XCTAssertTrue((0.6...0.85).contains(color.greenComponent), "\(name)")
      XCTAssertLessThan(color.blueComponent, 0.4, "\(name)")
      bar.hide()
    }
  }

  /// With `ARKT_COMMAND_BAR_SNAPSHOT_DIR` set, writes the render there (for the pull request's screenshots).
  static func writeSnapshot(_ rep: NSBitmapImageRep, named name: String) {
    guard let dir = ProcessInfo.processInfo.environment["ARKT_COMMAND_BAR_SNAPSHOT_DIR"],
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
  }
}
