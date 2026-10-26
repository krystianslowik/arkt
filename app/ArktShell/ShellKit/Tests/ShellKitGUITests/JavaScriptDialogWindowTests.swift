import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A page's dialog in the shell window (#400): the window's tab events reach the presenter, the panel sits over the
/// tab that is shown and follows the tab switching, and an answer reaches the engine.
@MainActor
final class JavaScriptDialogWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var first: NodeID!
  private var second: NodeID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    first = try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .today(space))
    second = try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine,
                                       sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.javaScriptDialogs.reduceMotion = { true }
  }

  override func tearDown() async throws {
    controller.close()
  }

  func testTheShownTabsDialogGetsAPanelOverTheWindow() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)

    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Delete it?"))

    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    XCTAssertTrue(controller.window?.childWindows?.contains(panel.panel) == true)
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testSwitchingTabsHidesTheDialogWithoutAnsweringAndShowingTheTabBringsItBack() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Saved")
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))

    controller.activate(node: second)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab), "the page is off screen: no panel")
    XCTAssertNotNil(controller.javaScriptDialogs.pending[tab], "still pending: the page may be waiting")
    XCTAssertTrue(engine.dialogAnswers.isEmpty)

    controller.activate(node: first)
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testAClosingWindowTakesItsPanelsDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Bye")
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))

    controller.window?.close()

    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }

  // MARK: Tab switching with the panel key

  /// A real click on a sidebar row, through the window's own event dispatch (the first-click rule included).
  private func clickRow(of node: NodeID) throws {
    let window = try XCTUnwrap(controller.window)
    let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    let view = outline.outlineView
    window.contentView?.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    let rect = view.rect(ofRow: outline.row(for: node))
    let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    func event(_ type: NSEvent.EventType) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1))
    }
    window.postEvent(try event(.leftMouseUp), atStart: true)
    window.sendEvent(try event(.leftMouseDown))
    window.discardEvents(matching: [.leftMouseUp], before: nil)
  }

  /// The panel is key while a dialog is up, so the shell window is not: the first click on a row must still be the
  /// click, not only a re-key (the real app: one click switched with an alert and with a confirm up). The window is
  /// not key in this runner either, so the event goes through `NSWindow.sendEvent` as a first click does.
  func testOneClickOnARowSwitchesTabsWithADialogUp() throws {
    let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController).outlineView
    let probe = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    XCTAssertTrue(outline.acceptsFirstMouse(for: probe), "a click on a row while another of our windows is key")

    for kind in [JavaScriptDialog.Kind.alert, .confirm] {
      controller.activate(node: first)
      let tab = try XCTUnwrap(controller.currentTab)
      let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: kind, message: "Now?"))
      XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab), "\(kind): the dialog is up")

      try clickRow(of: second)

      XCTAssertEqual(controller.currentTab, controller.engineTab(of: second), "\(kind): one click switches")
      XCTAssertNil(controller.javaScriptDialogs.panel(for: tab), "\(kind): the page is off screen: no panel")
      if kind == .alert {
        XCTAssertEqual(controller.javaScriptDialogs.pending[tab]?.id, id, "an alert stays attached")
        controller.activate(node: first)
        XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab), "and reappears on return")
        engine.respond(to: id, accepted: true, userInput: nil)
      } else {
        XCTAssertNil(controller.javaScriptDialogs.pending[tab], "a confirm ends on switch-away, as in Chromium")
        XCTAssertEqual(engine.dialogAnswers.count, 1, "only the alert was answered: the engine ended the confirm")
      }
    }
  }
}
