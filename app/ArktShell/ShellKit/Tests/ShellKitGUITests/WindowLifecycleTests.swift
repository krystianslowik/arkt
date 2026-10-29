import AppKit
import Carbon.HIToolbox
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #115 and #487: New Window, Close Window, last-window close, full screen and auto-archive across windows,
/// plus Blank Window (Ctrl-Cmd-N) and Incognito (Cmd-Shift-N), on InMemoryEngine and the real main menu.
@MainActor
final class WindowLifecycleTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private var savedMenu: NSMenu?

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedMenu = NSApp.mainMenu
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
    NSApp.mainMenu = savedMenu
  }

  /// Two Spaces, each with Today tabs, on one sidebar shared by every window.
  private struct Fixture {
    let set: ShellWindowSet
    let source: ModelSidebarSource
    let engine: InMemoryEngine
    let work: SpaceID
    let other: SpaceID
    let workToday: [NodeID]
    let otherToday: [NodeID]
  }

  private func makeFixture() throws -> Fixture {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let other = sidebar.addSpace(title: "Other")
    let workToday = try (0..<2).map {
      try sidebar.addTab(url: EngineWorld.url("w\($0)"), title: "W\($0)", in: .today(work))
    }
    let otherToday = try (0..<2).map {
      try sidebar.addTab(url: EngineWorld.url("o\($0)"), title: "O\($0)", in: .today(other))
    }
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return Fixture(set: set, source: source, engine: engine, work: work, other: other,
                   workToday: workToday, otherToday: otherToday)
  }

  private func key(_ keyCode: Int, _ flags: CGEventFlags) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    event.flags = flags
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  // MARK: New Window (Cmd-N, KB-005, BH-170)

  /// Cmd-N from a window showing the second Space opens a window on that Space, with that Space's Today tabs in its
  /// sidebar; the page comes with the first tab the user picks (decision 4).
  func testNewWindowOpensOnTheSpaceTheOpenerShows() throws {
    let f = try makeFixture()
    let first = f.set.openWindow()
    first.sidebarController.showSpace(f.other)
    XCTAssertTrue(f.set.primary === first)

    XCTAssertTrue(first.engineHost.perform(PendingEngineCommands.newWindow, disposition: .currentTab))

    XCTAssertEqual(f.set.controllers.count, 2)
    let second = try XCTUnwrap(f.set.controllers.last)
    XCTAssertEqual(second.currentSpace, f.other, "the new window opens on the Space Cmd-N was pressed in")
    XCTAssertNil(second.currentTab, "no page until the user picks one")
    XCTAssertNotEqual(second.currentSpace, f.work)
    second.activate(node: f.otherToday[1])
    XCTAssertEqual(second.currentNode, f.otherToday[1], "the Space's Today tabs are shared with the new window")
    XCTAssertEqual(second.currentSpace, f.other)
  }

  /// The menu route (`AppCommands.newWindow`) opens through the same call.
  func testOpeningAWindowWithoutAPageUsesTheMostRecentlyMainWindowsSpace() throws {
    let f = try makeFixture()
    let first = f.set.openWindow()
    let second = f.set.openWindow(opensFirstTab: false)
    second.sidebarController.showSpace(f.other)
    NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: second.window)   // runner is inactive
    XCTAssertTrue(f.set.primary === second)
    _ = first

    let third = f.set.openWindow(opensFirstTab: false)

    XCTAssertEqual(third.currentSpace, f.other)
  }

  // MARK: Close Window (Cmd-Shift-W, KB-009)

  /// The real main menu's Close Window item (Cmd-Shift-W) acts on the window it reaches; the other window stays. The
  /// runner is inactive, so the item's action goes to the window the responder chain would hand it to.
  func testCloseWindowClosesOnlyThatWindow() throws {
    let f = try makeFixture()
    let first = f.set.openWindow()
    let second = f.set.openWindow(opensFirstTab: false)
    let menu = MainMenu.make(commands: AppCommands()).menu
    let file = try XCTUnwrap(menu.items.first { $0.title == "File" }?.submenu)
    let item = try XCTUnwrap(file.items.first { $0.title == "Close Window" })
    XCTAssertEqual(item.keyEquivalent, "w")
    XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
    XCTAssertNil(item.target, "reaches the key window through the responder chain")
    let window = try XCTUnwrap(first.window)
    XCTAssertTrue(window.validateUserInterfaceItem(item), "enabled on the shell window")

    XCTAssertTrue(window.tryToPerform(try XCTUnwrap(item.action), with: item))

    XCTAssertTrue(first.isClosed)
    XCTAssertEqual(f.set.controllers.map(ObjectIdentifier.init), [ObjectIdentifier(second)])
    XCTAssertTrue(second.window?.isVisible ?? false, "the other window stays")
    XCTAssertFalse(second.isClosed)
  }

  // MARK: Last window (#241, #474)

  /// Closing the last window leaves nothing in the set, and Cmd-N (a new window with no opener) and a Dock reopen each
  /// bring a window back on the first Space.
  func testAfterTheLastWindowClosesNewWindowAndReopenBringOneBack() throws {
    let f = try makeFixture()
    let only = f.set.openWindow()
    only.window?.performClose(nil)
    XCTAssertTrue(f.set.controllers.isEmpty)
    XCTAssertNil(f.set.primary)

    let fresh = f.set.openWindow(opensFirstTab: false)
    XCTAssertTrue(fresh.window?.isVisible ?? false)
    XCTAssertEqual(f.set.controllers.count, 1)
    XCTAssertEqual(fresh.currentSpace, f.work)
    fresh.window?.performClose(nil)
    XCTAssertTrue(f.set.controllers.isEmpty)

    let reopened = f.set.reopen()
    XCTAssertTrue(reopened.window?.isVisible ?? false)
    XCTAssertEqual(f.set.controllers.count, 1)
    XCTAssertNotNil(reopened.currentTab, "a Dock reopen shows a page like a launch window")
  }

  // MARK: Full screen (KB-051)

  func testFullScreenEntersAndExitsWithTheSidebarAndCardLaidOut() throws {
    let f = try makeFixture()
    let controller = f.set.openWindow()
    let window = try XCTUnwrap(controller.window)
    window.makeKeyAndOrderFront(nil)
    let root = try XCTUnwrap(window.contentView as? ShellRootView)
    var entered = false
    var exited = false
    let center = NotificationCenter.default
    let observers = [
      center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in entered = true },
      center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in exited = true },
    ]
    defer { observers.forEach(center.removeObserver) }

    window.toggleFullScreen(nil)
    waitUntil("full screen is entered", timeout: 20) { entered }
    root.layoutSubtreeIfNeeded()
    XCTAssertTrue(window.styleMask.contains(.fullScreen))
    assertLaidOut(root, "in full screen")

    window.toggleFullScreen(nil)
    waitUntil("full screen is left", timeout: 20) { exited }
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(window.styleMask.contains(.fullScreen))
    assertLaidOut(root, "after leaving full screen")
  }

  private func assertLaidOut(_ root: ShellRootView, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
    let bounds = root.bounds
    let sidebar = root.sidebarContainer.frame
    let card = root.card.frame
    XCTAssertGreaterThan(sidebar.width, 0, "the sidebar has a width \(when)", file: file, line: line)
    XCTAssertEqual(sidebar.height, bounds.height, accuracy: 1, "the sidebar fills the height \(when)", file: file, line: line)
    XCTAssertGreaterThan(card.width, 100, "the card has a width \(when)", file: file, line: line)
    XCTAssertGreaterThan(card.height, 100, "the card has a height \(when)", file: file, line: line)
    XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(card), "the card is inside the window \(when)", file: file, line: line)
    XCTAssertGreaterThanOrEqual(card.minX, sidebar.maxX - 1, "the card sits right of the sidebar \(when)", file: file, line: line)
  }

  // MARK: Auto-archive across windows

  /// A tab shown only in the second window is exempt from auto-archive, and stays exempt after the first window
  /// closes; a tab shown in no window is not.
  func testAutoArchiveSkipsTabsShownInAnyWindow() throws {
    let f = try makeFixture()
    let first = f.set.openWindow(opensFirstTab: false)
    let second = f.set.openWindow(opensFirstTab: false)
    first.activate(node: f.workToday[0])
    second.activate(node: f.workToday[1])

    XCTAssertTrue(f.set.autoArchiveExempt.isSuperset(of: [f.workToday[0], f.workToday[1]]))
    XCTAssertFalse(f.set.autoArchiveExempt.contains(f.otherToday[0]))

    first.window?.close()
    XCTAssertTrue(f.set.autoArchiveExempt.contains(f.workToday[1]), "the surviving window's tab is still exempt")
    XCTAssertFalse(f.set.autoArchiveExempt.contains(f.workToday[0]), "a closed window shows nothing")
  }

  // MARK: Blank Window and Incognito (#487, BH-170, BH-174)

  /// Ctrl-Cmd-N (KB-006): a window whose sidebar has no items. The window it was opened beside keeps its Spaces,
  /// and the shared sidebar is unchanged. Cmd-N stays New Window.
  func testCtrlCmdNOpensABlankWindowWithNoSidebarItems() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let file = try XCTUnwrap(menu.items.first { $0.title == "File" }?.submenu)
    let blankItem = try XCTUnwrap(file.items.first { $0.title == "New Blank Window" })
    XCTAssertEqual(blankItem.action, #selector(AppCommands.newBlankWindow(_:)))
    XCTAssertEqual(blankItem.keyEquivalent, "n")
    XCTAssertEqual(blankItem.keyEquivalentModifierMask, [.command, .control])
    let newWindow = try XCTUnwrap(file.items.first { $0.title == "New Window" })
    XCTAssertEqual(newWindow.keyEquivalent, "n")
    XCTAssertEqual(newWindow.keyEquivalentModifierMask, .command)
    let event = try key(kVK_ANSI_N, [.maskCommand, .maskControl])
    XCTAssertTrue(ReservedKeys.arkt.matches(event))

    let f = try makeFixture()
    let first = f.set.openWindow()
    let before = f.source.sidebar
    let blank = f.set.openWindow(opensFirstTab: false)
    blank.makeBlank()

    XCTAssertEqual(blank.sidebarController.presentation, .blank)
    XCTAssertTrue(blank.sidebarController.spaces.isEmpty)
    XCTAssertNil(blank.sidebarController.currentPage)
    XCTAssertTrue(blank.sidebarController.view.favorites.isHidden)
    XCTAssertTrue(blank.sidebarController.view.spaceDots.isHidden)
    XCTAssertTrue(blank.sidebarController.view.incognitoLabel.isHidden)
    XCTAssertEqual(f.source.sidebar, before, "a blank window does not change the shared sidebar")
    XCTAssertEqual(first.sidebarController.spaces.count, 2, "the other window still shows its Spaces")
    XCTAssertFalse(visibleStrings(in: blank.sidebarController.view).contains { ["Work", "Other", "W0", "W1", "O0", "O1"].contains($0) })
  }

  /// Cmd-Shift-N (KB-007): the Incognito label is in the sidebar and nowhere else in the window, and a command-bar
  /// visit is absent from the shared sidebar. The same visit from a normal window is recorded.
  func testCmdShiftNOpensIncognitoAndDoesNotPersistTheVisit() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let file = try XCTUnwrap(menu.items.first { $0.title == "File" }?.submenu)
    let item = try XCTUnwrap(file.items.first { $0.title == "New Incognito Window" })
    XCTAssertEqual(item.action, #selector(AppCommands.newIncognitoWindow(_:)))
    XCTAssertEqual(item.keyEquivalent, "n")
    XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
    let event = try key(kVK_ANSI_N, [.maskCommand, .maskShift])
    XCTAssertTrue(ReservedKeys.arkt.matches(event))

    let f = try makeFixture()
    let normal = f.set.openWindow()
    let incognito = f.set.openWindow(opensFirstTab: false)
    incognito.makeIncognito()
    assertIncognitoLabelOnlyInTheSidebar(incognito)
    XCTAssertTrue(incognito.sidebarController.spaces.isEmpty)
    XCTAssertTrue(incognito.sidebarController.view.favorites.isHidden)

    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    incognito.commandBar.show(.newTab)
    incognito.commandBar.setQueryForTesting("secret-visit.example")
    incognito.commandBar.commit()
    XCTAssertEqual(saves, 0, "the visit does not schedule a sidebar save")
    XCTAssertEqual(f.source.sidebar, before)
    XCTAssertFalse(tabURLs(f.source.sidebar).contains { $0.contains("secret-visit.example") })
    XCTAssertTrue(incognito.sidebarController.spaces.isEmpty, "the visit does not fill the incognito sidebar")
    assertIncognitoLabelOnlyInTheSidebar(incognito)

    normal.commandBar.show(.newTab)
    normal.commandBar.setQueryForTesting("kept-visit.example")
    normal.commandBar.commit()
    XCTAssertGreaterThan(saves, 0)
    XCTAssertTrue(tabURLs(f.source.sidebar).contains { $0.contains("kept-visit.example") })
    XCTAssertFalse(tabURLs(f.source.sidebar).contains { $0.contains("secret-visit.example") })
  }

  private func tabURLs(_ sidebar: SidebarModel.Sidebar) -> [String] {
    sidebar.nodes.values.compactMap { node in
      if case .tab(let tab) = node.kind { tab.url.absoluteString } else { nil }
    }
  }

  private func assertIncognitoLabelOnlyInTheSidebar(_ controller: ShellWindowController,
                                                    file: StaticString = #filePath, line: UInt = #line) {
    let sidebar = controller.sidebarController.view
    let label = sidebar.incognitoLabel
    XCTAssertEqual(label.stringValue, "Incognito", file: file, line: line)
    XCTAssertFalse(label.isHidden, file: file, line: line)
    XCTAssertEqual(label.accessibilityIdentifier(), AXID.Incognito.label, file: file, line: line)
    XCTAssertTrue(label.isDescendant(of: sidebar), file: file, line: line)
    let window = controller.window
    XCTAssertFalse(window?.title.localizedCaseInsensitiveContains("incognito") ?? false, file: file, line: line)
    var hosts: [NSView] = []
    if let content = window?.contentView { hosts.append(content) }
    for child in window?.childWindows ?? [] {
      if let content = child.contentView { hosts.append(content) }
    }
    let fields = hosts.flatMap { textFields(in: $0) }.filter {
      $0.stringValue.localizedCaseInsensitiveContains("incognito") && isShown($0)
    }
    XCTAssertEqual(fields.map(\.stringValue), ["Incognito"], file: file, line: line)
    XCTAssertTrue(fields.allSatisfy { $0.isDescendant(of: sidebar) }, file: file, line: line)
  }

  private func visibleStrings(in view: NSView) -> [String] {
    guard isShown(view) else { return [] }
    var strings: [String] = []
    if let field = view as? NSTextField {
      let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { strings.append(text) }
    }
    for subview in view.subviews { strings.append(contentsOf: visibleStrings(in: subview)) }
    return strings
  }

  private func textFields(in view: NSView) -> [NSTextField] {
    var fields: [NSTextField] = []
    if let field = view as? NSTextField { fields.append(field) }
    for subview in view.subviews { fields.append(contentsOf: textFields(in: subview)) }
    return fields
  }

  private func isShown(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let view = current {
      if view.isHidden || view.alphaValue == 0 { return false }
      current = view.superview
    }
    return true
  }
}
