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

  override func tearDown() async throws { controller.close() }

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
