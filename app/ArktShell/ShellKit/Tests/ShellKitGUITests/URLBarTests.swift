import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// The sidebar URL bar (BH-031, GS-042), the content-card Toolbar (KB-018, BH-032) and their window wiring.
/// No synthetic input: presses go through accessibility actions and menu items, hits through `hitTest`.
@MainActor
final class URLBarTests: XCTestCase {
  private var suiteName: String?

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    if let suiteName { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
  }

  private func makeDefaults() throws -> UserDefaults {
    let name = "dev.arkt.tests.urlbar.\(UUID().uuidString)"
    suiteName = name
    return try XCTUnwrap(UserDefaults(suiteName: name))
  }

  private func makeController(engine: InMemoryEngine = InMemoryEngine(),
                              setting: ToolbarSetting = .ephemeral()) -> ShellWindowController {
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample(), toolbarSetting: setting)
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  private func currentTab(_ controller: ShellWindowController) throws -> TabID {
    try XCTUnwrap(controller.currentTab, "the window opens with the first tab of the first Space")
  }

  // MARK: Binding

  func testURLBarShowsTheActiveTabsHost() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    let url = try XCTUnwrap(engine.snapshot(of: tab)?.url)
    XCTAssertEqual(controller.urlBar.url, url)
    XCTAssertEqual(controller.urlBar.displayedText, AddressText.host(url))
  }

  func testURLBarFollowsURLChangesOfTheActiveTab() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let tab = try currentTab(controller)
    let next = try XCTUnwrap(URL(string: "https://www.example.org/docs/page?q=1"))
    engine.navigate(tab, to: next)
    XCTAssertEqual(controller.urlBar.displayedText, "example.org")
    XCTAssertEqual(controller.rootView.card.toolbar.urlBar.displayedText, next.absoluteString)
    XCTAssertEqual(controller.urlBar.accessibilityValue() as? String, "example.org")
  }

  func testURLChangesOfAnotherTabLeaveTheURLBarAlone() throws {
    let engine = InMemoryEngine()
    let sidebar = StubSidebar.sample()
    let controller = ShellWindowController(engine: engine, sidebar: sidebar, toolbarSetting: .ephemeral())
    let firstTab = try currentTab(controller)
    let other = try XCTUnwrap(sidebar.children(of: .today(sidebar.spaceOrder[0])).last)
    controller.activate(node: other)
    let otherTab = try currentTab(controller)
    XCTAssertNotEqual(firstTab, otherTab)
    let otherText = controller.urlBar.displayedText
    engine.navigate(firstTab, to: try XCTUnwrap(URL(string: "https://background.example")))
    XCTAssertEqual(controller.urlBar.displayedText, otherText)
  }

  func testClosingTheActiveTabClearsTheURLBar() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    engine.closeTab(try currentTab(controller))
    XCTAssertNil(controller.urlBar.url)
    XCTAssertEqual(controller.urlBar.displayedText, "")
  }

  // MARK: Placement

  func testURLBarSitsBelowTheTrafficLightsAboveFavoritesAndTakesClicks() throws {
    let controller = makeController()
    let window = try XCTUnwrap(controller.window)
    let sidebar = controller.sidebarController.view
    let bar = controller.urlBar
    XCTAssertGreaterThanOrEqual(bar.frame.minY, sidebar.topBar.frame.maxY, "below the traffic-light strip")
    XCTAssertLessThanOrEqual(bar.frame.maxY, sidebar.favorites.frame.minY, "above the favorites")
    XCTAssertEqual(bar.frame.minX, SidebarMetrics.horizontalPadding)
    XCTAssertEqual(bar.frame.width, sidebar.bounds.width - 2 * SidebarMetrics.horizontalPadding)
    XCTAssertEqual(bar.frame.height, SidebarMetrics.urlBarHeight)
    XCTAssertFalse(bar.mouseDownCanMoveWindow, "clicking the URL bar must not drag the window")
    // The traffic lights' titlebar container must not cover the bar.
    let center = bar.convert(NSPoint(x: bar.bounds.midX, y: bar.bounds.midY), to: nil)
    let themeFrame = try XCTUnwrap(window.contentView?.superview)
    let hit = themeFrame.hitTest(themeFrame.convert(center, from: nil))
    XCTAssertTrue(hit === bar || hit?.isDescendant(of: bar) == true, "hit \(String(describing: hit))")
  }

  // MARK: Press and menu

  func testPressOpensTheCommandBarPrefilledWithTheCurrentURL() async throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    controller.showWindow(nil)
    defer { controller.close() }
    let url = try XCTUnwrap(engine.snapshot(of: try currentTab(controller))?.url)
    XCTAssertTrue(controller.urlBar.accessibilityPerformPress())                         // same path as Cmd-L
    XCTAssertTrue(controller.commandBar.isVisible)
    XCTAssertEqual(controller.commandBar.mode, .currentTab(url))
    XCTAssertEqual(controller.commandBar.barView.field.stringValue, url.absoluteString)   // KB-002
    XCTAssertTrue(controller.urlBar.accessibilityPerformPress())
    XCTAssertFalse(controller.commandBar.isVisible, "a second press closes it, like Cmd-L")
  }

  func testContextMenuTogglesTheToolbar() throws {
    let controller = makeController()
    let menu = controller.urlBar.contextMenu()
    XCTAssertEqual(menu.items.map(\.title), ["Show Toolbar"])                            // BH-031, GS-042
    menu.performActionForItem(at: 0)
    XCTAssertTrue(controller.isToolbarVisible)
    XCTAssertEqual(controller.urlBar.contextMenu().items.map(\.title), ["Hide Toolbar"])
    let toolbarMenu = controller.rootView.card.toolbar.urlBar.contextMenu()
    XCTAssertEqual(toolbarMenu.items.map(\.title), ["Hide Toolbar"])
    toolbarMenu.performActionForItem(at: 0)
    XCTAssertFalse(controller.isToolbarVisible)
  }

  func testMenuItemTitleFollowsTheToolbarState() throws {
    let controller = makeController()
    let item = NSMenuItem(title: "", action: #selector(ShellWindowController.toggleToolbar(_:)), keyEquivalent: "")
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Show Toolbar")                                            // KB-018
    controller.toggleToolbar(item)
    XCTAssertTrue(controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Hide Toolbar")
  }

  // MARK: Toolbar

  func testToggleToolbarPutsTheToolbarAboveTheContent() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    let card = controller.rootView.card
    XCTAssertTrue(card.toolbar.isHidden)
    XCTAssertEqual(card.contentView?.frame, card.clipView.bounds)
    controller.toggleToolbar(nil)                                                         // BH-032
    card.layoutSubtreeIfNeeded()
    XCTAssertFalse(card.toolbar.isHidden)
    let height = ContentToolbarView.height
    let clip = card.clipView.bounds
    XCTAssertEqual(card.toolbar.frame, CGRect(x: 0, y: clip.height - height, width: clip.width, height: height))
    XCTAssertEqual(card.contentView?.frame, CGRect(x: 0, y: 0, width: clip.width, height: clip.height - height))
    let url = try XCTUnwrap(engine.snapshot(of: try currentTab(controller))?.url)
    XCTAssertEqual(card.toolbar.urlBar.displayedText, url.absoluteString)
    controller.toggleToolbar(nil)
    card.layoutSubtreeIfNeeded()
    XCTAssertTrue(card.toolbar.isHidden)
    XCTAssertEqual(card.contentView?.frame, card.clipView.bounds)
  }

  func testToolbarSettingPersistsAcrossWindows() throws {
    let defaults = try makeDefaults()
    let first = makeController(setting: ToolbarSetting(defaults: defaults))
    XCTAssertFalse(first.isToolbarVisible)
    first.toggleToolbar(nil)
    let second = makeController(setting: ToolbarSetting(defaults: defaults))
    XCTAssertTrue(second.isToolbarVisible)
    XCTAssertFalse(second.rootView.card.toolbar.isHidden)
  }

  func testToolbarButtonsDriveTheEngine() throws {
    let engine = InMemoryEngine()
    let controller = makeController(engine: engine)
    controller.toggleToolbar(nil)
    let tab = try currentTab(controller)
    let first = try XCTUnwrap(engine.snapshot(of: tab)?.url)
    let second = try XCTUnwrap(URL(string: "https://second.example/page"))
    engine.navigate(tab, to: second)
    engine.finishLoad(tab, title: "Second")
    let toolbar = controller.rootView.card.toolbar
    toolbar.backButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, first)
    XCTAssertEqual(controller.urlBar.displayedText, AddressText.host(first))
    engine.finishLoad(tab, title: "First")
    toolbar.forwardButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, second)
    engine.finishLoad(tab, title: "Second")
    let recorder = EventRecorder(engine)
    toolbar.reloadButton.performClick(nil)
    XCTAssertEqual(recorder.events(for: tab), [.loadingChanged(tab, isLoading: true)])
  }

  // MARK: Accessibility

  func testVoiceOverLabels() throws {
    let controller = makeController()
    let bar = controller.urlBar
    XCTAssertTrue(bar.isAccessibilityElement())
    XCTAssertEqual(bar.accessibilityRole(), .button)
    XCTAssertEqual(bar.accessibilityLabel(), "Address")
    XCTAssertEqual(bar.accessibilityValue() as? String, bar.displayedText)
    XCTAssertNotNil(bar.accessibilityHelp())
    let toolbar = controller.rootView.card.toolbar
    XCTAssertEqual(toolbar.backButton.accessibilityLabel(), "Back")
    XCTAssertEqual(toolbar.forwardButton.accessibilityLabel(), "Forward")
    XCTAssertEqual(toolbar.reloadButton.accessibilityLabel(), "Reload")
    XCTAssertEqual(toolbar.urlBar.accessibilityLabel(), "Address")
    XCTAssertEqual(toolbar.accessibilityRole(), .toolbar)
  }
}
