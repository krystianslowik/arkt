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
    harness.hidden = []

    XCTAssertFalse(harness.controller.windowShouldClose(window))
    XCTAssertTrue(harness.hidden.isEmpty, "nothing is stamped while the engine has not answered")

    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isClosing, true)
    XCTAssertTrue(harness.controller.sidebarController.closingNodes.contains(world.today[0]))
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: false))
    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(harness.controller.engineWindow, engineWindow)
    XCTAssertEqual(harness.controller.currentTab, tab)
    XCTAssertFalse(harness.controller.sidebarController.closingNodes.contains(world.today[0]))
    XCTAssertTrue(harness.hidden.isEmpty, "a cancelled close stamps nothing")

    XCTAssertFalse(harness.controller.windowShouldClose(window))
    XCTAssertTrue(window.isVisible)
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: true))
    XCTAssertEqual(harness.hidden, [world.today[0]], "the shown tab is stamped once, before its page closes")
    XCTAssertFalse(window.isVisible, "closed on .windowClosed")
    XCTAssertNil(harness.controller.engineWindow)
    XCTAssertTrue(harness.engine.windowIDs.isEmpty)
    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertNotNil(harness.source.node(world.today[0]))
  }

  /// PR #274 review: a close-button close the user cancels at the leave-site prompt leaves the stored sidebar
  /// byte-identical (no `lastActiveAt` stamp for tabs that never stopped being visible).
  func testACancelledWindowCloseLeavesTheStoredSidebarByteIdentical() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)
    harness.controller.activate(node: world.panes[0])
    let pane = try XCTUnwrap(harness.controller.currentTab)
    harness.engine.holdClose(pane)
    harness.hidden = []
    let before = try SidebarStorageFormat.encode(harness.source.sidebar)

    XCTAssertFalse(harness.controller.windowShouldClose(window))
    XCTAssertTrue(harness.engine.answerDialog(pane, accept: false))

    XCTAssertEqual(try SidebarStorageFormat.encode(harness.source.sidebar), before)
    XCTAssertTrue(harness.hidden.isEmpty)
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes), "both panes are still shown")
  }

  /// Without a prompt the close goes through at once: every shown tab, both panes of a shown split, is stamped once,
  /// before the pages close, and nothing else changes.
  func testAnUnheldWindowCloseStampsTheShownTabsOnce() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.panes[1])
    harness.hidden = []
    var visibleWhenStamped: [Set<UUID>] = []
    let stamp = harness.controller.onTabHidden
    harness.controller.onTabHidden = { [weak controller = harness.controller] id in
      visibleWhenStamped.append(controller?.visibleNodes ?? [])
      stamp?(id)
    }

    XCTAssertFalse(harness.controller.windowShouldClose(window))

    XCTAssertEqual(Set(harness.hidden), Set(world.panes))
    XCTAssertEqual(harness.hidden.count, 2)
    XCTAssertEqual(visibleWhenStamped, [Set(world.panes), Set(world.panes)], "stamped before any page closed")
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(harness.archived.isEmpty)
  }

  /// A tab the engine opens while the window's close is held gets no row: the window is going away.
  func testAnEngineTabOpenedWhileTheWindowCloseIsHeldGetsNoRow() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    harness.engine.holdClose(tab)
    harness.hidden = []
    XCTAssertFalse(harness.controller.windowShouldClose(window))
    let before = try SidebarStorageFormat.encode(harness.source.sidebar)

    let popup = harness.engine.engineCreateTab(url: EngineWorld.url("popup"),
                                               in: try XCTUnwrap(harness.controller.engineWindow), active: true)

    XCTAssertNil(harness.engine.snapshot(of: popup), "closed without a row")
    XCTAssertEqual(try SidebarStorageFormat.encode(harness.source.sidebar), before)
    let today = harness.source.children(of: .today(world.space))
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: true))
    XCTAssertEqual(harness.source.children(of: .today(world.space)), today, "only the shown tab's stamp, no row")
    XCTAssertEqual(harness.hidden, [world.today[0]])
  }
}

// MARK: - Part B: tabs by window, close reason and activation

