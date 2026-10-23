import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// Steps a scripted interaction once per display frame, so a scripted swipe exercises the same
/// per-frame path (and the same pacing measurement) as a real trackpad gesture.
@MainActor
private final class FrameScript: NSObject {
  private var link: CADisplayLink?
  private var remaining: Int
  private let step: @MainActor (CFTimeInterval) -> Void
  private let done: @MainActor () -> Void

  init(view: NSView, frames: Int, step: @escaping @MainActor (CFTimeInterval) -> Void,
       done: @escaping @MainActor () -> Void) {
    remaining = frames
    self.step = step
    self.done = done
    super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    guard remaining > 0 else { link.invalidate(); self.link = nil; done(); return }
    remaining -= 1
    step(link.timestamp)
  }
}

/// Waits on a display link until `count` consecutive frame intervals are within `threshold`, or until
/// `timeout` passes (then it gives up waiting and the measurement runs anyway; warm-up never fails a test).
@MainActor
private final class StableFrames: NSObject {
  private var link: CADisplayLink?
  private let count: Int
  private let threshold: Double
  private let deadline: CFTimeInterval
  private var last: CFTimeInterval?
  private var stable = 0
  private var continuation: CheckedContinuation<Int, Never>?

  private init(view: NSView, count: Int, threshold: Double, timeout: Double) {
    self.count = count
    self.threshold = threshold
    self.deadline = CACurrentMediaTime() + timeout
    super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  /// Returns the stable run reached (`count` when the display settled before the timeout).
  static func wait(on view: NSView, count: Int, threshold: Double, timeout: Double = 2) async -> Int {
    let waiter = StableFrames(view: view, count: count, threshold: threshold, timeout: timeout)
    // A display link that never ticks (display asleep) must not hang the test: the measurement then reports it.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(timeout + 0.5))
      waiter.finish()
    }
    return await withCheckedContinuation { waiter.continuation = $0 }
  }

  @objc private func tick(_ link: CADisplayLink) {
    if let last { stable = link.timestamp - last <= threshold ? stable + 1 : 0 }
    last = link.timestamp
    if stable >= count || link.timestamp >= deadline { finish() }
  }

  /// Stops the link and resumes the waiter once; later calls do nothing.
  private func finish() {
    link?.invalidate()
    link = nil
    continuation?.resume(returning: stable)
    continuation = nil
  }
}

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

  override func tearDown() async throws { controller.close() }

  private func awaitSettle(_ body: () -> Void) async {
    let settled = expectation(description: "settled")
    controller.pager.onSettleForTesting = { _ in settled.fulfill() }
    body()
    await fulfillment(of: [settled], timeout: 3)
    controller.pager.onSettleForTesting = nil
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
    XCTAssertTrue(moving && pager.offset > -pager.bounds.width, "mid-settle")
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
    for (index, page) in pager.pages.enumerated() {
      XCTAssertEqual(page.frame.width, 260, accuracy: 0.001)
      XCTAssertEqual(page.frame.minX, CGFloat(index) * 260, accuracy: 0.001)
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
    XCTAssertEqual(theme.baseColorsForTesting.count, 2)
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

  // Frame pacing: a display-paced scripted swipe and a keyboard switch, measured on the pager's display link.
  func testFramePacingDuringSwipeAndKeyboardSwitch() async throws {
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
    await awaitSettle { controller.nextSpace(nil) }
    let key = try XCTUnwrap(pager.lastPacing)
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
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[1])
    XCTAssertEqual(controller.sidebarController.view.flavor, .light)

    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let fps = NSScreen.main?.maximumFramesPerSecond ?? 0
    for (label, stats) in [("space-swipe", swipe), ("space-key", key), ("space-swipe-flavor", flavorSwipe)] {
      // "frame@ms": which frame of the interaction went over (the swipe tracks for 20 frames, then settles).
      // Indices count from the first gated interval; the lead-in (display-link start-up) is printed apart.
      let hitches = stats.intervals.enumerated().filter { $0.element > stats.hitchThreshold }
        .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) }
      let summary = String(
        format: "spacepager.pacing label=%@ screenMaxFPS=%d frames=%d over8.6=%d overBudgetPct=%.2f maxMs=%.2f "
          + "p99Ms=%.2f leadInMs=%.2f load1=%.2f cores=%d asserted=%@ hitchesMs=[%@]",
        label, fps, stats.frameCount, stats.hitchCount, stats.overBudgetRatio * 100, stats.maxInterval * 1000,
        stats.p99 * 1000, (stats.leadInInterval ?? 0) * 1000, load[0], cores, loaded ? "no" : "yes",
        hitches.joined(separator: ","))
      print(summary)
      let attachment = XCTAttachment(string: summary)
      attachment.name = "spacepager.pacing.\(label)"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertGreaterThan(stats.frameCount, 10, "\(label): the display link ran (is the display awake?)")
      if loaded {
        print("spacepager.pacing skipped assert: 1-minute load \(load[0]) >= \(cores) active cores")
      } else {
        XCTAssertEqual(stats.hitchCount, 0, "\(label): frames over 8.6 ms")
      }
    }
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
    XCTAssertTrue(moving, "the settle got under way before the fingers touched down")
    pager.gestureMayBegin()
    let frozen = pager.offset
    XCTAssertEqual(pager.frozenTarget, 1)
    try? await Task.sleep(nanoseconds: 50_000_000)
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

  private func collectVisibleTitles(_ view: NSView) -> [String] {
    if view.isHidden { return [] }
    var titles: [String] = []
    if let field = view as? NSTextField { titles.append(field.stringValue) }
    for sub in view.subviews { titles += collectVisibleTitles(sub) }
    return titles
  }
}
