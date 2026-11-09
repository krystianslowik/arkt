import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The Downloads popover over repeated shows (#878): each show used to add another popover view and pointer tracker to
/// a shared container that hiding never cleared. No time is waited for: Reduce Motion is on and the timers are fired by
/// hand, so every close is immediate.
@MainActor
final class DownloadsPopoverStateTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var settings: AppSettings!
  private var center: DownloadsCenter!
  private var controllers: [ShellWindowController] = []
  private var folder: URL!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    folder = FileManager.default.temporaryDirectory.appending(path: "arkt-downloads-popover-\(UUID().uuidString)")
    engine = InMemoryEngine(downloadFolder: folder)
    settings = AppSettings.ephemeral()
    center = try XCTUnwrap(DownloadsCenter(engine: engine, settings: settings))
    center.announce = { _ in }
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    center.library.window?.close()
    for controller in controllers { controller.close() }
    for id in engine.windowIDs { engine.closeWindow(id) }
    controllers = []
    try? FileManager.default.removeItem(at: folder)
    center = nil
    settings = nil
    engine = nil
  }

  private func makeWindow() -> ShellWindowController {
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    center.primaryWindow = { controller }
    center.attach(to: controller)
    controller.rootView.layoutSubtreeIfNeeded()
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    controllers.append(controller)
    return controller
  }

  private func popoverViews(in container: NSView) -> Int { container.subviews.filter { $0 is DownloadsPopoverView }.count }
  private func trackers(in container: NSView) -> Int { container.subviews.filter { $0 is PointerTracker }.count }

  /// The download rows VoiceOver reaches from the panel's content view, walking the accessibility tree.
  private func accessibleRows(in container: NSView) -> Int {
    var count = 0
    var queue: [Any] = container.accessibilityChildren() ?? []
    while let next = queue.popLast() {
      if let view = next as? NSView {
        if view.accessibilityIdentifier() == AXID.Downloads.row { count += 1 }
        queue.append(contentsOf: view.accessibilityChildren() ?? [])
      } else if let element = next as? NSAccessibilityElement {
        if element.accessibilityIdentifier() == AXID.Downloads.row { count += 1 }
        queue.append(contentsOf: element.accessibilityChildren() ?? [])
      }
    }
    return count
  }

  func testShowingAgainLeavesOnePopoverViewAndOneTracker() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    _ = engine.beginDownload(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", totalBytes: 1_000)

    popover.show(takesKey: false)                               // shown by code, closed by Esc
    let first = try XCTUnwrap(popover.panel)
    XCTAssertTrue(first.onEscape?() == true)
    button.performClick(nil)                                    // a click opens, a second click closes
    button.performClick(nil)
    button.setHovered(true)                                     // a hover opens, leaving closes after the grace
    popover.firePendingTimer()
    XCTAssertTrue(popover.isShown)
    button.setHovered(false)
    popover.firePendingTimer()
    XCTAssertFalse(popover.isShown)
    popover.show(takesKey: false)

    let container = try XCTUnwrap(popover.panel?.contentView)
    XCTAssertEqual(popoverViews(in: container), 1, "one popover view after four shows")
    XCTAssertEqual(trackers(in: container), 1, "one pointer tracker after four shows")
    XCTAssertEqual(accessibleRows(in: container), 1, "VoiceOver reaches the one download once")
    XCTAssertEqual(popover.contentView?.order.count, 1)
    let old = try XCTUnwrap(first.contentView, "each show has its own content view")
    XCTAssertFalse(old === container)
    XCTAssertEqual(trackers(in: old), 0, "a closed panel keeps no tracker")
    XCTAssertEqual(popoverViews(in: old), 0, "a closed panel keeps no rows")
    popover.hide(keyboard: true)
  }

  func testTheHoverPhasesFollowThePointer() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    XCTAssertEqual(popover.phaseName, .closed)
    button.setHovered(true)
    XCTAssertEqual(popover.phaseName, .showPending)
    popover.firePendingTimer()
    XCTAssertEqual(popover.phaseName, .open(pointerInside: false))
    button.setHovered(false)
    XCTAssertEqual(popover.phaseName, .leavePending)
    popover.pointerInPanelChanged(true)
    XCTAssertEqual(popover.phaseName, .open(pointerInside: true))
    popover.firePendingTimer()
    XCTAssertEqual(popover.phaseName, .open(pointerInside: true), "no timer runs while the pointer is on the panel")
    popover.pointerInPanelChanged(false)
    XCTAssertEqual(popover.phaseName, .leavePending)
    popover.firePendingTimer()
    XCTAssertEqual(popover.phaseName, .closed)
    XCTAssertNil(popover.panel)
    #if DEBUG
    XCTAssertEqual(popover.transitionLog.map(\.to), [
      .showPending, .open(pointerInside: false), .leavePending, .open(pointerInside: true),
      .leavePending, .closed,
    ])
    #endif
  }

  func testACancelledHoverShowAndAShowWhileOpenDoNothing() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    button.setHovered(true)
    button.setHovered(false)                                    // off the button before the delay
    XCTAssertEqual(popover.phaseName, .closed)
    popover.firePendingTimer()
    XCTAssertEqual(popover.phaseName, .closed, "the cancelled show does not run")
    button.performClick(nil)
    XCTAssertEqual(popover.phaseName, .open(pointerInside: false))
    popover.show(takesKey: false)                               // already open: nothing
    button.performClick(nil)
    XCTAssertEqual(popover.phaseName, .closed)
  }
}
