import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// Toolbar Back and Forward follow the current tab's `canGoBack` / `canGoForward` (engine contract rule 8): enabled
/// state, VoiceOver and the update on navigation, tab switch and close. Presses go through `performClick`.
@MainActor
final class ToolbarHistoryTests: XCTestCase {
  override func setUp() async throws { _ = NSApplication.shared }

  private func makeController(engine: InMemoryEngine, sidebar: StubSidebar = .sample()) -> ShellWindowController {
    let controller = ShellWindowController(engine: engine, sidebar: sidebar, toolbarSetting: .ephemeral())
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  private func currentTab(_ controller: ShellWindowController) throws -> TabID {
    try XCTUnwrap(controller.currentTab, "the window opens with the first tab of the first Space")
  }

  private func assertButtons(_ controller: ShellWindowController, back: Bool, forward: Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
    let toolbar = controller.rootView.card.toolbar
    XCTAssertEqual(toolbar.backButton.isEnabled, back, "Back", file: file, line: line)
    XCTAssertEqual(toolbar.forwardButton.isEnabled, forward, "Forward", file: file, line: line)
  }

  private func page(_ name: String) throws -> URL { try XCTUnwrap(URL(string: "https://\(name).example/page")) }

  // MARK: Enabled state

  func testBackAndForwardStartDisabledWithoutHistory() throws {
    let controller = makeController(engine: InMemoryEngine())
    _ = try currentTab(controller)
    assertButtons(controller, back: false, forward: false)
    XCTAssertTrue(controller.rootView.card.toolbar.reloadButton.isEnabled, "Reload does not depend on history")
  }

  func testNavigationEnablesBack() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    engine.navigate(try currentTab(controller), to: try page("second"))
    assertButtons(controller, back: true, forward: false)
  }

  func testBackEnablesForwardAndForwardRestoresBack() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    engine.navigate(tab, to: try page("second"))
    let toolbar = controller.rootView.card.toolbar
    toolbar.backButton.performClick(nil)
    assertButtons(controller, back: false, forward: true)
    toolbar.forwardButton.performClick(nil)
    assertButtons(controller, back: true, forward: false)
  }

  func testDisabledButtonsDoNothing() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    let recorder = EventRecorder(engine)
    let toolbar = controller.rootView.card.toolbar
    toolbar.backButton.performClick(nil)
    toolbar.forwardButton.performClick(nil)
    XCTAssertEqual(recorder.events(for: tab), [])
  }

  // MARK: Tab switch and close

  func testSwitchingTabsShowsThatTabsHistory() throws {
    let engine = InMemoryEngine()
    let sidebar = StubSidebar.sample()
    let controller = makeController(engine: engine, sidebar: sidebar)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    let (firstNode, other) = (try XCTUnwrap(today.first), try XCTUnwrap(today.last))
    XCTAssertNotEqual(firstNode, other)
    controller.activate(node: firstNode)
    let firstTab = try currentTab(controller)
    engine.navigate(firstTab, to: try page("second"))
    assertButtons(controller, back: true, forward: false)
    controller.activate(node: other)
    XCTAssertNotEqual(try currentTab(controller), firstTab)
    assertButtons(controller, back: false, forward: false)
    controller.activate(node: firstNode)
    XCTAssertEqual(try currentTab(controller), firstTab)
    assertButtons(controller, back: true, forward: false)
  }

  func testHistoryOfABackgroundTabLeavesTheToolbarAlone() throws {
    let engine = InMemoryEngine()
    let sidebar = StubSidebar.sample()
    let controller = makeController(engine: engine, sidebar: sidebar)
    let firstTab = try currentTab(controller)
    controller.activate(node: try XCTUnwrap(sidebar.children(of: .today(sidebar.spaceOrder[0])).last))
    engine.navigate(firstTab, to: try page("background"))
    assertButtons(controller, back: false, forward: false)
  }

  func testClosingTheCurrentTabDisablesBoth() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    engine.navigate(tab, to: try page("second"))
    engine.navigate(tab, to: try page("third"))
    engine.goBack(tab)
    assertButtons(controller, back: true, forward: true)
    engine.closeTab(tab)
    XCTAssertNil(controller.currentTab)
    assertButtons(controller, back: false, forward: false)
  }

  // MARK: VoiceOver

  func testVoiceOverReportsTheDisabledState() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let toolbar = controller.rootView.card.toolbar
    XCTAssertFalse(toolbar.backButton.isAccessibilityEnabled())
    XCTAssertFalse(toolbar.forwardButton.isAccessibilityEnabled())
    XCTAssertEqual(toolbar.backButton.accessibilityLabel(), "Back")
    engine.navigate(try currentTab(controller), to: try page("second"))
    XCTAssertTrue(toolbar.backButton.isAccessibilityEnabled())
    XCTAssertFalse(toolbar.forwardButton.isAccessibilityEnabled())
  }
}
