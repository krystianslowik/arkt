import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The page info panel (#582) from a split pane's own Toolbar (#698): each pane card's Toolbar shows its pane's site
/// glyph and reads its security state to VoiceOver; the glyph focuses that pane and opens the window's one panel for
/// its tab, below that Toolbar's glyph. Focusing another pane, leaving the split, the pane moving to another card and
/// hiding the Toolbar close it. No synthetic input: presses go through the bars' handlers.
@MainActor
final class SplitPageInfoTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController

    init(_ sidebar: SidebarModel.Sidebar, width: CGFloat = 1200) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitPageInfoTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source, toolbarSetting: .ephemeral())
      controller.showWindow(nil)
      // After showing: showing constrains the frame to the screen, which is small on a CI runner.
      controller.window?.setFrame(NSRect(x: 100, y: 100, width: width, height: 800), display: false)
      controller.rootView.split.reduceMotion = { true }
      controller.rootView.reduceMotion = { true }
      controller.pageInfo.reduceMotion = { true }         // a hide takes the panel down at once
      controller.pageInfo.increaseContrast = { false }
      controller.pageInfo.deniedInMacOS = { [:] }        // never the host's real location state (#856)
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: SplitPageInfoTests.now) }
      controller.toolbarSetting.isVisible = true
      layout()
    }

    var split: SplitContainerView { controller.rootView.split }
    var panel: PageInfoPanelController { controller.pageInfo }
    func bar(_ index: Int) -> URLBarView { split.paneCards[index].toolbar.urlBar }
    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
    func layout() { controller.window?.contentView?.layoutSubtreeIfNeeded() }

    /// Lets the re-show the source change queued run, so a test sees the state it settles in.
    func settleResync() {
      waitUntil("the split re-show ran") { !controller.splitState.resyncPending }
      layout()
    }

    func close() {
      panel.hide(keyboard: true)
      controller.close()
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// Today `[t0, split(panes)]`, one pane per address.
  private static func makeWorld(_ addresses: [String]) throws
    -> (sidebar: SidebarModel.Sidebar, other: UUID, panes: [UUID]) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let other = try sidebar.addTab(url: try XCTUnwrap(URL(string: "https://example.com/t0")), title: "T0",
                                   in: .today(space))
    let factors = Array(repeating: 1 / Double(addresses.count), count: addresses.count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors, in: .today(space))
    let panes = try addresses.enumerated().map { index, address in
      try sidebar.addTab(url: try XCTUnwrap(URL(string: address)), title: "S\(index)", in: .split(split))
    }
    return (sidebar, other, panes)
  }

  private static let secure = "https://fieldguide.example/trails"
  private static let insecure = "http://old-mirror.fieldguide.example/"
  private static let internalPage = "chrome://settings/"

  // MARK: The pane glyphs

  /// Each pane Toolbar shows its own pane's glyph, its VoiceOver state and the Show Site Controls action; a page of the
  /// browser itself leaves its pane's bar inert.
  func testEachPaneToolbarShowsItsOwnPanesGlyphAndVoiceOverState() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure, Self.internalPage])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.layout()

    XCTAssertEqual(harness.bar(0).siteSymbol, "lock")
    XCTAssertEqual(harness.bar(1).siteSymbol, "exclamationmark.triangle", "the other pane's own page, not the focus")
    XCTAssertNil(harness.bar(2).siteSymbol, "the browser's own pages leave the pane's bar inert")
    XCTAssertFalse(harness.bar(1).siteGlyph.isHidden)
    XCTAssertTrue(harness.bar(2).siteGlyph.isHidden)

    XCTAssertEqual(harness.bar(1).siteDescription, "Not secure")
    let value = try XCTUnwrap(harness.bar(1).accessibilityValue() as? String)
    XCTAssertTrue(value.hasPrefix("Not secure, "), "VoiceOver reads the state before the address: \(value)")
    XCTAssertEqual(harness.bar(1).accessibilityCustomActions()?.map(\.name), ["Show Site Controls"])
    XCTAssertNil(harness.bar(2).accessibilityCustomActions())
    harness.close()
  }

  /// A change of a pane's page info that is not focused (mixed content, a certificate error) reaches its own glyph.
  func testAnUnfocusedPanesGlyphFollowsTheEngine() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let right = try XCTUnwrap(harness.tab(world.panes[1]))

    harness.engine.setConnection(right, .notFullySecure)

    XCTAssertEqual(harness.bar(1).siteSymbol, "exclamationmark.triangle")
    XCTAssertEqual(harness.bar(0).siteSymbol, "lock")
    harness.close()
  }

  // MARK: Opening

  /// The glyph of a pane that is not focused focuses it and opens the panel for its tab below that Toolbar's glyph.
  func testAPaneGlyphFocusesItsPaneAndOpensThePanelBelowThatToolbar() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    let right = try XCTUnwrap(harness.tab(world.panes[1]))
    let bar = harness.bar(1)

    bar.onPressSiteGlyph?()

    XCTAssertEqual(harness.controller.currentTab, right, "the pane is focused first, as its other buttons do")
    XCTAssertTrue(harness.panel.isShown)
    XCTAssertEqual(harness.panel.tab, right)
    let window = try XCTUnwrap(harness.panel.panel)
    XCTAssertEqual(window.accessibilityLabel(), "Site controls for old-mirror.fieldguide.example")
    XCTAssertTrue(window.parent === harness.controller.window)
    harness.layout()
    let parent = try XCTUnwrap(bar.window)
    let barRect = parent.convertToScreen(bar.convert(bar.bounds, to: nil))
    let glyph = parent.convertToScreen(bar.convert(bar.siteGlyph.frame, to: nil))
    XCTAssertEqual(window.frame.maxY, barRect.minY - PageInfoMetrics.gap, accuracy: 0.5, "below that Toolbar")
    // Under its glyph, as the main Toolbar's panel, unless the window's trailing edge holds it back (a runner's small
    // screen shrinks the window).
    let wanted = glyph.minX - PageInfoMetrics.sideInset
    let rightmost = parent.frame.maxX - PageInfoMetrics.windowMargin - window.frame.width
    XCTAssertEqual(window.frame.minX, min(wanted, rightmost), accuracy: 0.5, "under its glyph, inside the window")
    XCTAssertLessThanOrEqual(window.frame.minX, glyph.minX, "the panel spans its glyph")
    XCTAssertGreaterThanOrEqual(window.frame.maxX, glyph.maxX)
    if wanted <= rightmost {
      let left = harness.bar(0)
      let leftRect = parent.convertToScreen(left.convert(left.bounds, to: nil))
      XCTAssertGreaterThan(window.frame.minX, leftRect.maxX, "not under the other pane's Toolbar")
    }
    harness.close()
  }

  /// The smallest window: the panel under a trailing pane's glyph stays inside the window and still spans the glyph.
  func testInANarrowWindowThePanelStaysInsideAndSpansThePanesGlyph() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure])
    let harness = Harness(world.sidebar, width: 760)
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    let bar = harness.bar(1)

    bar.onPressSiteGlyph?()

    let window = try XCTUnwrap(harness.panel.panel)
    harness.layout()
    let parent = try XCTUnwrap(bar.window)
    let glyph = parent.convertToScreen(bar.convert(bar.siteGlyph.frame, to: nil))
    XCTAssertGreaterThan(glyph.minX - PageInfoMetrics.sideInset,
                         parent.frame.maxX - PageInfoMetrics.windowMargin - window.frame.width,
                         "the glyph sits too far right for the panel to start under it: the clamp is what is tested")
    XCTAssertLessThanOrEqual(window.frame.maxX, parent.frame.maxX - PageInfoMetrics.windowMargin + 0.5,
                             "inside the window")
    XCTAssertLessThanOrEqual(window.frame.minX, glyph.minX, "the panel spans its glyph")
    XCTAssertGreaterThanOrEqual(window.frame.maxX, glyph.maxX)
    harness.close()
  }

  /// The same glyph closes it again; an inert pane's glyph opens nothing and leaves the focus alone.
  func testThePaneGlyphTogglesAndAnInertPaneOpensNothing() throws {
    let world = try Self.makeWorld([Self.secure, Self.internalPage])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let left = try XCTUnwrap(harness.tab(world.panes[0]))

    harness.bar(0).onPressSiteGlyph?()
    XCTAssertTrue(harness.panel.isShown)
    harness.bar(0).onPressSiteGlyph?()
    XCTAssertFalse(harness.panel.isShown)

    harness.bar(1).onPressSiteGlyph?()
    XCTAssertFalse(harness.panel.isShown)
    XCTAssertEqual(harness.controller.currentTab, left)
    harness.close()
  }

  /// VoiceOver's Show Site Controls on a pane's bar opens the panel for that pane.
  func testVoiceOverActionOpensThePanelForThatPane() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let action = try XCTUnwrap(harness.bar(1).accessibilityCustomActions()?.first)

    XCTAssertTrue(action.handler?() ?? false)

    XCTAssertEqual(harness.panel.tab, try XCTUnwrap(harness.tab(world.panes[1])))
    harness.close()
  }

  /// A Peek over one wide pane leaves the other panes' Toolbars clickable and in the accessibility tree, but the panel
  /// follows the window's current page, which the Peek's address stands in for: every pane glyph is inert while the
  /// Peek shows, as the main bars are, and comes back when it closes.
  func testPaneGlyphsAreInertWhileAPeekShows() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure])
    let harness = Harness(world.sidebar, width: 1720)      // each pane at least 600 pt: the Peek covers one pane
    let peek = harness.controller.peek
    peek.reduceMotion = { true }
    peek.animator.drivesDisplayLink = false
    peek.linkSettings = { PeekLinkSettings() }
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    let left = try XCTUnwrap(harness.tab(world.panes[0]))
    XCTAssertEqual(harness.bar(1).siteSymbol, "exclamationmark.triangle")

    // Shift-click a link in the left pane: a Peek over that pane (as PeekWindowTests opens one).
    let link = try XCTUnwrap(URL(string: "https://atlas.example/"))
    let decision = harness.engine.simulateLinkActivation(in: left, url: link, modifiers: .shift,
                                                         disposition: .newWindow)
    XCTAssertEqual(decision, .cancel)
    waitUntil("the Peek opens") { peek.session != nil }
    peek.animator.settleNow()
    harness.layout()

    XCTAssertTrue(peek.isOpen)
    let root = harness.controller.rootView
    XCTAssertGreaterThanOrEqual(root.split.paneCards[0].frame.width, PeekLayout.minimumWidth,
                                "the premise: a pane wide enough for a Peek of its own")
    let scrim = try XCTUnwrap(peek.overlay?.scrim.frame)
    let rightBar = root.convert(harness.bar(1).bounds, from: harness.bar(1))
    XCTAssertFalse(scrim.intersects(rightBar), "the scrim leaves the other pane's Toolbar reachable")
    XCTAssertNil(peek.overlay?.hitTest(CGPoint(x: rightBar.midX, y: rightBar.midY)), "clicks reach it")
    XCTAssertNil(harness.bar(0).siteSymbol)
    XCTAssertNil(harness.bar(1).siteSymbol, "the uncovered pane's glyph is inert too")
    XCTAssertNil(harness.bar(1).accessibilityCustomActions(), "no Show Site Controls for VoiceOver")
    harness.bar(1).onPressSiteGlyph?()
    XCTAssertFalse(harness.panel.isShown)

    peek.close(.control)
    peek.animator.settleNow()
    waitUntil("the Peek closes") { !peek.isOpen }

    XCTAssertEqual(harness.bar(0).siteSymbol, "lock")
    XCTAssertEqual(harness.bar(1).siteSymbol, "exclamationmark.triangle", "back when the Peek closes")
    harness.close()
  }

  // MARK: Closing

  /// Focusing another pane closes it.
  func testFocusingAnotherPaneClosesIt() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.bar(0).onPressSiteGlyph?()
    XCTAssertTrue(harness.panel.isShown)

    harness.controller.activate(node: world.panes[1])

    XCTAssertFalse(harness.panel.isShown)
    harness.close()
  }

  /// Opening it from one pane's glyph and then the other's moves it to the other pane.
  func testTheOtherPanesGlyphMovesItThere() throws {
    let world = try Self.makeWorld([Self.secure, Self.insecure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.bar(0).onPressSiteGlyph?()

    harness.bar(1).onPressSiteGlyph?()

    XCTAssertTrue(harness.panel.isShown)
    XCTAssertEqual(harness.panel.tab, try XCTUnwrap(harness.tab(world.panes[1])))
    harness.close()
  }

  /// Leaving the split for a plain tab closes it.
  func testLeavingTheSplitClosesIt() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.bar(0).onPressSiteGlyph?()

    harness.controller.activate(node: world.other)

    XCTAssertFalse(harness.panel.isShown)
    harness.close()
  }

  /// The split ends while its focused pane's page stays current (the other pane closed): the pane Toolbar the panel
  /// hung from is gone, so it closes.
  func testTheSplitEndingUnderTheSameTabClosesIt() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let right = try XCTUnwrap(harness.tab(world.panes[1]))
    harness.bar(1).onPressSiteGlyph?()
    XCTAssertTrue(harness.panel.isShown)

    harness.controller.closePane(at: 0)
    harness.settleResync()

    XCTAssertFalse(harness.controller.rootView.showsSplit, "one pane left: a plain tab")
    XCTAssertEqual(harness.controller.currentTab, right)
    XCTAssertFalse(harness.panel.isShown)
    harness.close()
  }

  /// A pane before it closes and the focused pane moves to another card: the panel hung from the old card's Toolbar,
  /// which now shows another pane, so it closes.
  func testThePaneMovingToAnotherCardClosesIt() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let middle = try XCTUnwrap(harness.tab(world.panes[1]))
    harness.bar(1).onPressSiteGlyph?()
    XCTAssertTrue(harness.panel.isShown)

    harness.controller.closePane(at: 0)
    harness.settleResync()

    XCTAssertEqual(harness.split.paneCount, 2)
    XCTAssertEqual(harness.controller.currentTab, middle)
    XCTAssertFalse(harness.panel.isShown)
    harness.close()
  }

  /// Hiding the Toolbar takes the pane bars away, and the panel with them.
  func testHidingTheToolbarClosesIt() throws {
    let world = try Self.makeWorld([Self.secure, Self.secure])
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.bar(0).onPressSiteGlyph?()
    XCTAssertTrue(harness.panel.isShown)

    harness.controller.toolbarSetting.isVisible = false

    XCTAssertFalse(harness.panel.isShown)
    harness.close()
  }
}
