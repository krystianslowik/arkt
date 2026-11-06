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

  /// A blank or incognito window still navigates: a command-bar commit and Paste and Go load the page in that
  /// window, and neither writes the shared sidebar.
  func testBlankAndIncognitoWindowsLoadCommandBarAndPasteAndGoVisits() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar

    for incognito in [false, true] {
      let window = f.set.openWindow(opensFirstTab: false)
      if incognito { window.makeIncognito() } else { window.makeBlank() }
      XCTAssertNil(window.currentTab)

      window.commandBar.show(.newTab)
      window.commandBar.setQueryForTesting("private-visit.example")
      window.commandBar.commit()
      let first = try XCTUnwrap(window.currentTab, "the commit loads a page in this window")
      XCTAssertTrue(f.engine.snapshot(of: first)?.url?.absoluteString.contains("private-visit.example") ?? false)

      let pasted = EngineWorld.url("pasted-visit")
      let onPasteAndGo = try XCTUnwrap(window.sidebarController.onPasteAndGo)
      onPasteAndGo(pasted)
      let second = try XCTUnwrap(window.currentTab)
      XCTAssertEqual(second, first, "a second visit reuses the window's one page")
      XCTAssertEqual(f.engine.snapshot(of: second)?.url, pasted, "Paste and Go loads in this window")
      XCTAssertEqual(f.engine.tabIDs.filter { f.engine.snapshot(of: $0)?.window == window.engineWindow }.count, 1)

      XCTAssertEqual(saves, 0, "no visit schedules a sidebar save")
      XCTAssertEqual(f.source.sidebar, before, "no visit reaches the shared sidebar")
      XCTAssertTrue(window.sidebarController.spaces.isEmpty)
      XCTAssertTrue(tabURLs(f.source.sidebar).allSatisfy {
        !$0.contains("private-visit.example") && !$0.contains("pasted-visit")
      })
    }
  }

  /// The private page follows its engine tab: a redirect or link click updates the address bar, a page the engine
  /// closed clears the window and the next visit makes a new one, and closing the window closes the page.
  func testPrivatePageFollowsItsEngineTab() throws {
    let f = try makeFixture()
    let window = f.set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("private-visit.example")
    window.commandBar.commit()
    let first = try XCTUnwrap(window.currentTab)

    let redirected = EngineWorld.url("redirected")
    f.engine.navigate(first, to: redirected)
    XCTAssertEqual(window.urlBar.url, redirected, "the address bar follows the page")
    f.engine.navigate(first, to: EngineWorld.url("second-page"))
    f.engine.goBack(first)
    XCTAssertEqual(window.urlBar.url, redirected, "Back moves the address bar")

    f.engine.engineCloseTab(first)
    XCTAssertNil(window.privateTab)
    XCTAssertNil(window.currentTab, "a closed page clears the window")
    XCTAssertNil(window.urlBar.url)

    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("again.example")
    window.commandBar.commit()
    let again = try XCTUnwrap(window.currentTab, "the next visit makes a new page")
    XCTAssertNotEqual(again, first)
    XCTAssertEqual(window.privateTab, again)

    window.window?.performClose(nil)
    XCTAssertNil(window.privateTab, "closing the window leaves no private page behind")
    XCTAssertNil(f.engine.snapshot(of: again))
    XCTAssertTrue(f.engine.tabIDs.isEmpty)
  }

  /// #559: a tab the engine opens on its own in a blank or incognito window (a `target=_blank` link, `window.open`,
  /// `chrome.tabs.create`) becomes one of the window's private pages, not a Today row. A foreground one is shown, a
  /// background one waits, and closing the shown page shows the one before it. None of it schedules a sidebar save.
  func testEngineCreatedTabsInPrivateWindowsStayOutOfTheSharedSidebar() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar

    for incognito in [false, true] {
      let window = f.set.openWindow(opensFirstTab: false)
      if incognito { window.makeIncognito() } else { window.makeBlank() }
      window.commandBar.show(.newTab)
      window.commandBar.setQueryForTesting("private-visit.example")
      window.commandBar.commit()
      let opener = try XCTUnwrap(window.currentTab)
      let engineWindow = try XCTUnwrap(window.engineWindow)

      let popup = f.engine.engineCreateTab(url: EngineWorld.url("blank-target"), in: engineWindow, opener: opener)
      XCTAssertEqual(window.currentTab, popup, "a foreground target=_blank page is shown in this window")
      XCTAssertEqual(window.urlBar.url, EngineWorld.url("blank-target"))
      XCTAssertEqual(window.privateTabs, [opener, popup])
      XCTAssertNotNil(f.engine.snapshot(of: opener), "the opener stays open for the page that opened it")

      let background = f.engine.engineCreateTab(url: EngineWorld.url("background"), in: engineWindow,
                                                opener: popup, active: false)
      XCTAssertEqual(window.currentTab, popup, "a background page does not take the window")
      XCTAssertEqual(Set(window.privateTabs), [opener, popup, background])

      f.engine.engineActivate(background)
      XCTAssertEqual(window.currentTab, background, "an engine activation shows the page")
      XCTAssertEqual(window.urlBar.url, EngineWorld.url("background"))

      f.engine.engineCloseTab(background)
      XCTAssertEqual(window.currentTab, popup, "closing the shown page shows the one before it")
      XCTAssertEqual(f.engine.activeTab(in: engineWindow), popup, "the engine is told which page is shown")
      f.engine.engineCloseTab(popup)
      XCTAssertEqual(window.currentTab, opener)
      XCTAssertEqual(window.privateTabs, [opener])

      let pasted = EngineWorld.url("pasted-after-popup")
      try XCTUnwrap(window.sidebarController.onPasteAndGo)(pasted)
      XCTAssertEqual(window.currentTab, opener, "a later visit reuses the shown page")
      XCTAssertEqual(f.engine.snapshot(of: opener)?.url, pasted)

      XCTAssertEqual(saves, 0, "no engine-created tab schedules a sidebar save")
      XCTAssertEqual(f.source.sidebar, before, "no engine-created tab reaches the shared sidebar")
      XCTAssertTrue(window.sidebarController.spaces.isEmpty)

      window.window?.performClose(nil)
      XCTAssertTrue(window.privateTabs.isEmpty, "closing the window leaves no private page behind")
    }
    XCTAssertTrue(f.engine.tabIDs.isEmpty)
  }

  /// #559: when the shown private page closes, the window shows the page shown before it, not the engine's own pick
  /// (its next tab in the strip), and tells the engine.
  func testClosingAPrivatePageShowsThePageShownBeforeItOverTheEnginesPick() throws {
    let f = try makeFixture()
    let window = f.set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("private-visit.example")
    window.commandBar.commit()
    let opener = try XCTUnwrap(window.currentTab)
    let engineWindow = try XCTUnwrap(window.engineWindow)
    let popup = f.engine.engineCreateTab(url: EngineWorld.url("popup"), in: engineWindow, opener: opener)
    let background = f.engine.engineCreateTab(url: EngineWorld.url("background"), in: engineWindow,
                                              opener: popup, active: false)
    f.engine.engineActivate(background)
    f.engine.engineActivate(opener)
    XCTAssertEqual(window.privateTabs, [popup, background, opener])

    f.engine.engineCloseTab(opener)                       // the engine's pick is its next tab, `popup`
    XCTAssertEqual(window.currentTab, background, "the page shown before the closed one is shown")
    XCTAssertEqual(f.engine.activeTab(in: engineWindow), background, "the engine is told the shell's pick")
    XCTAssertEqual(window.urlBar.url, EngineWorld.url("background"))
    window.window?.performClose(nil)
  }

  /// #559: the user cancels a private window's close at a leave-site prompt. The window is not closing any more: a
  /// page the engine opens afterwards is adopted, and closing it shows the page before it.
  func testCancelledCloseOfAPrivateWindowKeepsAdoptingEngineTabs() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    let window = f.set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("private-visit.example")
    window.commandBar.commit()
    let page = try XCTUnwrap(window.currentTab)
    let engineWindow = try XCTUnwrap(window.engineWindow)

    f.engine.holdClose(page)
    window.window?.performClose(nil)
    XCTAssertTrue(window.isWindowCloseRequested, "the close waits on the leave-site prompt")
    XCTAssertTrue(f.engine.answerDialog(page, accept: false))
    XCTAssertFalse(window.isWindowCloseRequested, "staying on the page cancels the window close")
    XCTAssertEqual(window.currentTab, page)

    let popup = f.engine.engineCreateTab(url: EngineWorld.url("after-cancel"), in: engineWindow, opener: page)
    XCTAssertNotNil(f.engine.snapshot(of: popup), "the page is adopted, not closed on creation")
    XCTAssertEqual(window.currentTab, popup)
    f.engine.engineCloseTab(popup)
    XCTAssertEqual(window.currentTab, page, "closing it shows the page before it")
    XCTAssertEqual(saves, 0)
    XCTAssertEqual(f.source.sidebar, before)
  }

  /// #559: Paste URL as New Tab (Cmd-Opt-V) in a blank or incognito window opens a new private page, not a Today row.
  func testPasteURLAsNewTabInAPrivateWindowOpensAPrivatePage() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    let board = NSPasteboard(name: .init("WindowLifecycleTests.paste"))
    board.clearContents()
    board.setString("https://example.com/pasted-new-tab", forType: .string)

    for incognito in [false, true] {
      let window = f.set.openWindow(opensFirstTab: false)
      if incognito { window.makeIncognito() } else { window.makeBlank() }
      window.pasteboard = board
      window.pasteURLAsNewTab(nil)
      let first = try XCTUnwrap(window.currentTab, "the pasted URL opens in this window")
      XCTAssertEqual(f.engine.snapshot(of: first)?.url?.absoluteString, "https://example.com/pasted-new-tab")

      window.pasteURLAsNewTab(nil)
      let second = try XCTUnwrap(window.currentTab)
      XCTAssertNotEqual(second, first, "as a new page")
      XCTAssertEqual(window.privateTabs, [first, second])

      XCTAssertEqual(saves, 0, "no paste schedules a sidebar save")
      XCTAssertEqual(f.source.sidebar, before, "no paste reaches the shared sidebar")
      XCTAssertTrue(window.sidebarController.spaces.isEmpty)
      window.window?.performClose(nil)
    }
  }

  /// #669: a window the engine opens for a page of a blank or incognito window (a `window.open` popup, which would
  /// go to Little Arkt, a `window.open` without window features, an extension's `chrome.windows.create`) is a private
  /// window of the same kind. Its pages, the first one and any the engine opens there later, never reach the shared
  /// sidebar or schedule a save, and it never takes over an open normal window.
  func testEngineWindowsOpenedForAPrivatePageStayPrivate() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    let spare = f.set.openWindow(opensFirstTab: false)       // a normal window with no engine window yet

    for incognito in [false, true] {
      let opener = f.set.openWindow(opensFirstTab: false)
      if incognito { opener.makeIncognito() } else { opener.makeBlank() }
      opener.commandBar.show(.newTab)
      opener.commandBar.setQueryForTesting("private-opener.example")
      opener.commandBar.commit()
      let openerWindow = try XCTUnwrap(opener.engineWindow)

      let requests: [(String, EngineWindowRequest)] = [
        ("popup", EngineWindowRequest(kind: .page, openerWindow: openerWindow,
                                      bounds: CGRect(x: 200, y: 200, width: 480, height: 360),
                                      profile: EngineProfileID("default"), initialURL: EngineWorld.url("popup"),
                                      isPopup: true)),
        ("new window", EngineWindowRequest(kind: .reopen, openerWindow: openerWindow,
                                           profile: EngineProfileID("default"),
                                           initialURL: EngineWorld.url("new-window"))),
        ("extension", EngineWindowRequest(kind: .extension, openerWindow: openerWindow,
                                          profile: EngineProfileID("default"),
                                          initialURL: EngineWorld.url("extension"))),
      ]
      for (name, request) in requests {
        let id = try XCTUnwrap(f.engine.openEngineWindow(request), name)
        XCTAssertTrue(f.set.littleArkts.isEmpty, "\(name): not a Little Arkt window, whose Open in writes a row")
        XCTAssertNil(spare.engineWindow, "\(name): an open normal window is not taken over")
        let window = try XCTUnwrap(f.set.controllers.first { $0.engineWindow == id }, name)
        XCTAssertTrue(window.isPrivateWindow, name)
        XCTAssertEqual(window.sidebarController.presentation, opener.sidebarController.presentation,
                       "\(name): the same kind of window as its opener")
        XCTAssertFalse(window.savesSession, name)
        let page = try XCTUnwrap(window.currentTab, "\(name): the window shows its page")
        XCTAssertEqual(window.privateTabs, [page], name)
        XCTAssertEqual(f.engine.snapshot(of: page)?.url, request.initialURL, name)

        let later = f.engine.engineCreateTab(url: EngineWorld.url("later"), in: id, opener: page)
        XCTAssertEqual(window.privateTabs, [page, later], "\(name): a later engine tab is a private page too")
        XCTAssertTrue(window.sidebarController.spaces.isEmpty, name)
        XCTAssertEqual(saves, 0, "\(name): no save is scheduled")
        XCTAssertEqual(f.source.sidebar, before, "\(name): the shared sidebar is unchanged")
        window.window?.performClose(nil)
      }
      opener.window?.performClose(nil)
    }
    XCTAssertEqual(saves, 0)
    XCTAssertEqual(f.source.sidebar, before)
  }

  /// #669: a window the engine marks as off the record is an incognito window even with no opener, and never takes
  /// over saving the session (a Dock reopen would).
  func testOffTheRecordEngineWindowIsAnIncognitoWindow() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    let request = EngineWindowRequest(kind: .reopen, profile: EngineProfileID("default"),
                                      initialURL: EngineWorld.url("off-the-record"), isOffTheRecord: true)
    let id = try XCTUnwrap(f.engine.openEngineWindow(request))
    let window = try XCTUnwrap(f.set.controllers.first { $0.engineWindow == id })
    XCTAssertTrue(window.isPrivateWindow)
    XCTAssertEqual(window.sidebarController.presentation, .incognito)
    XCTAssertFalse(window.savesSession, "an off-the-record window never saves the session")
    let page = try XCTUnwrap(window.currentTab)
    XCTAssertEqual(window.privateTabs, [page])
    XCTAssertEqual(saves, 0)
    XCTAssertEqual(f.source.sidebar, before)
    window.window?.performClose(nil)
  }

  /// #669: the same requests from a normal window keep their normal routing: a popup goes to Little Arkt and an
  /// extension window is a normal window.
  func testEngineWindowsOpenedForANormalPageAreNotPrivate() throws {
    let f = try makeFixture()
    let opener = f.set.openWindow()
    let openerWindow = try XCTUnwrap(opener.engineWindow)
    let popup = try XCTUnwrap(f.engine.openEngineWindow(EngineWindowRequest(
      kind: .page, openerWindow: openerWindow, profile: EngineProfileID("default"),
      initialURL: EngineWorld.url("popup"), isPopup: true)))
    XCTAssertNotNil(f.set.littleArkts.first { $0.engineWindow == popup })
    let id = try XCTUnwrap(f.engine.openEngineWindow(EngineWindowRequest(
      kind: .extension, openerWindow: openerWindow, profile: EngineProfileID("default"),
      initialURL: EngineWorld.url("extension"))))
    let window = try XCTUnwrap(f.set.controllers.first { $0.engineWindow == id })
    XCTAssertFalse(window.isPrivateWindow)
    XCTAssertEqual(window.sidebarController.presentation, .standard)
    for little in f.set.littleArkts { little.window.orderOut(nil) }
  }

  // MARK: Opt-Cmd-click from a private page (#710)

  /// #710: Opt-Cmd-click on a link in a blank or incognito window opens the link in a private window of the same
  /// kind, as #669 does for the engine's popups, never in Little Arkt (its Open in and its Space chooser use the
  /// shared sidebar, and closing it writes an Archive entry). Nothing reaches the shared sidebar, the Archive or
  /// session saving, before or after the new window closes.
  func testOptionCommandClickInAPrivateWindowOpensAPrivateWindow() async throws {
    let f = try makeFixture()
    var saves = 0
    var archived: [NodeID] = []
    var littleArchived = 0
    f.source.onDidChange = { _ in saves += 1 }
    f.set.configure = { controller in controller.onArchive = { archived += $0 } }
    f.set.onLittleArktArchive = { _ in
      littleArchived += 1
      return UUID()
    }
    let before = f.source.sidebar
    let link = EngineWorld.url("linked")

    for incognito in [false, true] {
      let opener = f.set.openWindow(opensFirstTab: false)
      if incognito { opener.makeIncognito() } else { opener.makeBlank() }
      opener.commandBar.show(.newTab)
      opener.commandBar.setQueryForTesting("private-opener.example")
      opener.commandBar.commit()
      let page = try XCTUnwrap(opener.currentTab)
      let pageURL = f.engine.snapshot(of: page)?.url
      let name = incognito ? "incognito" : "blank"

      let decision = f.engine.simulateLinkActivation(in: page, url: link, modifiers: [.command, .option],
                                                     disposition: .newBackgroundTab)

      XCTAssertEqual(decision, .cancel, "\(name): the engine does not open the link itself")
      await until("\(name): a window shows the link") {
        !f.set.littleArkts.isEmpty || f.set.controllers.contains { $0 !== opener && $0.currentTab != nil }
      }
      XCTAssertTrue(f.set.littleArkts.isEmpty, "\(name): not a Little Arkt window")
      XCTAssertEqual(f.set.controllers.count, 2, name)
      let window = try XCTUnwrap(f.set.controllers.first { $0 !== opener }, name)
      XCTAssertTrue(window.isPrivateWindow, name)
      XCTAssertEqual(window.sidebarController.presentation, opener.sidebarController.presentation,
                     "\(name): the same kind of window as its opener")
      XCTAssertFalse(window.savesSession, name)
      let shown = try XCTUnwrap(window.currentTab, name)
      XCTAssertEqual(window.privateTabs, [shown], name)
      XCTAssertEqual(f.engine.snapshot(of: shown)?.url, link, name)
      XCTAssertEqual(opener.currentTab, page, "\(name): the source page stays where it was")
      XCTAssertEqual(f.engine.snapshot(of: page)?.url, pageURL, "\(name): the source page did not navigate")
      XCTAssertTrue(window.sidebarController.spaces.isEmpty, name)
      XCTAssertEqual(saves, 0, "\(name): no save is scheduled")
      XCTAssertEqual(f.source.sidebar, before, "\(name): the shared sidebar is unchanged")

      window.window?.performClose(nil)
      opener.window?.performClose(nil)
      for little in f.set.littleArkts { little.window.performClose(nil) }
      XCTAssertTrue(archived.isEmpty, "\(name): closing it archives nothing")
      XCTAssertEqual(littleArchived, 0, "\(name): no Little Arkt Archive entry")
    }
    XCTAssertEqual(saves, 0)
    XCTAssertEqual(f.source.sidebar, before)
  }

  /// #710 control: in a normal window, Opt-Cmd-click on a link still opens it in a Little Arkt window, and no new
  /// browser window.
  func testOptionCommandClickInANormalWindowStillOpensLittleArkt() async throws {
    let f = try makeFixture()
    let opener = f.set.openWindow()
    let page = try XCTUnwrap(opener.currentTab)
    let link = EngineWorld.url("linked")

    let decision = f.engine.simulateLinkActivation(in: page, url: link, modifiers: [.command, .option],
                                                   disposition: .newBackgroundTab)

    XCTAssertEqual(decision, .cancel)
    await until("a window shows the link") {
      !f.set.littleArkts.isEmpty || f.set.controllers.count > 1
    }
    XCTAssertEqual(f.set.littleArkts.count, 1)
    let little = try XCTUnwrap(f.set.littleArkts.first)
    let shown = try XCTUnwrap(little.shownTab)
    XCTAssertEqual(f.engine.snapshot(of: shown)?.url, link)
    XCTAssertEqual(f.set.controllers.count, 1, "no new browser window")
    XCTAssertEqual(opener.currentTab, page)
    for little in f.set.littleArkts { little.window.orderOut(nil) }
  }

  /// Takes main-actor turns until `condition` holds; bounded, no clock. The Opt-Cmd-click opens its window one
  /// main-queue hop after the engine's decision.
  private func until(_ what: String, turns: Int = 5000, file: StaticString = #filePath, line: UInt = #line,
                     _ condition: () -> Bool) async {
    for _ in 0..<turns {
      if condition() { return }
      await Task.yield()
    }
    XCTFail("never reached: \(what)", file: file, line: line)
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
