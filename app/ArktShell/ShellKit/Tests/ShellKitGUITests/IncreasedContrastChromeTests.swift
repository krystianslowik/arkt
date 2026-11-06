import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Increase Contrast for the main window's chrome (#640, design/increase-contrast/README.md): fills stay as they are,
/// each filled state gets a 1 pt `ShellTokens.increasedContrastEdge` as a layer border, and the focused Split View
/// pane a 2 pt ink ring. Each surface follows the setting when the system posts its display-options change, without
/// a relaunch. The setting is injected; the notification is posted in-process, so nothing depends on timing.
@MainActor
final class IncreasedContrastChromeTests: XCTestCase {
  private var windows: [NSWindow] = []
  /// What every injected `increaseContrast` closure reads.
  private var increased = false

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    for window in windows { window.close() }
    windows = []
  }

  private func host(_ view: NSView, size: NSSize = NSSize(width: 240, height: 60),
                    appearance: NSAppearance.Name = .aqua) {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    windows.append(window)
    view.frame = NSRect(origin: .zero, size: size)
    window.contentView = NSView(frame: view.frame)
    window.contentView?.addSubview(view)
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
  }

  /// Turns the setting on or off and posts the system's change, then lets the views draw. A layer-backed view's
  /// `displayIfNeeded` draws its own layer only, so each view that redraws is listed.
  private func setIncreased(_ value: Bool, redrawing views: NSView...) {
    increased = value
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                               object: nil)
    for view in views {
      view.layoutSubtreeIfNeeded()
      view.displayIfNeeded()
    }
  }

  private func assertEdge(_ layer: CALayer, _ flavor: ThemeFlavor, file: StaticString = #filePath,
                          line: UInt = #line) {
    XCTAssertEqual(layer.borderWidth, 1, file: file, line: line)
    XCTAssertEqual(layer.borderColor, ShellTokens.increasedContrastEdge.resolve(flavor).cgColor, file: file, line: line)
  }

  // MARK: Sidebar

  func testAFilledRowGainsTheEdgeLiveAndKeepsItsFillAndSize() {
    let row = SidebarRowView(frame: .zero)
    row.increaseContrast = { [unowned self] in increased }
    row.state = .current
    host(row, size: NSSize(width: 240, height: SidebarMetrics.rowPitch))
    let fill = row.backgroundLayer.backgroundColor
    let frame = row.backgroundLayer.frame
    XCTAssertEqual(row.backgroundLayer.borderWidth, 0)

    setIncreased(true, redrawing: row)
    assertEdge(row.backgroundLayer, .light)
    XCTAssertEqual(row.backgroundLayer.backgroundColor, fill)
    XCTAssertEqual(row.backgroundLayer.frame, frame)

    setIncreased(false, redrawing: row)
    XCTAssertEqual(row.backgroundLayer.borderWidth, 0)
  }

  func testAHoveredRowIsEdgedAndAnUnfilledRowIsNot() {
    let row = SidebarRowView(frame: .zero)
    row.increaseContrast = { [unowned self] in increased }
    row.flavor = .dark
    host(row, size: NSSize(width: 240, height: SidebarMetrics.rowPitch), appearance: .darkAqua)
    setIncreased(true, redrawing: row)
    XCTAssertNil(row.displayedFill)
    XCTAssertEqual(row.backgroundLayer.borderWidth, 0)

    row.isHovered = true
    row.displayIfNeeded()
    XCTAssertEqual(row.displayedFill, ShellTokens.sidebarItemHovered.dark)
    assertEdge(row.backgroundLayer, .dark)
  }

  func testAHoveredRowKeepsTheEdgeWhenPressed() {
    let row = SidebarRowView(frame: .zero)
    row.increaseContrast = { [unowned self] in increased }
    row.state = .previous
    host(row, size: NSSize(width: 240, height: SidebarMetrics.rowPitch))
    setIncreased(true, redrawing: row)
    row.isHovered = true
    row.displayIfNeeded()
    assertEdge(row.backgroundLayer, .light)

    row.isPressed = true
    XCTAssertEqual(row.displayedFill, ShellTokens.tabPressed.light)
    assertEdge(row.backgroundLayer, .light)
    row.displayIfNeeded()
    assertEdge(row.backgroundLayer, .light)
  }

  func testEveryFavoriteTileIsEdged() {
    let tile = FavoriteTileView(frame: .zero)
    tile.increaseContrast = { [unowned self] in increased }
    host(tile, size: NSSize(width: 60, height: 44))
    XCTAssertEqual(tile.fillLayer.borderWidth, 0)
    setIncreased(true, redrawing: tile)
    assertEdge(tile.fillLayer, .light)
    XCTAssertEqual(tile.fillLayer.backgroundColor, ShellTokens.sidebarItemBackground.light.cgColor)
  }

  func testTheSidebarURLBarIsEdgedAndTheToolbarsIsNot() throws {
    let pill = URLBarView(style: .host)
    pill.increaseContrast = { [unowned self] in increased }
    host(pill, size: NSSize(width: 200, height: SidebarMetrics.urlBarHeight))
    setIncreased(true, redrawing: pill)
    assertEdge(try XCTUnwrap(pill.layer), .light)
    setIncreased(false, redrawing: pill)
    XCTAssertEqual(pill.layer?.borderWidth, 0)

    let toolbar = URLBarView(style: .full)
    toolbar.increaseContrast = { true }
    host(toolbar, size: NSSize(width: 200, height: SidebarMetrics.urlBarHeight))
    XCTAssertEqual(toolbar.layer?.borderWidth, 0)
  }

  // MARK: Overlays

  func testTheCommandBarSelectionTradesItsHairlineForTheEdge() throws {
    let indicator = CommandBarSelectionIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
    indicator.increaseContrast = { [unowned self] in increased }
    indicator.flavorForColors = .light
    let fill = try XCTUnwrap(indicator.layer?.sublayers?.first)
    XCTAssertEqual(fill.borderWidth, 0.5)
    XCTAssertEqual(fill.borderColor, ShellTokens.commandBarDivider.light.cgColor)
    setIncreased(true, redrawing: indicator)
    assertEdge(fill, .light)
    XCTAssertEqual(fill.backgroundColor, ShellTokens.commandBarSelectedRow.light.cgColor)
  }

  func testTheTabSwitcherHighlightTakesTheEdgeColor() {
    let panel = TabSwitcherView(frame: .zero)
    panel.increaseContrast = { [unowned self] in increased }
    host(panel, size: NSSize(width: TabSwitcherView.width, height: TabSwitcherView.height(rows: 3)))
    XCTAssertEqual(panel.highlightLayer.borderWidth, 1)
    XCTAssertEqual(panel.highlightLayer.borderColor, ShellTokens.sidebarDivider.light.cgColor)
    setIncreased(true, redrawing: panel)
    assertEdge(panel.highlightLayer, .light)
  }

  func testTheFindBarTradesItsOverlayEdgeForTheEdge() {
    let bar = FindBarView(presenter: FindBarPresenter(engine: InMemoryEngine()))
    bar.increaseContrast = { [unowned self] in increased }
    host(bar, size: NSSize(width: 300, height: 36), appearance: .darkAqua)
    bar.isHidden = false
    XCTAssertEqual(bar.surfaceLayer.borderWidth, 0.5)
    XCTAssertEqual(bar.surfaceLayer.borderColor, ShellTokens.overlayEdge.dark.cgColor)
    setIncreased(true, redrawing: bar)
    assertEdge(bar.surfaceLayer, .dark)
  }

  func testThePeekCardTradesItsHairlineForTheEdge() throws {
    let card = PeekCardView(frame: .zero)
    card.increaseContrast = { [unowned self] in increased }
    host(card, size: NSSize(width: 400, height: 300))
    let surface = try XCTUnwrap(card.surface.layer)
    // One physical pixel: 0.5 pt on a 2x display, 1 pt on a 1x one (CI), so the color tells the two edges apart.
    let scale = try XCTUnwrap(card.window).backingScaleFactor
    XCTAssertEqual(surface.borderWidth, 1 / scale)
    XCTAssertEqual(surface.borderColor, ShellTokens.cardBorder.light.cgColor)
    setIncreased(true, redrawing: card)
    assertEdge(surface, .light)
  }

  // MARK: Split View

  func testOnlyTheFocusedSplitPaneDrawsTheInkRingAndOnlyUnderIncreaseContrast() {
    let container = SplitContainerView()
    host(container, size: NSSize(width: 1010, height: 600))
    container.show(panes: [NSView(), NSView()], axis: .sideBySide, factors: [0.5, 0.5])
    container.focusedIndex = 1
    for card in container.paneCards { card.increaseContrast = { [unowned self] in increased } }
    container.layoutSubtreeIfNeeded()
    container.paneCards.forEach { $0.displayIfNeeded() }
    XCTAssertTrue(container.paneCards.allSatisfy { $0.paneFocusRing.isHidden })

    setIncreased(true, redrawing: container.paneCards[0], container.paneCards[1])
    let focused = container.paneCards[1]
    XCTAssertTrue(container.paneCards[0].paneFocusRing.isHidden)
    XCTAssertFalse(focused.paneFocusRing.isHidden)
    XCTAssertEqual(focused.paneFocusRing.borderWidth, 2)
    XCTAssertEqual(focused.paneFocusRing.borderColor, ShellTokens.splitPaneFocusRing.light.cgColor)
    // Outside the card: the page keeps its frame.
    XCTAssertEqual(focused.paneFocusRing.frame, focused.bounds.insetBy(dx: -2, dy: -2))
    XCTAssertEqual(focused.clipView.frame, focused.bounds)

    container.focusedIndex = 0
    container.paneCards.forEach { $0.displayIfNeeded() }
    XCTAssertFalse(container.paneCards[0].paneFocusRing.isHidden)
    XCTAssertTrue(container.paneCards[1].paneFocusRing.isHidden)

    setIncreased(false, redrawing: container.paneCards[0], container.paneCards[1])
    XCTAssertTrue(container.paneCards.allSatisfy { $0.paneFocusRing.isHidden })
  }

  func testASingleCardNeverDrawsTheRing() {
    let card = ContentCardView()
    card.increaseContrast = { true }
    host(card, size: NSSize(width: 400, height: 300))
    XCTAssertTrue(card.paneFocusRing.isHidden)
  }
}
