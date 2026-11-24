import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI
@testable import Motion

@MainActor
final class SpacePagerTests: XCTestCase {
  var controller: ShellWindowController!
  var sidebar: StubSidebar!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    sidebar = StubSidebar.sample()
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  // XCTest keeps each test case object until the run ends: release the window too, not only close it (#805).
  override func tearDown() async throws {
    controller.close()
    controller = nil
    sidebar = nil
  }

  private func awaitSettle(_ body: () -> Void) async {
    let settled = expectation(description: "settled")
    controller.pager.onSettleForTesting = { _ in settled.fulfill() }
    body()
    await fulfillment(of: [settled], timeout: 3)
    controller.pager.onSettleForTesting = nil
  }

  /// Returns after `count` display frames have run, so a "holds still" check spans real frames, not a sleep.
  private func displayFrames(_ count: Int, on view: NSView) async {
    let ran = expectation(description: "\(count) display frames")
    _ = FrameScript(view: view, frames: count, step: { _ in }, done: { ran.fulfill() })
    await fulfillment(of: [ran], timeout: 3)
  }

  /// Polls once a millisecond (display frames keep running meanwhile) until `condition` holds.
  private func waitUntil(timeout: Double = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline { return false }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return true
  }

  private func hiddenStates() -> [Bool] { controller.pager.pages.map(\.isHidden) }

  // BH-035, GS-001
  func testScriptedSwipeSettlesOnNextSpace() async throws {
    let pager = controller.pager
    await awaitSettle {
      pager.beginTracking()
      var t = 0.0
      for _ in 0..<12 { t += 1.0 / 120; pager.track(delta: -12, at: t) }    // 144 pt left, ~1440 pt/s
      pager.endTracking()
    }
    XCTAssertEqual(pager.index, 1)
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
    XCTAssertEqual(pager.offset, -pager.bounds.width, accuracy: 0.001)
    XCTAssertEqual(controller.sidebarController.currentPage?.titleLabel.stringValue, "Work")
    XCTAssertEqual(controller.sidebarController.view.spaceDots.selectedIndex, 1)
  }