/// W3-7 part B: engine tabs become Today rows of their own window, activation goes both ways, and closes follow
/// their reason (Decision 12) and held prompts (Decision 11).
@MainActor
final class EngineTabRoutingTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: Engine-created tabs

  func testAnEngineTabBecomesATodayTabOnlyInItsOwnWindowAndIsSelectedWhenActive() throws {
    let engine = InMemoryEngine()
    let worldA = try EngineWorld.make()
    let worldB = try EngineWorld.make()
    let first = EngineHarnessWindow(worldA.sidebar, engine: engine)
    let second = EngineHarnessWindow(worldB.sidebar, engine: engine)
    let todayB = second.source.children(of: .today(worldB.space))
    let secondCurrent = second.controller.currentTab
    let url = EngineWorld.url("popup")

    let tab = engine.engineCreateTab(url: url, in: try XCTUnwrap(first.controller.engineWindow), active: true)

    let rows = first.source.children(of: .today(worldA.space))
    let node = try XCTUnwrap(rows.first { first.controller.engineTab(of: $0) == tab })
    guard case .tab(_, let rowURL, _)? = first.source.node(node) else { return XCTFail("no tab row") }
    XCTAssertEqual(rowURL, url)
    XCTAssertEqual(first.controller.currentTab, tab, "an active engine tab is selected")
    XCTAssertEqual(first.controller.rowState(for: node), .current)
    XCTAssertEqual(second.source.children(of: .today(worldB.space)), todayB, "no row in the other window")
    XCTAssertEqual(second.controller.currentTab, secondCurrent)
  }

  func testABackgroundEngineTabGetsARowButStaysInTheBackground() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let current = harness.controller.currentTab
    let countBefore = harness.source.children(of: .today(world.space)).count

    let tab = harness.engine.engineCreateTab(url: EngineWorld.url("bg"), in: try XCTUnwrap(harness.controller.engineWindow),
                                             active: false)

    XCTAssertEqual(harness.source.children(of: .today(world.space)).count, countBefore + 1)
    XCTAssertNotNil(harness.controller.nodeByTab[tab])
    XCTAssertEqual(harness.controller.currentTab, current)
  }

  func testAnEngineActivationSelectsItsRow() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.today[1])
    let firstTab = try XCTUnwrap(harness.controller.engineTab(of: world.today[0]))

    harness.engine.engineActivate(firstTab)

    XCTAssertEqual(harness.controller.currentNode, world.today[0])
    XCTAssertEqual(harness.controller.rowState(for: world.today[0]), .current)
  }

  /// The shell picks the successor after Cmd-W; the engine's own pick is answered with the shell's tab.
  func testTheEnginesPickAfterAClosedTabIsNotFollowed() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let window = try XCTUnwrap(harness.controller.engineWindow)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.controller.currentNode, world.today[2], "the sibling below, as before")
    XCTAssertEqual(harness.engine.activeTab(in: window), harness.controller.currentTab)
  }

  func testTheEnginesActiveTabFollowsTheFocusedPane() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let window = try XCTUnwrap(harness.controller.engineWindow)
    harness.controller.activate(node: world.panes[0])
    XCTAssertEqual(harness.engine.activeTab(in: window), harness.controller.engineTab(of: world.panes[0]))

    harness.controller.focusPane(at: 1)

    XCTAssertEqual(harness.controller.currentNode, world.panes[1])
    XCTAssertEqual(harness.engine.activeTab(in: window), harness.controller.engineTab(of: world.panes[1]))
    harness.controller.activate(node: world.today[0])
    XCTAssertEqual(harness.engine.activeTab(in: window), harness.controller.engineTab(of: world.today[0]))
  }

  /// When the engine's pick after a close is the shell's successor, no stray event follows; a later engine
  /// activation (an extension's `chrome.tabs.update`) is followed again.
  func testAnEngineActivationIsFollowedAfterAgreeingSuccessors() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    for node in world.today { harness.controller.activate(node: node) }
    harness.controller.activate(node: world.today[1])
    let held = try XCTUnwrap(harness.controller.currentTab)
    let first = try XCTUnwrap(harness.controller.engineTab(of: world.today[0]))
    harness.engine.holdClose(held)
    harness.controller.closeTab(nil)
    XCTAssertTrue(harness.engine.answerDialog(held, accept: true))
    XCTAssertEqual(harness.controller.currentNode, world.today[2])

    let lapsed = expectation(description: "reactivation grace lapsed")
    DispatchQueue.main.asyncAfter(deadline: .now() + ShellWindowController.reactivationGrace + 0.1) {
      lapsed.fulfill()
    }
    wait(for: [lapsed], timeout: ShellWindowController.reactivationGrace + 2)
    harness.engine.engineActivate(first)

    XCTAssertEqual(harness.controller.currentNode, world.today[0])
  }

  // MARK: Close reasons

  func testAnExtensionCloseRemovesATodayRowOnce() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.controller.currentTab)

    harness.engine.engineCloseTab(tab, reason: .extension)

    XCTAssertEqual(harness.archived, [[world.today[0]]])
    XCTAssertNil(harness.source.node(world.today[0]))
    XCTAssertEqual(harness.controller.currentNode, world.today[1], "the sibling below becomes current")
    XCTAssertTrue(harness.engine.tabIDs.allSatisfy { harness.controller.nodeByTab[$0] != nil })
  }

  func testAPageCloseOfAPinnedTabKeepsItsRow() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let tab = try XCTUnwrap(harness.controller.currentTab)

    harness.engine.engineCloseTab(tab, reason: .page)

    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertNotNil(harness.source.node(world.pinned))
    XCTAssertNil(harness.controller.engineTab(of: world.pinned))
  }

  /// The engine closing the window (`chrome.windows.remove`, the close button after its stamp) only unloads: the
  /// stored sidebar is byte-identical, with the app's `markInactive` wiring in place.
  func testAWindowCloseLeavesTheStoredSidebarByteIdentical() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.controller.activate(node: world.today[2])
    harness.engine.engineCreateTab(url: EngineWorld.url("x"), in: try XCTUnwrap(harness.controller.engineWindow),
                                   active: false)
    let before = try SidebarStorageFormat.encode(harness.source.sidebar)
    harness.hidden = []

    harness.engine.closeWindow(try XCTUnwrap(harness.controller.engineWindow))

    XCTAssertEqual(try SidebarStorageFormat.encode(harness.source.sidebar), before)
    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertTrue(harness.hidden.isEmpty)
    XCTAssertNil(harness.controller.currentTab)
    XCTAssertTrue(harness.controller.sidebarController.loadedNodes.isEmpty)
    XCTAssertTrue(harness.engine.tabIDs.isEmpty, "nothing reopened while the window closed")
  }

  /// Quit only unloads, and stamps nothing (`prepareForTermination` did that before the closes).
  func testAnAppTerminatingCloseLeavesTheStoredSidebarByteIdentical() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    harness.controller.activate(node: world.today[0])
    let before = try SidebarStorageFormat.encode(harness.source.sidebar)
    harness.hidden = []

    for tab in harness.engine.tabIDs { harness.engine.engineCloseTab(tab, reason: .appTerminating) }

    XCTAssertEqual(try SidebarStorageFormat.encode(harness.source.sidebar), before)
    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertTrue(harness.hidden.isEmpty)
    XCTAssertNil(harness.controller.currentTab)
    XCTAssertTrue(harness.engine.tabIDs.isEmpty, "nothing reopened while quitting")
  }

  // MARK: Held closes (Decision 11)

  func testAHeldCmdWKeepsTheRowUntilTheTabCloses() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    let page = try XCTUnwrap(harness.engine.contentView(for: tab))
    harness.engine.holdClose(tab)

    harness.controller.closeTab(nil)

    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertNotNil(harness.source.node(world.today[1]))
    XCTAssertTrue(harness.controller.sidebarController.closingNodes.contains(world.today[1]))
    XCTAssertEqual(harness.controller.currentTab, tab)
    XCTAssertTrue(page.isDescendant(of: harness.controller.rootView.card), "the prompt's page stays mounted")
    XCTAssertEqual(harness.controller.engineHost.claim(.closeTab), CommandClaim(isEnabled: true))
    harness.controller.closeTab(nil)
    XCTAssertTrue(harness.archived.isEmpty, "a second Cmd-W while held does nothing")

    XCTAssertTrue(harness.engine.answerDialog(tab, accept: true))

    XCTAssertEqual(harness.archived, [[world.today[1]]])
    XCTAssertNil(harness.source.node(world.today[1]))
    XCTAssertEqual(harness.controller.currentNode, world.today[2])
    XCTAssertTrue(harness.controller.sidebarController.closingNodes.isEmpty)
  }

  func testACancelledCmdWKeepsTheTabAndDoesNotArchive() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    harness.engine.holdClose(tab)
    harness.controller.closeTab(nil)

    XCTAssertTrue(harness.engine.answerDialog(tab, accept: false))

    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertNotNil(harness.source.node(world.today[1]))
    XCTAssertEqual(harness.controller.currentTab, tab)
    XCTAssertEqual(harness.controller.engineTab(of: world.today[1]), tab)
    XCTAssertTrue(harness.controller.sidebarController.closingNodes.isEmpty)
    // The page keeps its handler: Cmd-W asks again, and accepting archives.
    harness.controller.closeTab(nil)
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: true))
    XCTAssertEqual(harness.archived, [[world.today[1]]])
  }

  /// The X on a Today split row archives the split once all its pages have closed; one held pane holds the archive.
  func testASplitArchivesAfterItsLastPaneCloses() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let held = try XCTUnwrap(harness.controller.engineTab(of: world.panes[1]))
    harness.engine.holdClose(held)

    harness.controller.close(node: world.split)

    XCTAssertTrue(harness.archived.isEmpty)
    XCTAssertNotNil(harness.source.node(world.split))
    XCTAssertTrue(harness.engine.answerDialog(held, accept: true))
    XCTAssertEqual(harness.archived, [[world.split]])
    XCTAssertNil(harness.source.node(world.split))
  }

  /// Auto-archive skips a tab that would hold (and its split), and tries again on its next pass.
  func testTabsThatWouldHoldTheirCloseAreReportedForAutoArchive() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.panes[1])
    XCTAssertTrue(harness.controller.nodesHoldingClose.isEmpty)

    harness.engine.holdClose(try XCTUnwrap(harness.controller.engineTab(of: world.today[0])))
    harness.engine.holdClose(try XCTUnwrap(harness.controller.engineTab(of: world.panes[1])))

    XCTAssertEqual(harness.controller.nodesHoldingClose, [world.today[0], world.panes[1], world.split])
  }

  /// A row removed by something other than Cmd-W (auto-archive, Delete Space) closes its page without a prompt, so no
  /// live tab is left without a row.
  func testARemovedRowClosesItsPageWithoutAPrompt() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.today[1])
    let tab = try XCTUnwrap(harness.controller.engineTab(of: world.today[0]))
    harness.engine.holdClose(tab)

    harness.source.archive([world.today[0]], reason: .auto, at: EngineWorld.now)

    XCTAssertNil(harness.engine.snapshot(of: tab), "closed, not held")
    XCTAssertNil(harness.controller.engineTab(of: world.today[0]))
  }

  /// A row removed while its prompt is up (Delete Space, an import merge): cancelling the prompt closes the page, so
  /// no live tab is left without a row; accepting archives nothing more.
  func testARowRemovedWhileItsCloseIsHeldLeavesNoLiveTab() throws {
    for accept in [false, true] {
      let world = try EngineWorld.make()
      let harness = EngineHarnessWindow(world.sidebar)
      harness.controller.activate(node: world.today[1])
      let tab = try XCTUnwrap(harness.controller.currentTab)
      harness.engine.holdClose(tab)
      harness.controller.closeTab(nil)
      harness.source.archive([world.today[1]], reason: .manual, at: EngineWorld.now)
      XCTAssertNotNil(harness.engine.snapshot(of: tab), "still held")

      XCTAssertTrue(harness.engine.answerDialog(tab, accept: accept))

      XCTAssertNil(harness.engine.snapshot(of: tab), "accept \(accept)")
      XCTAssertNil(harness.controller.nodeByTab[tab])
      XCTAssertTrue(harness.archived.isEmpty, "the row was removed elsewhere; nothing is archived again")
    }
  }

  // MARK: Engine-initiated windows

  /// A window the engine asks for (Dock reopen, `chrome.windows.create`) is built by the provider without calling
  /// the engine, adopted on its `.windowOpened`, and shows the engine's tab as a Today tab.
  func testAnEngineInitiatedWindowIsAdoptedAndShowsItsTab() throws {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    var pending: [ShellWindowController] = []
    var adopted: [ShellWindowController] = []
    engine.windowHostProvider = { _ in
      let controller = ShellWindowController(engine: engine, sidebar: source, opensFirstTab: false)
      pending.append(controller)
      return controller.engineHost
    }
    let pairing = engine.observeWindows { event in
      guard case .windowOpened(let id) = event, !pending.isEmpty else { return }
      let controller = pending.removeFirst()
      controller.adopt(engineWindow: id)
      adopted.append(controller)
    }
    let url = EngineWorld.url("reopen")

    let window = try XCTUnwrap(engine.openEngineWindow(
      EngineWindowRequest(kind: .reopen, profile: EngineProfileID("default"), initialURL: url)))

    let controller = try XCTUnwrap(adopted.first)
    XCTAssertEqual(controller.engineWindow, window)
    XCTAssertEqual(engine.windowIDs, [window], "the provider's window created no engine window of its own")
    let tab = try XCTUnwrap(controller.currentTab)
    let node = try XCTUnwrap(controller.currentNode)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, window)
    XCTAssertEqual(source.section(containing: node), .today(world.space))
    pairing.cancel()
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
/// ArchiveCoordinator, and hidden tabs are recorded and stamped in the model like the app's `markInactive`.
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
    controller.onTabHidden = { [unowned self] id in               // stamps `lastActiveAt`, as the app does
      hidden.append(id)
      source.markInactive([id], at: EngineWorld.now.addingTimeInterval(TimeInterval(hidden.count)))
    }
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
