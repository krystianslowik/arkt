import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI
@testable import Motion

/// Steps a scripted swipe once per display frame.
@MainActor
private final class SteppedSwipe: NSObject {
  private var link: CADisplayLink?
  private var remaining: Int
  private let step: @MainActor () -> Void
  private let done: @MainActor () -> Void

  init(view: NSView, frames: Int, step: @escaping @MainActor () -> Void, done: @escaping @MainActor () -> Void) {
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
    step()
  }
}

/// #24: main-thread cost of each frame of a scripted Space swipe, per frame index and direction, measured with the
/// pacer's run loop probe (thread CPU time, so it holds on a loaded machine where wall-clock pacing does not).
@MainActor
final class SpaceSwipeHitchTests: XCTestCase {
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

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    controller.close()
    controller = nil
    sidebar = nil
  }

  /// One main run loop pass of an interaction; `frame` is the scripted step it ran, if any.
  struct Pass { var cpu: Double; var wall: Double; var frame: Int? }

  /// Runs `start` (which begins an interaction that ends in a settle) and returns every main run loop pass until the
  /// settle, with the scripted step index for the passes that ran one.
  private func passes(_ start: (_ stepRan: @escaping @MainActor () -> Void) -> Void) async -> [Pass] {
    let probe = MainThreadBusyProbe(capacity: 4096)
    var stepTimes: [CFTimeInterval] = []
    probe.start()
    let settled = expectation(description: "settled")
    controller.pager.onSettleForTesting = { _ in settled.fulfill() }
    start { stepTimes.append(CACurrentMediaTime()) }
    await fulfillment(of: [settled], timeout: 5)
    controller.pager.onSettleForTesting = nil
    probe.stop()
    return probe.spans.map { span in
      Pass(cpu: span.cpu, wall: span.wall, frame: stepTimes.firstIndex { span.start <= $0 && $0 <= span.end })
    }
  }

  /// A scripted swipe of 20 display frames of `delta` points each (the smoke's medium swipe), then release.
  private func swipe(delta: CGFloat) async -> [Pass] {
    let pager = controller.pager
    var script: SteppedSwipe?
    let result = await passes { stepRan in
      pager.gestureMayBegin()
      pager.beginTracking()
      script = SteppedSwipe(view: pager, frames: 20, step: {
        stepRan()
        pager.track(delta: delta, at: CACurrentMediaTime())
      }, done: { pager.endTracking() })
    }
    _ = script
    return result
  }

  private func keyboardSwitch(next: Bool) async -> [Pass] {
    await passes { _ in if next { controller.nextSpace(nil) } else { controller.previousSpace(nil) } }
  }

  /// The strip moves on its layer while the fingers track it: the view frame (and so AppKit's view geometry, layout
  /// and display under it) stays put, the layer translation follows the fingers without an implicit animation, and
  /// at rest the frame catches up and the translation is cleared.
  func testSwipeMovesTheStripLayerNotItsFrame() async throws {
    let pager = controller.pager
    let restFrame = pager.strip.frame
    pager.beginTracking()
    pager.track(delta: -0.3 * pager.bounds.width, at: 0.01)
    XCTAssertEqual(pager.strip.frame, restFrame, "no view frame change per frame")
    XCTAssertEqual(pager.stripLayerShiftForTesting, pager.offset - restFrame.minX, accuracy: 0.5)
    XCTAssertNil(pager.strip.layer?.animationKeys(), "the translation is not animated implicitly")
    let settled = expectation(description: "settled")
    pager.onSettleForTesting = { _ in settled.fulfill() }
    pager.endTracking()
    await fulfillment(of: [settled], timeout: 3)
    pager.onSettleForTesting = nil
    XCTAssertEqual(pager.index, 1)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, -pager.bounds.width, accuracy: 0.01)
  }

  /// A swipe or a keyboard switch shows each page it passes at most once and hides it at most once at rest, however
  /// the settle swings around the destination: each show or hide updates every row's tracking areas, and those ask
  /// the window server where the pointer is (a blocking round trip on the main thread).
  func testAnInteractionShowsAndHidesEachPageOnce() async throws {
    try await checkShowsAndHidesEachPageOnce()
  }

  /// Reduce Motion: the settle presents its final value at once, before its completion runs.
  func testAnInteractionShowsAndHidesEachPageOnceWithReduceMotion() async throws {
    controller.pager.reduceMotionForTesting = true
    try await checkShowsAndHidesEachPageOnce()
  }

  private func checkShowsAndHidesEachPageOnce() async throws {
    let pager = controller.pager
    for (label, run) in [("swipe-next", { await self.swipe(delta: -9) }), ("swipe-back", { await self.swipe(delta: 9) }),
                         ("key-next", { await self.keyboardSwitch(next: true) }),
                         ("key-previous", { await self.keyboardSwitch(next: false) })] {
      let before = pager.pageVisibilityChangesForTesting
      _ = await run()
      for (page, count) in pager.pageVisibilityChangesForTesting {
        XCTAssertLessThanOrEqual(count - before[page, default: 0], 2, "\(label): page \(page) shown or hidden again")
      }
    }
  }

  /// Presents frames of the pager's running settle at chosen times, 1/120 s apart from `start`, until `reached`
  /// holds for the position or the spring stops. No display link and no waiting: the test runs on the main actor
  /// without suspending, so the real display link cannot present a frame in between.
  private func presentSettleFrames(_ pager: SpacePagerView, from start: CFTimeInterval,
                                   until reached: (CGFloat) -> Bool) -> CFTimeInterval {
    var time = start
    while pager.isSettling, !reached(pager.position), time < start + 2 {
      time += 1.0 / 120
      pager.driver.tick(at: time)
    }
    return time
  }

  /// Starts `go(to: 1)` from page 0 and stops it a third of the way (or more) there, with the strip shown on its
  /// layer translation. Returns the time of the last presented frame.
  private func midSettle(_ pager: SpacePagerView) throws -> CFTimeInterval {
    pager.reduceMotionForTesting = false
    XCTAssertEqual(pager.index, 0)
    let start = CACurrentMediaTime()
    pager.go(to: 1)
    let time = presentSettleFrames(pager, from: start) { $0 >= 0.3 }
    XCTAssertTrue(pager.isSettling, "mid-settle")
    XCTAssertGreaterThanOrEqual(pager.position, 0.3)
    XCTAssertLessThan(pager.position, 0.9)
    XCTAssertNotEqual(pager.stripLayerShiftForTesting, 0, "mid-settle the strip shows on its layer translation")
    return time
  }

  /// A click mid-settle lands on what is drawn under the pointer. In the pager's right part page 1 already shows
  /// there; the strip's view frame from before the settle puts page 0 there. The hit test brings the view geometry to
  /// the screen first, so the hit is on page 1 and page 1 converts the point with its on-screen frame (a table would
  /// pick the row under the pointer). The settle carries on to page 1 from there.
  func testAHitTestMidSettleFindsTheViewShownUnderThePoint() throws {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    let width = pager.bounds.width
    let time = try midSettle(pager)
    let local = NSPoint(x: width * 0.85, y: pager.bounds.midY)
    let point = pager.convert(local, to: nil)
    let hit = try XCTUnwrap(window.contentView?.hitTest(point))
    XCTAssertTrue(hit === pager.pages[1] || hit.isDescendant(of: pager.pages[1]), "hit \(hit) is not on page 1")
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, pager.offset, accuracy: 0.5, "the synced frame is within a backing pixel")
    let framePixels = pager.strip.frame.minX * pager.shellBackingScale
    XCTAssertEqual(framePixels, framePixels.rounded(), accuracy: 0.000001)
    XCTAssertEqual(pager.pages[1].convert(point, from: nil).x, local.x - (pager.offset + width), accuracy: 0.5,
                   "page 1 converts the click with the frame it shows at")
    XCTAssertTrue(pager.isSettling, "the click does not stop the settle")
    _ = presentSettleFrames(pager, from: time) { _ in false }
    XCTAssertFalse(pager.isSettling)
    XCTAssertEqual(pager.index, 1)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, -width, accuracy: 0.01)
  }

  /// Hit tests for the changed-phase and momentum events of a scroll gesture leave the geometry alone (they stream at
  /// display rate); the first event of a gesture, a wheel click and every other event bring it to the screen.
  func testOnlyGestureStartsAndNonScrollEventsSyncTheGeometryOnAHitTest() throws {
    func scroll(phase: Int64, momentum: Int64 = 0, continuous: Bool = true) throws -> NSEvent {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: 0, wheel2: -4, wheel3: 0))
      cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
      cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
      cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
      return try XCTUnwrap(NSEvent(cgEvent: cg))
    }
    XCTAssertTrue(SpacePagerView.hitTestNeedsCurrentGeometry(for: nil))
    XCTAssertTrue(SpacePagerView.hitTestNeedsCurrentGeometry(for: try scroll(phase: 128)), "may begin")
    XCTAssertTrue(SpacePagerView.hitTestNeedsCurrentGeometry(for: try scroll(phase: 1)), "began")
    XCTAssertFalse(SpacePagerView.hitTestNeedsCurrentGeometry(for: try scroll(phase: 2)), "changed")
    XCTAssertFalse(SpacePagerView.hitTestNeedsCurrentGeometry(for: try scroll(phase: 0, momentum: 2)), "momentum")
    XCTAssertTrue(SpacePagerView.hitTestNeedsCurrentGeometry(for: try scroll(phase: 0, continuous: false)), "wheel")
    let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: 1))
    XCTAssertTrue(SpacePagerView.hitTestNeedsCurrentGeometry(for: click))
  }

  /// A pointer moving over the strip mid-settle syncs the geometry, so rows enter and leave by where they show.
  func testAPointerMoveMidSettleSyncsTheStripFrame() throws {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    _ = try midSettle(pager)
    let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                                                location: pager.convert(NSPoint(x: 10, y: 10), to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    pager.mouseMoved(with: move)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, pager.offset, accuracy: 0.5)
    XCTAssertTrue(pager.isSettling)
    pager.stopInteraction()
  }

  /// A pointer moving on every frame of a settle must not put the per-frame geometry sync back (#295): at most one
  /// sync per `pointerSyncFrameInterval` presented frames, while the first move still syncs and hover stays right at
  /// rest.
  func testAPointerMovingEveryFrameMidSettleSyncsAtMostOncePerFewFrames() throws {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    var time = try midSettle(pager)
    let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                                                location: pager.convert(NSPoint(x: 10, y: 10), to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    // The first move of the settle syncs: the frame catches up to the screen and hover is right from there.
    pager.mouseMoved(with: move)
    let synced = pager.stripFrameSyncsForTesting
    XCTAssertGreaterThanOrEqual(synced, 1)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    // Each following frame moves the strip again. A pointer move on each of them, inside the interval, must leave
    // the geometry alone; it is the per-frame path #24 removed.
    for _ in 1..<SpacePagerView.pointerSyncFrameInterval {
      time += 1.0 / 120
      pager.driver.tick(at: time)
      pager.mouseMoved(with: move)
      XCTAssertEqual(pager.stripFrameSyncsForTesting, synced, "a pointer move synced again inside the rate limit")
      XCTAssertNotEqual(pager.stripLayerShiftForTesting, 0, "the strip still translates on its layer")
    }
    // The next presented frame is past the interval: a move syncs again.
    time += 1.0 / 120
    pager.driver.tick(at: time)
    pager.mouseMoved(with: move)
    XCTAssertEqual(pager.stripFrameSyncsForTesting, synced + 1)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    // At rest, hover does not need another sync: the settle leaves the frame on the page boundary.
    pager.stopInteraction()
    let atRest = pager.stripFrameSyncsForTesting
    pager.mouseMoved(with: move)
    XCTAssertEqual(pager.stripFrameSyncsForTesting, atRest)
    XCTAssertEqual(pager.strip.frame.minX, pager.offset, accuracy: 0.001)
  }

  /// A sync mid-motion rounds the strip frame to whole backing pixels, so the layer translations that follow start
  /// from a pixel-aligned origin instead of keeping the fractional offset of the frame that happened to be current.
  func testASyncMidMotionRoundsTheStripFrameToBackingPixels() throws {
    let pager = controller.pager
    let window = try XCTUnwrap(pager.window)
    let scale = pager.shellBackingScale
    XCTAssertGreaterThan(scale, 0)
    pager.beginTracking()
    pager.track(delta: -100.3, at: 0.01)
    let fractionalPixels = pager.offset * scale
    XCTAssertNotEqual(fractionalPixels.rounded(), fractionalPixels, accuracy: 0.0001,
                      "the tracked offset is between backing pixels")
    let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                                                location: pager.convert(NSPoint(x: 10, y: 10), to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    pager.mouseMoved(with: move)
    XCTAssertTrue(pager.isTracking)
    let framePixels = pager.strip.frame.minX * scale
    XCTAssertEqual(framePixels, framePixels.rounded(), accuracy: 0.000001,
                   "the synced frame origin is a whole number of backing pixels")
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    // The next translation is measured from the aligned frame, so the strip stays on whole pixels mid-motion.
    pager.track(delta: -1.3, at: 0.02)
    let shownPixels = (pager.strip.frame.minX + pager.stripLayerShiftForTesting) * scale
    XCTAssertEqual(shownPixels, shownPixels.rounded(), accuracy: 0.000001)
    pager.stopInteraction()
  }

  /// A backing change mid-settle (the window dragged to a display with another scale) moves the strip's geometry to
  /// where it shows and clears the translation, so AppKit resetting the backing layer's transform loses nothing; the
  /// next frame translates from there.
  func testABackingChangeMidSettleKeepsTheStripWhereItShows() throws {
    let pager = controller.pager
    let time = try midSettle(pager)
    let shown = pager.strip.frame.minX + pager.stripLayerShiftForTesting
    pager.viewDidChangeBackingProperties()
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, shown, accuracy: 0.5, "the strip stays where it showed")
    XCTAssertTrue(pager.isSettling)
    pager.driver.tick(at: time + 1.0 / 120)
    XCTAssertEqual(pager.strip.frame.minX + pager.stripLayerShiftForTesting, pager.offset, accuracy: 0.5)
    pager.stopInteraction()
  }

  /// Touching down freezes the settle with the view frame where the strip shows, so rows under the fingers hit-test.
  func testFrozenSettleSyncsTheStripFrame() throws {
    let pager = controller.pager
    _ = try midSettle(pager)
    pager.gestureMayBegin()
    XCTAssertFalse(pager.isSettling)
    XCTAssertEqual(pager.frozenTarget, 1)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, pager.offset, accuracy: 0.01)
    pager.stopInteraction()
  }

  /// Stopping mid-settle leaves the pager at rest on its last settled page: the moving range is dropped, so a later
  /// at-rest update cannot show the abandoned target.
  func testStopInteractionMidSettleRestsOnTheSettledPage() throws {
    let pager = controller.pager
    _ = try midSettle(pager)
    XCTAssertFalse(pager.pages[1].isHidden, "page 1 shows while the strip moves")
    pager.stopInteraction()
    XCTAssertFalse(pager.isSettling)
    XCTAssertEqual(pager.targetIndex, pager.index)
    XCTAssertEqual(pager.pages.indices.filter { !pager.pages[$0].isHidden }, [pager.index])
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
  }

  /// Personal -> Work -> Dev (dark) -> Work -> Personal, by swipe and by keyboard. The two `flavor` legs cross the
  /// halfway point where the sidebar chrome flips between light and dark; that pass is reported but not gated here
  /// (#275: the appearance flip costs 4 ms in an optimized build and up to 16 ms in Debug).
  private static let labels = ["swipe-next", "key-flavor-next", "swipe-flavor-back", "swipe-back", "key-next",
                               "key-previous"]

  /// The screen-only pacing gate looks at the display, not at load: a test that measures thread CPU time is
  /// measurable on a loaded machine, unlike the wall-clock pacing tests.
  func testScreenOnlyPacingGateIgnoresLoad() throws {
    XCTAssertNil(PacingEnvironment.screenNotMeasurableReason(fps: 120))
    XCTAssertEqual(PacingEnvironment.screenNotMeasurableReason(fps: 60), "screen 60 Hz")
    XCTAssertThrowsError(try PacingEnvironment.skipIfScreenBelow120Hz(fps: 60)) { error in
      XCTAssertTrue(error is XCTSkip)
    }
    XCTAssertNoThrow(try PacingEnvironment.skipIfScreenBelow120Hz(fps: 120))
  }

  /// #24: main-thread CPU of every run loop pass during scripted swipes and keyboard switches both ways stays under
  /// one 120 Hz refresh. Thread CPU time does not include time the thread was preempted, so this holds on a loaded machine where the
  /// wall-clock pacing test reports NOT-MEASURABLE. Before the fix (strip moved with `setFrameOrigin`) single passes
  /// took 10-15 ms of CPU and about 1 in 20 passes of a swipe-back went over 8.3 ms; after it the maximum was
  /// under 5 ms.
  func testSpaceSwitchPassesStayUnderOneFrameOfMainThreadCPU() async throws {
    // CPU time does not depend on load, but it does on the hardware: a virtualized runner below 120 Hz (CI) is not
    // the machine this budget is for, and its display link ticks too rarely to drive the scripted frames. The
    // screen-only gate is deliberate: thread CPU time is the load-independent number of #24.
    try PacingEnvironment.skipIfScreenBelow120Hz(fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
    await checkSpaceSwitchPasses()
  }

  /// #648: the same switches with the sidebar banner shown and Personal's rows running under its fade, so the row
  /// list is masked while Personal is in view and not on the pages whose rows end above it. Opt-in: it runs only with
  /// `ARKT_PACING_GATE=1` (the frame-timing lane), never in the required lane, since its swipes wait on the display.
  func testSpaceSwitchPassesWithTheBannerStayUnderOneFrameOfMainThreadCPU() async throws {
    guard ProcessInfo.processInfo.environment["ARKT_PACING_GATE"] == "1" else {
      throw XCTSkip("set ARKT_PACING_GATE=1 to run the banner's Space switch pacing")
    }
    try PacingEnvironment.skipIfScreenBelow120Hz(fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
    controller.close()
    sidebar = StubSidebar.sample()
    let personal = sidebar.spaceOrder[0]
    for index in 0..<40 {
      _ = sidebar.addTab(url: URL(string: "https://example.com/banner/\(index)")!, title: "Long list tab \(index)",
                         in: .today(personal))
    }
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    let model = SidebarBannerModel(source: ManualSidebarNoticeSource(notices: [.update(version: "1.4.2")]),
                                   dismissals: .ephemeral()) { _, _ in }
    model.reduceMotion = { true }
    let center = SidebarBannerCenter(model: model)
    center.attach(to: controller)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let container = controller.sidebarController.view
    XCTAssertFalse(container.banner.isHidden)
    XCTAssertTrue(container.pager.layer?.mask === container.bannerSlot.fade, "Personal's rows reach the fade")
    await checkSpaceSwitchPasses(prefix: "banner.")
    withExtendedLifetime(center) {}
  }

  private func checkSpaceSwitchPasses(prefix: String = "") async {
    let rounds = Int(ProcessInfo.processInfo.environment["ARKT_SWIPE_ROUNDS"] ?? "") ?? 6
    var hitches: [HitchDetail] = []
    var all: [String: [Pass]] = [:]
    for _ in 0..<rounds {
      for label in Self.labels {
        switch label {
        case "swipe-next": all[label, default: []] += await swipe(delta: -9)
        case "swipe-back", "swipe-flavor-back": all[label, default: []] += await swipe(delta: 9)
        case "key-next", "key-flavor-next": all[label, default: []] += await keyboardSwitch(next: true)
        default: all[label, default: []] += await keyboardSwitch(next: false)
        }
        hitches += controller.pager.pacer.hitchDetails
      }
    }
    var worst = 0.0
    for label in Self.labels {
      let passes = all[label] ?? []
      let cpu = passes.map(\.cpu).sorted()
      let frame0 = passes.filter { $0.frame == 0 }.map(\.cpu).sorted()
      func ms(_ v: [Double], _ q: Double) -> Double { v.isEmpty ? 0 : v[min(v.count - 1, Int(Double(v.count) * q))] * 1000 }
      print(prefix + String(format: "spaceswipe.cost label=%@ passes=%d cpuMedianMs=%.2f cpuP95Ms=%.2f cpuMaxMs=%.2f "
                   + "over8.3=%d over4=%d frame0MedianMs=%.2f frame0MaxMs=%.2f", label, cpu.count, ms(cpu, 0.5),
                   ms(cpu, 0.95), (cpu.last ?? 0) * 1000, cpu.filter { $0 > 0.0083 }.count,
                   cpu.filter { $0 > 0.004 }.count, ms(frame0, 0.5), (frame0.last ?? 0) * 1000))
      XCTAssertGreaterThan(cpu.count, rounds * 10, "\(label): the probe saw the interaction's passes")
      if !label.contains("flavor") { worst = max(worst, cpu.last ?? 0) }
    }
    for h in hitches {
      print(prefix + String(format: "spaceswipe.hitch label=%@ frame=%d ms=%.2f prevLateMs=%.2f busyMs=%.2f cpuMs=%.2f "
                   + "offCpuMs=%.2f passes=%d", h.label, h.frame, h.interval * 1000, h.previousLate * 1000,
                   (h.longest?.wall ?? 0) * 1000, (h.longest?.cpu ?? 0) * 1000, (h.longest?.offCPU ?? 0) * 1000,
                   h.passes))
    }
    var load = [0.0]
    _ = getloadavg(&load, 1)
    print(prefix + String(format: "spaceswipe.summary rounds=%d hitches=%d load1=%.2f", rounds, hitches.count, load[0]))
    XCTAssertLessThan(worst, FrameStats().designBudget, "a Space switch pass took a whole 120 Hz frame of main-thread CPU")
  }

  // MARK: Imported profile (#605)

  /// A distinct favicon per index (as after an import: every site its own icon), `pixels` square, with enough detail
  /// that its PNG does not shrink to a few bytes.
  static func importedFaviconPNG(_ index: Int, pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let hue = CGFloat(index % 97) / 97
    context.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    var seed = UInt64(index) &* 6_364_136_223_846_793_005 &+ 1
    for _ in 0..<(pixels / 2) {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let x = CGFloat(seed >> 40 & 0xFF) / 255 * CGFloat(pixels)
      let y = CGFloat(seed >> 24 & 0xFF) / 255 * CGFloat(pixels)
      let r = CGFloat(seed >> 16 & 0x0F) / 15 * CGFloat(pixels) / 4 + 1
      let dot = NSColor(hue: CGFloat(seed & 0xFF) / 255, saturation: 0.8, brightness: 0.6, alpha: 0.8)
      context.setFillColor(dot.cgColor)
      context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  /// The sample sidebar with an imported Space of `tabs` Today tabs (each with its own favicon) right after Personal,
  /// shown in a fresh window with every favicon handed to the sidebar the way the app does after an import.
  private func showImportedProfile(tabs: Int, pixels: Int) async {
    controller.close()
    sidebar = StubSidebar.sample()
    let imported = sidebar.addSpace(title: "Imported", after: sidebar.spaceOrder[0])
    var favicons: [NodeID: Data] = [:]
    for index in 0..<tabs {
      let node = sidebar.addTab(url: URL(string: "https://site\(index).example/page")!,
                                title: "Imported tab \(index) with a fairly long page title", in: .today(imported))
      if pixels > 0 { favicons[node] = Self.importedFaviconPNG(index, pixels: pixels) }
    }
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.sidebarController.setFavicons(favicons)
    await controller.sidebarController.settleFaviconDecodes()
  }

  /// #605: the first swipe into a Space of 300 imported tabs draws every visible favicon for the first time inside
  /// the swipe's frames. Main-thread CPU of each pass from the first frame on stays under one 120 Hz frame; the pass
  /// that begins the gesture (before any frame, where the page is first shown and laid out) is reported. Before the
  /// fix the favicons were `NSImage(data:)`, decoded lazily on the main thread at first draw.
  func testFirstSwipeIntoAnImportedSpaceStaysUnderOneFrameOfMainThreadCPU() async throws {
    try PacingEnvironment.skipIfScreenBelow120Hz(fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
    let pixels = Int(ProcessInfo.processInfo.environment["ARKT_IMPORTED_FAVICON_PIXELS"] ?? "") ?? 256
    await showImportedProfile(tabs: 300, pixels: pixels)
    let cold = await swipe(delta: -9)
    XCTAssertEqual(controller.pager.index, 1, "the swipe landed on the imported Space")
    _ = await swipe(delta: 9)
    let warm = await swipe(delta: -9)
    /// Passes from the swipe's first frame on, and the ones before it.
    func split(_ passes: [Pass]) -> (begin: [Pass], frames: [Pass]) {
      let first = passes.firstIndex { $0.frame == 0 } ?? passes.count
      return (Array(passes[..<first]), Array(passes[first...]))
    }
    func worst(_ passes: [Pass]) -> Double { (passes.map(\.cpu).max() ?? 0) * 1000 }
    func frame0(_ passes: [Pass]) -> Double { (passes.filter { $0.frame == 0 }.map(\.cpu).max() ?? 0) * 1000 }
    print(String(format: "importedswipe.cost pixels=%d coldBeginMs=%.2f coldFramesMaxMs=%.2f coldFrame0Ms=%.2f "
                 + "warmBeginMs=%.2f warmFramesMaxMs=%.2f warmFrame0Ms=%.2f", pixels, worst(split(cold).begin),
                 worst(split(cold).frames), frame0(cold), worst(split(warm).begin), worst(split(warm).frames),
                 frame0(warm)))
    XCTAssertLessThan(worst(split(cold).frames) / 1000, FrameStats().designBudget,
                      "a frame of the first swipe into the imported Space took a whole 120 Hz frame of main-thread CPU")
  }
}
