import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// BH-066 (Tab Handoff, #300): two windows show the same Space, and a tab's page is loaded in one window at a time.
/// Selecting a row whose page is live in another window moves that page here (no second load); the window it left
/// shows a placeholder and keeps its other pages and its window.
@MainActor
final class TabHandoffTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet() throws -> (set: ShellWindowSet, engine: InMemoryEngine, source: ModelSidebarSource,
                                    world: EngineWorld) {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.configure = { controller in
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: EngineWorld.now) }
    }
    sets.append(set)
    return (set, engine, source, world)
  }

  /// Two windows without a page yet, so every engine tab in a test is one the test asked for.
  private func twoWindows(_ set: ShellWindowSet) -> (ShellWindowController, ShellWindowController) {
    (set.openWindow(opensFirstTab: false), set.openWindow(opensFirstTab: false))
  }

  // MARK: Plain tabs

  func testSelectingARowLiveInAnotherWindowMovesItsPage() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[1])
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let tabsBefore = engine.tabIDs

    second.activate(node: world.today[0])

    XCTAssertEqual(engine.tabIDs, tabsBefore, "no second page for the row")
    XCTAssertEqual(second.currentTab, tab, "the same tab, with its page and history")
    XCTAssertEqual(second.engineTab(of: world.today[0]), tab)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, second.engineWindow)
    XCTAssertTrue(page.isDescendant(of: second.rootView.card), "the page is mounted in the selecting window")
    XCTAssertFalse(page.isDescendant(of: first.rootView.card))
    XCTAssertNil(first.engineTab(of: world.today[0]))
    XCTAssertEqual(second.visibleNodes, [world.today[0]])
    XCTAssertEqual(first.visibleNodes, [])
  }

  /// The window the page left keeps the row selectable, shows the placeholder, and does not follow the engine's pick
  /// of its next active tab: the user did not ask for another tab there.
  func testTheWindowThePageLeftShowsThePlaceholder() throws {
    let (set, _, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[1])
    first.activate(node: world.today[0])

    second.activate(node: world.today[0])

    XCTAssertNil(first.currentTab)
    XCTAssertNotEqual(first.rowState(for: world.today[0]), .current, "a second click takes the page back")
    let placeholder = try XCTUnwrap(first.handoffPlaceholder)
    XCTAssertTrue(placeholder.isDescendant(of: first.rootView.card))
    XCTAssertEqual(placeholder.accessibilityIdentifier(), AXID.Handoff.placeholder)
    XCTAssertTrue(first.window?.isVisible ?? false)
    XCTAssertNotNil(first.engineTab(of: world.today[1]), "its other pages stay")
    XCTAssertFalse(second.handoffPlaceholder?.isDescendant(of: second.rootView.card) ?? false)
  }

  /// Selecting the row again in the first window moves the page back; no window ever holds a second copy.
  func testSelectingTheRowAgainMovesThePageBack() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[1])
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    second.activate(node: world.today[0])
    let tabsBefore = engine.tabIDs

    first.activate(node: world.today[0])

    XCTAssertEqual(engine.tabIDs, tabsBefore)
    XCTAssertEqual(first.currentTab, tab)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, first.engineWindow)
    XCTAssertNil(second.engineTab(of: world.today[0]))
    XCTAssertNil(second.currentTab)
    XCTAssertFalse(first.handoffPlaceholder?.isDescendant(of: first.rootView.card) ?? false)
  }

  /// The placeholder's button takes the page back too.
  func testThePlaceholderButtonMovesThePageBack() throws {
    let (set, _, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[1])
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    second.activate(node: world.today[0])

    try XCTUnwrap(first.handoffPlaceholder).moveHereButton.performClick(nil)

    XCTAssertEqual(first.currentTab, tab)
    XCTAssertNil(second.currentTab)
  }

  /// The engine closes a window whose last tab moved out; the shell window stays open without an engine window, as
  /// after New Window, and its next selection gets a new one.
  func testMovingAWindowsLastPageKeepsTheWindowOpen() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    let firstEngineWindow = try XCTUnwrap(first.engineWindow)

    second.activate(node: world.today[0])

    XCTAssertEqual(second.currentTab, tab)
    XCTAssertFalse(engine.windowIDs.contains(firstEngineWindow), "the engine closed the emptied window")
    XCTAssertNil(first.engineWindow)
    XCTAssertFalse(first.isClosed)
    XCTAssertTrue(first.window?.isVisible ?? false)
    XCTAssertEqual(set.controllers.count, 2)

    first.activate(node: world.today[1])

    XCTAssertNotNil(first.engineWindow)
    let other = try XCTUnwrap(first.currentTab)
    XCTAssertEqual(engine.snapshot(of: other)?.window, first.engineWindow)
    XCTAssertEqual(second.currentTab, tab, "the other window keeps its page")
  }

  /// The real-app sequence: every page of the first window moves out one by one, the shown one first.
  func testMovingEveryPageOneByOneKeepsTheWindowOpen() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    for node in [world.today[2], world.today[1], world.today[0]] { first.activate(node: node) }

    for node in [world.today[0], world.today[1], world.today[2]] { second.activate(node: node) }

    XCTAssertEqual(engine.tabIDs.count, 3)
    XCTAssertNil(first.engineWindow)
    XCTAssertFalse(first.isClosed)
    XCTAssertTrue(first.window?.isVisible ?? false)
    XCTAssertEqual(second.currentNode, world.today[2])
  }

  /// A page whose close is held behind a leave-site prompt stays where it is, and no copy loads.
  func testAPageWhoseCloseIsHeldIsNotMovedOrCopied() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.pinned)
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    engine.holdClose(tab)
    first.closeTab(nil)
    XCTAssertEqual(engine.snapshot(of: tab)?.isClosing, true)
    let tabsBefore = engine.tabIDs

    second.activate(node: world.today[0])

    XCTAssertEqual(engine.tabIDs, tabsBefore)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, first.engineWindow)
    XCTAssertNil(second.engineTab(of: world.today[0]))
  }

  // MARK: Split View

  /// The issue's case: the first window archives its tab, and the successor is the split the second window shows.
  /// Its panes move to the first window; none loads twice.
  func testAnArchiveSuccessorLiveInAnotherWindowMovesItsPanes() throws {
    let (set, engine, source, world) = try makeSet()
    let (first, second) = twoWindows(set)
    second.activate(node: world.panes[0])
    let paneTabs = try world.panes.map { try XCTUnwrap(second.engineTab(of: $0)) }
    second.activate(node: world.today[0])              // the second window keeps a page of its own
    first.activate(node: world.today[2])
    let shown = try XCTUnwrap(first.currentTab)
    let tabsBefore = Set(engine.tabIDs)

    first.closeTab(nil)                                 // Cmd-W archives T2; the split below is the successor

    XCTAssertNil(source.node(world.today[2]))
    XCTAssertEqual(Set(engine.tabIDs).subtracting(first.reopenStack.parkedTabs), tabsBefore.subtracting([shown]),
                   "the panes moved; nothing new loaded besides the closed page's parked copy (#346)")
    XCTAssertEqual(world.panes.map { first.engineTab(of: $0) }, paneTabs)
    for tab in paneTabs { XCTAssertEqual(engine.snapshot(of: tab)?.window, first.engineWindow) }
    XCTAssertEqual(first.visibleNodes, Set(world.panes))
    XCTAssertTrue(world.panes.allSatisfy { second.engineTab(of: $0) == nil })
    XCTAssertNotNil(second.engineTab(of: world.today[0]))
  }

  /// A split shown in the first window and selected in the second: both panes move, and the first window shows the
  /// placeholder.
  func testSelectingASplitShownInAnotherWindowMovesItAndLeavesThePlaceholder() throws {
    let (set, engine, _, world) = try makeSet()
    let (first, second) = twoWindows(set)
    first.activate(node: world.today[0])
    first.activate(node: world.panes[0])
    let paneTabs = try world.panes.map { try XCTUnwrap(first.engineTab(of: $0)) }
    let tabsBefore = Set(engine.tabIDs)

    second.activate(node: world.split)

    XCTAssertEqual(Set(engine.tabIDs), tabsBefore)
    XCTAssertEqual(world.panes.map { second.engineTab(of: $0) }, paneTabs)
    XCTAssertEqual(second.visibleNodes, Set(world.panes))
    XCTAssertNil(first.currentTab)
    XCTAssertEqual(first.visibleNodes, [])
    XCTAssertTrue(first.handoffPlaceholder?.isDescendant(of: first.rootView.card) ?? false)
  }
}
