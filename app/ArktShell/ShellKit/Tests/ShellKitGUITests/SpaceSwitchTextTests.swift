import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI
@testable import Motion

/// #415: a Space page the strip shows mid-motion draws its text from the first frame. The strip moves on its layer
/// (#24), so AppKit's view geometry lags the screen; AppKit draws a text field only inside its visible rect, so a page
/// shown outside the pager in that geometry showed its favicons and glyphs (layer contents) but no row titles and no
/// Space name. The checks read the geometry AppKit draws by: every realized row title and the Space header of every
/// shown page must have a non-empty visible rect, on the first frame that shows the page and on every frame after.
@MainActor
final class SpaceSwitchTextTests: XCTestCase {
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

  private var pager: SpacePagerView { controller.pager }

  /// The part of `view` AppKit draws: its visible rect, within its bounds.
  private func drawnRect(_ view: NSView) -> NSRect { view.visibleRect.intersection(view.bounds) }

  /// Every shown page has its Space name and the titles of the rows in its scroll view's visible area laid out with
  /// text and inside AppKit's visible area. Returns the number of pages checked.
  @discardableResult
  private func assertShownPagesDrawText(_ moment: String, file: StaticString = #filePath,
                                        line: UInt = #line) -> Int {
    var checked = 0
    for case let page as SpacePageView in pager.pages where !page.isHidden {
      checked += 1
      let space = page.titleLabel.stringValue
      XCTAssertFalse(space.isEmpty, "\(moment): a shown page has a Space name", file: file, line: line)
      XCTAssertGreaterThan(page.titleLabel.frame.width, 0, "\(moment): \(space) header title laid out",
                           file: file, line: line)
      XCTAssertFalse(drawnRect(page.titleLabel).isEmpty, "\(moment): \(space) header title is drawn",
                     file: file, line: line)
      let outline = page.outlineView
      let rows = outline.rows(in: page.scrollView.contentView.bounds)
      var titled = 0
      for row in rows.lowerBound..<rows.upperBound {
        guard let cell = outline.rowView(atRow: row, makeIfNecessary: false)?.view(atColumn: 0)
          as? SidebarTabCellView else { continue }
        let field = cell.titleField
        // A row cut by the clip edge (a short window on a small screen) can show none of its title; only titles the
        // scroll view shows at all are checked.
        let clip = page.scrollView.contentView
        guard clip.bounds.intersects(field.convert(field.bounds, to: clip)) else { continue }
        titled += 1
        XCTAssertFalse(field.stringValue.isEmpty, "\(moment): \(space) row \(row) has a title", file: file, line: line)
        XCTAssertGreaterThan(field.frame.width, 0, "\(moment): \(space) row \(row) title laid out",
                             file: file, line: line)
        XCTAssertFalse(field.isHiddenOrHasHiddenAncestor, "\(moment): \(space) row \(row) title shown",
                       file: file, line: line)
        XCTAssertFalse(drawnRect(field).isEmpty, "\(moment): \(space) row \(row) title is drawn",
                       file: file, line: line)
      }
      XCTAssertGreaterThan(titled, 0, "\(moment): \(space) shows its rows", file: file, line: line)
    }
    return checked
  }

  /// Where `view` shows on screen, in its own coordinates, and only the part the pager shows. AppKit's geometry lags
  /// the screen mid-motion (#24), so the rect is derived from the layer translations of the strip and of a parked
  /// page, not from view frames: it is the oracle the drawn rect is checked against.
  private func shownRect(_ view: NSView, on page: NSView) -> NSRect {
    let shift = (pager.strip.layer?.affineTransform().tx ?? 0) + (page.layer?.affineTransform().tx ?? 0)
    let onScreen = view.convert(view.bounds, to: pager).offsetBy(dx: shift, dy: 0)
    let shown = onScreen.intersection(pager.bounds)
    guard !shown.isEmpty else { return .zero }
    return view.convert(shown.offsetBy(dx: -shift, dy: 0), from: pager)
  }

