import AppKit
import XCTest
@testable import ShellUI

/// #193: with more Spaces than fit between the archive and new-tab buttons, the dock scrolls instead of drawing
/// over the buttons, keeps the current Space's dot in view and routes clicks to the dot under the pointer.
@MainActor
final class SpaceDockOverflowTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    windows.forEach { $0.close() }
    windows = []
  }

  private func makeSidebar(spaces: Int, width: CGFloat) -> SidebarController {
    let stub = StubSidebar()
    for index in 0..<spaces { _ = stub.addSpace(title: "Space \(index + 1)") }
    let controller = SidebarController(source: stub)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    window.setContentSize(NSSize(width: width, height: 600))
    controller.view.layoutSubtreeIfNeeded()
    controller.view.spaceDots.displayIfNeeded()
    windows.append(window)
    return controller
  }

  private var cases: [(spaces: Int, width: CGFloat)] {
    [5, 7, 12].flatMap { count in [150, 190].map { (spaces: count, width: CGFloat($0)) } }
  }

  /// Dot `index` drawn inside the dock's bounds (the dot itself, not its hit box).
  private func dotIsVisible(_ dots: SpaceDotsView, _ index: Int) -> Bool {
    let hit = dots.dotFrame(index)
    let size = SidebarMetrics.spaceDotSize
    let dotMinX = hit.midX - size / 2
    return dotMinX >= 0 && dotMinX + size <= dots.bounds.width
  }

  private func click(_ dots: SpaceDotsView, at point: NSPoint) throws {
    let inWindow = dots.convert(point, to: nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: inWindow, modifierFlags: [], timestamp: 0,
      windowNumber: dots.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    dots.mouseDown(with: event)
  }

  private func scroll(_ dots: SpaceDotsView, dx: Int32) throws {
    let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: 0, wheel2: dx, wheel3: 0))
    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
    dots.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
  }

  func testDockStaysBetweenTheButtons() throws {
    for (spaces, width) in cases {
      let view = makeSidebar(spaces: spaces, width: width).view
      let label = "\(spaces) Spaces at \(width) pt"
      XCTAssertFalse(view.spaceDots.frame.intersects(view.archiveButton.frame), label)
      XCTAssertFalse(view.spaceDots.frame.intersects(view.newTabButton.frame), label)
      XCTAssertEqual(view.spaceDots.frame.minX, view.archiveButton.frame.maxX, label)
      XCTAssertEqual(view.spaceDots.frame.maxX, view.newTabButton.frame.minX, label)
      XCTAssertTrue(view.spaceDots.layer?.sublayers?.first?.masksToBounds ?? false, "\(label): dots are clipped")
    }
  }

  func testCurrentDotIsVisibleAndAccessibilityFramesStayInTheDock() throws {
    for (spaces, width) in cases {
      let controller = makeSidebar(spaces: spaces, width: width)
      let dots = controller.view.spaceDots
      let space = controller.spaces[spaces - 1]
      controller.showSpace(space)
      controller.view.layoutSubtreeIfNeeded()
      dots.displayIfNeeded()
      let label = "\(spaces) Spaces at \(width) pt"
      XCTAssertEqual(dots.selectedIndex, spaces - 1, label)
      XCTAssertTrue(dotIsVisible(dots, spaces - 1), "\(label): the last Space's dot is scrolled into view")
      let dockOnScreen = try XCTUnwrap(dots.window).convertToScreen(dots.convert(dots.bounds, to: nil))
      let children = try XCTUnwrap(dots.accessibilityChildren() as? [NSAccessibilityElement])
      XCTAssertEqual(children.count, spaces, "\(label): every Space stays in the accessibility tree")
      for (index, child) in children.enumerated() {
        let frame = child.accessibilityFrame()
        XCTAssertGreaterThanOrEqual(frame.minX, dockOnScreen.minX - 0.01, "\(label): dot \(index)")
        XCTAssertLessThanOrEqual(frame.maxX, dockOnScreen.maxX + 0.01, "\(label): dot \(index)")
      }
      controller.showSpace(controller.spaces[0])
      XCTAssertTrue(dotIsVisible(dots, 0), "\(label): back to the first Space")
    }
  }

  func testClicksRouteToTheDotUnderThePointer() throws {
    for (spaces, width) in cases {
      let controller = makeSidebar(spaces: spaces, width: width)
      let dots = controller.view.spaceDots
      let label = "\(spaces) Spaces at \(width) pt"
      let last = spaces - 1
      controller.showSpace(controller.spaces[last])
      dots.displayIfNeeded()
      // The last dot is in view now; clicking its center selects it, and its left neighbour selects that one.
      for index in [last, last - 1] {
        let frame = dots.dotFrame(index)
        try click(dots, at: NSPoint(x: frame.midX, y: dots.bounds.midY))
        XCTAssertEqual(controller.view.pager.targetIndex, index, "\(label): click on dot \(index)")
      }
    }
  }

  func testScrollWheelScrollsOnlyWhenTheDotsOverflow() throws {
    let fits = makeSidebar(spaces: 5, width: 190).view.spaceDots
    try scroll(fits, dx: -30)
    XCTAssertEqual(fits.scrollOffset, 0)

    let controller = makeSidebar(spaces: 12, width: 150)
    let dots = controller.view.spaceDots
    XCTAssertEqual(dots.scrollOffset, 0)
    XCTAssertFalse(dotIsVisible(dots, 11))
    try scroll(dots, dx: -30)
    XCTAssertEqual(dots.scrollOffset, 30, "fingers moving left reveal the dots on the right")
    try scroll(dots, dx: -1000)
    XCTAssertTrue(dotIsVisible(dots, 11), "clamped at the end with the last dot in view")
    let frame = dots.dotFrame(11)
    try click(dots, at: NSPoint(x: frame.midX, y: dots.bounds.midY))
    XCTAssertEqual(controller.view.pager.targetIndex, 11)
    try scroll(dots, dx: 1000)
    XCTAssertEqual(dots.scrollOffset, 0)
  }

  func testSwipePositionScrollsTheDockWithoutRelayout() throws {
    let controller = makeSidebar(spaces: 12, width: 150)
    let dots = controller.view.spaceDots
    let repaintsBefore = dots.repaintCountForTesting
    controller.view.pager.setPositionForTesting(6.2)
    XCTAssertTrue(dotIsVisible(dots, 6), "the dot nearest the fingers follows the swipe into view")
    XCTAssertFalse(dots.needsDisplay, "a swipe frame moves the strip, it does not redraw the dock")
    XCTAssertFalse(dots.needsLayout)
    XCTAssertLessThanOrEqual(dots.repaintCountForTesting - repaintsBefore, 3, "only the dots whose weight changed")
    let scale = dots.shellBackingScale
    let strip = try XCTUnwrap(dots.layer?.sublayers?.first?.sublayers?.first)
    for (index, dot) in (strip.sublayers ?? []).enumerated() {
      let px = (strip.frame.minX + dot.frame.minX) * scale
      XCTAssertEqual(px, px.rounded(), accuracy: 0.0001, "dot \(index) sits on a whole device pixel")
    }
  }

  func testRemovingSpacesUntilTheyFitCentersTheDots() throws {
    let stub = StubSidebar()
    let ids = (0..<8).map { stub.addSpace(title: "Space \($0 + 1)") }
    let controller = SidebarController(source: stub)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 190, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    windows.append(window)
    controller.view.layoutSubtreeIfNeeded()
    controller.showSpace(ids[7])
    let dots = controller.view.spaceDots
    dots.displayIfNeeded()
    XCTAssertGreaterThan(dots.scrollOffset, 0)
    for id in ids[3...] { stub.removeSpace(id) }
    controller.view.layoutSubtreeIfNeeded()
    dots.displayIfNeeded()
    XCTAssertEqual(dots.count, 3)
    XCTAssertEqual(dots.scrollOffset, 0)
    let center = (dots.dotFrame(0).midX + dots.dotFrame(2).midX) / 2
    XCTAssertEqual(center, dots.bounds.midX, accuracy: 1, "three dots sit centered again")
  }
}
