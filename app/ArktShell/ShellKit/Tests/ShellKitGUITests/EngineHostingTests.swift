import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// W3-7 part A: the shell window as the engine's window host. The engine window is created on the first tab
/// (decision 4), every tab lands in it, the host claims Arc's commands and forwards the rest, and the close button
/// asks the engine instead of closing the window.
@MainActor
final class EngineHostingTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testTheFirstTabCreatesTheEngineWindowWithThisWindowsHost() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.engineWindow)
    XCTAssertEqual(harness.engine.windowIDs, [window])
    XCTAssertTrue(harness.engine.host(of: window) === harness.controller.engineHost)
    XCTAssertTrue(harness.controller.engineHost.window === harness.controller.window)
    XCTAssertTrue(harness.controller.engineHost.cardView === harness.controller.rootView.card)
    harness.controller.activate(node: world.today[0])
    XCTAssertEqual(harness.engine.windowIDs, [window], "later tabs reuse the window")
    for tab in harness.engine.tabIDs { XCTAssertEqual(harness.engine.snapshot(of: tab)?.window, window) }
  }

  func testNoEngineWindowBeforeTheFirstTab() throws {
    var sidebar = SidebarModel.Sidebar()
    _ = sidebar.addSpace(title: "Empty")
    let harness = EngineHarnessWindow(sidebar)
    XCTAssertNil(harness.controller.engineWindow)
    XCTAssertTrue(harness.engine.windowIDs.isEmpty)
    XCTAssertTrue(harness.controller.windowShouldClose(try XCTUnwrap(harness.controller.window)),
                  "without an engine window the window closes as before")
  }

  /// With two windows on one engine each tab opens in its own window's engine window.
  func testTwoWindowsOpenTabsInTheirOwnEngineWindows() throws {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let first = EngineHarnessWindow(world.sidebar, engine: engine)
    let second = EngineHarnessWindow(world.sidebar, engine: engine)
    let (one, two) = (try XCTUnwrap(first.controller.engineWindow), try XCTUnwrap(second.controller.engineWindow))
    XCTAssertNotEqual(one, two)
    first.controller.activate(node: world.today[0])
    second.controller.activate(node: world.today[1])
    XCTAssertEqual(engine.snapshot(of: try XCTUnwrap(first.controller.currentTab))?.window, one)
    XCTAssertEqual(engine.snapshot(of: try XCTUnwrap(second.controller.currentTab))?.window, two)
  }

  func testTheHostClaimsNewTabAndCloseTab() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let host = harness.controller.engineHost
    XCTAssertEqual(host.claim(.newTab), CommandClaim(isEnabled: true))
    XCTAssertEqual(host.claim(.closeTab), CommandClaim(isEnabled: true))
    XCTAssertNil(host.claim(.reload))
    harness.controller.activate(node: world.today[1])

    XCTAssertTrue(host.perform(.closeTab, disposition: .currentTab))
    XCTAssertEqual(harness.archived, [[world.today[1]]])
    XCTAssertTrue(host.perform(.newTab, disposition: .currentTab))
    XCTAssertTrue(harness.controller.commandBar.isVisible)
    harness.controller.commandBar.toggle(.newTab)
    XCTAssertFalse(host.perform(.reload, disposition: .currentTab))
    XCTAssertTrue(harness.engine.executedCommands.isEmpty, "claimed commands never reach the engine")
  }

  func testCloseTabIsDisabledWithoutACurrentTab() throws {
    var sidebar = SidebarModel.Sidebar()
    _ = sidebar.addSpace(title: "Empty")
    let harness = EngineHarnessWindow(sidebar)
    XCTAssertEqual(harness.controller.engineHost.claim(.closeTab), CommandClaim(isEnabled: false))
  }

  /// `commandDispatch:` (Chromium's menu and Arkt's page-command items): a claimed command runs in the shell, an
  /// unclaimed one goes to the engine with the window and disposition.
  func testCommandDispatchRunsClaimedCommandsAndForwardsTheRest() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window as? ShellWindow)
    let reload = NSMenuItem(title: "Reload", action: #selector(ShellWindow.commandDispatch(_:)), keyEquivalent: "")
    reload.tag = EngineCommand.reload.rawValue
    XCTAssertTrue(window.validateUserInterfaceItem(reload))

    window.commandDispatch(reload)

    let executed = harness.engine.executedCommands
    XCTAssertEqual(executed.map(\.command), [.reload])
    XCTAssertEqual(executed.map(\.disposition), [.currentTab])
    XCTAssertEqual(executed.map(\.window), [harness.controller.engineWindow])

    let newTab = NSMenuItem(title: "New Tab", action: #selector(ShellWindow.commandDispatch(_:)), keyEquivalent: "")
    newTab.tag = EngineCommand.newTab.rawValue
    window.commandDispatch(newTab)
    XCTAssertTrue(harness.controller.commandBar.isVisible)
    XCTAssertEqual(harness.engine.executedCommands.count, 1)
    harness.controller.commandBar.toggle(.newTab)
  }

  func testUnclaimedCommandsAreDisabledWithoutAnEngineWindow() throws {
    var sidebar = SidebarModel.Sidebar()
    _ = sidebar.addSpace(title: "Empty")
    let harness = EngineHarnessWindow(sidebar)
    let window = try XCTUnwrap(harness.controller.window as? ShellWindow)
    let reload = NSMenuItem(title: "Reload", action: #selector(ShellWindow.commandDispatch(_:)), keyEquivalent: "")
    reload.tag = EngineCommand.reload.rawValue
    XCTAssertFalse(window.validateUserInterfaceItem(reload))
  }

  func testKeyModifiersPickTheDisposition() {
    XCTAssertEqual(ShellWindow.disposition(for: []), .currentTab)
    XCTAssertEqual(ShellWindow.disposition(for: [.command]), .newBackgroundTab)
    XCTAssertEqual(ShellWindow.disposition(for: [.command, .shift]), .newForegroundTab)
    XCTAssertEqual(ShellWindow.disposition(for: [.shift]), .newWindow)
    XCTAssertEqual(ShellWindow.disposition(for: [.option]), .currentTab)
  }

  /// The close button never closes the window itself: the engine closes the tabs, and the window closes on its
  /// `.windowClosed`. A held prompt keeps it open; cancelling keeps the window and its rows.
  func testTheCloseButtonAsksTheEngineAndAHeldCloseKeepsTheWindow() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    let engineWindow = try XCTUnwrap(harness.controller.engineWindow)
    harness.engine.holdClose(tab)
    let before = try SidebarStorageFormat.encode(harness.source.sidebar)

    XCTAssertFalse(harness.controller.windowShouldClose(window))

    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isClosing, true)
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: false))
    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(harness.controller.engineWindow, engineWindow)
    XCTAssertEqual(harness.controller.currentTab, tab)

    XCTAssertFalse(harness.controller.windowShouldClose(window))
    XCTAssertTrue(window.isVisible)
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: true))
    XCTAssertFalse(window.isVisible, "closed on .windowClosed")
    XCTAssertNil(harness.controller.engineWindow)
    XCTAssertTrue(harness.engine.windowIDs.isEmpty)
    XCTAssertEqual(try SidebarStorageFormat.encode(harness.source.sidebar), before)
    XCTAssertTrue(harness.archived.isEmpty)
  }
}