  func testSlowShortSwipeSettlesBack() async throws {
    let pager = controller.pager
    await awaitSettle {
      pager.beginTracking()
      var t = 0.0
      for _ in 0..<10 { t += 0.05; pager.track(delta: -3, at: t) }         // 30 pt at 60 pt/s
      pager.endTracking()
    }
    XCTAssertEqual(pager.index, 0)
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[0])
  }

  func testRubberBandsAtTheFirstSpace() async throws {
    let pager = controller.pager
    pager.beginTracking()
    var t = 0.0
    for _ in 0..<10 { t += 1.0 / 120; pager.track(delta: 30, at: t) }       // 300 pt right of the first page
    XCTAssertGreaterThan(pager.offset, 0)
    XCTAssertLessThan(pager.offset, 150, "resists well below the finger travel")
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(pager.index, 0)
    XCTAssertEqual(pager.offset, 0, accuracy: 0.001)
  }

  // KB-033, KB-034
  func testKeyboardNextAndPreviousSpace() async throws {
    await awaitSettle { controller.nextSpace(nil) }
    XCTAssertEqual(controller.pager.index, 1)
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
    await awaitSettle { controller.previousSpace(nil) }
    XCTAssertEqual(controller.pager.index, 0)
    controller.previousSpace(nil)                                            // first Space: stays put
    XCTAssertEqual(controller.pager.targetIndex, 0)
  }

  func testNextSpaceTwiceCountsFromTheTarget() async throws {
    let settled = expectation(description: "settled on the last Space")
    controller.pager.onSettleForTesting = { index in if index == 2 { settled.fulfill() } }
    controller.nextSpace(nil)
    controller.nextSpace(nil)
    await fulfillment(of: [settled], timeout: 3)
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[2])
  }

  // KB-035, BH-041
  func testControlNumberGoesToThatSpace() async throws {
    let item = NSMenuItem(title: "Space 3", action: nil, keyEquivalent: "3")
    item.tag = 2
    await awaitSettle { controller.goToSpace(item) }
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[2])
    XCTAssertEqual(controller.sidebarController.view.flavor, .dark)
    XCTAssertEqual(controller.sidebarController.view.appearance?.name, .darkAqua)
  }

  // BH-036
  func testSwitchingBackRestoresTheSpacesLastActiveTab() async throws {
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let chosen = sidebar.children(of: .today(personal))[1]
    controller.activate(node: chosen)
    await awaitSettle { controller.nextSpace(nil) }
    let current = try XCTUnwrap(controller.sidebarController.current)
    XCTAssertEqual(sidebar.spaceID(containing: current), work, "the new Space shows one of its own tabs")
    await awaitSettle { controller.previousSpace(nil) }
    XCTAssertEqual(controller.sidebarController.current, chosen)
  }

  func testInterruptingASettleContinuesFromTheSpring() async throws {
    let pager = controller.pager
    controller.nextSpace(nil)
    let moving = await waitUntil { pager.offset < -0.2 * pager.bounds.width }
    try PacingEnvironment.requireCaught(moving && pager.offset > -pager.bounds.width, "the settle mid-flight")
    let before = pager.offset
    pager.beginTracking()
    pager.track(delta: 0, at: 1)
    XCTAssertEqual(pager.offset, before, accuracy: 0.5, "no jump when the fingers catch the strip")
    await awaitSettle { pager.endTracking() }
  }

  /// #99 (M3): catching a settle while it overshoots past the first or last page keeps the exact position without
  /// re-applying rubber-band resistance on the first tracking tick.
  func testCatchingAnOvershootingSettleKeepsTheExactPosition() async throws {
    let pager = controller.pager
    let width = pager.bounds.width

    // Overshoot past the last page (page 2): position > 2 (offset < -2 * width).
    let pastLast = -2 * width - 16
    pager.setPositionForTesting(-pastLast / width)
    XCTAssertEqual(pager.offset, pastLast, accuracy: 0.001)
    pager.beginTracking()
    pager.track(delta: 0, at: 1)
    XCTAssertEqual(pager.offset, pastLast, accuracy: 0.001, "catching overshoot past last page keeps exact offset")
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(pager.index, 2)

    // Overshoot past the first page (page 0): position < 0 (offset > 0).
    let pastFirst: CGFloat = 14
    pager.setPositionForTesting(-pastFirst / width)
    XCTAssertEqual(pager.offset, pastFirst, accuracy: 0.001)
    pager.beginTracking()
    pager.track(delta: 0, at: 2)
    XCTAssertEqual(pager.offset, pastFirst, accuracy: 0.001, "catching overshoot past first page keeps exact offset")
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(pager.index, 0)
  }

  /// #99 (M4): resizing the sidebar during an active swipe updates the page frames and strip offset to the new width
  /// immediately instead of keeping the old page width until the gesture ends.
  func testPageWidthFollowsASidebarResizeDuringASwipe() async throws {
    let pager = controller.pager
    await awaitSettle { controller.nextSpace(nil) }
    XCTAssertEqual(pager.index, 1)

    pager.beginTracking()
    pager.track(delta: -30, at: 0.01)
    XCTAssertEqual(pager.offset, -pager.bounds.width - 30, accuracy: 0.001)

    controller.rootView.sidebarWidth = 260
    controller.rootView.layoutSubtreeIfNeeded()
    XCTAssertEqual(pager.bounds.width, 260, accuracy: 0.001)
    // Mid-swipe a shown page's view frame sits in the visible slot and its layer translation shows it at its own
    // place in the strip (#415, #841): its place on screen is the frame plus that translation.
    for (index, page) in pager.pages.enumerated() {
      XCTAssertEqual(page.frame.width, 260, accuracy: 0.001)
      let shownX = page.frame.minX + (page.layer?.affineTransform().tx ?? 0)
      XCTAssertEqual(shownX, CGFloat(index) * 260, accuracy: 0.001)
    }
    XCTAssertEqual(pager.offset, -260 - 30, accuracy: 0.001, "strip offset follows the new page width during swipe")
    await awaitSettle { pager.endTracking() }
  }

  // Design section 2: the theme crossfades with the pager position.
  func testThemeBlendFollowsPosition() throws {
    controller.pager.setPositionForTesting(0.5)
    let theme = controller.themeBackground
    XCTAssertEqual(theme.overlayOpacityForTesting, 0.5, accuracy: 0.001)
    // Personal has grain at 0.5, Work none: halfway is a quarter of the maximum.
    XCTAssertEqual(Double(theme.grainOpacityForTesting), 0.25 * ShellTokens.themeTextureMaxOpacity, accuracy: 0.001)
    controller.pager.setPositionForTesting(1.75)
    XCTAssertEqual(theme.overlayOpacityForTesting, 0.75, accuracy: 0.001)
    XCTAssertEqual(theme.baseColorsForTesting.count, ThemeGradient.segmentsPerPair + 1)
    XCTAssertEqual(controller.sidebarController.view.flavor, .dark, "chrome follows the nearest Space")
  }

  // BH-040: the active dot hands over during the swipe.
  func testDotFillFollowsPosition() throws {
    let dots = controller.sidebarController.view.spaceDots
    controller.pager.setPositionForTesting(0.25)
    XCTAssertEqual(dots.fillWeight(0), 0.75, accuracy: 0.001)
    XCTAssertEqual(dots.fillWeight(1), 0.25, accuracy: 0.001)
    XCTAssertEqual(dots.fillWeight(2), 0, accuracy: 0.001)
  }

  // C3 review follow-up: dots are accessibility buttons named after their Space.
  func testSpaceDotsAreAccessibleButtons() async throws {
    let dots = controller.sidebarController.view.spaceDots
    let children = try XCTUnwrap(dots.accessibilityChildren() as? [NSAccessibilityElement])
    XCTAssertEqual(children.map { $0.accessibilityLabel() }, ["Personal", "Work", "Dev"])
    XCTAssertEqual(children.map { $0.accessibilityRole() }, [.button, .button, .button])
    XCTAssertTrue(children[0].isAccessibilitySelected())
    XCTAssertGreaterThan(children[1].accessibilityFrame().width, 0)
    await awaitSettle { _ = children[2].accessibilityPerformPress() }
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[2])
    XCTAssertTrue(children[2].isAccessibilitySelected())
  }

  // GS-001 routing: a horizontal trackpad gesture over the outline moves the pager.
  func testHorizontalGestureOverOutlineReachesThePager() throws {
    let scrollView = try XCTUnwrap(controller.sidebarController.currentPage?.scrollView)
    func event(_ phase: Int, dx: Int32, dy: Int32) throws -> NSEvent {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: dy, wheel2: dx, wheel3: 0))
      cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
      cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
      cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
      return try XCTUnwrap(NSEvent(cgEvent: cg))
    }
    scrollView.scrollWheel(with: try event(1, dx: 0, dy: 0))        // began
    scrollView.scrollWheel(with: try event(2, dx: -20, dy: 0))      // changed
    XCTAssertTrue(controller.pager.isTracking)
    XCTAssertNotEqual(controller.pager.offset, 0)
    scrollView.scrollWheel(with: try event(4, dx: 0, dy: 0))        // ended
    XCTAssertFalse(controller.pager.isTracking)
  }

  func testVerticalGestureOverOutlineLeavesThePager() throws {
    let scrollView = try XCTUnwrap(controller.sidebarController.currentPage?.scrollView)
    func event(_ phase: Int, dy: Int32) throws -> NSEvent {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: dy, wheel2: 0, wheel3: 0))
      cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
      cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
      return try XCTUnwrap(NSEvent(cgEvent: cg))
    }
    scrollView.scrollWheel(with: try event(1, dy: 0))
    scrollView.scrollWheel(with: try event(2, dy: -20))
    scrollView.scrollWheel(with: try event(4, dy: 0))
    XCTAssertFalse(controller.pager.isTracking)
    XCTAssertEqual(controller.pager.offset, 0)
  }

  /// #98 (GS-002, BH-035): mouse buttons 3 and 4 switch to the previous and next Space anywhere in the window and
  /// stop at the first and last Space ([I], PARITY(NEEDS-RUNTIME-CHECK #78)).
  func testMouseButtons3And4SwitchToPreviousAndNextSpaceAndStopAtEnds() async throws {
    let window = try XCTUnwrap(controller.window)
    func mouseEvent(button: Int) throws -> NSEvent {
      let mouseButton = try XCTUnwrap(CGMouseButton(rawValue: UInt32(button)))
      let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                     mouseCursorPosition: CGPoint(x: 400, y: 400), mouseButton: mouseButton))
      return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    let button2 = try mouseEvent(button: 2)
    let button3 = try mouseEvent(button: 3)
    let button4 = try mouseEvent(button: 4)

    // Button 2 (middle click) does not switch Spaces.
    window.sendEvent(button2)
    XCTAssertEqual(controller.pager.targetIndex, 0)

    // Button 3 at the first Space stops at index 0.
    window.sendEvent(button3)
    XCTAssertEqual(controller.pager.targetIndex, 0)

    // Button 4 advances to the next Space, and at the last Space stops at index 2.
    await awaitSettle { window.sendEvent(button4) }
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
    await awaitSettle { window.sendEvent(button4) }
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[2])
    window.sendEvent(button4)
    XCTAssertEqual(controller.pager.targetIndex, 2)
    controller.nextSpace(nil)
    XCTAssertEqual(controller.pager.targetIndex, 2)

    // Button 3 moves back to the previous Space.
    await awaitSettle { window.sendEvent(button3) }
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
  }

  /// #98 (M1, GS-001): horizontal trackpad swipes starting over the Favorites grid or the bottom bar page the Spaces.
  func testHorizontalGestureOverFavoritesGridAndBottomBarReachesThePager() throws {
    func event(_ phase: Int, dx: Int32, dy: Int32) throws -> NSEvent {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: dy, wheel2: dx, wheel3: 0))
      cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
      cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
      cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
      return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    let favoritesGrid = controller.sidebarController.view.favorites.collectionView
    favoritesGrid.scrollWheel(with: try event(1, dx: 0, dy: 0))
    favoritesGrid.scrollWheel(with: try event(2, dx: -20, dy: 0))
    XCTAssertTrue(controller.pager.isTracking, "swipe starting over the Favorites grid reaches the pager")
    XCTAssertNotEqual(controller.pager.offset, 0)
    favoritesGrid.scrollWheel(with: try event(4, dx: 0, dy: 0))
    XCTAssertFalse(controller.pager.isTracking)
    controller.pager.jump(to: 0)

    let bottomBar = controller.sidebarController.view.spaceDots
    bottomBar.scrollWheel(with: try event(1, dx: 0, dy: 0))
    bottomBar.scrollWheel(with: try event(2, dx: -20, dy: 0))
    XCTAssertTrue(controller.pager.isTracking, "swipe starting over the bottom bar reaches the pager")
    XCTAssertNotEqual(controller.pager.offset, 0)
    bottomBar.scrollWheel(with: try event(4, dx: 0, dy: 0))
    XCTAssertFalse(controller.pager.isTracking)
  }

  /// Frame pacing: a display-paced scripted swipe and a keyboard switch, measured on the pager's display link.
  /// NOT-MEASURABLE below 120 Hz or under load; the hitch count is asserted only with `ARKT_PACING_GATE=1` or when
  /// this class runs alone (`PacingEnvironment.checkFrameGate`, #671).
  func testFramePacingDuringSwipeAndKeyboardSwitch() async throws {
    try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen)
    let pager = controller.pager
    // The window just appeared: its first frames carry window-server start-up (a 13.8 ms frame 0 seen once,
    // C7 phase 2). Measure from a steady display: wait for consecutive on-time frames first. The gate on the
    // measured frames is unchanged.
    let warmUp = 10
    let stable = await StableFrames.wait(on: pager, count: warmUp, threshold: FrameStats().hitchThreshold)
    print("spacepager.pacing warmup stableFrames=\(stable) of \(warmUp)")
    await awaitSettle {
      pager.gestureMayBegin()                       // fingers touch down, as a trackpad gesture does
      pager.beginTracking()
      // The display link retains the script until it invalidates itself after the last frame.
      _ = FrameScript(view: pager, frames: 20, step: { t in pager.track(delta: -9, at: t) },
                      done: { pager.endTracking() })
    }
    let swipe = try XCTUnwrap(pager.lastPacing)
    var details = pager.pacer.hitchDetails
    await awaitSettle { controller.nextSpace(nil) }
    let key = try XCTUnwrap(pager.lastPacing)
    details += pager.pacer.hitchDetails
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[2])
    XCTAssertEqual(controller.sidebarController.view.flavor, .dark)
    // #99 (M9): swipe from Dev (.dark) back to Work (.light) crosses the halfway flavor flip (.darkAqua -> .aqua).
    await awaitSettle {
      pager.gestureMayBegin()
      pager.beginTracking()
      _ = FrameScript(view: pager, frames: 20, step: { t in pager.track(delta: 9, at: t) },
                      done: { pager.endTracking() })
    }
    let flavorSwipe = try XCTUnwrap(pager.lastPacing)
    details += pager.pacer.hitchDetails
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
    XCTAssertEqual(controller.sidebarController.view.flavor, .light)

    PacingEnvironment.checkFrameGate(
      "spacepager", results: [("space-swipe", swipe), ("space-key", key), ("space-swipe-flavor", flavorSwipe)],
      details: details, gate: Self.self, in: self, fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
  }

  // C6 review I1: offscreen pages stay out of accessibility and the key loop.
  func testOnlyTheCurrentPageIsShownAtRest() async throws {
    XCTAssertEqual(hiddenStates(), [false, true, true])
    await awaitSettle { controller.nextSpace(nil) }
    XCTAssertEqual(hiddenStates(), [true, false, true])
    controller.sidebarController.showSpace(sidebar.spaceOrder[2])
    XCTAssertEqual(hiddenStates(), [true, true, false])
    let window = try XCTUnwrap(controller.window)
    let titles = window.contentView.map(collectVisibleTitles) ?? []
    XCTAssertFalse(titles.contains("Personal"), "a hidden page's title is not reachable")
    XCTAssertTrue(titles.contains("Dev"))
  }

  func testOnlyTheNeighbouringPagesAreShownWhileMoving() async throws {
    let pager = controller.pager
    pager.beginTracking()
    pager.track(delta: -0.4 * pager.bounds.width, at: 0.01)
    XCTAssertEqual(hiddenStates(), [false, false, true])
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(hiddenStates(), [true, false, true])
  }

  // C6 review M2: fingers touching down freeze a settle; a vertical gesture lets it finish.
  func testTouchDownFreezesASettleAndVerticalResumesIt() async throws {
    let pager = controller.pager
    controller.nextSpace(nil)
    let moving = await waitUntil { pager.offset < -0.2 * pager.bounds.width }
    try PacingEnvironment.requireCaught(moving, "the settle under way before the fingers touch down")
    // Only the timing (did the settle finish before the test looked) may skip; the freeze itself is a hard check.
    try PacingEnvironment.requireCaught(pager.isSettling, "the settle still running at touch down")
    pager.gestureMayBegin()
    let frozen = pager.offset
    XCTAssertEqual(pager.frozenTarget, 1)
    await displayFrames(3, on: pager)
    XCTAssertEqual(pager.offset, frozen, "the strip holds still under the fingers")
    await awaitSettle { pager.gestureEndedWithoutPaging() }
    XCTAssertEqual(pager.index, 1)
    XCTAssertNil(pager.frozenTarget)
  }

  // C6 review M7: a position change repaints only the dots whose weight changed.
  func testDotsRepaintOnlyChangedWeights() throws {
    let dots = controller.sidebarController.view.spaceDots
    controller.pager.setPositionForTesting(0.25)
    let before = dots.repaintCountForTesting
    controller.pager.setPositionForTesting(0.5)
    XCTAssertEqual(dots.repaintCountForTesting - before, 2, "dot 2 stays at weight 0 and is not repainted")
    XCTAssertEqual(dots.fillWeight(0), 0.5, accuracy: 0.001)
  }

  // MARK: A gesture whose events land on another page (#986)

  /// Timestamp of the last scripted trackpad event, in nanoseconds of system uptime.
  private var trackpadClock = DispatchTime.now().uptimeNanoseconds
  /// The pager's settle clock in these tests (`nowForTesting`): settle frames are presented at chosen times on it.
  private var settleClock: CFTimeInterval = 1_000

  /// A trackpad scroll event at `point` in the pager, with CGEvent's phase values (1 began, 2 changed, 4 ended,
  /// 8 cancelled, 128 may begin; momentum 1 began, 2 changed, 3 ended). Built from a CGEvent it has no window; its
  /// location is placed so that its window location is `point`'s, so `NSWindow.sendEvent` hit-tests it there. Events
  /// are 1/120 s apart, as a trackpad sends them, so release velocities are a real finger's.
  private func trackpadEvent(_ phase: Int64, momentum: Int64 = 0, dx: Int32 = 0, dy: Int32 = 0,
                             at point: NSPoint? = nil) throws -> NSEvent {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    let point = point ?? stillPointer
    let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: dy, wheel2: dx, wheel3: 0))
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    trackpadClock += 8_333_333
    cg.timestamp = trackpadClock
    let screen = window.convertPoint(toScreen: pager.convert(point, to: nil))
    cg.location = CGPoint(x: screen.x, y: try XCTUnwrap(NSScreen.screens.first).frame.maxY - screen.y)
    let event = try XCTUnwrap(NSEvent(cgEvent: cg))
    XCTAssertEqual(event.locationInWindow.x, pager.convert(point, to: nil).x, accuracy: 1e-3)
    return event
  }

  /// Where the fingers' pointer rests in these tests: over the outlines, left of the middle.
  private var stillPointer: NSPoint {
    NSPoint(x: controller.pager.bounds.midX, y: controller.pager.bounds.height * 0.4)
  }

  /// Settles are driven by hand on `settleClock`: no display link, no wall time.
  private func driveSettlesByHand() {
    let pager = controller.pager
    pager.reduceMotionForTesting = false
    pager.driver.drivesDisplayLink = false
    pager.nowForTesting = { [unowned self] in self.settleClock }
  }

  /// Presents `count` settle frames, 1/120 s apart on `settleClock`, while a settle runs.
  private func presentFrames(_ count: Int) {
    for _ in 0..<count where controller.pager.isSettling {
      settleClock += 1.0 / 120
      controller.pager.driver.tick(at: settleClock)
    }
  }

  /// Presents settle frames until the settle ends (at most 3 s of them).
  private func settleByHand() {
    presentFrames(360)
    XCTAssertFalse(controller.pager.isSettling, "the settle ended within 3 s of frames")
  }

  private func outline(_ index: Int) throws -> SidebarScrollView {
    try XCTUnwrap(controller.pager.pages[index] as? SpacePageView).scrollView
  }

  /// The scroll events each outline's `NSScrollView` handles itself (what scrolls it), recorded at AppKit's boundary
  /// while `body` runs. Not the clip view's origin: `NSScrollView` applies a trackpad scroll on a later display pass
  /// and starts its own fling, and it does not scroll for a synthetic momentum event at all, so the origin can only
  /// be read against wall time. Recording the calls is exact and does not depend on this branch's code.
  private func recordingOutlineScrolls(_ body: (OutlineScrollLog) throws -> Void) throws {
    let selector = #selector(NSResponder.scrollWheel(with:))
    let method = try XCTUnwrap(class_getInstanceMethod(NSScrollView.self, selector))
    XCTAssertNotEqual(method, class_getInstanceMethod(NSResponder.self, selector), "NSScrollView's own method")
    typealias ScrollWheel = @convention(c) (AnyObject, Selector, NSEvent) -> Void
    let originalIMP = method_getImplementation(method)
    let original = unsafeBitCast(originalIMP, to: ScrollWheel.self)
    let log = OutlineScrollLog()
    let recording: @convention(block) (AnyObject, NSEvent) -> Void = { view, event in
      MainActor.assumeIsolated { log.record(view, event) }
      original(view, selector, event)
    }
    method_setImplementation(method, imp_implementationWithBlock(recording))
    defer { method_setImplementation(method, originalIMP) }
    try body(log)
  }

  /// A vertical scroll on `view`: began, three moves of `dy`, ended.
  private func scrollVertically(_ view: NSView, dy: Int32 = -20) throws {
    view.scrollWheel(with: try trackpadEvent(1))
    for _ in 0..<3 { view.scrollWheel(with: try trackpadEvent(2, dy: dy)) }
    view.scrollWheel(with: try trackpadEvent(4))
  }

  /// Momentum events (began, two changes, ended) carrying `dx` and `dy`, sent to `view`.
  private func momentum(to view: NSView, dx: Int32 = 0, dy: Int32) throws {
    for phase: Int64 in [1, 2, 2, 3] { view.scrollWheel(with: try trackpadEvent(0, momentum: phase, dx: dx, dy: dy)) }
  }

  /// Counts the scroll events each page's scroll view receives.
  private func countScrollEvents() -> () -> [Int] {
    var counts = Array(repeating: 0, count: controller.pager.pages.count)
    for (i, page) in controller.pager.pages.enumerated() {
      guard let page = page as? SpacePageView else { continue }
      let previous = page.scrollView.onUserScroll
      page.scrollView.onUserScroll = { counts[i] += 1; previous?() }
    }
    return { counts }
  }

  /// Every gesture ends with the pager resting on exactly one page.
  private func assertRestsOnOnePage(_ target: Int, _ moment: String, file: StaticString = #filePath,
                                    line: UInt = #line) {
    let pager = controller.pager
    XCTAssertFalse(pager.isTracking, "\(moment): the swipe ended", file: file, line: line)
    XCTAssertFalse(pager.isSettling, "\(moment): the settle ended", file: file, line: line)
    XCTAssertNil(pager.frozenTarget, "\(moment): nothing frozen", file: file, line: line)
    XCTAssertEqual(pager.index, target, "\(moment)", file: file, line: line)
    XCTAssertEqual(pager.position, CGFloat(target), accuracy: 1e-9, "\(moment): on the page", file: file, line: line)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0, "\(moment): no translation left", file: file, line: line)
  }

  /// #986: AppKit sends each event of a scroll gesture to the view under the pointer, and a swipe moves the next
  /// Space's page under a still pointer. The rest of the swipe, its end included, lands on that page's scroll view.
  /// Its outline was last scrolled vertically; the swipe must still end and settle on one page, and no event of the
  /// swipe, its momentum included, may scroll that outline.
  func testASwipeThatMovesTheNextPageUnderThePointerStillSettles() throws {
    let pager = controller.pager
    driveSettlesByHand()
    let window = try XCTUnwrap(pager.window)
    try scrollVertically(try outline(1))                   // the user scrolled the next Space's outline before
    let received = countScrollEvents()

    try recordingOutlineScrolls { log in
      window.sendEvent(try trackpadEvent(1))
      var steps = 0
      while pager.position < 0.75, steps < 60 {
        window.sendEvent(try trackpadEvent(2, dx: 12))
        steps += 1
      }
      window.sendEvent(try trackpadEvent(4))
      try momentum(to: try outline(1), dx: 6, dy: -4)    // AppKit's window dispatch drops synthetic momentum
      XCTAssertGreaterThan(received()[1], 0, "the swipe's later events land on the next page's scroll view")
      XCTAssertEqual(log.events(of: try outline(1)), [], "no event of the swipe scrolls the outline it lands on")
      XCTAssertEqual(log.events(of: try outline(0)), [], "nor the outline it began on")
    }
    XCTAssertFalse(pager.isTracking, "the swipe ended")
    settleByHand()
    assertRestsOnOnePage(1, "after the swipe")
    pager.stopInteraction()
  }

  /// A vertical scroll's momentum scrolls the outline it began on; a swipe's momentum, wherever it lands, scrolls no
  /// outline (the spring owns the deceleration). Momentum is sent to the scroll views directly: AppKit's window
  /// dispatch does not deliver a synthetic momentum event to a view.
  func testMomentumScrollsTheOutlineOnlyAfterAVerticalScroll() throws {
    let pager = controller.pager
    driveSettlesByHand()
    let first = try outline(0)
    let next = try outline(1)
    try recordingOutlineScrolls { log in
      try scrollVertically(first)
      try momentum(to: first, dy: -20)
      XCTAssertEqual(log.events(of: first), ["began", "changed", "changed", "changed", "ended",
                                             "momentum began", "momentum changed", "momentum changed",
                                             "momentum ended"], "a vertical scroll and its momentum scroll the outline")
    }
    try recordingOutlineScrolls { log in
      first.scrollWheel(with: try trackpadEvent(1))
      for _ in 0..<8 { first.scrollWheel(with: try trackpadEvent(2, dx: 24)) }
      first.scrollWheel(with: try trackpadEvent(4))
      XCTAssertTrue(pager.isSettling, "the swipe settles")
      try momentum(to: first, dx: 12, dy: -6)
      try momentum(to: next, dx: 12, dy: -6)
      XCTAssertEqual(log.events(of: first), [], "a swipe and its momentum do not scroll the outline it began on")
      XCTAssertEqual(log.events(of: next), [], "nor the next page's outline its momentum lands on")
    }
    settleByHand()
    assertRestsOnOnePage(1, "after the swipe")
  }

  /// A touch freezes a settle; the gesture turns out vertical and the settle resumes, which moves the strip under
  /// the fingers, so the rest of the scroll lands on the next page's scroll view. The scroll, its end and its momentum
  /// stay with the outline it began on.
  func testAVerticalScrollThatResumesASettleKeepsScrollingItsOutline() throws {
    let pager = controller.pager
    driveSettlesByHand()
    let first = try outline(0)
    let next = try outline(1)
    pager.go(to: 1)
    presentFrames(3)
    XCTAssertTrue(pager.isSettling, "the settle runs when the fingers touch down")
    try recordingOutlineScrolls { log in
      first.scrollWheel(with: try trackpadEvent(128))
      XCTAssertEqual(pager.frozenTarget, 1)
      first.scrollWheel(with: try trackpadEvent(1))
      first.scrollWheel(with: try trackpadEvent(2, dy: -20))
      XCTAssertTrue(pager.isSettling, "a vertical gesture lets the frozen settle finish")
      settleByHand()
      for _ in 0..<3 { next.scrollWheel(with: try trackpadEvent(2, dy: -20)) }   // now under the pointer
      next.scrollWheel(with: try trackpadEvent(4))
      try momentum(to: next, dy: -20)
      XCTAssertEqual(log.events(of: first), ["may begin", "began", "changed", "changed", "changed", "changed", "ended",
                                             "momentum began", "momentum changed", "momentum changed",
                                             "momentum ended"], "the scroll, its end and its momentum stay with it")
      XCTAssertEqual(log.events(of: next), [], "the outline the later events landed on does not scroll")
    }
    assertRestsOnOnePage(1, "after the settle")
  }

  /// A swipe whose end never arrived (the app lost it): the next touch settles it on the nearest page, whatever the
  /// new gesture turns out to be.
  func testANewGestureAfterASwipeThatLostItsEndSettlesOnOnePage() throws {
    let pager = controller.pager
    driveSettlesByHand()
    let first = try outline(0)
    first.scrollWheel(with: try trackpadEvent(1))
    while pager.position < 0.7 { first.scrollWheel(with: try trackpadEvent(2, dx: 12)) }
    XCTAssertTrue(pager.isTracking)
    // No ended event. The next gesture is a vertical scroll.
    try scrollVertically(first)
    XCTAssertFalse(pager.isTracking, "the new gesture ended the stale swipe")
    settleByHand()
    assertRestsOnOnePage(1, "after the vertical scroll")
  }

  /// Focus leaving mid-swipe can swallow the gesture's end: the window resigning key, or the app deactivating,
  /// settles the swipe on the nearest page.
  func testLosingFocusMidSwipeSettlesOnOnePage() throws {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    driveSettlesByHand()
    for (name, object, target) in [(NSWindow.didResignKeyNotification, window as AnyObject?, 1),
                                   (NSApplication.didResignActiveNotification, NSApp as AnyObject?, 0)] {
      pager.beginTracking()
      pager.track(delta: target == 1 ? -0.7 * pager.bounds.width : 0.7 * pager.bounds.width, at: 0.01)
      NotificationCenter.default.post(name: name, object: object)
      XCTAssertFalse(pager.isTracking, "\(name.rawValue) ended the swipe")
      settleByHand()
      assertRestsOnOnePage(target, name.rawValue)
    }
  }

  /// #986: quick swipes back and forth under a still pointer, a fast flick with momentum, a second swipe that catches
  /// the settle, and a touch that lifts without moving. After each one the pager rests on one page.
  func testQuickSwipesUnderAStillPointerEachEndOnOnePage() throws {
    let pager = controller.pager
    driveSettlesByHand()
    let window = try XCTUnwrap(pager.window)
    for index in pager.pages.indices { try scrollVertically(try outline(index)) }   // every outline scrolled before
    func flick(_ dx: Int32, frames: Int) throws {
      window.sendEvent(try trackpadEvent(1))
      for _ in 0..<frames { window.sendEvent(try trackpadEvent(2, dx: dx)) }
      window.sendEvent(try trackpadEvent(4))
      // AppKit's window dispatch drops synthetic momentum events, so they go to the scroll view under the pointer.
      let page = pager.pages[min(max(Int(pager.position.rounded()), 0), pager.pages.count - 1)]
      if let page = page as? SpacePageView { try momentum(to: page.scrollView, dx: dx, dy: 0) }
    }
    let width = Int32(pager.bounds.width)
    try flick(width / 8, frames: 7)                        // to page 1, past half way
    settleByHand()
    assertRestsOnOnePage(1, "flick to page 1")
    try flick(width / 8, frames: 7)                        // to page 2 ...
    presentFrames(3)
    XCTAssertTrue(pager.isSettling, "the settle to page 2 runs when the next swipe catches it")
    try flick(-width / 8, frames: 7)                       // ... caught mid-settle and swiped back toward page 1
    settleByHand()
    assertRestsOnOnePage(1, "swipe that caught the settle")
    try flick(-width / 8, frames: 7)                       // to page 0 ...
    presentFrames(3)
    XCTAssertTrue(pager.isSettling, "the settle to page 0 runs when the fingers touch down")
    window.sendEvent(try trackpadEvent(128))               // ... a touch mid-settle that lifts without moving
    window.sendEvent(try trackpadEvent(8))
    settleByHand()
    assertRestsOnOnePage(0, "touch that lifted")
    pager.stopInteraction()
  }

  private func collectVisibleTitles(_ view: NSView) -> [String] {
    if view.isHidden { return [] }
    var titles: [String] = []
    if let field = view as? NSTextField { titles.append(field.stringValue) }
    for sub in view.subviews { titles += collectVisibleTitles(sub) }
    return titles
  }
}

/// Scroll events `NSScrollView` handled itself, per scroll view, as phase names in order (#986 tests).
@MainActor
final class OutlineScrollLog {
  private var entries: [(view: ObjectIdentifier, event: String)] = []

  func record(_ view: AnyObject, _ event: NSEvent) {
    entries.append((ObjectIdentifier(view), Self.name(of: event)))
  }

  func events(of view: NSScrollView) -> [String] {
    entries.filter { $0.view == ObjectIdentifier(view) }.map(\.event)
  }

  private static func name(of event: NSEvent) -> String {
    func phase(_ p: NSEvent.Phase) -> String {
      switch p {
      case .mayBegin: "may begin"
      case .began: "began"
      case .changed: "changed"
      case .stationary: "stationary"
      case .ended: "ended"
      case .cancelled: "cancelled"
      default: "none"
      }
    }
    return event.momentumPhase != [] ? "momentum \(phase(event.momentumPhase))" : phase(event.phase)
  }
}
