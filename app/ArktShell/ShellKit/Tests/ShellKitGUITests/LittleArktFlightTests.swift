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
        little.flight?.abort(.closeRequested)
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
  private func makeScene(reduceMotion: Bool = false, todayTabs: Int = 0, clock: ManualClock? = nil,
                         watchdog: ManualWatchdog? = nil) throws -> Scene {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { reduceMotion }
    let gate = SnapshotGate()
    gates.append(gate)
    set.littleArktConfigure = { little in
      little.drivesDisplayLink = false
      if let clock { little.motionClock = { clock.read() } }
      if let watchdog { little.flightWatchdog = { watchdog.schedule($0) } }
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

  /// #455: the old selection's fill fades out on the room spring while the new row and its selection fade in on the
  /// row spring. Only layer properties move: the rows are not reconfigured per frame.
  func testTheOldSelectionFadesOutAndTheNewSelectionFadesIn() throws {
    let scene = try makeScene(todayTabs: 2)
    let space = try XCTUnwrap(scene.main.currentSpace)
    let old = try XCTUnwrap(scene.main.sidebarController.current)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    let arrived = try XCTUnwrap(scene.main.sidebar.children(of: .today(space)).first)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    XCTAssertEqual(outline.rowStyle(for: old).selectionAlpha, 1, accuracy: 1e-6)
    XCTAssertEqual(outline.displayedState(for: arrived), .current,
                   "the arriving row draws the selection while it fades in")
    XCTAssertEqual(outline.rowStyle(for: arrived).alpha, 0, "the new row is not shown yet")
    let oldRow = try XCTUnwrap(outline.outlineView.rowView(atRow: outline.row(for: old), makeIfNecessary: true)
                                 as? SidebarRowView)
    let arrivedRow = try XCTUnwrap(outline.outlineView.rowView(atRow: outline.row(for: arrived),
                                                               makeIfNecessary: true) as? SidebarRowView)
    XCTAssertEqual(arrivedRow.state, .current)
    let configured = outline.rowConfigureCount
    for t in stride(from: 0.01, to: 0.2, by: 0.02) { flight.tick(at: t) }
    XCTAssertEqual(outline.rowConfigureCount, configured, "no per-frame reconfigure before the room opens")

    flight.tick(at: LittleArktFlightMotion.roomDelay)
    XCTAssertEqual(outline.rowStyle(for: old).selectionAlpha, 1, accuracy: 1e-6,
                   "the room spring starts at 200 ms, so the fill is still full at the edge")
    flight.tick(at: 0.26)
    let fading = outline.rowStyle(for: old).selectionAlpha
    XCTAssertGreaterThan(fading, 0)
    XCTAssertLessThan(fading, 1)
    XCTAssertEqual(oldRow.backgroundLayer.opacity, Float(fading), accuracy: 1e-6)
    XCTAssertEqual(oldRow.state, .current, "only the fill fades; the row keeps its state")
    XCTAssertEqual(oldRow.layer?.opacity, 1, "only the fill layer fades, not the whole row")
    XCTAssertEqual(outline.rowStyle(for: arrived).alpha, 0, "the new row follows 90 ms later")
    flight.tick(at: 0.36)
    XCTAssertGreaterThan(outline.rowStyle(for: arrived).alpha, 0)
    XCTAssertLessThan(outline.rowStyle(for: old).selectionAlpha, fading)

    XCTAssertNotNil(step(flight, from: 0.37) { flight.stage != .flying })
    XCTAssertEqual(scene.main.sidebarController.current, arrived, "selected once the page is there")
    XCTAssertEqual(oldRow.state, .normal, "the old row does not pop back to the previous fill")
    XCTAssertNil(oldRow.displayedFill)
    XCTAssertEqual(oldRow.backgroundLayer.opacity, 1, "the old row draws its fill at rest after the landing")
    XCTAssertEqual(outline.rowStyle(for: old), .rest)
    XCTAssertEqual(outline.rowStyle(for: arrived), .rest)
    XCTAssertEqual(arrivedRow.state, .current)
  }

  /// #455: a landing before the first arrival frame never faded the old fill, so the old row keeps the previous fill
  /// the no-flight path draws instead of losing it without a fade.
  func testAFlightAbortedBeforeItsFirstFrameKeepsThePreviousFill() throws {
    let scene = try makeScene(todayTabs: 2)
    let old = try XCTUnwrap(scene.main.sidebarController.current)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.abort(.framesStopped)                              // lands with no room frame presented

    let space = try XCTUnwrap(scene.main.currentSpace)
    let arrived = try XCTUnwrap(scene.main.sidebar.children(of: .today(space)).first)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    XCTAssertEqual(scene.main.sidebarController.current, arrived)
    XCTAssertEqual(outline.state(for: old), .previous, "the fill never faded")
    let oldRow = try XCTUnwrap(outline.outlineView.rowView(atRow: outline.row(for: old), makeIfNecessary: true)
                                 as? SidebarRowView)
    XCTAssertEqual(oldRow.state, .previous)
    XCTAssertNotNil(oldRow.displayedFill)
  }

  /// #455: the page closing itself mid-flight takes the arrival back, so the old selection stays and its fill returns
  /// to full: nothing of the fade is left behind.
  func testAPageClosedMidFlightLeavesTheOldSelectionAtFullOpacity() throws {
    let scene = try makeScene(todayTabs: 2)
    let old = try XCTUnwrap(scene.main.sidebarController.current)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    flight.tick(at: 0.26)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    let fading = try XCTUnwrap(outline.outlineView.rowView(atRow: outline.row(for: old), makeIfNecessary: true)
                                 as? SidebarRowView)
    XCTAssertLessThan(fading.backgroundLayer.opacity, 1, "the fill was fading")

    flight.abort(.pageClosed)

    XCTAssertEqual(scene.main.sidebarController.current, old, "the page never came, so the selection stays")
    let oldRow = try XCTUnwrap(outline.outlineView.rowView(atRow: outline.row(for: old), makeIfNecessary: true)
                                 as? SidebarRowView)
    XCTAssertEqual(oldRow.state, .current)
    XCTAssertEqual(oldRow.backgroundLayer.opacity, 1, "the fill is back at rest")
    XCTAssertEqual(outline.rowStyle(for: old), .rest)
  }

  /// #455: the arrival belongs to the outline of the Space that owns the row, so switching Space mid-flight keeps
  /// drawing it there instead of freezing it and leaving its row stuck as the selection.
  func testASpaceSwitchMidFlightKeepsTheArrivalOnItsOwnOutline() throws {
    let scene = try makeScene(todayTabs: 2)
    let space = try XCTUnwrap(scene.main.currentSpace)
    let old = try XCTUnwrap(scene.main.sidebarController.current)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    let arrived = try XCTUnwrap(scene.main.sidebar.children(of: .today(space)).first)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    let other = try XCTUnwrap(scene.main.createSpace())
    scene.main.sidebarController.showSpace(other)
    XCTAssertEqual(scene.main.currentSpace, other, "the window shows another Space mid-flight")

    for t in stride(from: 0.01, through: 0.36, by: 0.01) { flight.tick(at: t) }
    XCTAssertGreaterThan(outline.rowStyle(for: arrived).alpha, 0,
                         "the arrival keeps advancing on the outline that owns the row")
    XCTAssertLessThan(outline.rowStyle(for: old).selectionAlpha, 1, "the old fill keeps fading there too")

    XCTAssertNotNil(step(flight, from: 0.37) { flight.stage != .flying })
    XCTAssertEqual(scene.main.currentSpace, space, "landing shows the row's Space")
    XCTAssertEqual(scene.main.sidebarController.current, arrived)
    XCTAssertEqual(outline.rowStyle(for: old), .rest)
    XCTAssertEqual(outline.rowStyle(for: arrived), .rest, "nothing of the arrival is left running")
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

  /// #455: Reduce Motion has no flight and so no fades. The instant change stays, including the old row's previous
  /// fill; nothing is cleared on this path.
  func testReduceMotionKeepsTheInstantSelectionChange() throws {
    let scene = try makeScene(reduceMotion: true, todayTabs: 2)
    let space = try XCTUnwrap(scene.main.currentSpace)
    let old = try XCTUnwrap(scene.main.sidebarController.current)
    scene.little.openIn()
    XCTAssertNil(scene.little.flight)
    scene.little.finishMotion()
    let arrived = try XCTUnwrap(scene.main.sidebar.children(of: .today(space)).first)
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    XCTAssertEqual(scene.main.sidebarController.current, arrived)
    XCTAssertEqual(outline.state(for: old), .previous, "today's instant path keeps the previous fill")
    XCTAssertEqual(outline.rowStyle(for: old), .rest)
    XCTAssertEqual(outline.rowStyle(for: arrived), .rest)
  }

  // MARK: Abort (a flight that cannot land by itself)

  /// A flight in the air: opened, started, and a few frames in.
  private func flyAFewFrames(_ scene: Scene) throws -> LittleArktFlight {
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    flight.tick(at: 0.1)
    XCTAssertEqual(flight.stage, .flying)
    XCTAssertTrue(flight.overlay.isVisible)
    return flight
  }

  /// The page landed in the main window with no flight, and nothing of the flight is left on screen.
  private func assertLandedWithoutTheFlight(_ scene: Scene, _ flight: LittleArktFlight, _ page: NSView,
                                            _ message: String, line: UInt = #line) {
    XCTAssertEqual(flight.stage, .finished, message, line: line)
    XCTAssertFalse(flight.overlay.isVisible, "the overlay is gone: \(message)", line: line)
    XCTAssertNil(scene.little.flight, message, line: line)
    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.main.engineWindow,
                   "the page landed in the main window: \(message)", line: line)
    XCTAssertTrue(page.isDescendant(of: scene.main.rootView.card), message, line: line)
    XCTAssertEqual(scene.main.currentTab, scene.tab, message, line: line)
    let outline = scene.main.sidebarController.currentPage?.outlineController
    let arrived = scene.main.nodeByTab[scene.tab]
    XCTAssertEqual(arrived.flatMap { outline?.rowStyle(for: $0) }, .rest, "the row draws at rest: \(message)",
                   line: line)
  }

  func testTheMainWindowClosingMidFlightKeepsThePageInTheSmallWindow() throws {
    let scene = try makeScene(todayTabs: 1)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)
    let node = try XCTUnwrap(scene.main.nodeByTab[scene.tab])

    scene.main.window?.close()

    XCTAssertEqual(flight.stage, .finished)
    XCTAssertFalse(flight.overlay.isVisible, "the overlay is gone")
    XCTAssertNil(scene.little.flight)
    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "the page stayed")
    XCTAssertTrue(page.isDescendant(of: scene.little.card))
    XCTAssertFalse(scene.little.window.ignoresMouseEvents, "the small window takes clicks again")
    XCTAssertEqual(scene.little.lastTransition, .appear, "and comes back")
    XCTAssertFalse(scene.little.isClosed)
    XCTAssertNil(scene.main.tabsByNode[node], "the main window let go of the page it never received")
  }

  func testTheMainWindowMiniaturizingMidFlightLandsThePageWithoutTheFlight() throws {
    let scene = try makeScene(todayTabs: 1)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)

    NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: scene.main.window)

    assertLandedWithoutTheFlight(scene, flight, page, "main window miniaturized")
  }

  func testTheSmallWindowClosingMidFlightLandsThePageWithoutTheFlight() throws {
    let scene = try makeScene(todayTabs: 1)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)

    scene.little.window.close()

    assertLandedWithoutTheFlight(scene, flight, page, "small window closed")
    XCTAssertTrue(scene.little.isClosed)
  }

  /// `window.close()` in the page: the page is gone, so the small window goes without replaying its appear, and the
  /// row that was arriving for it is the main window's again.
  func testThePageClosingItselfMidFlightClosesTheWindowWithoutReplayingTheAppear() throws {
    let scene = try makeScene(todayTabs: 1)
    let flight = try flyAFewFrames(scene)
    let node = try XCTUnwrap(scene.main.nodeByTab[scene.tab])
    XCTAssertEqual(scene.little.lastTransition, .fadeOut)

    scene.engine.closeWindow(scene.littleWindow)

    XCTAssertEqual(flight.stage, .finished)
    XCTAssertFalse(flight.overlay.isVisible, "the overlay is gone")
    XCTAssertNil(scene.little.flight)
    XCTAssertEqual(scene.little.lastTransition, .fadeOut, "no appear on an emptied window")
    XCTAssertTrue(scene.little.isClosed, "the window is closed")
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    XCTAssertEqual(outline.rowStyle(for: node), .rest, "no row is left held back or faded")
  }

  func testTheAppTerminatingMidFlightLandsThePageWithoutTheFlight() throws {
    let scene = try makeScene(todayTabs: 1)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)

    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)

    assertLandedWithoutTheFlight(scene, flight, page, "app terminating")
  }

  /// Cmd-W while the page is in the air: the flight lands at once, then the window closes, so the tab is never
  /// stranded in an invisible window that ignores the keyboard.
  func testCmdWMidFlightLandsThePageThenClosesTheWindow() throws {
    let scene = try makeScene(todayTabs: 1)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)

    scene.little.requestClose()

    assertLandedWithoutTheFlight(scene, flight, page, "Cmd-W")
  }

  /// Cmd-W mid-flight with the main window gone: the page stays in the small window, which then closes as asked.
  func testCmdWMidFlightWithTheMainWindowGoneStillClosesTheSmallWindow() throws {
    let scene = try makeScene(todayTabs: 1)
    let flight = try flyAFewFrames(scene)
    scene.main.window?.close()
    XCTAssertEqual(flight.stage, .finished)

    scene.little.requestClose()
    scene.little.finishMotion()

    XCTAssertEqual(scene.little.lastTransition, .close, "the close the user asked for runs")
  }

  /// The display link stops delivering frames: counted in checks of the injected watchdog, not in seconds.
  func testFramesStoppingMidFlightLandsThePageWithoutTheFlight() throws {
    let watchdog = ManualWatchdog()
    let scene = try makeScene(todayTabs: 1, watchdog: watchdog)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let flight = try flyAFewFrames(scene)

    watchdog.fire()                                           // frames came in since the flight started
    XCTAssertEqual(flight.stage, .flying)
    flight.tick(at: 0.2)
    watchdog.fire()                                           // and again: not stalled
    XCTAssertEqual(flight.stage, .flying, "frames keep arriving, so the flight keeps going")

    watchdog.fire()                                           // no frame since the last check
    XCTAssertEqual(flight.stage, .flying, "one quiet interval is a hitch, not a stop")
    watchdog.fire()                                           // none for a second interval
    assertLandedWithoutTheFlight(scene, flight, page, "frames stopped")
    XCTAssertEqual(watchdog.pending, 0, "the watchdog stops with the flight")
  }

  /// The main window never delivers its first frame (so the flight never starts).
  func testNoFirstFrameLandsThePageWithoutTheFlight() throws {
    let watchdog = ManualWatchdog()
    let scene = try makeScene(todayTabs: 1, watchdog: watchdog)
    let page = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    XCTAssertEqual(flight.stage, .waitingForFrame)

    watchdog.fire()
    watchdog.fire()

    assertLandedWithoutTheFlight(scene, flight, page, "no first frame")
  }

  /// Frames stop after the page landed (the crossfade never ends): the overlay still comes off.
  func testFramesStoppingDuringTheCrossfadeRemovesTheOverlay() throws {
    let watchdog = ManualWatchdog()
    let scene = try makeScene(todayTabs: 1, watchdog: watchdog)
    let flight = try flyAFewFrames(scene)
    XCTAssertNotNil(step(flight, from: 0.2) { flight.stage == .landed })
    flight.tick(at: 5)
    XCTAssertEqual(flight.stage, .crossfading)
    watchdog.fire()                                           // frames arrived
    watchdog.fire()
    watchdog.fire()

    XCTAssertEqual(flight.stage, .finished)
    XCTAssertFalse(flight.overlay.isVisible)
    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.main.engineWindow, "the page stays landed")
  }

  /// A flight that is released takes its overlay with it.
  func testReleasingAFlightOrdersItsOverlayOut() throws {
    var flight: LittleArktFlight? = LittleArktFlight(
      source: CGRect(x: 100, y: 100, width: 400, height: 500), scale: 1, opacity: 1,
      target: CGRect(x: 600, y: 100, width: 800, height: 600), span: CGRect(x: 100, y: 100, width: 1300, height: 600),
      level: .floating, flavor: .light)
    flight?.drivesDisplayLink = false
    flight?.tick(at: 0)
    let overlay = try XCTUnwrap(flight?.overlay)
    XCTAssertTrue(overlay.isVisible)

    flight = nil

    XCTAssertFalse(overlay.isVisible)
  }

  // MARK: The clock

  /// One read of the clock per run: the first frame is where the run starts, however long the machine takes between
  /// two reads (#450). The clock here advances on every read.
  func testARunReadsTheClockOnce() {
    let clock = ManualClock(step: 0.05)
    let animator = LittleArktAnimator(scene: .rest, now: { clock.read() })
    animator.drivesDisplayLink = false
    var frames: [LittleArktScene] = []
    animator.onFrame = { frames.append($0) }

    animator.run(LittleArktMotion.targets(for: .fadeOut, reduceMotion: false), label: "test", in: NSView())

    XCTAssertEqual(clock.reads, 1)
    XCTAssertEqual(frames.count, 1)
    XCTAssertEqual(frames.first?[.opacity], 1, "the first frame is the start of the run, not 50 ms into it")
  }

  func testARunWithoutADisplayReadsTheClockOnceToo() {
    let clock = ManualClock(step: 0.05)
    let animator = LittleArktAnimator(scene: .rest, now: { clock.read() })
    var completed: Bool?

    animator.run(LittleArktMotion.targets(for: .fadeOut, reduceMotion: false), label: "test", in: NSView()) {
      completed = $0
    }

    XCTAssertEqual(clock.reads, 1)
    XCTAssertEqual(completed, true)
  }

  /// Open in reads the window's clock once to take the card's current scale and opacity, and each run it starts
  /// (the small frame's fade at the first frame) once.
  func testOpenInReadsTheWindowsClockOncePerRun() throws {
    let clock = ManualClock(step: 0.01)
    let scene = try makeScene(clock: clock)
    clock.reads = 0

    scene.little.openIn()
    XCTAssertEqual(clock.reads, 1, "the card's current scene, read once")

    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    XCTAssertEqual(clock.reads, 2, "plus the fade's one read")
  }

  // MARK: The card's shadow (#456)

  /// A flight over a main window in `appearance`, stepped to its first frame.
  private func flightInAir(_ scene: Scene, appearance: NSAppearance.Name) throws -> LittleArktFlight {
    scene.main.window?.appearance = NSAppearance(named: appearance)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    return flight
  }

  /// The shadow layer's geometry is the card's, and its path is the card's rounded rectangle at the size it has now.
  private func assertShadowFollowsTheCard(_ flight: LittleArktFlight, _ message: String, line: UInt = #line) {
    let card = flight.cardLayer
    let shadow = flight.shadowLayer
    XCTAssertEqual(shadow.bounds, card.bounds, "bounds: \(message)", line: line)
    XCTAssertEqual(shadow.position, card.position, "position: \(message)", line: line)
    XCTAssertTrue(CATransform3DEqualToTransform(shadow.transform, card.transform), "scale: \(message)", line: line)
    XCTAssertEqual(shadow.opacity, card.opacity, "opacity: \(message)", line: line)
    XCTAssertEqual(shadow.shadowPath?.boundingBoxOfPath, CGRect(origin: .zero, size: card.bounds.size),
                   "the path is the card's size in the same tick: \(message)", line: line)
  }

  /// The design's card shadow (the prototype's lifted plate carries `--card-shadow`; light only), the same values the
  /// main window's card lands with, through the whole flight.
  func testTheCardCarriesTheDesignsShadowThroughTheFlight() throws {
    let scene = try makeScene()
    let flight = try flightInAir(scene, appearance: .aqua)
    let landing = try XCTUnwrap(scene.main.rootView.card.layer)
    scene.main.rootView.card.appearance = NSAppearance(named: .aqua)
    scene.main.rootView.card.needsDisplay = true
    scene.main.rootView.card.displayIfNeeded()

    var t = 0.0
    var ticks = 0
    while flight.stage == .flying, t < 5 {
      let shadow = flight.shadowLayer
      XCTAssertEqual(shadow.shadowOpacity, 1, "at \(t)")
      XCTAssertEqual(shadow.shadowRadius, landing.shadowRadius, "the main card's blur at \(t)")
      XCTAssertEqual(shadow.shadowOffset, landing.shadowOffset, "and offset at \(t)")
      XCTAssertEqual(shadow.shadowColor, ShellTokens.cardShadow.resolve(.light).cgColor, "the token's color at \(t)")
      XCTAssertEqual(shadow.shadowColor, landing.shadowColor, "the same color the main card lands with at \(t)")
      XCTAssertNotNil(shadow.shadowPath, "an explicit path, so no offscreen pass, at \(t)")
      assertShadowFollowsTheCard(flight, "flying at \(t)")
      t += Self.frame
      flight.tick(at: t)
      ticks += 1
    }
    XCTAssertGreaterThan(ticks, 30)
    XCTAssertTrue(flight.shadowLayer.superlayer === flight.overlay.contentView?.layer, "on the overlay")
    XCTAssertTrue(flight.cardLayer.superlayer === flight.overlay.contentView?.layer)
    let layers = try XCTUnwrap(flight.overlay.contentView?.layer?.sublayers)
    XCTAssertEqual(layers.firstIndex { $0 === flight.shadowLayer }, 0, "under the card")
    XCTAssertTrue(flight.cardLayer.masksToBounds, "the mask clips the card, so the shadow is a layer of its own")
    XCTAssertFalse(flight.shadowLayer.masksToBounds)
  }

  /// The path is rebuilt only when the card's size changed since the last frame, in the same tick: it follows the
  /// growing mask, then stays while the card is at rest and fades.
  func testTheShadowPathChangesOnlyWithTheSize() throws {
    let scene = try makeScene()
    let flight = try flightInAir(scene, appearance: .aqua)
    var t = 0.0
    var sizes: [CGSize] = [flight.cardLayer.bounds.size]
    while flight.stage == .flying, t < 5 {
      let before = flight.shadowPathUpdates
      t += Self.frame
      flight.tick(at: t)
      let size = flight.cardLayer.bounds.size
      let changed = size != sizes.last
      XCTAssertEqual(flight.shadowPathUpdates - before, changed ? 1 : 0, "one rebuild per size change at \(t)")
      sizes.append(size)
    }
    XCTAssertEqual(flight.stage, .landed)
    XCTAssertGreaterThan(Set(sizes.map { "\($0.width)x\($0.height)" }).count, 10, "the size animates, so the path follows")
    let atRest = flight.shadowPathUpdates
    for _ in 0..<20 {
      t += Self.frame
      flight.tick(at: t)
      assertShadowFollowsTheCard(flight, "at rest and fading at \(t)")
    }
    XCTAssertEqual(flight.shadowPathUpdates, atRest, "no rebuild while the size is still")
  }

  /// The shadow fades with the card: the landing's crossfade carries it out, and the finished flight has none left.
  func testTheShadowFadesWithTheLanding() throws {
    let scene = try makeScene()
    let flight = try flightInAir(scene, appearance: .aqua)
    var t = try XCTUnwrap(step(flight, from: Self.frame) { flight.stage == .landed })
    t += Self.frame
    flight.tick(at: t)
    XCTAssertEqual(flight.stage, .crossfading)
    XCTAssertEqual(flight.shadowLayer.opacity, 1, "full at the start of the crossfade")
    t += 0.05
    flight.tick(at: t)
    XCTAssertLessThan(flight.shadowLayer.opacity, 1)
    XCTAssertGreaterThan(flight.shadowLayer.opacity, 0)
    assertShadowFollowsTheCard(flight, "fading")
    XCTAssertNotNil(step(flight, from: t + Self.frame) { flight.stage == .finished })
    XCTAssertNil(flight.shadowLayer.superlayer, "gone with the overlay")
    XCTAssertNil(flight.shadowLayer.shadowPath)
    XCTAssertEqual(flight.shadowLayer.shadowOpacity, 0)
  }

  /// The card has no shadow in dark (the token is clear), and then no shadow pass or path work at all.
  func testNoShadowInDark() throws {
    let scene = try makeScene()
    let flight = try flightInAir(scene, appearance: .darkAqua)
    var t = 0.0
    while flight.stage == .flying, t < 5 {
      XCTAssertEqual(flight.shadowLayer.shadowOpacity, 0, "at \(t)")
      XCTAssertNil(flight.shadowLayer.shadowPath, "at \(t)")
      t += Self.frame
      flight.tick(at: t)
    }
    XCTAssertEqual(flight.shadowPathUpdates, 0)
  }

  /// Reduce Motion takes no flight, so there is no card to carry a shadow: the card fades in the small window.
  func testReduceMotionHasNoFlightAndSoNoShadow() throws {
    let scene = try makeScene(reduceMotion: true)
    scene.main.window?.appearance = NSAppearance(named: .aqua)
    scene.little.openIn()
    XCTAssertNil(scene.little.flight, "no flight, so no overlay and no shadow layer")
    XCTAssertEqual(scene.little.lastTransition, .fadeOut, "the card fades in place (0.12 s)")
    XCTAssertFalse(LittleArktFlightConditions(reduceMotion: true).allowsFlight)
  }

  /// An aborted flight clears the shadow with the overlay, at every stage it can end in the air.
  func testAnAbortedFlightClearsItsShadow() throws {
    for reason in [LittleArktFlightAbort.mainWindowClosed, .mainWindowMiniaturized, .framesStopped, .appTerminating,
                   .smallWindowClosing, .closeRequested, .pageClosed] {
      let scene = try makeScene(todayTabs: 1)
      let flight = try flightInAir(scene, appearance: .aqua)
      flight.tick(at: 0.1)
      XCTAssertEqual(flight.shadowLayer.shadowOpacity, 1, "in the air before \(reason)")
      XCTAssertNotNil(flight.shadowLayer.superlayer)

      flight.abort(reason)

      XCTAssertEqual(flight.stage, .finished, "\(reason)")
      XCTAssertNil(flight.shadowLayer.superlayer, "\(reason)")
      XCTAssertNil(flight.shadowLayer.shadowPath, "\(reason)")
      XCTAssertEqual(flight.shadowLayer.shadowOpacity, 0, "\(reason)")
      XCTAssertFalse(flight.overlay.isVisible, "\(reason)")
    }
  }

  /// A flight stepped to the end with no display clears its shadow too.
  func testARunToTheEndLeavesNoShadow() throws {
    let scene = try makeScene()
    scene.main.window?.appearance = NSAppearance(named: .aqua)
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.runToEnd()
    XCTAssertEqual(flight.stage, .finished)
    XCTAssertNil(flight.shadowLayer.superlayer)
    XCTAssertNil(flight.shadowLayer.shadowPath)
  }

  /// For the pull request: the main-thread cost of one flying frame, with the shadow and without it, over 10 flights
  /// each (interleaved), in microseconds. A frame is the tick plus the transaction commit that encodes the layer
  /// tree. Skipped unless `ARKT_FLIGHT_MEASURE` is set.
  func testMeasureAFlyingFrameWithAndWithoutTheShadow() throws {
    guard ProcessInfo.processInfo.environment["ARKT_FLIGHT_MEASURE"] != nil else {
      throw XCTSkip("set ARKT_FLIGHT_MEASURE to measure a flying frame")
    }
    let clock = ContinuousClock()
    var costs: [Bool: [Double]] = [true: [], false: []]
    for run in 0..<20 {
      let withShadow = run % 2 == 0
      let scene = try makeScene()
      let flight = try flightInAir(scene, appearance: .aqua)
      flight.carriesShadow = withShadow
      var t = 0.0
      while flight.stage == .flying, t < 5 {
        t += Self.frame
        let start = clock.now
        flight.tick(at: t)
        CATransaction.flush()
        let took = start.duration(to: clock.now)
        costs[withShadow, default: []].append(Double(took.components.attoseconds) / 1e12
                                              + Double(took.components.seconds) * 1e6)
      }
      flight.abort(.closeRequested)
    }
    for (label, key) in [("with shadow", true), ("without", false)] {
      let values = (costs[key] ?? []).sorted()
      let mean = values.reduce(0, +) / Double(max(values.count, 1))
      let p95 = values.isEmpty ? 0 : values[Int(Double(values.count - 1) * 0.95)]
      print("FLYING FRAME \(label): \(values.count) frames, mean \(Int(mean)) us, p95 \(Int(p95)) us, "
            + "worst \(Int(values.last ?? 0)) us")
    }
  }

  // MARK: The arrival's cost

  /// For the pull request: the cost of one arrival frame with 500 Today rows. Skipped unless `ARKT_FLIGHT_MEASURE`
  /// is set; prints the mean and worst of 600 frames in microseconds.
  func testMeasureOneArrivalFrameWith500Rows() throws {
    guard ProcessInfo.processInfo.environment["ARKT_FLIGHT_MEASURE"] != nil else {
      throw XCTSkip("set ARKT_FLIGHT_MEASURE to measure an arrival frame")
    }
    let scene = try makeScene()
    let space = try XCTUnwrap(scene.main.currentSpace)
    for index in 0..<500 {
      _ = try scene.main.sidebar.addTab(url: try XCTUnwrap(URL(string: "arkt-test://page/Row\(index)")),
                                        title: "Row \(index)", in: .today(space), at: nil)
    }
    scene.main.window?.contentView?.layoutSubtreeIfNeeded()
    scene.little.openIn()
    let node = try XCTUnwrap(scene.main.nodeByTab[scene.tab])
    let outline = try XCTUnwrap(scene.main.sidebarController.currentPage?.outlineController)
    XCTAssertGreaterThan(outline.outlineView.numberOfRows, 400)
    let clock = ContinuousClock()
    var micros: [Double] = []
    for frame in 0..<600 {
      let room = Double(frame % 120) / 120
      let start = clock.now
      outline.presentArrival(of: node, room: room, appear: room)
      let took = start.duration(to: clock.now)
      micros.append(Double(took.components.attoseconds) / 1e12 + Double(took.components.seconds) * 1e6)
    }
    outline.endArrival()
    let mean = micros.reduce(0, +) / Double(micros.count)
    print("ARRIVAL FRAME, \(outline.outlineView.numberOfRows) rows: mean \(Int(mean)) us, worst \(Int(micros.max() ?? 0)) us")
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
  /// How far `read()` moves the clock on from the value it returns: a clock that advances on every read.
  let step: CFTimeInterval
  var reads = 0

  init(step: CFTimeInterval = 0) { self.step = step }

  func read() -> CFTimeInterval {
    reads += 1
    defer { now += step }
    return now
  }
}

/// The flight's watchdog on a clock the test turns: `fire()` is one interval passing.
@MainActor
final class ManualWatchdog {
  private var checks: [@MainActor () -> Void] = []
  var pending: Int { checks.count }

  func schedule(_ check: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
    checks.append(check)
    return { [weak self] in self?.checks.removeAll() }
  }

  func fire() {
    let due = checks
    checks = []
    for check in due { check() }
  }
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