  /// The whole part of every shown page's Space name and row titles that the pager shows is inside AppKit's visible
  /// rect for that field. AppKit draws a text field only there, so a title shown outside it is cut off or blank
  /// (#841). A non-empty visible rect is not enough: a page caught half way keeps a visible rect of half a title.
  private func assertShownTitlesFullyDrawn(_ moment: String, file: StaticString = #filePath, line: UInt = #line) {
    for case let page as SpacePageView in pager.pages where !page.isHidden {
      let space = page.titleLabel.stringValue
      // Only a layer-backed page can be parked (and its translation read here).
      XCTAssertNotNil(page.layer, "\(moment): \(space) page is layer-backed", file: file, line: line)
      var fields: [(String, NSTextField)] = [("header", page.titleLabel)]
      let outline = page.outlineView
      let rows = outline.rows(in: page.scrollView.contentView.bounds)
      for row in rows.lowerBound..<rows.upperBound {
        guard let cell = outline.rowView(atRow: row, makeIfNecessary: false)?.view(atColumn: 0)
          as? SidebarTabCellView else { continue }
        fields.append(("row \(row)", cell.titleField))
      }
      for (name, field) in fields {
        let shown = shownRect(field, on: page)
        guard shown.width > 0.5 else { continue }
        let drawn = drawnRect(field)
        XCTAssertTrue(drawn.minX <= shown.minX + 0.5 && drawn.maxX >= shown.maxX - 0.5,
                      "\(moment): \(space) \(name) title shows \(shown.minX)...\(shown.maxX) but AppKit draws "
                        + "\(drawn.minX)...\(drawn.maxX)", file: file, line: line)
      }
    }
  }

  private func awaitSettle(_ body: () -> Void) async {
    let settled = expectation(description: "settled")
    pager.onSettleForTesting = { _ in settled.fulfill() }
    body()
    await fulfillment(of: [settled], timeout: 3)
    pager.onSettleForTesting = nil
  }

  /// A swipe from the current page toward `direction` (-1 next, 1 previous): the first frame shows the neighbour by a
  /// point, then half a page, then the swipe settles on it.
  private func swipe(_ direction: CGFloat, to target: Int) async {
    let width = pager.bounds.width
    pager.beginTracking()
    pager.track(delta: direction, at: 0.01)
    XCTAssertEqual(assertShownPagesDrawText("first frame"), 2, "the neighbour shows from the first frame")
    pager.track(delta: direction * 0.5 * width, at: 0.02)
    assertShownPagesDrawText("half way")
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(pager.index, target)
    assertShownPagesDrawText("at rest")
  }

  func testASwipeToTheNextSpaceShowsItsTitlesFromTheFirstFrame() async throws {
    assertShownPagesDrawText("before")
    await swipe(-1, to: 1)
  }

  /// The reported case: back to a Space the strip passed before, whose page was parked and hidden in between.
  func testASwipeBackShowsTheTitlesOfTheSpaceLeftBefore() async throws {
    await swipe(-1, to: 1)
    await swipe(1, to: 0)
    await swipe(-1, to: 1)
  }

  /// A still pointer over the sidebar mid-swipe: the incoming page is parked in the outgoing page's geometry, so its
  /// row under the pointer there must not light up; once the swipe settles the row under the pointer does.
  func testAParkedPageDoesNotHoverTheRowUnderAStillPointer() async throws {
    let window = try XCTUnwrap(controller.window)
    let incoming = try XCTUnwrap(pager.pages[1] as? SpacePageView)
    pager.beginTracking()
    pager.track(delta: -1, at: 0.01)
    XCTAssertFalse(incoming.isHidden)
    let row = try XCTUnwrap(incoming.outlineView.rowView(atRow: 0, makeIfNecessary: false) as? SidebarRowView)
    let pointer = HoverPointerStub(window: window)
    pointer.move(toCenterOf: row)
    XCTAssertTrue(pager.bounds.contains(pager.convert(pointer.pointInWindow, from: nil)),
                  "the parked row sits under the pointer in AppKit's geometry")
    incoming.outlineView.hoverPointerLookup = pointer.lookup

    incoming.outlineView.resyncHoverWithPointer()
    XCTAssertFalse(row.isHovered, "a parked page's row does not light up under a still pointer")

    pager.track(delta: -0.6 * pager.bounds.width, at: 0.02)
    await awaitSettle { pager.endTracking() }
    XCTAssertEqual(pager.index, 1)
    incoming.outlineView.resyncHoverWithPointer()
    XCTAssertTrue(row.isHovered, "at rest the row under the pointer is hovered")
    // The stub's lookup holds it unowned: a resync queued by the settle reads it, so it stays until the system's is back.
    XCTAssertGreaterThan(pointer.windowServerQueries, 0)
    incoming.outlineView.hoverPointerLookup = .system
  }

