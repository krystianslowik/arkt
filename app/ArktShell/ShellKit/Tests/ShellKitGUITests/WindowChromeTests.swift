import AppKit
import XCTest
import EngineAPITestSupport
@testable import ShellUI

@MainActor
final class WindowChromeTests: XCTestCase {
  override func setUp() async throws { _ = NSApplication.shared }

  private func closeButtonTopLeft(_ window: NSWindow) throws -> (CGPoint, NSRect) {
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    let inWindow = close.convert(close.bounds, to: nil)            // window coords, origin bottom-left
    return (CGPoint(x: inWindow.minX, y: window.frame.height - inWindow.maxY), inWindow)
  }

  func testTrafficLightsSitInSidebar() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    window.setContentSize(NSSize(width: 1200, height: 800))
    window.contentView?.layoutSubtreeIfNeeded()
    let (topLeft, inWindow) = try closeButtonTopLeft(window)
    XCTAssertEqual(topLeft.x, 12, accuracy: 0.5)
    XCTAssertEqual(topLeft.y, 16, accuracy: 0.5)
    XCTAssertLessThan(inWindow.maxX, 190, "traffic lights must stay inside the sidebar")
    let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton)).convert(NSPoint.zero, to: nil)
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton)).convert(NSPoint.zero, to: nil)
    XCTAssertEqual(zoom.x - close.x, 2 * 23, accuracy: 0.5, "Arc's 23 pt pitch")
  }

  func testTrafficLightsStayPutAfterResize() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    window.setContentSize(NSSize(width: 900, height: 600))
    window.contentView?.layoutSubtreeIfNeeded()
    let (topLeft, _) = try closeButtonTopLeft(window)
    XCTAssertEqual(topLeft.x, 12, accuracy: 0.5)
    XCTAssertEqual(topLeft.y, 16, accuracy: 0.5)
  }

  func testWindowIsTitlelessFullSizeContent() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window)
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertEqual(window.titleVisibility, .hidden)
  }

  func testCardHasHairlineAndRadius() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    root.layoutSubtreeIfNeeded()
    let clip = try XCTUnwrap(root.card.clipView.layer)
    XCTAssertEqual(clip.cornerRadius, 10)
    XCTAssertEqual(clip.cornerCurve, .continuous)
    XCTAssertTrue(clip.masksToBounds)
    XCTAssertEqual(clip.borderWidth, 1 / (controller.window?.backingScaleFactor ?? 2), accuracy: 0.001)
    XCTAssertEqual(root.card.frame, CGRect(x: 190, y: 10, width: root.bounds.width - 200, height: root.bounds.height - 20))
  }

  func testCardHostsTheEngineContentView() throws {
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    let tab = try XCTUnwrap(engine.tabIDs.first)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(page.superview === root.card.clipView)
    root.layoutSubtreeIfNeeded()
    XCTAssertEqual(page.frame, root.card.clipView.bounds)
  }

  func testResizeHandleClampsSidebarWidth() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    root.resizeHandle.onWidthChange?(1000)
    root.layoutSubtreeIfNeeded()
    XCTAssertEqual(root.sidebarWidth, ShellMetrics.standard.sidebarMaxWidth)
    XCTAssertEqual(root.card.frame.minX, ShellMetrics.standard.sidebarMaxWidth)
    root.resizeHandle.onWidthChange?(10)
    root.layoutSubtreeIfNeeded()
    XCTAssertEqual(root.sidebarWidth, ShellMetrics.standard.sidebarMinWidth)
  }

  func testTitlebarContainerIsNarrowedToSidebar() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    window.contentView?.layoutSubtreeIfNeeded()
    let container = try XCTUnwrap(window.standardWindowButton(.closeButton)?.superview?.superview)
    XCTAssertEqual(container.frame.minX, 0)
    XCTAssertEqual(container.frame.width, 190)
    // As tall as the sidebar's traffic-light strip, so it never covers the URL bar below it.
    XCTAssertEqual(container.frame.height, ShellMetrics.standard.sidebarTopBarHeight)
  }

  func testClickNearWindowTopInsideCardReachesCard() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    let root = try XCTUnwrap(window.contentView as? ShellRootView)
    root.layoutSubtreeIfNeeded()
    let frameView = try XCTUnwrap(root.superview)              // NSThemeFrame, hosts the titlebar container too
    let pointInWindow = NSPoint(x: 600, y: window.frame.height - 20)
    let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(pointInWindow, from: nil)))
    XCTAssertTrue(hit.isDescendant(of: root.card), "got \(hit)")
  }

  func testDarkAppearanceUsesDarkCardTokens() throws {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(controller.window)
    window.appearance = NSAppearance(named: .darkAqua)
    let root = try XCTUnwrap(window.contentView as? ShellRootView)
    root.layoutSubtreeIfNeeded()
    root.card.updateLayer()
    let clip = try XCTUnwrap(root.card.clipView.layer)
    XCTAssertEqual(clip.borderColor, RGBA.white(0.20).cgColor)
    XCTAssertEqual(root.card.layer?.shadowOpacity, 0)
  }
}