// MARK: - Extensions control

@MainActor
final class ExtensionsControlTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testTheControlListsTheWindowsActionsAndRunsOneAnchoredToItself() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let button = try XCTUnwrap(harness.controller.extensionsButton)
    XCTAssertTrue(button.isDescendant(of: harness.controller.sidebarController.view))
    XCTAssertFalse(button.isEnabled, "no actions yet")
    let window = try XCTUnwrap(harness.controller.engineWindow)

    harness.engine.setExtensionActions([ExtensionAction(id: "a", name: "Alpha"),
                                        ExtensionAction(id: "b", name: "Beta", isEnabled: false)], in: window)

    XCTAssertTrue(button.isEnabled)
    let menu = button.makeMenu()
    XCTAssertEqual(menu.items.map(\.title), ["Alpha", "Beta"])
    XCTAssertEqual(menu.items.map(\.isEnabled), [true, false])
    button.runItem(menu.items[0])
    let ran = harness.engine.ranExtensionActions
    XCTAssertEqual(ran.map(\.id), ["a"])
    XCTAssertEqual(ran.map(\.window), [window])
    XCTAssertTrue(ran.first?.anchor === button)
  }

  func testTheControlIsLaidOutLeftOfNewTab() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let view = harness.controller.sidebarController.view
    view.layoutSubtreeIfNeeded()
    let button = try XCTUnwrap(harness.controller.extensionsButton)
    XCTAssertEqual(button.frame.maxX, view.newTabButton.frame.minX)
    XCTAssertLessThanOrEqual(view.spaceDots.frame.maxX, button.frame.minX)
  }

  /// An engine without extensions (FakeEngine) shows no control.
  func testNoControlWithoutEngineExtensions() throws {
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let controller = ShellWindowController(engine: PlainEngine(), sidebar: source)
    XCTAssertNil(controller.extensionsButton)
    XCTAssertNil(controller.sidebarController.view.extensionsButton)
  }
}

