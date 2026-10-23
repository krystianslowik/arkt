import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Cmd-W (KB-008): Today tabs archive, pinned tabs and Favorites close their page and stay; removed nodes lose their
/// engine tab; the window reports tabs that stop being visible (decision 10).
@MainActor
final class CloseTabTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with one pinned tab, Today tabs `today`, a two-pane split after them, and one Favorite.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
    var favorite: UUID
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [[UUID]] = []
    var hidden: [UUID] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { CloseTabTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.onArchive = { [unowned self] ids in
        archived.append(ids)
        source.archive(ids, reason: .manual, at: CloseTabTests.now)
      }
      controller.onTabHidden = { [unowned self] id in hidden.append(id) }
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(today count: Int = 3, pinned hasPinned: Bool = true) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = hasPinned
      ? try sidebar.addTab(url: url("p"), title: "Pinned", in: .pinned(space)) : UUID()
    let today = try (0..<count).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    let favorite = try sidebar.addTab(url: url("f"), title: "Fav", in: .favorites(profile: "default"))
    return World(sidebar: sidebar, space: space, pinned: pinned, today: today, split: split, panes: panes,
                 favorite: favorite)
  }

  // MARK: Today

  /// BH-071, KB-008: the active Today tab is archived; the next sibling below becomes current.
  func testTodayTabArchivesAndTheNextSiblingBelowBecomesCurrent() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let tab = try XCTUnwrap(harness.controller.currentTab)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [[world.today[1]]])
    XCTAssertNil(harness.source.node(world.today[1]))
    XCTAssertFalse(harness.engine.tabIDs.contains(tab), "the archived tab's engine tab is closed")
    XCTAssertEqual(harness.controller.visibleNodes, [world.today[2]])
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[2])
    harness.controller.close()
  }

  /// With no sibling below, the one above becomes current.
  func testLastTodayItemFallsBackToTheSiblingAbove() throws {
    var world = try Self.makeWorld()
    world.sidebar.remove(world.split)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[2])

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [[world.today[2]]])
    XCTAssertEqual(harness.controller.visibleNodes, [world.today[1]])
    harness.controller.close()
  }

  /// BH-073: archiving the last Today tab leaves the window open on the empty Space with an empty card.
  func testLastTodayTabLeavesTheWindowOpenWithAnEmptyCard() throws {
    var world = try Self.makeWorld(today: 1, pinned: false)
    world.sidebar.remove(world.split)
    let harness = Harness(world.sidebar)
    harness.controller.showWindow(nil)
    harness.controller.activate(node: world.today[0])
    XCTAssertNotNil(harness.controller.rootView.card.contentView)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [[world.today[0]]])
    XCTAssertNil(harness.controller.currentTab)
    XCTAssertNil(harness.controller.rootView.card.contentView)
    XCTAssertEqual(harness.controller.visibleNodes, [])
    XCTAssertEqual(harness.controller.currentSpace, world.space)
    XCTAssertEqual(harness.controller.window?.isVisible, true)
    XCTAssertTrue(harness.engine.tabIDs.isEmpty)
    harness.controller.close()
  }

  /// User decision 4, PARITY(NEEDS-RUNTIME-CHECK BH-123): Cmd-W on a split pane in Today archives only that pane;
  /// the split collapses into the remaining pane, which becomes current.
  func testSplitPaneInTodayArchivesOnlyThatPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [[world.panes[0]]])
    XCTAssertNil(harness.source.node(world.split), "a split left with one pane becomes a plain tab")
    XCTAssertEqual(harness.source.children(of: .today(world.space)), world.today + [world.panes[1]])
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[1]])
    harness.controller.close()
  }

  // MARK: Pinned and Favorites

  /// BH-067: Cmd-W on the active pinned tab closes its page and keeps the node; nothing is archived.
  func testPinnedTabClosesItsPageAndStays() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let tab = try XCTUnwrap(harness.controller.currentTab)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(tab))
    XCTAssertEqual(harness.source.children(of: .pinned(world.space)), [world.pinned])
    XCTAssertNil(harness.controller.currentTab)
    XCTAssertNil(harness.controller.rootView.card.contentView)
    XCTAssertEqual(harness.controller.visibleNodes, [])
    harness.controller.close()
  }

  /// BH-048 [I]: a Favorite behaves like a pinned tab.
  func testFavoriteClosesItsPageAndStays() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.favorite)
    let tab = try XCTUnwrap(harness.controller.currentTab)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(tab))
    XCTAssertEqual(harness.source.children(of: .favorites(profile: "default")), [world.favorite])
    XCTAssertNil(harness.controller.currentTab)
    harness.controller.close()
  }

  /// A pane of a pinned split closes only its own page (user decision 4).
  func testPinnedSplitPaneClosesOnlyItsOwnPage() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: Self.url($0), title: $0, in: .split(split)) }
    let harness = Harness(sidebar)
    harness.controller.activate(node: panes[0])
    let left = try XCTUnwrap(harness.controller.currentTab)
    harness.controller.activate(node: panes[1])
    let right = try XCTUnwrap(harness.controller.currentTab)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [])
    XCTAssertEqual(harness.engine.tabIDs, [left])
    XCTAssertFalse(harness.engine.tabIDs.contains(right))
    XCTAssertEqual(harness.source.children(of: .split(split)), panes)
    harness.controller.close()
  }

  // MARK: No current tab

  /// BH-069 (a second Cmd-W unpins) is NEEDS-RUNTIME-CHECK and not implemented: with no current tab nothing happens.
  func testNoCurrentTabDoesNothing() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    harness.controller.closeTab(nil)
    XCTAssertNil(harness.controller.currentTab)
    let before = harness.source.sidebar

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [])
    XCTAssertEqual(harness.source.sidebar, before)
    harness.controller.close()
  }

  // MARK: Engine cleanup

  /// A node removed by any cause (here: archived directly, not through Cmd-W) loses its engine tab.
  func testRemovingANodeClosesItsEngineTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let first = try XCTUnwrap(harness.controller.currentTab)
    harness.controller.activate(node: world.today[1])
    let second = try XCTUnwrap(harness.controller.currentTab)
    XCTAssertTrue(harness.engine.tabIDs.contains(first))

    harness.source.archive([world.today[0], world.today[1]], reason: .auto, at: Self.now)

    XCTAssertFalse(harness.engine.tabIDs.contains(first))
    XCTAssertFalse(harness.engine.tabIDs.contains(second))
    XCTAssertNil(harness.controller.currentTab, "the current tab's page leaves the card")
    XCTAssertNil(harness.controller.rootView.card.contentView)
    harness.controller.close()
  }

  // MARK: Visibility

  /// Decision 10: the outgoing tab is reported when another becomes current and the current one when the window
  /// closes; re-activating the current tab reports nothing.
  func testTabHiddenFiresOnSwitchAndOnWindowClose() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.hidden = []
    harness.controller.activate(node: world.today[0])
    let initial = harness.hidden
    harness.controller.activate(node: world.today[1])
    harness.controller.activate(node: world.today[1])
    XCTAssertEqual(harness.controller.visibleNodes, [world.today[1]])

    harness.controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

    XCTAssertEqual(initial, [world.pinned], "the launch tab (first pinned) is hidden by the first switch")
    XCTAssertEqual(harness.hidden, [world.pinned, world.today[0], world.today[1]])
    harness.controller.close()
  }

  func testVisibleNodesIsEmptyWithoutACurrentTab() throws {
    let harness = Harness(SidebarModel.Sidebar())
    XCTAssertEqual(harness.controller.visibleNodes, [])
    harness.controller.close()
  }
}