  /// #295: a geometry sync from a pointer move unparks the pages so hit tests are exact. The next presented frame
  /// must park the shown pages again, or the incoming page's text (drawn only from a parked frame, #415) disappears
  /// for the rest of the motion.
  func testAPointerSyncMidMotionKeepsTheShownPagesTextDrawn() throws {
    let window = try XCTUnwrap(controller.window)
    pager.reduceMotionForTesting = false
    pager.go(to: 1)
    var time = CACurrentMediaTime()
    time += 1.0 / 120
    pager.driver.tick(at: time)
    XCTAssertEqual(assertShownPagesDrawText("first frame"), 2)
    let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                                                location: pager.convert(NSPoint(x: 10, y: 10), to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    pager.mouseMoved(with: move)
    time += 1.0 / 120
    pager.driver.tick(at: time)
    assertShownPagesDrawText("after the pointer sync and the next frame")
    pager.stopInteraction()
  }

  // MARK: A swipe that catches a settle (#841)

  /// Presents settle frames by hand, checking the titles on each, until the settle ends.
  private func settleByHand(from time: inout CFTimeInterval, _ moment: String,
                            file: StaticString = #filePath, line: UInt = #line) {
    let deadline = time + 3
    var frames = 0
    while pager.isSettling, time < deadline {
      time += 1.0 / 120
      pager.driver.tick(at: time)
      frames += 1
      assertShownTitlesFullyDrawn("\(moment) frame \(frames)", file: file, line: line)
    }
    XCTAssertFalse(pager.isSettling, "\(moment): the settle ended", file: file, line: line)
  }

  /// Settle frames are presented by hand only (no display link), from a clock read after the settle starts.
  private func presentFramesByHand() {
    pager.reduceMotionForTesting = false
    pager.driver.drivesDisplayLink = false
  }

  /// Drags from the first page past the second, so the third shows (parked), releases, and presents two frames of
  /// the settle: the strip is between the second and third pages, all three shown.
  private func releaseASwipePastTheSecondSpace() -> CFTimeInterval {
    presentFramesByHand()
    pager.beginTracking()
    for step in 1...12 {
      pager.track(delta: -0.1 * pager.bounds.width, at: Double(step) * 0.01)
      assertShownTitlesFullyDrawn("drag step \(step)")
    }
    XCTAssertGreaterThan(pager.position, 1.1)
    XCTAssertFalse(pager.pages[2].isHidden, "the drag shows the third page")
    pager.endTracking()
    var time = CACurrentMediaTime()
    for frame in 1...2 {
      time += 1.0 / 120
      pager.driver.tick(at: time)
      assertShownTitlesFullyDrawn("first settle frame \(frame)")
    }
    XCTAssertTrue(pager.isSettling)
    XCTAssertTrue((1.05...1.95).contains(pager.position), "the settle is between pages: \(pager.position)")
    return time
  }

  /// The reported case (#841): swiping quickly between Spaces, the fingers touch down while the last swipe still
  /// settles. Touch-down freezes the settle and syncs the strip geometry between two pages, which puts the pages the
  /// settle showed back in their own slots; the next swipe must show their titles whole on every frame, not the part
  /// AppKit had in view where the strip froze.
  func testASwipeThatCatchesASettleShowsWholeTitlesOnEveryFrame() throws {
    var time = releaseASwipePastTheSecondSpace()
    pager.gestureMayBegin()
    XCTAssertNotNil(pager.frozenTarget)
    assertShownTitlesFullyDrawn("frozen")
    pager.beginTracking()
    pager.track(delta: -1, at: 1.0)
    assertShownTitlesFullyDrawn("first frame after the catch")
    for step in 1...6 {
      pager.track(delta: -0.1 * pager.bounds.width, at: 1.0 + Double(step) * 0.01)
      assertShownTitlesFullyDrawn("catch drag step \(step)")
    }
    pager.endTracking()
    time = CACurrentMediaTime()
    settleByHand(from: &time, "settle after the catch")
    assertShownTitlesFullyDrawn("at rest")
  }

  /// The same catch, where the gesture turns out vertical: the frozen settle resumes from where it froze.
  func testASettleResumedAfterATouchShowsWholeTitlesOnEveryFrame() throws {
    _ = releaseASwipePastTheSecondSpace()
    let target = pager.targetIndex
    pager.gestureMayBegin()
    pager.gestureEndedWithoutPaging()
    XCTAssertTrue(pager.isSettling)
    var time = CACurrentMediaTime()
    settleByHand(from: &time, "resumed settle")
    XCTAssertEqual(pager.index, target)
  }

  /// A swipe from a light Space to a dark one flips the sidebar's flavor half way, and the window's next layout pass
  /// lays the pager out mid-swipe: that puts the strip frame where the strip shows and the parked page back in its
  /// own slot. Every frame after the flip must still show both pages' titles whole (#841).
  func testASwipeAcrossTheLightDarkFlipShowsWholeTitlesAfterTheFlip() throws {
    presentFramesByHand()
    pager.jump(to: 1)
    let window = try XCTUnwrap(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    let flavorBefore = controller.sidebarController.view.flavor
    let width = pager.bounds.width
    pager.beginTracking()
    for step in 1...16 {
      pager.track(delta: -0.06 * width, at: Double(step) / 120)
      window.contentView?.layoutSubtreeIfNeeded()
      assertShownTitlesFullyDrawn("step \(step), position \(pager.position)")
    }
    XCTAssertNotEqual(controller.sidebarController.view.flavor, flavorBefore, "the swipe crossed the light/dark flip")
    pager.stopInteraction()
  }

  /// A pointer sync half way through a swipe puts the strip frame between two pages; when the fingers turn back, the
  /// page the swipe started from slides back in and must show its titles whole, not the half AppKit had in view.
  func testASwipeThatTurnsBackAfterAPointerSyncShowsWholeTitles() throws {
    presentFramesByHand()
    let window = try XCTUnwrap(controller.window)
    let width = pager.bounds.width
    pager.beginTracking()
    pager.track(delta: -0.5 * width, at: 0.01)
    let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
                                                location: pager.convert(NSPoint(x: 10, y: 10), to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    pager.mouseMoved(with: move)
    XCTAssertEqual(pager.stripLayerShiftForTesting, 0, "the pointer move synced the strip half way")
    for step in 1...4 {
      pager.track(delta: 0.1 * width, at: 0.01 + Double(step) * 0.01)
      assertShownTitlesFullyDrawn("turning back, step \(step)")
    }
    pager.stopInteraction()
  }

  /// Back and forth across all three Spaces, every swipe catching the last one's settle.
  func testSwipesBackAndForthThatEachCatchTheLastSettleShowWholeTitles() throws {
    presentFramesByHand()
    var time = CACurrentMediaTime()
    var clock = 0.0
    for (round, direction) in [-1.0, -1, 1, 1, -1, 1].enumerated() {
      if pager.isSettling { pager.gestureMayBegin() }
      pager.beginTracking()
      for _ in 0..<5 {
        clock += 0.01
        pager.track(delta: direction * 0.12 * pager.bounds.width, at: clock)
        assertShownTitlesFullyDrawn("swipe \(round) drag")
      }
      pager.endTracking()
      time = max(time, CACurrentMediaTime())
      for frame in 1...5 {
        time += 1.0 / 120
        pager.driver.tick(at: time)
        assertShownTitlesFullyDrawn("swipe \(round) settle frame \(frame)")
      }
    }
    time = max(time, CACurrentMediaTime())
    settleByHand(from: &time, "last settle")
    assertShownTitlesFullyDrawn("at rest")
  }

  /// Ctrl-N and the keyboard: every presented frame of the settle, from the first, draws both pages' text.
  func testAKeyboardSwitchShowsTheTitlesOnEveryFrame() throws {
    pager.reduceMotionForTesting = false
    for target in [1, 2, 0] {
      var time = CACurrentMediaTime()
      pager.go(to: target)
      let deadline = time + 3
      var frames = 0
      while pager.isSettling, time < deadline {
        time += 1.0 / 120
        pager.driver.tick(at: time)
        frames += 1
        assertShownPagesDrawText("to \(target) frame \(frames)")
      }
      XCTAssertEqual(pager.index, target)
      XCTAssertGreaterThan(frames, 2)
      assertShownPagesDrawText("at rest on \(target)")
    }
  }
}
