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

  // MARK: History menus and modifier clicks (#81, GS-024..026, BH-027, BH-165, BH-166)

  func testBackAndForwardHistoryMenusListEntriesAndJumpToSelectedOffset() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    let toolbar = controller.rootView.card.toolbar

    // Without history, right-click / menu returns nil.
    XCTAssertNil(toolbar.backHistoryMenu())
    XCTAssertNil(toolbar.forwardHistoryMenu())

    let first = try XCTUnwrap(engine.snapshot(of: tab)?.url)
    engine.finishLoad(tab, title: "First Title")
    let second = try page("second")
    engine.navigate(tab, to: second)
    engine.finishLoad(tab, title: "Second Title")
    let third = try page("third")
    engine.navigate(tab, to: third)
    engine.finishLoad(tab, title: "Third Title")

    // Back menu lists nearest-first ("Second Title" at tag -1, "First Title" at tag -2), both via right-click
    // (`menu(for:)`) and long-press (`triggerLongPressForTesting()`).
    let backMenu = try XCTUnwrap(toolbar.backHistoryMenu())
    XCTAssertEqual(backMenu.items.map(\.title), ["Second Title", "First Title"])
    XCTAssertEqual(backMenu.items.map(\.tag), [-1, -2])

    var shownByLongPress: NSMenu?
    toolbar.backButton.onShowHistoryMenu = { shownByLongPress = $0 }
    toolbar.backButton.triggerLongPressForTesting()
    XCTAssertEqual(shownByLongPress?.items.map(\.title), ["Second Title", "First Title"])

    // Selecting the second item (offset -2) jumps straight back to `first`.
    _ = backMenu.items[1].target?.perform(backMenu.items[1].action, with: backMenu.items[1])
    XCTAssertEqual(engine.snapshot(of: tab)?.url, first)

    // Forward menu now lists "Second Title" (tag +1) and "Third Title" (tag +2); selecting tag +2 jumps to `third`.
    let forwardMenu = try XCTUnwrap(toolbar.forwardHistoryMenu())
    XCTAssertEqual(forwardMenu.items.map(\.title), ["Second Title", "Third Title"])
    XCTAssertEqual(forwardMenu.items.map(\.tag), [1, 2])
    _ = forwardMenu.items[1].target?.perform(forwardMenu.items[1].action, with: forwardMenu.items[1])
    XCTAssertEqual(engine.snapshot(of: tab)?.url, third)
  }

  func testCommandClickAndMiddleClickOnBackAndForwardOpenEntryInBackgroundTodayTab() throws {
    let engine = InMemoryEngine()
    let sidebar = StubSidebar.sample()
    let controller = makeController(engine: engine, sidebar: sidebar)
    let space = sidebar.spaceOrder[0]
    let tab = try currentTab(controller)
    let originalNode = try XCTUnwrap(controller.sidebarController.current)
    let first = try XCTUnwrap(engine.snapshot(of: tab)?.url)
    engine.finishLoad(tab, title: "First Title")
    let second = try page("second")
    engine.navigate(tab, to: second)
    engine.finishLoad(tab, title: "Second Title")
    let third = try page("third")
    engine.navigate(tab, to: third)
    engine.finishLoad(tab, title: "Third Title")
    engine.goBack(tab)   // now on `second`: back has `first`, forward has `third`
    XCTAssertEqual(engine.snapshot(of: tab)?.url, second)

    let toolbar = controller.rootView.card.toolbar
    let beforeToday = sidebar.children(of: .today(space))

    // Cmd-click Back opens `first` in a new background Today tab; current tab stays on `second`.
    toolbar.backButton.performClickWithModifiers(.command)
    let afterCmdBack = sidebar.children(of: .today(space))
    XCTAssertEqual(afterCmdBack.count, beforeToday.count + 1)
    let backOpenedNode = try XCTUnwrap(afterCmdBack.last)
    if case .tab(_, let url, let title)? = sidebar.node(backOpenedNode) {
      XCTAssertEqual(url, first)
      XCTAssertEqual(title, "First Title")
    } else {
      XCTFail("expected background Today tab for Back entry")
    }
    XCTAssertEqual(controller.sidebarController.current, originalNode, "active tab stays on original")
    XCTAssertEqual(engine.snapshot(of: tab)?.url, second, "original tab does not navigate back")

    // Middle-click Forward opens `third` in a new background Today tab; current tab stays on `second`.
    toolbar.forwardButton.performMiddleClick()
    let afterMiddleForward = sidebar.children(of: .today(space))
    XCTAssertEqual(afterMiddleForward.count, afterCmdBack.count + 1)
    let forwardOpenedNode = try XCTUnwrap(afterMiddleForward.last)
    if case .tab(_, let url, let title)? = sidebar.node(forwardOpenedNode) {
      XCTAssertEqual(url, third)
      XCTAssertEqual(title, "Third Title")
    } else {
      XCTFail("expected background Today tab for Forward entry")
    }
    XCTAssertEqual(controller.sidebarController.current, originalNode)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, second)
  }

  func testCommandClickReloadDuplicatesCurrentTabWithHistory() throws {
    let engine = InMemoryEngine()
    let sidebar = StubSidebar.sample()
    let controller = makeController(engine: engine, sidebar: sidebar)
    let space = sidebar.spaceOrder[0]
    let tab = try currentTab(controller)
    let originalNode = try XCTUnwrap(controller.sidebarController.current)
    let first = try XCTUnwrap(engine.snapshot(of: tab)?.url)
    engine.finishLoad(tab, title: "First Title")
    let second = try page("second")
    engine.navigate(tab, to: second)
    engine.finishLoad(tab, title: "Second Title")
    let third = try page("third")
    engine.navigate(tab, to: third)
    engine.finishLoad(tab, title: "Third Title")
    engine.goBack(tab)   // on `second`: back has `first`, forward has `third`

    let beforeToday = sidebar.children(of: .today(space))
    controller.rootView.card.toolbar.reloadButton.performClickWithModifiers(.command)

    let afterToday = sidebar.children(of: .today(space))
    XCTAssertEqual(afterToday.count, beforeToday.count + 1)
    let duplicatedNode = try XCTUnwrap(afterToday.last)
    XCTAssertNotEqual(duplicatedNode, originalNode)
    XCTAssertEqual(controller.sidebarController.current, duplicatedNode, "duplicate becomes the current tab")
    let duplicatedTab = try currentTab(controller)
    XCTAssertNotEqual(duplicatedTab, tab)
    XCTAssertEqual(engine.snapshot(of: duplicatedTab)?.url, second)
    XCTAssertEqual(engine.history(of: duplicatedTab)?.back.map(\.url), [first])
    XCTAssertEqual(engine.history(of: duplicatedTab)?.forward.map(\.url), [third])
    assertButtons(controller, back: true, forward: true)
  }
}
