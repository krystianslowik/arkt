import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// Sidebar hide and hover reveal in a real window (#102: KB-017, BH-001 to BH-004, BH-006, GS-017, GS-018).
@MainActor
final class SidebarHideTests: XCTestCase {
  var controller: ShellWindowController!
  var root: ShellRootView { controller.rootView }
  var overlay: SidebarOverlayView { controller.rootView.sidebarOverlay }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    controller.showWindow(nil)               // the reveal spring runs on the window's display link
    root.layoutSubtreeIfNeeded()
    // Tests drive the pointer through the overlay's seams; the real pointer never decides anything here.
    overlay.revealDelay = .zero
    overlay.concealDelay = .zero
    overlay.pointerIsInside = { false }
    overlay.mouseButtonsDown = { false }
  }

  override func tearDown() async throws { controller.close() }

  private func menuItem() -> NSMenuItem {
    NSMenuItem(title: "Hide Sidebar", action: #selector(ShellWindowController.toggleSidebar(_:)), keyEquivalent: "s")
  }

  private func waitForSettle(_ what: String, _ body: () -> Void) async {
    let settled = expectation(description: what)
    overlay.onSettleForTesting = { _ in settled.fulfill() }
    body()
    await fulfillment(of: [settled], timeout: 3)
    overlay.onSettleForTesting = nil
  }

  // MARK: Cmd-S (KB-017, BH-001)

  func testToggleHidesTheSidebarAndTheCardTakesTheFullWidth() throws {
    XCTAssertTrue(controller.isSidebarVisible)
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(controller.isSidebarVisible)
    XCTAssertEqual(root.card.frame, CGRect(x: 10, y: 10, width: 1180, height: 780))
    XCTAssertTrue(overlay.isHidden, "concealed: nothing drawn, hit or exposed to accessibility")
    XCTAssertEqual(root.effectiveSidebarWidth, 0)
    XCTAssertEqual(root.sidebarContainer.frame.width, 190, "the sidebar keeps its width: no row relayout")

    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertEqual(root.card.frame.minX, 190)
    XCTAssertFalse(overlay.isHidden)
    XCTAssertEqual(overlay.frame, CGRect(x: 0, y: 0, width: 190, height: 800))
  }

  func testMenuItemIsTitledForTheState() {
    let item = menuItem()
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Hide Sidebar")
    controller.toggleSidebar(item)
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Show Sidebar")
  }

  func testToggleDoesNotAnimate() {
    controller.toggleSidebar(nil)
    XCTAssertFalse(overlay.isAnimating, "a keyboard toggle is instant")
    controller.toggleSidebar(nil)
    XCTAssertFalse(overlay.isAnimating)
    XCTAssertTrue(overlay.layer?.affineTransform().isIdentity ?? false)
  }

  func testHiddenStateIsPerWindow() throws {
    let other = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    defer { other.close() }
    controller.toggleSidebar(nil)
    XCTAssertFalse(controller.isSidebarVisible)
    XCTAssertTrue(other.isSidebarVisible, "each window keeps its own sidebar state")
  }

  // MARK: Edge gestures (BH-002, BH-003, GS-017)

  func testDraggingTheEdgeFullyLeftHidesAndDraggingBackShows() throws {
    let handle = root.resizeHandle
    handle.onWidthChange?(120)
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertEqual(root.sidebarWidth, ShellMetrics.standard.sidebarMinWidth)
    handle.onWidthChange?(20)
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(controller.isSidebarVisible, "fully left hides (BH-002)")
    XCTAssertEqual(root.card.frame.minX, 10)
    // Still in the same drag: back to the right brings it back.
    handle.onWidthChange?(260)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertEqual(root.sidebarWidth, 260)
  }

  func testDoubleClickOnTheEdgeResetsTheWidth() throws {
    root.sidebarWidth = 320
    root.layoutSubtreeIfNeeded()
    let handle = root.resizeHandle
    let window = try XCTUnwrap(controller.window)
    let point = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
    handle.mouseDown(with: event)
    XCTAssertEqual(root.sidebarWidth, ShellMetrics.standard.sidebarDefaultWidth, "BH-003")
  }

  // MARK: Hover reveal (BH-004, GS-018)

  func testPointerAtTheLeftEdgeRevealsAnOverlayAboveTheContent() async throws {
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    await waitForSettle("revealed") { self.root.pointerReachedRevealEdge() }
    XCTAssertTrue(overlay.isRevealed)
    XCTAssertFalse(overlay.isHidden)
    XCTAssertEqual(root.card.frame.minX, 10, "an overlay: the content does not move")
    let inset = ShellMetrics.standard.sidebarOverlayInset
    XCTAssertEqual(overlay.frame, CGRect(x: inset, y: inset, width: 190, height: 800 - 2 * inset))
    XCTAssertTrue(overlay.layer?.affineTransform().isIdentity ?? false)
    XCTAssertEqual(overlay.alphaValue, 1)
    // Drawn and hit above the card.
    let subviews = root.subviews
    let index = { (view: NSView) in subviews.firstIndex { $0 === view } ?? -1 }
    XCTAssertGreaterThan(index(overlay), index(root.card))
    XCTAssertGreaterThan(index(overlay), index(root.split))
    let hit = try XCTUnwrap(root.hitTest(NSPoint(x: inset + 100, y: 400)))
    XCTAssertTrue(hit.isDescendant(of: overlay), "a click on the overlay reaches the sidebar, not the page")
  }

  func testOverlayHidesWhenThePointerLeaves() async throws {
    controller.toggleSidebar(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    await waitForSettle("concealed") { self.overlay.pointerLeft() }
    XCTAssertFalse(overlay.isRevealed)
    XCTAssertTrue(overlay.isHidden)
    XCTAssertFalse(controller.isSidebarVisible, "still hidden, only the overlay went away")
  }

  func testOverlayStaysWhileTheButtonIsHeldOrThePointerCameBack() async throws {
    controller.toggleSidebar(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    overlay.mouseButtonsDown = { true }
    overlay.pointerLeft()
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(overlay.isRevealed, "a drag out of the overlay keeps it")
    overlay.mouseButtonsDown = { false }
    overlay.pointerIsInside = { true }
    overlay.pointerLeft()
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(overlay.isRevealed, "the pointer is back inside")
  }

  func testEdgeIsIgnoredWhileTheSidebarIsVisibleOrAButtonIsHeld() async throws {
    root.pointerReachedRevealEdge()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(overlay.isRevealed)
    controller.toggleSidebar(nil)
    overlay.mouseButtonsDown = { true }       // the edge drag that hid it is still going
    root.pointerReachedRevealEdge()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(overlay.isRevealed)
  }

  func testLeavingTheEdgeBeforeTheDelayCancelsTheReveal() async throws {
    controller.toggleSidebar(nil)
    overlay.revealDelay = .milliseconds(80)
    root.pointerReachedRevealEdge()
    root.pointerLeftRevealEdge()
    try await Task.sleep(for: .milliseconds(160))
    XCTAssertFalse(overlay.isRevealed)
    XCTAssertTrue(overlay.isHidden)
  }

  func testRevealIsInterruptibleWithoutAJump() async throws {
    controller.toggleSidebar(nil)
    overlay.reduceMotionForTesting = false
    overlay.reveal()
    // Let a few frames run, then turn around mid-flight.
    let deadline = Date().addingTimeInterval(1)
    while overlay.offsetForTesting < -150, Date() < deadline { try await Task.sleep(for: .milliseconds(2)) }
    let before = overlay.offsetForTesting
    overlay.conceal()
    XCTAssertEqual(overlay.offsetForTesting, before, accuracy: 0.001, "the conceal starts where the reveal was")
    XCTAssertTrue(overlay.isAnimating)
    await waitForSettle("concealed") {}
    XCTAssertTrue(overlay.isHidden)
  }

  func testReduceMotionFadesInPlace() async throws {
    controller.toggleSidebar(nil)
    overlay.reduceMotionForTesting = true
    overlay.reveal()
    XCTAssertEqual(overlay.layer?.affineTransform().tx ?? -1, 0, "no slide under Reduce Motion")
    XCTAssertLessThan(overlay.alphaValue, 1)
    await waitForSettle("revealed") {}
    XCTAssertEqual(overlay.alphaValue, 1)
    XCTAssertTrue(overlay.layer?.affineTransform().isIdentity ?? false)
  }

  func testCmdSWhileRevealedDocksAtOnce() async throws {
    controller.toggleSidebar(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertFalse(overlay.isAnimating)
    XCTAssertEqual(overlay.frame, CGRect(x: 0, y: 0, width: 190, height: 800))
    XCTAssertEqual(overlay.alphaValue, 1)
  }

  func testTrafficLightsHideWithTheSidebarAndComeBackWithTheOverlay() async throws {
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(close.isHidden, "no traffic lights over the page")
    await waitForSettle("revealed") { self.overlay.reveal() }
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(close.isHidden)
    XCTAssertEqual(close.alphaValue, 1)
    let inWindow = close.convert(close.bounds, to: nil)
    let inset = ShellMetrics.standard.sidebarOverlayInset
    XCTAssertEqual(inWindow.minX, inset + 12, accuracy: 0.5, "inside the overlay, where they sit in the sidebar")
    XCTAssertEqual(window.frame.height - inWindow.maxY, inset + 16, accuracy: 0.5)
  }

  func testHiddenSidebarLeavesThePageTopLeftCornerClickable() throws {
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    let frameView = try XCTUnwrap(root.superview)              // NSThemeFrame, hosts the titlebar container too
    let pointInWindow = NSPoint(x: 30, y: window.frame.height - 24)   // where the close button sits when docked
    let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(pointInWindow, from: nil)))
    XCTAssertTrue(hit.isDescendant(of: root.card), "got \(hit)")
  }

  func testOverlayFollowsTheSpaceThemeAndHasItsOwnChrome() async throws {
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertEqual(overlay.backdrop.themes, root.themeBackground.themes)
    root.themeBackground.setPosition(1)
    XCTAssertEqual(overlay.backdrop.position, 1, "a Space swipe in the overlay moves its backdrop too")
    await waitForSettle("revealed") { self.overlay.reveal() }
    XCTAssertFalse(overlay.backdrop.isHidden)
    XCTAssertEqual(overlay.clip.layer?.masksToBounds, true)
    XCTAssertEqual(overlay.clip.layer?.cornerRadius, ShellMetrics.standard.cardCornerRadius)
    XCTAssertGreaterThan(overlay.layer?.shadowOpacity ?? 0, 0)
    controller.toggleSidebar(nil)
    XCTAssertTrue(overlay.backdrop.isHidden, "docked, the root's theme shows through as before")
    XCTAssertEqual(overlay.layer?.shadowOpacity, 0)
    XCTAssertEqual(overlay.clip.layer?.cornerRadius, 0)
  }

  // MARK: Toasts while hidden (BH-006)

  func testNewTabWhileHiddenShowsAToastThatShowsTheSidebar() throws {
    controller.toggleSidebar(nil)
    controller.open(try XCTUnwrap(URL(string: "https://example.com/")), inNewTab: true)
    XCTAssertEqual(controller.toasts.current?.text, "New Tab Created")
    XCTAssertNotNil(controller.toasts.current?.actionTitle)
    controller.toasts.performActionForTesting()
    XCTAssertTrue(controller.isSidebarVisible)
  }

  func testNewTabWithTheSidebarVisibleShowsNoToast() throws {
    controller.open(try XCTUnwrap(URL(string: "https://example.com/")), inNewTab: true)
    XCTAssertNil(controller.toasts.current)
  }

  func testNewSpaceWhileHiddenShowsAToastAndOpensNoHiddenRenameField() throws {
    controller.toggleSidebar(nil)
    controller.newSpace(nil)
    XCTAssertEqual(controller.toasts.current?.text, "New Space Created")
    XCTAssertFalse(controller.window?.firstResponder is NSText, "no rename field typed into out of sight")
  }

  // MARK: Frame-time gate (BH-004 reveal overlay)

  func testRevealPacing() async throws {
    try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen)
    controller.toggleSidebar(nil)
    root.layoutSubtreeIfNeeded()
    overlay.reduceMotionForTesting = false
    // Warm the window up the way the pager gate does: a few on-time frames before measuring.
    try await Task.sleep(for: .milliseconds(300))
    var results: [(String, FrameStats)] = []
    for round in 0..<2 {
      await waitForSettle("revealed \(round)") { self.overlay.reveal() }
      results.append(("sidebar-reveal-\(round)", try XCTUnwrap(overlay.lastPacing)))
      await waitForSettle("concealed \(round)") { self.overlay.conceal() }
      results.append(("sidebar-conceal-\(round)", try XCTUnwrap(overlay.lastPacing)))
    }
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let fps = NSScreen.main?.maximumFramesPerSecond ?? 0
    for (label, stats) in results {
      let hitches = stats.intervals.enumerated().filter { $0.element > stats.hitchThreshold }
        .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) }
      let summary = String(
        format: "sidebar.pacing label=%@ screenMaxFPS=%d frames=%d over8.6=%d overBudgetPct=%.2f maxMs=%.2f "
          + "p99Ms=%.2f leadInMs=%.2f load1=%.2f cores=%d asserted=%@ hitchesMs=[%@]",
        label, fps, stats.frameCount, stats.hitchCount, stats.overBudgetRatio * 100, stats.maxInterval * 1000,
        stats.p99 * 1000, (stats.leadInInterval ?? 0) * 1000, load[0], cores, loaded ? "no" : "yes",
        hitches.joined(separator: ","))
      print(summary)
      let attachment = XCTAttachment(string: summary)
      attachment.name = "sidebar.pacing.\(label)"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertGreaterThan(stats.frameCount, 10, "\(label): the display link ran (is the display awake?)")
      if loaded {
        print("sidebar.pacing skipped assert: 1-minute load \(load[0]) >= \(cores) active cores")
      } else {
        XCTAssertEqual(stats.hitchCount, 0, "\(label): frames over 8.6 ms")
      }
    }
  }
}
