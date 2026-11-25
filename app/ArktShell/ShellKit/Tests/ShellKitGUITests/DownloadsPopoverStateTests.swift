import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The Downloads popover over repeated shows (#878): each show used to add another popover view and pointer tracker to
/// a shared container that hiding never cleared. No time is waited for: Reduce Motion is on, so every close is
/// immediate.
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

  func testShowingAgainLeavesOnePopoverView() throws {
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
    button.performClick(nil)                                    // a click opens, a click elsewhere closes
    XCTAssertTrue(popover.isShown)
    popover.handleMouseDown(in: controller.window, at: NSPoint(x: 600, y: 400))
    XCTAssertFalse(popover.isShown)
    popover.show(takesKey: false)

    let container = try XCTUnwrap(popover.panel?.contentView)
    XCTAssertEqual(popoverViews(in: container), 1, "one popover view after four shows")
    XCTAssertEqual(accessibleRows(in: container), 1, "VoiceOver reaches the one download once")
    XCTAssertEqual(popover.contentView?.order.count, 1)
    let old = try XCTUnwrap(first.contentView, "each show has its own content view")
    XCTAssertFalse(old === container)
    XCTAssertEqual(popoverViews(in: old), 0, "a closed panel keeps no rows")
    popover.hide(keyboard: true)
  }

  func testAShowWhileOpenDoesNothing() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    button.performClick(nil)
    XCTAssertEqual(popover.phaseName, .open)
    let panel = try XCTUnwrap(popover.panel)
    popover.show(takesKey: false)                               // already open: nothing
    XCTAssertTrue(popover.panel === panel, "a show while open keeps the same panel")
    XCTAssertEqual(popover.phaseName, .open)
    button.performClick(nil)
    XCTAssertEqual(popover.phaseName, .closed)
  }

  /// The popover opens on a click only (#987): resting the pointer on the button opens nothing, however long it stays.
  func testHoveringTheButtonDoesNotOpenThePopover() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    _ = engine.beginDownload(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", totalBytes: 1_000)
    button.mouseEntered(with: try pointerEvent(.mouseEntered, in: controller.window))
    XCTAssertEqual(popover.phaseName, .closed, "hovering opens nothing")
    XCTAssertNil(popover.panel)
    XCTAssertFalse(popover.isShown)
    button.mouseExited(with: try pointerEvent(.mouseExited, in: controller.window))
    XCTAssertEqual(popover.phaseName, .closed)
    button.mouseEntered(with: try pointerEvent(.mouseEntered, in: controller.window))
    button.performClick(nil)                                    // a click still opens it
    XCTAssertTrue(popover.isShown)
    popover.hide(keyboard: true)
  }

  /// A popover the user clicked open stays until it is dismissed (#987): the pointer leaving the button and the panel
  /// closes nothing. Only Esc, a click elsewhere, a second click or an action inside it does.
  func testAClickedOpenPopoverStaysWhenThePointerLeaves() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { true }
    _ = engine.beginDownload(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", totalBytes: 1_000)
    let enter = try pointerEvent(.mouseEntered, in: controller.window)
    let exit = try pointerEvent(.mouseExited, in: controller.window)
    button.mouseEntered(with: enter)
    button.performClick(nil)
    let panel = try XCTUnwrap(popover.panel)
    let content = try XCTUnwrap(panel.contentView)
    button.mouseExited(with: exit)                              // off the button
    for view in content.subviews { view.mouseEntered(with: enter) }  // over the panel
    for view in content.subviews { view.mouseExited(with: exit) }    // and off it again
    XCTAssertTrue(popover.isShown, "leaving does not close a popover the user clicked open")
    XCTAssertTrue(popover.panel === panel)
    XCTAssertEqual(popover.phaseName, .open)
    button.performClick(nil)
    XCTAssertFalse(popover.isShown, "a second click closes it")
    #if DEBUG
    XCTAssertEqual(popover.transitionLog.map(\.to), [.open, .closed], "the pointer moving changes no phase")
    #endif
  }

  /// An enter or exit event for the pointer tracking calls above; only its type matters to the views.
  private func pointerEvent(_ type: NSEvent.EventType, in window: NSWindow?) throws -> NSEvent {
    try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                                         trackingNumber: 0, userData: nil))
  }

  func testShowingDuringTheExitFadeStartsCleanAndLeavesTheFadingPanelItsRows() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { false }
    _ = engine.beginDownload(url: URL(string: "https://files.example/a.bin")!, filename: "a.bin", totalBytes: 1_000)
    button.performClick(nil)
    let fading = try XCTUnwrap(popover.panel)
    popover.hide(keyboard: false)                               // fades out
    popover.show(takesKey: false)                               // at once, before the fade has ended

    let fadingContent = try XCTUnwrap(fading.contentView)
    XCTAssertEqual(popoverViews(in: fadingContent), 1, "the fading panel keeps its rows until it leaves")
    let current = try XCTUnwrap(popover.panel)
    XCTAssertFalse(current === fading)
    let container = try XCTUnwrap(current.contentView)
    XCTAssertFalse(container === fadingContent)
    XCTAssertEqual(popoverViews(in: container), 1)
    XCTAssertEqual(popover.phaseName, .open)

    // The end state of the fade, so no window outlives the test (#805); the deadline is only the failure path.
    waitUntil("the faded panel to leave") { popoverViews(in: fadingContent) == 0 && !fading.isVisible }
    popover.hide(keyboard: true)
  }
}
