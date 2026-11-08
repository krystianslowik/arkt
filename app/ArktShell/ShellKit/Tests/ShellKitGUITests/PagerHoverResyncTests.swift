import AppKit
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI
@testable import Motion

/// Counts the actual window-server lookup through the sidebar hosts while the real pager changes state.
@MainActor
final class PagerHoverResyncTests: XCTestCase {
  @MainActor
  private final class Harness {
    let controller: ShellWindowController
    let outline: SidebarOutlineView
    let grid: FavoritesGridView
    let rowPointer: HoverPointerStub
    let tilePointer: HoverPointerStub

    init() throws {
      _ = NSApplication.shared
      NSApp.setActivationPolicy(.accessory)
      let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
      controller.window?.isReleasedWhenClosed = false
      controller.showWindow(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      let window = try XCTUnwrap(controller.window)
      let outline = try XCTUnwrap(controller.sidebarController.view.currentOutline)
      let grid = controller.sidebarController.view.favorites
      let rowPointer = HoverPointerStub(window: window)
      let tilePointer = HoverPointerStub(window: window)
      outline.hoverPointerLookup = rowPointer.lookup
      outline.hoverResyncEnqueue = rowPointer.enqueue
      grid.hoverPointerLookup = tilePointer.lookup
      grid.hoverResyncEnqueue = tilePointer.enqueue
      controller.pager.reduceMotionForTesting = false
      controller.pager.driver.drivesDisplayLink = false
      self.controller = controller
      self.outline = outline
      self.grid = grid
      self.rowPointer = rowPointer
      self.tilePointer = tilePointer
    }

    func request() {
      outline.setNeedsHoverResync()
      outline.setNeedsHoverResync()
      grid.setNeedsHoverResync()
      grid.setNeedsHoverResync()
    }

    func drain() {
      rowPointer.runNextTurn()
      tilePointer.runNextTurn()
    }

    var counts: [Int] { [rowPointer.windowServerQueries, tilePointer.windowServerQueries] }

    func settle() {
      let start = CACurrentMediaTime()
      for frame in 1...600 where controller.pager.isSettling {
        controller.pager.driver.tick(at: start + Double(frame) / 120)
      }
      XCTAssertFalse(controller.pager.isSettling)
    }
  }

  func testSwipeDefersAndCoalescesBothHostsUntilRest() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let pager = h.controller.pager
    pager.beginTracking()
    pager.track(delta: -pager.bounds.width * 0.6, at: 1)
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0], "tracking must not query the window server")
    pager.endTracking()
    XCTAssertTrue(pager.isSettling)
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0], "settling must not query the window server")
    h.settle()
    h.drain()
    XCTAssertEqual(h.counts, [1, 1], "one deferred lookup per host at rest")
    h.drain()
    XCTAssertEqual(h.counts, [1, 1])
  }

  func testKeyboardSettleInterruptedBySwipeFlushesOnlyAtFinalRest() throws {
    let h = try Harness()
    defer { h.controller.close() }
    h.controller.nextSpace(nil)
    XCTAssertTrue(h.controller.pager.isSettling)
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0])
    h.controller.pager.beginTracking()
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0], "interruption is not rest")
    h.controller.pager.endTracking()
    h.settle()
    h.drain()
    XCTAssertEqual(h.counts, [1, 1])
  }

  func testReducedMotionAndIdleRequestsResyncAtRest() throws {
    let h = try Harness()
    defer { h.controller.close() }
    h.controller.pager.reduceMotionForTesting = true
    h.controller.nextSpace(nil)
    XCTAssertFalse(h.controller.pager.isSettling)
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [1, 1])
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [2, 2], "a later idle request still runs")
  }

  func testRestResyncUsesFinalPointerPosition() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let row = try XCTUnwrap(h.outline.rowView(atRow: 0, makeIfNecessary: true) as? SidebarRowView)
    h.rowPointer.move(toCenterOf: row)
    h.controller.pager.beginTracking()
    h.request()
    h.drain()
    XCTAssertEqual(h.rowPointer.windowServerQueries, 0)
    h.controller.pager.endTracking()
    h.settle()
    h.drain()
    XCTAssertEqual(h.rowPointer.windowServerQueries, 1)
    XCTAssertTrue(row.isHovered, "the final pointer position determines the row hover")
  }

  func testQueuedIdleRequestWaitsForPagingAndJumpFlushes() throws {
    let h = try Harness()
    defer { h.controller.close() }
    h.request()
    h.controller.pager.beginTracking()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0])
    h.controller.pager.jump(to: 0)
    h.drain()
    XCTAssertEqual(h.counts, [1, 1])
  }

  func testDetachedHostDoesNotFlushItsOldRequest() throws {
    let h = try Harness()
    defer { h.controller.close() }
    h.controller.pager.beginTracking()
    h.request()
    h.drain()
    h.grid.removeFromSuperview()
    h.controller.pager.jump(to: 0)
    h.drain()
    XCTAssertEqual(h.tilePointer.windowServerQueries, 0)
  }

  func testClosingDuringMotionDoesNotRunDeferredQueries() throws {
    let h = try Harness()
    h.controller.pager.beginTracking()
    h.request()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0])
    h.controller.close()
    h.drain()
    XCTAssertEqual(h.counts, [0, 0], "closed windows must not flush stale work")
  }
}
