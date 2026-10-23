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
    // The traffic lights' titlebar container must not cover any of the bar, its top edge included.
    let themeFrame = try XCTUnwrap(window.contentView?.superview)
    for y in [bar.bounds.minY + 1, bar.bounds.midY, bar.bounds.maxY - 1] {
      let point = bar.convert(NSPoint(x: bar.bounds.midX, y: y), to: nil)
      let hit = themeFrame.hitTest(themeFrame.convert(point, from: nil))
      XCTAssertTrue(hit === bar || hit?.isDescendant(of: bar) == true, "y \(y): hit \(String(describing: hit))")
    }
  }

  /// Arc hides the sidebar URL bar while the Toolbar is on: the favorites move up under the traffic-light strip
  /// (36 pt, tiles 8 pt below it).
  func testSidebarURLBarHidesWhileTheToolbarIsOn() throws {
    let controller = makeController()
    let sidebar = controller.sidebarController.view
    XCTAssertFalse(controller.urlBar.isHidden)
    controller.toggleToolbar(nil)
    sidebar.layoutSubtreeIfNeeded()
    XCTAssertTrue(controller.urlBar.isHidden)
    XCTAssertEqual(sidebar.favorites.frame.minY, sidebar.topBar.frame.maxY + SidebarMetrics.favoritesTopGap)
    XCTAssertEqual(sidebar.favorites.frame.minY, 44)
    controller.toggleToolbar(nil)
    sidebar.layoutSubtreeIfNeeded()
    XCTAssertFalse(controller.urlBar.isHidden)
    XCTAssertEqual(sidebar.favorites.frame.minY, controller.urlBar.frame.maxY + SidebarMetrics.favoritesTopGap)
  }

  func testWindowOpenedWithTheToolbarOnHidesTheSidebarURLBar() throws {
    let setting = ToolbarSetting.ephemeral()
    setting.isVisible = true
    let controller = makeController(setting: setting)
    XCTAssertTrue(controller.urlBar.isHidden)
    XCTAssertEqual(controller.sidebarController.view.favorites.frame.minY, 44)
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

  /// An event value handed straight to the view's handler; nothing is posted to the window or the system.
  private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in bar: URLBarView) throws -> NSEvent {
    let window = try XCTUnwrap(bar.window)
    return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: bar.convert(point, to: nil),
                                            modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                            clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
  }

  func testClickPressesOnMouseUpInside() throws {
    let controller = makeController()
    let bar = controller.urlBar
    var presses = 0
    bar.onPress = { presses += 1 }
    let center = NSPoint(x: bar.bounds.midX, y: bar.bounds.midY)
    bar.mouseDown(with: try mouseEvent(.leftMouseDown, at: center, in: bar))
    XCTAssertEqual(presses, 0, "mouse down alone does not press")
    bar.mouseUp(with: try mouseEvent(.leftMouseUp, at: center, in: bar))
    XCTAssertEqual(presses, 1)
  }

  func testReleasingOutsideCancelsThePress() throws {
    let controller = makeController()
    let bar = controller.urlBar
    var presses = 0
    bar.onPress = { presses += 1 }
    let center = NSPoint(x: bar.bounds.midX, y: bar.bounds.midY)
    bar.mouseDown(with: try mouseEvent(.leftMouseDown, at: center, in: bar))
    bar.mouseUp(with: try mouseEvent(.leftMouseUp, at: NSPoint(x: bar.bounds.maxX + 40, y: center.y), in: bar))
    XCTAssertEqual(presses, 0, "dragging out before release cancels")
    bar.mouseUp(with: try mouseEvent(.leftMouseUp, at: center, in: bar))
    XCTAssertEqual(presses, 0, "a mouse up without its mouse down does not press")
  }

  func testLabelHeightIsFixedByTheFont() throws {
    let bar = URLBarView(style: .full)
    bar.frame = NSRect(x: 0, y: 0, width: 400, height: SidebarMetrics.urlBarHeight)
    bar.layoutSubtreeIfNeeded()
    let empty = bar.label.frame
    bar.url = try XCTUnwrap(URL(string: "https://www.example.org/a/long/path?with=query&and=more"))
    bar.needsLayout = true
    bar.layoutSubtreeIfNeeded()
    XCTAssertEqual(bar.label.frame, empty)
    let probe = NSTextField(labelWithString: "example.org")
    probe.font = bar.label.font
    XCTAssertEqual(URLBarView.labelHeight, ceil(probe.intrinsicContentSize.height))
    XCTAssertEqual(bar.label.frame.height, URLBarView.labelHeight)
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

  /// Arc's Toolbar: a 32 pt strip and a 1 pt hairline; 32 x 24 buttons 4 pt from the top, 5 pt apart and 5 pt
  /// from the leading edge; the URL as plain text centered in the strip.
  func testToolbarLayoutFollowsArc() throws {
    let controller = makeController()
    controller.toggleToolbar(nil)
    let toolbar = controller.rootView.card.toolbar
    controller.rootView.card.layoutSubtreeIfNeeded()
    toolbar.layoutSubtreeIfNeeded()
    XCTAssertEqual(toolbar.bounds.height, 33)
    XCTAssertEqual(toolbar.backButton.frame, CGRect(x: 5, y: 4, width: 32, height: 24))
    XCTAssertEqual(toolbar.forwardButton.frame, CGRect(x: 42, y: 4, width: 32, height: 24))
    XCTAssertEqual(toolbar.reloadButton.frame, CGRect(x: 79, y: 4, width: 32, height: 24))
    XCTAssertEqual(toolbar.hairline.frame, CGRect(x: 0, y: 32, width: toolbar.bounds.width, height: 1))
    let bar = toolbar.urlBar.frame
    XCTAssertEqual(bar.midX, toolbar.bounds.midX, accuracy: 0.5, "centered in the strip, not after the buttons")
    XCTAssertGreaterThanOrEqual(bar.minX, toolbar.reloadButton.frame.maxX + 5)
    XCTAssertEqual(bar.minY, 4)
    XCTAssertEqual(bar.height, 24)
    XCTAssertEqual(toolbar.urlBar.label.alignment, .center)
  }

  /// No pill in the Toolbar: no fill, border or radius, hovered or not. The sidebar bar keeps its pill.
  func testToolbarURLIsPlainTextWithoutAPill() throws {
    let controller = makeController()
    controller.toggleToolbar(nil)
    let bar = controller.rootView.card.toolbar.urlBar
    let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                      trackingNumber: 0, userData: nil))
    for hovered in [false, true] {
      if hovered { bar.mouseEntered(with: event) }
      bar.updateLayer()
      let layer = try XCTUnwrap(bar.layer)
      XCTAssertNil(layer.backgroundColor, "hovered \(hovered)")
      XCTAssertEqual(layer.cornerRadius, 0)
      XCTAssertEqual(layer.borderWidth, 0)
    }
    let sidebarBar = URLBarView(style: .host)
    sidebarBar.updateLayer()
    XCTAssertEqual(sidebarBar.layer?.cornerRadius, SidebarMetrics.urlBarCornerRadius)
    XCTAssertNotNil(sidebarBar.layer?.backgroundColor)
    XCTAssertEqual(sidebarBar.label.alignment, .natural)
  }

  func testToolbarHairlineUsesTheMeasuredDarkLevel() throws {
    let controller = makeController()
    controller.window?.appearance = NSAppearance(named: .darkAqua)
    controller.toggleToolbar(nil)
    let toolbar = controller.rootView.card.toolbar
    toolbar.viewDidChangeEffectiveAppearance()
    toolbar.updateLayer()
    XCTAssertEqual(toolbar.hairline.backgroundColor, ShellTokens.toolbarHairline.dark.cgColor)
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

  func testToggleUpdatesEveryWindowSharingTheSetting() throws {
    let setting = ToolbarSetting.ephemeral()
    let first = makeController(setting: setting)
    let second = makeController(setting: setting)
    first.toggleToolbar(nil)
    for controller in [first, second] {
      controller.rootView.card.layoutSubtreeIfNeeded()
      XCTAssertTrue(controller.isToolbarVisible)
      XCTAssertFalse(controller.rootView.card.toolbar.isHidden)
      XCTAssertTrue(controller.urlBar.isHidden, "the sidebar URL bar hides while the Toolbar is on")
      XCTAssertEqual(controller.urlBar.contextMenu().items.map(\.title), ["Hide Toolbar"])
      XCTAssertEqual(controller.rootView.card.toolbar.urlBar.contextMenu().items.map(\.title), ["Hide Toolbar"])
    }
    second.toggleToolbar(nil)
    XCTAssertTrue(first.rootView.card.toolbar.isHidden, "a toggle in the second window hides the first's too")
    XCTAssertFalse(first.urlBar.isHidden)
    XCTAssertEqual(first.urlBar.contextMenu().items.map(\.title), ["Show Toolbar"])
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
