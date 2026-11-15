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
    // A small CI screen can clamp the window: frames below are asserted against the bounds it actually got.
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    controller.showWindow(nil)               // the reveal spring runs on the window's display link
    root.layoutSubtreeIfNeeded()
    // Tests drive the pointer through the overlay's seams; the real pointer never decides anything here.
    overlay.revealDelay = .zero
    overlay.concealDelay = .zero
    overlay.pointerIsInside = { false }
    overlay.mouseButtonsDown = { false }
  }

  // XCTest keeps each test case object until the run ends: release the window too, not only close it (#805).
  override func tearDown() async throws {
    controller.close()
    controller = nil
  }

  private func menuItem() -> NSMenuItem {
    NSMenuItem(title: "Hide Sidebar", action: #selector(ShellWindowController.toggleSidebarVisibility(_:)), keyEquivalent: "s")
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
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(controller.isSidebarVisible)
    XCTAssertEqual(root.card.frame,
                   CGRect(x: 10, y: 10, width: root.bounds.width - 20, height: root.bounds.height - 20))
    XCTAssertTrue(overlay.isHidden, "concealed: nothing drawn, hit or exposed to accessibility")
    XCTAssertEqual(root.effectiveSidebarWidth, 0)
    XCTAssertEqual(root.sidebarContainer.frame.width, 190, "the sidebar keeps its width: no row relayout")

    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertEqual(root.card.frame.minX, 190)
    XCTAssertFalse(overlay.isHidden)
    XCTAssertEqual(overlay.frame, CGRect(x: 0, y: 0, width: 190, height: root.bounds.height))
  }

  func testMenuItemIsTitledForTheState() {
    let item = menuItem()
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Hide Sidebar")
    controller.toggleSidebarVisibility(item)
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Show Sidebar")
  }

  /// The menu item has a nil target: the action must reach this controller through the window's responder chain.
  /// `NSWindow` itself answers `toggleSidebar:` (disabled), which is why the action has its own name.
  func testMenuActionReachesTheControllerThroughTheResponderChain() throws {
    let window = try XCTUnwrap(controller.window)
    let action = #selector(ShellWindowController.toggleSidebarVisibility(_:))
    XCTAssertFalse(NSWindow.instancesRespond(to: action), "the window must not take the action first")
    XCTAssertTrue(window.tryToPerform(action, with: nil))
    XCTAssertFalse(controller.isSidebarVisible)
  }

  func testToggleDoesNotAnimate() {
    controller.toggleSidebarVisibility(nil)
    XCTAssertFalse(overlay.isAnimating, "a keyboard toggle is instant")
    controller.toggleSidebarVisibility(nil)
    XCTAssertFalse(overlay.isAnimating)
    XCTAssertTrue(overlay.layer?.affineTransform().isIdentity ?? false)
  }

  func testHiddenStateIsPerWindow() throws {
    let other = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    defer { other.close() }
    controller.toggleSidebarVisibility(nil)
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
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    await waitForSettle("revealed") { self.root.pointerReachedRevealEdge() }
    XCTAssertTrue(overlay.isRevealed)
    XCTAssertFalse(overlay.isHidden)
    XCTAssertEqual(root.card.frame.minX, 10, "an overlay: the content does not move")
    let inset = ShellMetrics.standard.sidebarOverlayInset
    XCTAssertEqual(overlay.frame, CGRect(x: inset, y: inset, width: 190, height: root.bounds.height - 2 * inset))
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
    controller.toggleSidebarVisibility(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    await waitForSettle("concealed") { self.overlay.pointerLeft() }
    XCTAssertFalse(overlay.isRevealed)
    XCTAssertTrue(overlay.isHidden)
    XCTAssertFalse(controller.isSidebarVisible, "still hidden, only the overlay went away")
  }

  func testOverlayStaysWhileTheButtonIsHeldOrThePointerCameBack() async throws {
    controller.toggleSidebarVisibility(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    overlay.mouseButtonsDown = { true }
    overlay.pointerLeft()
    await overlay.pendingForTesting?.value
    XCTAssertTrue(overlay.isRevealed, "a drag out of the overlay keeps it")
    XCTAssertNotNil(overlay.pendingForTesting, "it checks again when the button may be up")
    overlay.mouseButtonsDown = { false }
    overlay.pointerIsInside = { true }
    overlay.pointerLeft()
    await overlay.pendingForTesting?.value
    XCTAssertTrue(overlay.isRevealed, "the pointer is back inside")
    XCTAssertNil(overlay.pendingForTesting)
  }

  func testEdgeIsIgnoredWhileTheSidebarIsVisibleOrAButtonIsHeld() async throws {
    root.pointerReachedRevealEdge()
    XCTAssertNil(overlay.pendingForTesting, "docked: nothing scheduled")
    XCTAssertFalse(overlay.isRevealed)
    controller.toggleSidebarVisibility(nil)
    overlay.mouseButtonsDown = { true }       // the edge drag that hid it is still going
    root.pointerReachedRevealEdge()
    XCTAssertNil(overlay.pendingForTesting, "button held: nothing scheduled")
    XCTAssertFalse(overlay.isRevealed)
  }

  func testLeavingTheEdgeBeforeTheDelayCancelsTheReveal() async throws {
    controller.toggleSidebarVisibility(nil)
    overlay.revealDelay = .seconds(60)
    root.pointerReachedRevealEdge()
    let scheduled = try XCTUnwrap(overlay.pendingForTesting)
    root.pointerLeftRevealEdge()
    XCTAssertNil(overlay.pendingForTesting)
    await scheduled.value                     // returns at once: cancelled during its delay
    XCTAssertFalse(overlay.isRevealed)
    XCTAssertTrue(overlay.isHidden)
  }

  func testRevealIsInterruptibleWithoutAJump() async throws {
    controller.toggleSidebarVisibility(nil)
    overlay.reduceMotionForTesting = false
    let concealed = overlay.offsetForTesting
    // Turn around mid-flight, on the frame the reveal passes -150 pt.
    await withCheckedContinuation { (midFlight: CheckedContinuation<Void, Never>) in
      overlay.onFrameForTesting = { [weak self] offset in
        guard offset >= -150 else { return }
        self?.overlay.onFrameForTesting = nil
        midFlight.resume()
      }
      overlay.reveal()
    }
    let before = overlay.offsetForTesting
    XCTAssertGreaterThan(before, concealed, "the reveal was under way")
    XCTAssertLessThan(before, 0, "and not yet at rest")
    overlay.conceal()
    XCTAssertEqual(overlay.offsetForTesting, before, accuracy: 0.001, "the conceal starts where the reveal was")
    XCTAssertTrue(overlay.isAnimating)
    await waitForSettle("concealed") {}
    XCTAssertTrue(overlay.isHidden)
  }

  func testReduceMotionFadesInPlace() async throws {
    controller.toggleSidebarVisibility(nil)
    overlay.reduceMotionForTesting = true
    overlay.reveal()
    XCTAssertEqual(overlay.layer?.affineTransform().tx ?? -1, 0, "no slide under Reduce Motion")
    XCTAssertLessThan(overlay.alphaValue, 1)
    await waitForSettle("revealed") {}
    XCTAssertEqual(overlay.alphaValue, 1)
    XCTAssertTrue(overlay.layer?.affineTransform().isIdentity ?? false)
  }

  func testCmdSWhileRevealedDocksAtOnce() async throws {
    controller.toggleSidebarVisibility(nil)
    await waitForSettle("revealed") { self.overlay.reveal() }
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertFalse(overlay.isAnimating)
    XCTAssertEqual(overlay.frame, CGRect(x: 0, y: 0, width: 190, height: root.bounds.height))
    XCTAssertEqual(overlay.alphaValue, 1)
  }

  func testTrafficLightsHideWithTheSidebarAndComeBackWithTheOverlay() async throws {
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    controller.toggleSidebarVisibility(nil)
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
    // Docked again, every button is back at its place in the sidebar.
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    // The buttons are placed again one main-queue turn after they show (AppKit's own titlebar pass): wait that turn.
    await withCheckedContinuation { (turn: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { turn.resume() } }
    for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
      let button = try XCTUnwrap(window.standardWindowButton(kind))
      let frame = button.convert(button.bounds, to: nil)
      XCTAssertFalse(button.isHidden)
      XCTAssertEqual(frame.minX, 12 + CGFloat(index) * 23, accuracy: 0.5, "\(kind)")
      XCTAssertEqual(window.frame.height - frame.maxY, 16, accuracy: 0.5, "\(kind)")
    }
  }

  // MARK: Traffic lights ride on the sliding overlay (#807)

  /// Where the close button is drawn and how opaque, against where the overlay is drawn, on one spring frame.
  private struct TrafficLightFrame {
    var offset: CGFloat
    var overlayX: CGFloat
    var closeX: CGFloat
    var overlayAlpha: CGFloat
    var closeAlpha: CGFloat
    var closeHidden: Bool
    /// Right edge of the buttons' host (NSTitlebarView), which takes clicks wherever it is, and of the overlay at rest.
    var titlebarMaxX: CGFloat
    var overlayRestMaxX: CGFloat
  }

  /// Read in the spring frame's own callback, after the overlay presented it: nothing races the display link.
  private func trafficLightFrame(offset: CGFloat) -> TrafficLightFrame? {
    guard let close = controller.window?.standardWindowButton(.closeButton) else { return nil }
    return TrafficLightFrame(offset: offset,
                             overlayX: overlay.frame.minX + (overlay.layer?.affineTransform().tx ?? 0),
                             closeX: close.convert(close.bounds, to: nil).minX,
                             overlayAlpha: overlay.alphaValue, closeAlpha: close.alphaValue,
                             closeHidden: close.isHidden,
                             titlebarMaxX: close.superview.map { $0.convert($0.bounds, to: nil).maxX } ?? .infinity,
                             overlayRestMaxX: overlay.frame.maxX)
  }

  /// Records every spring frame of `body` until the overlay settles.
  private func recordUntilSettled(_ what: String, _ body: () -> Void) async -> [TrafficLightFrame] {
    var frames: [TrafficLightFrame] = []
    overlay.onFrameForTesting = { [weak self] offset in
      if let frame = self?.trafficLightFrame(offset: offset) { frames.append(frame) }
    }
    await waitForSettle(what, body)
    overlay.onFrameForTesting = nil
    return frames
  }

  /// Every frame the buttons show, they are drawn where they sit in the overlay, as opaque as the overlay, and the
  /// titlebar never reaches past the overlay's place to take the page's clicks.
  private func assertAttached(_ frames: [TrafficLightFrame], _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(frames.isEmpty, "\(what): no spring frames", file: file, line: line)
    for frame in frames where !frame.closeHidden {
      XCTAssertEqual(frame.closeX, frame.overlayX + 12, accuracy: 0.5,
                     "\(what): close button off the overlay at offset \(frame.offset)", file: file, line: line)
      XCTAssertEqual(frame.closeAlpha, frame.overlayAlpha, accuracy: 0.01,
                     "\(what): close button opacity off the overlay's at offset \(frame.offset)", file: file, line: line)
    }
    for frame in frames {
      XCTAssertLessThanOrEqual(frame.titlebarMaxX, frame.overlayRestMaxX,
                               "\(what): titlebar over the page at offset \(frame.offset)", file: file, line: line)
    }
  }

  func testTrafficLightsTrackTheSlidingOverlayThroughRevealReversalAndConceal() async throws {
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    overlay.reduceMotionForTesting = false
    // A reveal turned around on the frame it passes -150 pt.
    var reveal: [TrafficLightFrame] = []
    await withCheckedContinuation { (midFlight: CheckedContinuation<Void, Never>) in
      overlay.onFrameForTesting = { [weak self] offset in
        guard let self else { return }
        if let frame = self.trafficLightFrame(offset: offset) { reveal.append(frame) }
        guard offset >= -150 else { return }
        self.overlay.onFrameForTesting = nil
        midFlight.resume()
      }
      overlay.reveal()
    }
    assertAttached(reveal, "interrupted reveal")
    XCTAssertTrue(reveal.contains { !$0.closeHidden && $0.overlayX < -20 },
                  "the buttons were checked while the overlay was well off its place")
    let reversed = await recordUntilSettled("concealed after the turn") { overlay.conceal() }
    assertAttached(reversed, "reversed conceal")
    XCTAssertTrue(try XCTUnwrap(controller.window?.standardWindowButton(.closeButton)).isHidden,
                  "concealed: no buttons over the page")

    let full = await recordUntilSettled("revealed") { overlay.reveal() }
    assertAttached(full, "full reveal")
    let conceal = await recordUntilSettled("concealed") { overlay.conceal() }
    assertAttached(conceal, "full conceal")
    XCTAssertTrue(try XCTUnwrap(controller.window?.standardWindowButton(.closeButton)).isHidden)
  }

  func testTrafficLightsFadeWithTheOverlayUnderReduceMotion() async throws {
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    overlay.reduceMotionForTesting = true
    let reveal = await recordUntilSettled("revealed") { overlay.reveal() }
    assertAttached(reveal, "Reduce Motion reveal")
    XCTAssertTrue(reveal.contains { !$0.closeHidden && $0.overlayAlpha < 0.9 },
                  "the buttons were checked mid-fade")
    let conceal = await recordUntilSettled("concealed") { overlay.conceal() }
    assertAttached(conceal, "Reduce Motion conceal")
  }

  func testHiddenSidebarLeavesThePageTopLeftCornerClickable() throws {
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    let frameView = try XCTUnwrap(root.superview)              // NSThemeFrame, hosts the titlebar container too
    let pointInWindow = NSPoint(x: 30, y: window.frame.height - 24)   // where the close button sits when docked
    let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(pointInWindow, from: nil)))
    XCTAssertTrue(hit.isDescendant(of: root.card), "got \(hit)")
  }

  func testOverlayFollowsTheSpaceThemeAndHasItsOwnChrome() async throws {
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    XCTAssertEqual(overlay.backdrop.themes, root.themeBackground.themes)
    root.themeBackground.setPosition(1)
    XCTAssertEqual(overlay.backdrop.position, 1, "a Space swipe in the overlay moves its backdrop too")
    await waitForSettle("revealed") { self.overlay.reveal() }
    XCTAssertFalse(overlay.backdrop.isHidden)
    XCTAssertEqual(overlay.clip.layer?.masksToBounds, true)
    XCTAssertEqual(overlay.clip.layer?.cornerRadius, ShellMetrics.standard.cardCornerRadius)
    XCTAssertGreaterThan(overlay.layer?.shadowOpacity ?? 0, 0)
    controller.toggleSidebarVisibility(nil)
    XCTAssertTrue(overlay.backdrop.isHidden, "docked, the root's theme shows through as before")
    XCTAssertEqual(overlay.layer?.shadowOpacity, 0)
    XCTAssertEqual(overlay.clip.layer?.cornerRadius, 0)
  }

  // MARK: Toasts while hidden (BH-006)

  func testNewTabWhileHiddenShowsAToastThatShowsTheSidebar() throws {
    controller.toggleSidebarVisibility(nil)
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
    controller.toggleSidebarVisibility(nil)
    controller.newSpace(nil)
    XCTAssertEqual(controller.toasts.current?.text, "New Space Created")
    XCTAssertFalse(controller.window?.firstResponder is NSText, "no rename field typed into out of sight")
  }

  // MARK: Frame-time gate (BH-004 reveal overlay)

  /// NOT-MEASURABLE below 120 Hz or under load (`PacingEnvironment`); the 1-minute load is read again after measuring.
  /// The hitch count is asserted only with `ARKT_PACING_GATE=1` or when this class runs alone
  /// (`PacingEnvironment.checkFrameGate`, #671).
  func testRevealPacing() async throws {
    try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen)
    controller.toggleSidebarVisibility(nil)
    root.layoutSubtreeIfNeeded()
    overlay.reduceMotionForTesting = false
    // Warm the window up the way the pager gate does: wait for on-time frames before measuring.
    let warmUp = 10
    let stable = await StableFrames.wait(on: root, count: warmUp, threshold: FrameStats().hitchThreshold)
    print("sidebar.pacing warmup stableFrames=\(stable) of \(warmUp)")
    var results: [(String, FrameStats)] = []
    var details: [HitchDetail] = []
    for round in 0..<2 {
      await waitForSettle("revealed \(round)") { self.overlay.reveal() }
      results.append(("sidebar-reveal-\(round)", try XCTUnwrap(overlay.lastPacing)))
      details += overlay.pacer.hitchDetails
      await waitForSettle("concealed \(round)") { self.overlay.conceal() }
      results.append(("sidebar-conceal-\(round)", try XCTUnwrap(overlay.lastPacing)))
      details += overlay.pacer.hitchDetails
    }
    PacingEnvironment.checkFrameGate("sidebar", results: results, details: details, gate: Self.self, in: self,
                                     fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
  }
}