// MARK: - Fixtures

/// A Space with one pinned tab, three Today tabs, a two-pane Today split, and one Favorite.
struct EngineWorld {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  var sidebar = SidebarModel.Sidebar()
  var space: UUID
  var pinned: UUID
  var today: [UUID]
  var split: UUID
  var panes: [UUID]

  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  static func make() throws -> EngineWorld {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: url("p"), title: "Pinned", in: .pinned(space))
    let today = try (0..<3).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    _ = try sidebar.addTab(url: url("f"), title: "Fav", in: .favorites(profile: "default"))
    return EngineWorld(sidebar: sidebar, space: space, pinned: pinned, today: today, split: split, panes: panes)
  }
}

/// One shell window over a model source and an `InMemoryEngine`; archives go to the model like the app's
/// ArchiveCoordinator, and hidden tabs are recorded.
@MainActor
final class EngineHarnessWindow {
  let source: ModelSidebarSource
  let engine: InMemoryEngine
  let controller: ShellWindowController
  var archived: [[UUID]] = []
  var hidden: [UUID] = []

  init(_ sidebar: SidebarModel.Sidebar, engine: InMemoryEngine = InMemoryEngine()) {
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    self.source = source
    self.engine = engine
    controller = ShellWindowController(engine: engine, sidebar: source)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.onArchive = { [unowned self] ids in
      archived.append(ids)
      source.archive(ids, reason: .manual, at: EngineWorld.now)
    }
    controller.onTabHidden = { [unowned self] id in hidden.append(id) }
  }
}

/// An engine without `EngineExtensions`, like FakeEngine, without WebKit.
@MainActor
private final class PlainEngine: EngineClient {
  let inner = InMemoryEngine()
  var tabIDs: [TabID] { inner.tabIDs }
  func createTab(url: URL?) -> TabID { inner.createTab(url: url) }
  func createTab(url: URL?, in window: EngineWindowID) -> TabID { inner.createTab(url: url, in: window) }
  func closeTab(_ id: TabID) { inner.closeTab(id) }
  func closeTab(_ id: TabID, mode: CloseMode) { inner.closeTab(id, mode: mode) }
  func navigate(_ id: TabID, to url: URL) { inner.navigate(id, to: url) }
  func reload(_ id: TabID) { inner.reload(id) }
  func goBack(_ id: TabID) { inner.goBack(id) }
  func goForward(_ id: TabID) { inner.goForward(id) }
  func goToHistory(_ id: TabID, offset: Int) { inner.goToHistory(id, offset: offset) }
  func history(of id: TabID) -> TabHistory? { inner.history(of: id) }
  func duplicateTab(_ id: TabID) -> TabID? { inner.duplicateTab(id) }
  func snapshot(of id: TabID) -> TabSnapshot? { inner.snapshot(of: id) }
  func contentView(for id: TabID) -> NSView? { inner.contentView(for: id) }
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { inner.observe(handler) }
  var windowIDs: [EngineWindowID] { inner.windowIDs }
  func createWindow(host: any EngineWindowHosting) -> EngineWindowID { inner.createWindow(host: host) }
  func closeWindow(_ id: EngineWindowID) { inner.closeWindow(id) }
  func activateTab(_ id: TabID) { inner.activateTab(id) }
  func activeTab(in window: EngineWindowID) -> TabID? { inner.activeTab(in: window) }
  func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    inner.observeWindows(handler)
  }
  func observe(window: EngineWindowID, _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    inner.observe(window: window, handler)
  }
}
