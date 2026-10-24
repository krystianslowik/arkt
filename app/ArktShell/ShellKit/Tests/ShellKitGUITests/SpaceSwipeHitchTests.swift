import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

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

  override func tearDown() async throws { controller.close() }

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

  /// Touching down freezes the settle with the view frame where the strip shows, so rows under the fingers hit-test.
  func testFrozenSettleSyncsTheStripFrame() async throws {
    let pager = controller.pager
    controller.nextSpace(nil)
    try? await Task.sleep(nanoseconds: 60_000_000)
    try PacingEnvironment.requireCaught(pager.isSettling, "the settle still running at touch down")
    pager.gestureMayBegin()
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0)
    XCTAssertEqual(pager.strip.frame.minX, pager.offset, accuracy: 0.01)
    pager.stopInteraction()
  }

  /// Personal -> Work -> Dev (dark) -> Work -> Personal, by swipe and by keyboard. The two `flavor` legs cross the
  /// halfway point where the sidebar chrome flips between light and dark; that pass is reported but not gated here
  /// (#275: the appearance flip costs 4 ms in an optimized build and up to 16 ms in Debug).
  private static let labels = ["swipe-next", "key-flavor-next", "swipe-flavor-back", "swipe-back", "key-next",
                               "key-previous"]

  /// #24: main-thread CPU of every run loop pass during scripted swipes and keyboard switches both ways stays under
  /// one 120 Hz refresh. Thread CPU time does not include time the thread was preempted, so this holds on a loaded machine where the
  /// wall-clock pacing test reports NOT-MEASURABLE. Before the fix (strip moved with `setFrameOrigin`) single passes
  /// took 10-15 ms of CPU and about 1 in 20 passes of a swipe-back went over 8.3 ms; after it the maximum was
  /// under 5 ms.
  func testSpaceSwitchPassesStayUnderOneFrameOfMainThreadCPU() async throws {
    // CPU time does not depend on load, but it does on the hardware: a virtualized runner below 120 Hz (CI) is not
    // the machine this budget is for, and its display link ticks too rarely to drive the scripted frames.
    let fps = controller.window?.screen?.maximumFramesPerSecond ?? 0
    if fps < 120 { throw XCTSkip("NOT-MEASURABLE (screen \(fps) Hz)") }
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
      print(String(format: "spaceswipe.cost label=%@ passes=%d cpuMedianMs=%.2f cpuP95Ms=%.2f cpuMaxMs=%.2f "
                   + "over8.3=%d over4=%d frame0MedianMs=%.2f frame0MaxMs=%.2f", label, cpu.count, ms(cpu, 0.5),
                   ms(cpu, 0.95), (cpu.last ?? 0) * 1000, cpu.filter { $0 > 0.0083 }.count,
                   cpu.filter { $0 > 0.004 }.count, ms(frame0, 0.5), (frame0.last ?? 0) * 1000))
      XCTAssertGreaterThan(cpu.count, rounds * 10, "\(label): the probe saw the interaction's passes")
      if !label.contains("flavor") { worst = max(worst, cpu.last ?? 0) }
    }
    for h in hitches {
      print(String(format: "spaceswipe.hitch label=%@ frame=%d ms=%.2f prevLateMs=%.2f busyMs=%.2f cpuMs=%.2f "
                   + "offCpuMs=%.2f passes=%d", h.label, h.frame, h.interval * 1000, h.previousLate * 1000,
                   (h.longest?.wall ?? 0) * 1000, (h.longest?.cpu ?? 0) * 1000, (h.longest?.offCPU ?? 0) * 1000,
                   h.passes))
    }
    var load = [0.0]
    _ = getloadavg(&load, 1)
    print(String(format: "spaceswipe.summary rounds=%d hitches=%d load1=%.2f", rounds, hitches.count, load[0]))
    XCTAssertLessThan(worst, FrameStats().designBudget, "a Space switch pass took a whole 120 Hz frame of main-thread CPU")
  }
}
