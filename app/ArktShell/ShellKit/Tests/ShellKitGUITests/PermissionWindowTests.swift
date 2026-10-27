import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A site's permission request in the shell window (#400): the window's tab events reach the presenter, the panel sits
/// over the tab that is shown and follows the tab switching as Chromium does (ended on switch-away, asked again on
/// return), an answer reaches the engine, and closing the window leaves nothing behind.
@MainActor
final class PermissionWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var first: NodeID!
  private var second: NodeID!
  private var now: TimeInterval = 50

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
    controller.permissionPrompts.reduceMotion = { true }
    controller.permissionPrompts.clock = { [unowned self] in now }
  }

  override func tearDown() async throws {
    controller.close()
  }

  func testTheShownTabsAskGetsAPanelOverTheWindowAndAnAnswerReachesTheEngine() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)

    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.notifications]))

    let panel = try XCTUnwrap(controller.permissionPrompts.panel(for: tab))
    XCTAssertTrue(controller.window?.childWindows?.contains(panel.panel) == true)
    now += 1
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.map(\.id), [id])
    XCTAssertEqual(engine.permissionAnswers.first?.choice, .allow)
    XCTAssertNil(controller.permissionPrompts.panel(for: tab))
  }

  func testSwitchingTabsEndsThePromptWithoutAnsweringAndShowingTheTabAsksAgain() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    XCTAssertNotNil(controller.permissionPrompts.panel(for: tab))

    controller.activate(node: second)
    XCTAssertNil(controller.permissionPrompts.panel(for: tab), "the page is off screen: no panel")
    XCTAssertNil(controller.permissionPrompts.pending[tab], "Chromium deletes the prompt of a hidden tab")
    XCTAssertTrue(engine.permissionAnswers.isEmpty)

    controller.activate(node: first)
    let back = try XCTUnwrap(controller.permissionPrompts.pending[tab])
    XCTAssertNotEqual(back.id, id)
    XCTAssertNotNil(controller.permissionPrompts.panel(for: tab))
  }

  func testAClosingWindowTakesItsPanelsDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.askPermission(in: tab, kinds: [.camera])
    let panel = try XCTUnwrap(controller.permissionPrompts.panel(for: tab))

    controller.window?.close()

    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(controller.permissionPrompts.panel(for: tab))
  }
}
