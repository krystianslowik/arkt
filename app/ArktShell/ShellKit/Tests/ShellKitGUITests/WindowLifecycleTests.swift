import AppKit
import Carbon.HIToolbox
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #115 (preview scope): New Window, Close Window, last-window close, full screen and auto-archive across windows,
/// on InMemoryEngine and the real main menu. Incognito, Blank Window and the quit warning are not offered.
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
    return Fixture(set: set, engine: engine, work: work, other: other, workToday: workToday, otherToday: otherToday)
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

  // MARK: Not offered in the preview

  func testIncognitoAndBlankWindowAreNotInAnyMenu() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    var titles: [String] = []
    func collect(_ menu: NSMenu) {
      for item in menu.items {
        titles.append(item.title)
        if let submenu = item.submenu { collect(submenu) }
      }
    }
    collect(menu)
    XCTAssertTrue(titles.contains("New Window"), "the menu was built")
    for title in titles {
      let lowered = title.lowercased()
      XCTAssertFalse(lowered.contains("incognito") || lowered.contains("private window") || lowered.contains("blank window"),
                     "\(title) is cut for the preview")
    }
    // Cmd-Shift-N (Incognito) and Ctrl-Cmd-N (Blank Window) are bound to nothing.
    var bound: [(String, NSEvent.ModifierFlags)] = []
    func collectKeys(_ menu: NSMenu) {
      for item in menu.items {
        if !item.keyEquivalent.isEmpty { bound.append((item.keyEquivalent.lowercased(), item.keyEquivalentModifierMask)) }
        if let submenu = item.submenu { collectKeys(submenu) }
      }
    }
    collectKeys(menu)
    XCTAssertFalse(bound.contains { $0.0 == "n" && $0.1 == [.command, .shift] })
    XCTAssertFalse(bound.contains { $0.0 == "n" && $0.1 == [.command, .control] })
  }
}
