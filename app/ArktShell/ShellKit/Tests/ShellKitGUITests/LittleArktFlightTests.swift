import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Little Arkt's Open in flight (#352, docs/design/little-arkt.md, Motion): a snapshot of the page flies from the
/// small window's card into the main window's content card on a transparent, click-through overlay window; the live
/// page moves once, at rest, and the snapshot crossfades away after the page's first frame there.
///
/// Every flight here is stepped by hand (`drivesDisplayLink = false`, `tick(at:)`) on times the test chooses, and the
/// snapshot arrives when the test releases it, so nothing depends on how long the machine takes.
@MainActor
final class LittleArktFlightTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private var gates: [SnapshotGate] = []
  private let popupURL = URL(string: "arkt-test://page/SignIn")!
  private static let frame = 1.0 / 120

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for gate in gates { gate.deliver(nil) }
    gates = []
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts {
        little.flight?.overlay.orderOut(nil)
        little.window.orderOut(nil)
      }
    }
    sets = []
  }

  // MARK: Harness

  private struct Scene {
    let set: ShellWindowSet
    let engine: InMemoryEngine
    let main: ShellWindowController
    let little: LittleArktWindowController
    let littleWindow: EngineWindowID
    let tab: TabID
    let gate: SnapshotGate
  }

  /// A main window with `todayTabs` Today rows, and a Little Arkt popup whose motion and flight are stepped by hand.
  private func makeScene(reduceMotion: Bool = false, todayTabs: Int = 0, clock: ManualClock? = nil) throws -> Scene {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { reduceMotion }
    let gate = SnapshotGate()
    gates.append(gate)
    set.littleArktConfigure = { little in
      little.drivesDisplayLink = false
      if let clock { little.motionClock = { clock.now } }
      little.snapshotSource = { [gate] tab in await gate.source(tab) }
    }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let main = set.openWindow()
    for index in 0..<todayTabs {
      main.open(try XCTUnwrap(URL(string: "arkt-test://page/Today\(index)")), inNewTab: true)
    }
    main.window?.contentView?.layoutSubtreeIfNeeded()
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: popupURL, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    if clock == nil { little.finishMotion() }                 // the appear at rest, unless the test steps it
    little.window.contentView?.layoutSubtreeIfNeeded()
    return Scene(set: set, engine: engine, main: main, little: little, littleWindow: id, tab: tab, gate: gate)
  }

  /// Steps `flight` from `start` until `done` holds, one 120 Hz frame at a time; the time it held, or nil after 5 s
  /// of flight time.
  @discardableResult
  private func step(_ flight: LittleArktFlight, from start: Double, until done: () -> Bool) -> Double? {
    var t = start
    while t < start + 5 {
      flight.tick(at: t)
      if done() { return t }
      t += Self.frame
    }
    return nil
  }

  /// Turns the main actor until the snapshot task has handed `flight` its image, at most 200 turns.
  private func awaitSnapshot(_ flight: LittleArktFlight) async throws {
    for _ in 0..<200 where !flight.hasSnapshot {
      await Task.yield()
    }
    XCTAssertTrue(flight.hasSnapshot, "the released snapshot reached the flight")
  }

  private func screenCard(of main: ShellWindowController) throws -> CGRect {
    let card = main.rootView.card
    let window = try XCTUnwrap(card.window)
    return window.convertToScreen(card.convert(card.bounds, to: nil))
  }

  // MARK: The overlay

  func testTheOverlayIsTransparentClickThroughAndSpansBothWindows() throws {
    let scene = try makeScene()
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    XCTAssertFalse(flight.overlay.isVisible, "nothing changes on screen before the first frame")

    flight.tick(at: 0)

    let overlay = flight.overlay
    let mainWindow = try XCTUnwrap(scene.main.window)
    XCTAssertTrue(overlay.isVisible)
    XCTAssertFalse(overlay.isOpaque)
    XCTAssertEqual(overlay.backgroundColor, .clear)
    XCTAssertFalse(overlay.hasShadow)
    XCTAssertTrue(overlay.ignoresMouseEvents, "clicks go through to the windows below")
    XCTAssertTrue(overlay.isExcludedFromWindowsMenu)
    XCTAssertFalse(overlay.canBecomeKey)
    XCTAssertTrue(overlay.frame.contains(scene.little.window.frame), "spans the Little Arkt window")
    XCTAssertTrue(overlay.frame.contains(mainWindow.frame), "and the main window")
    XCTAssertGreaterThan(overlay.level.rawValue, mainWindow.level.rawValue)
    XCTAssertGreaterThan(overlay.level.rawValue, scene.little.window.level.rawValue)
    XCTAssertTrue(mainWindow.isVisible, "the main window comes forward at the start")
  }

  // MARK: The flight

  /// The small frame fades at once (`fadeOut`, 0.12 s), the card flies to the main card, and the page never moves
  /// mid-flight: it moves once at rest, mounted at its final size, and the snapshot crossfades away after its first
  /// frame there.
  func testTheLiveViewMovesOnceAtRestAndTheSnapshotCrossfadesAway() throws {
    let scene = try makeScene()
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let pageFrame = page.frame
    let target = try screenCard(of: scene.main)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    XCTAssertEqual(scene.little.lastTransition, .fadeOut, "the small frame fades at once")

    var t = 0.0
    var positions: [CGFloat] = []
    while flight.stage == .flying, t < 5 {
      XCTAssertTrue(page.isDescendant(of: scene.little.card), "the live page stays in the small window at \(t)")
      XCTAssertEqual(page.frame, pageFrame, "and keeps its frame at \(t)")
      XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "no move at \(t)")
      positions.append(flight.cardFrameOnScreen.midX)
      t += Self.frame
      flight.tick(at: t)
    }
    XCTAssertEqual(flight.stage, .landed, "the flight came to rest")
    XCTAssertGreaterThan(positions.count, 30, "it flew over several frames")
    XCTAssertEqual(flight.cardFrameOnScreen, target, "at rest on the main card")

    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.main.engineWindow, "moved once, at rest")
    XCTAssertTrue(scene.engine.contentView(for: scene.tab) === page, "the same page view, not a reload")
    XCTAssertTrue(page.isDescendant(of: scene.main.rootView.card))
    XCTAssertEqual(page.frame.width, scene.main.rootView.card.clipView.bounds.width, "mounted at its final size")
    XCTAssertEqual(scene.main.currentTab, scene.tab)
    XCTAssertTrue(flight.overlay.isVisible, "the snapshot covers the page until its first frame")

    t += Self.frame
    flight.tick(at: t)                                        // the page's first frame in the main card
    XCTAssertEqual(flight.stage, .crossfading)
    t += 0.05
    flight.tick(at: t)
    XCTAssertLessThan(flight.cardLayer.opacity, 1)
    XCTAssertGreaterThan(flight.cardLayer.opacity, 0)
    XCTAssertNotNil(step(flight, from: t + Self.frame) { flight.stage == .finished }, "the crossfade ends")
    XCTAssertFalse(flight.overlay.isVisible, "the overlay is removed")
    XCTAssertNil(flight.snapshotLayer.contents, "and lets go of the image")
    waitUntil("the emptied Little Arkt window closes") { !scene.little.window.isVisible }
    XCTAssertTrue(scene.set.littleArkts.isEmpty)
  }

  /// No snapshot within one frame: the card flies as its plate (the page's background), and the snapshot fades in on
  /// it when it arrives.
  func testThePlateFliesWhenTheSnapshotIsNotReadyWithinOneFrame() async throws {
    let scene = try makeScene()
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    XCTAssertEqual(flight.snapshotLayer.opacity, 0, "no snapshot yet")
    XCTAssertNotNil(flight.cardLayer.backgroundColor, "the plate")
    XCTAssertEqual(flight.cardLayer.opacity, 1)

    scene.gate.deliver(try SnapshotGate.snapshot())
    try await awaitSnapshot(flight)
    flight.tick(at: 0.05)                                     // the frame after it arrived starts the fade
    flight.tick(at: 0.1)
    XCTAssertGreaterThan(flight.snapshotLayer.opacity, 0, "the snapshot fades in on the plate")
    XCTAssertLessThan(flight.snapshotLayer.opacity, 1)
    flight.tick(at: 0.8)
    XCTAssertEqual(flight.snapshotLayer.opacity, 1, accuracy: 0.01)
  }

  func testASnapshotReadyWithinOneFrameFliesFromTheStart() async throws {
    let scene = try makeScene()
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    let snapshot = try SnapshotGate.snapshot()
    scene.gate.deliver(snapshot)
    try await awaitSnapshot(flight)

    flight.tick(at: 0)

    XCTAssertEqual(flight.snapshotLayer.opacity, 1, "no fade: it was ready for the first frame")
    XCTAssertNotNil(flight.snapshotLayer.contents)
    XCTAssertEqual(flight.snapshotLayer.contentsScale, 2)
    XCTAssertEqual(flight.snapshotLayer.bounds.size, snapshot.pointSize, "drawn at the page's size, not stretched")
  }

  // MARK: The Today rows

  func testTheTodayRowsMakeRoomAfter200Milliseconds() throws {
    let scene = try makeScene(todayTabs: 2)
    let space = try XCTUnwrap(scene.main.currentSpace)
    let before = scene.main.sidebar.children(of: .today(space))
    let firstOld = try XCTUnwrap(before.first)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    let today = scene.main.sidebar.children(of: .today(space))
    XCTAssertEqual(Array(today.dropFirst()), before, "the new row is at the top of Today")
    let arrived = try XCTUnwrap(today.first)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    let height = outline.outlineView.rect(ofRow: outline.row(for: arrived)).height
    XCTAssertEqual(outline.rowStyle(for: arrived).alpha, 0, "the new row is not shown yet")
    XCTAssertEqual(outline.rowStyle(for: firstOld).offsetY, -height, "the rows hold their place")

    flight.tick(at: 0.19)
    XCTAssertEqual(outline.rowStyle(for: firstOld).offsetY, -height, "still holding at 190 ms")
    flight.tick(at: 0.26)
    XCTAssertGreaterThan(outline.rowStyle(for: firstOld).offsetY, -height, "making room after 200 ms")
    XCTAssertLessThan(outline.rowStyle(for: firstOld).offsetY, 0)
    XCTAssertEqual(outline.rowStyle(for: arrived).alpha, 0, "the new row follows 90 ms later")
    flight.tick(at: 0.36)
    XCTAssertGreaterThan(outline.rowStyle(for: arrived).alpha, 0)
    XCTAssertNotNil(step(flight, from: 0.37) { flight.stage != .flying })
    XCTAssertEqual(outline.rowStyle(for: firstOld), .rest)
    XCTAssertEqual(outline.rowStyle(for: arrived), .rest)
    XCTAssertEqual(scene.main.sidebarController.current, arrived, "selected once the page is there")
  }

  /// The chooser (Cmd-Opt-O) names another Space, empty or not: that Space shows at the start, and the page still
  /// moves only at rest.
  func testOpenInAnotherSpaceMovesThePageOnlyAtRest() throws {
    for filled in [false, true] {
      let scene = try makeScene(todayTabs: 1)
      let first = try XCTUnwrap(scene.main.currentSpace)
      let other = try XCTUnwrap(scene.main.createSpace())
      if filled {
        _ = try scene.main.sidebar.addTab(url: try XCTUnwrap(URL(string: "arkt-test://page/Other")), title: "Other",
                                          in: .today(other), at: nil)
      }
      XCTAssertEqual(scene.main.currentSpace, first)
      let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
      scene.little.openIn(space: other)
      let flight = try XCTUnwrap(scene.little.flight)
      var t = 0.0
      flight.tick(at: t)
      XCTAssertEqual(scene.main.currentSpace, other, "the chosen Space shows at the start (filled \(filled))")
      while flight.stage == .flying, t < 5 {
        XCTAssertTrue(page.isDescendant(of: scene.little.card), "the page stays put at \(t) (filled \(filled))")
        XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "no move at \(t)")
        t += Self.frame
        flight.tick(at: t)
      }
      XCTAssertEqual(flight.stage, .landed)
      XCTAssertTrue(page.isDescendant(of: scene.main.rootView.card))
      XCTAssertEqual(scene.main.sidebar.children(of: .today(other)).first.flatMap { scene.main.tabsByNode[$0] },
                     scene.tab, "the first Today tab of the chosen Space")
      XCTAssertEqual(scene.main.currentTab, scene.tab)
    }
  }

  // MARK: No flight

  /// A minimized, other-desktop or full-screen main window, or Reduce Motion: today's path. The small window fades
  /// out (0.12 s), then the page moves.
  func testNoFlightForAMainWindowTheUserCannotSee() throws {
    let cases: [LittleArktFlightConditions] = [
      LittleArktFlightConditions(mainMiniaturized: true),
      LittleArktFlightConditions(mainOnActiveSpace: false),
      LittleArktFlightConditions(mainFullScreen: true),
    ]
    for conditions in cases {
      let scene = try makeScene()
      scene.little.mainWindowConditions = { _ in conditions }
      scene.little.openIn()
      XCTAssertNil(scene.little.flight, "\(conditions)")
      XCTAssertEqual(scene.little.lastTransition, .fadeOut)
      XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "the fade first")
      scene.little.finishMotion()
      XCTAssertEqual(scene.main.currentTab, scene.tab, "\(conditions)")
      XCTAssertEqual(scene.gate.asked, 0, "no snapshot is taken")
    }
  }

  func testReduceMotionKeepsTodaysFades() throws {
    let scene = try makeScene(reduceMotion: true)
    scene.little.openIn()
    XCTAssertNil(scene.little.flight)
    XCTAssertEqual(scene.little.lastTransition, .fadeOut)
    scene.little.finishMotion()
    XCTAssertEqual(scene.main.currentTab, scene.tab)
  }

  // MARK: Interrupt

  /// Open in during the appear (prototype: Play > Interrupt): the flight starts from the card's current scale and
  /// opacity, without a jump.
  func testOpenInDuringTheAppearStartsFromWhereTheAppearIs() throws {
    let clock = ManualClock()
    let scene = try makeScene(clock: clock)
    XCTAssertEqual(scene.little.lastTransition, .appear)
    clock.now = 0.04
    let appear = scene.little.currentScene
    XCTAssertLessThan(appear[.scale], 0.99, "mid-appear")
    XCTAssertLessThan(appear[.opacity], 0.99)

    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    XCTAssertEqual(flight.startScene[.scale], appear[.scale], accuracy: 1e-9)
    XCTAssertEqual(flight.startScene[.opacity], appear[.opacity], accuracy: 1e-9)
    XCTAssertEqual(Double(flight.cardLayer.opacity), appear[.opacity], accuracy: 1e-6)
    XCTAssertEqual(flight.cardLayer.transform.m11, CGFloat(appear[.scale]), accuracy: 1e-6)
    XCTAssertNotNil(step(flight, from: Self.frame) { flight.stage != .flying })
    XCTAssertEqual(flight.cardLayer.transform.m11, 1, accuracy: 1e-6)
    XCTAssertEqual(flight.cardLayer.opacity, 1)
  }
}

/// A clock a test sets by hand.
@MainActor
final class ManualClock {
  var now: CFTimeInterval = 0
}

/// Holds the flight's snapshot until the test releases it.
@MainActor
final class SnapshotGate {
  private var waiting: [CheckedContinuation<LittleArktSnapshot?, Never>] = []
  private var released: LittleArktSnapshot??
  private(set) var asked = 0

  func source(_ tab: TabID) async -> LittleArktSnapshot? {
    asked += 1
    if let released { return released }
    return await withCheckedContinuation { waiting.append($0) }
  }

  func deliver(_ snapshot: LittleArktSnapshot?) {
    released = .some(snapshot)
    for continuation in waiting { continuation.resume(returning: snapshot) }
    waiting = []
  }

  /// A 468 x 574 pt page at 2x: the default Little Arkt card.
  static func snapshot() throws -> LittleArktSnapshot {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: nil, width: 936, height: 1148, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
    context.setFillColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 936, height: 1148))
    return LittleArktSnapshot(image: try XCTUnwrap(context.makeImage()), scale: 2)
  }
}
