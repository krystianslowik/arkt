import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Peek motion on a real display: the layer transforms move the card the way the scene says, scale it about its
/// center, change no view frame while it moves, and stay inside the repo's frame-time gate (`FrameStats`).
@MainActor
final class PeekMotionOnScreenTests: XCTestCase {
  private var controller: ShellWindowController!
  private var engine: InMemoryEngine!
  private var pinned: UUID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    pinned = try sidebar.addTab(url: URL(string: "https://mail.example.com/")!, title: "Mail", in: .pinned(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar))
    controller.peek.reduceMotion = { false }
    controller.window?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: true)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.activate(node: pinned)
  }

  override func tearDown() async throws { controller.close() }

  private func openPeek() throws -> PeekOverlayView {
    let tab = try XCTUnwrap(controller.engineTab(of: pinned))
    controller.peek.open(URL(string: "https://atlas.example/")!, from: tab, at: nil)
    return try XCTUnwrap(controller.peek.overlay)
  }

  /// The card's on-screen rect in window coordinates (unflipped), through the layer tree with its transform.
  private func screenRect(_ view: NSView) throws -> CGRect {
    let layer = try XCTUnwrap(view.layer)
    let root = try XCTUnwrap(controller.window?.contentView?.layer)
    let rect = layer.convert(layer.bounds, to: root)
    return root.contentsAreFlipped() ? CGRect(x: rect.minX, y: root.bounds.height - rect.maxY, width: rect.width,
                                              height: rect.height) : rect
  }

  func testADownwardSceneMovesTheCardDownOnScreen() throws {
    let overlay = try openPeek()
    controller.peek.animator.settleNow()
    let rest = try screenRect(overlay.card)
    overlay.apply(PeekScene.rest.with(.cardY, 100))
    let moved = try screenRect(overlay.card)
    XCTAssertEqual(moved.minY, rest.minY - 100, accuracy: 0.5, "window coordinates measure y upwards")
    XCTAssertEqual(moved.minX, rest.minX, accuracy: 0.5)
  }

  func testTheCardScalesAboutItsCenter() throws {
    let overlay = try openPeek()
    controller.peek.animator.settleNow()
    let rest = try screenRect(overlay.card)
    overlay.apply(PeekScene.rest.with(.cardScale, 0.9))
    let scaled = try screenRect(overlay.card)
    XCTAssertEqual(scaled.midX, rest.midX, accuracy: 0.5)
    XCTAssertEqual(scaled.midY, rest.midY, accuracy: 0.5)
    XCTAssertEqual(scaled.width, rest.width * 0.9, accuracy: 0.5)
  }

  func testTheSourceRecedesAboutItsCenter() throws {
    let card = controller.rootView.card
    let rest = try screenRect(card)
    _ = try openPeek()
    controller.peek.animator.settleNow()
    let receded = try screenRect(card)
    XCTAssertEqual(receded.midX, rest.midX, accuracy: 0.5)
    XCTAssertEqual(receded.midY, rest.midY, accuracy: 0.5)
    XCTAssertEqual(receded.width, rest.width * 0.985, accuracy: 0.5)
  }

  /// No view frame changes while the Peek moves: the page is resized once, at rest.
  func testOpenAndCloseChangeNoViewFrameWhileMoving() throws {
    let overlay = try openPeek()
    let page = try XCTUnwrap(overlay.card.page)
    let frames = (overlay.card.frame, page.frame, controller.rootView.card.frame)
    let done = expectation(description: "open settled")
    controller.peek.animator.onFrame = { [weak overlay] scene in
      overlay?.apply(scene)
      XCTAssertEqual(overlay?.card.frame, frames.0)
      XCTAssertEqual(page.frame, frames.1)
    }
    waitUntil("the open settles", timeout: 5) { self.controller.peek.session?.phase == .open }
    done.fulfill()
    wait(for: [done], timeout: 1)
    XCTAssertEqual(controller.rootView.card.frame, frames.2)
  }

  /// The repo's frame-time gate (8.6 ms per interval at 120 Hz) for the open and the close, on a machine that can
  /// measure it.
  func testOpenAndCloseStayInsideTheFrameTimeGate() throws {
    try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen)
    _ = try openPeek()
    waitUntil("the open settles", timeout: 5) { self.controller.peek.session?.phase == .open }
    let open = try XCTUnwrap(controller.peek.animator.lastPacing)
    XCTAssertGreaterThan(open.frameCount, 20, "the open ran on the display")
    XCTAssertEqual(open.hitchCount, 0, "open: max \(open.maxInterval * 1000) ms")
    controller.peek.close(.control)
    waitUntil("the close finishes", timeout: 5) { self.controller.peek.session == nil }
    let close = try XCTUnwrap(controller.peek.animator.lastPacing)
    XCTAssertEqual(close.hitchCount, 0, "close: max \(close.maxInterval * 1000) ms")
  }
}
