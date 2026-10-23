import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Split View S4: the window shows every pane of a split, each with its own engine tab; the focused pane is the
/// current tab and drives the URL bar, the Toolbar and Cmd-L (BH-125, KB-074); panes that leave the screen are
/// reported (decision 10); a closed Pinned pane shows a placeholder that reopens on click (decision 6).
@MainActor
final class SplitWindowTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with one pinned tab, Today `[t0, split(p0, p1), t1]`.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var hidden: [UUID] = []
    var changes = 0

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitWindowTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: SplitWindowTests.now) }
      controller.onTabHidden = { [unowned self] id in hidden.append(id) }
      source.onDidChange = { [unowned self] _ in changes += 1 }
    }

    var split: SplitContainerView { controller.rootView.split }

    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }

    func page(_ node: UUID) -> NSView? { tab(node).flatMap { engine.contentView(for: $0) } }

    func layout() { controller.window?.contentView?.layoutSubtreeIfNeeded() }

    /// Lets deferred work (the re-show after a source change) run.
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(panes count: Int = 2) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: url("p"), title: "Pinned", in: .pinned(space))
    let t0 = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let factors = Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors, in: .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let t1 = try sidebar.addTab(url: url("t1"), title: "T1", in: .today(space))
    return World(sidebar: sidebar, space: space, pinned: pinned, today: [t0, t1], split: split, panes: panes)
  }

  // MARK: Showing a split

  /// Decision 6: activating a pane shows every pane, each in its own card with its own lazily created engine tab.
  func testActivatingAPaneShowsAllPanesWithOneEngineTabEach() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let before = harness.engine.tabIDs.count

    harness.controller.activate(node: world.panes[1])

    XCTAssertEqual(harness.engine.tabIDs.count, before + 2, "one engine tab per pane")
    let left = try XCTUnwrap(harness.tab(world.panes[0]))
    let right = try XCTUnwrap(harness.tab(world.panes[1]))
    XCTAssertNotEqual(left, right)
    XCTAssertFalse(harness.split.isHidden)
    XCTAssertTrue(harness.controller.rootView.card.isHidden, "the split replaces the single card")
    XCTAssertEqual(harness.split.paneCount, 2)
    XCTAssertTrue(harness.split.paneCards[0].contentView === harness.page(world.panes[0]))
    XCTAssertTrue(harness.split.paneCards[1].contentView === harness.page(world.panes[1]))
    XCTAssertEqual(harness.split.focusedIndex, 1)
    XCTAssertEqual(harness.controller.currentTab, right)
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes))
    harness.controller.close()
  }

  /// Showing the same split again reuses the panes' engine tabs.
  func testReShowingASplitReusesItsEngineTabs() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let tabs = harness.engine.tabIDs

    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.panes[1])

    XCTAssertEqual(Set(harness.engine.tabIDs), Set(tabs + [try XCTUnwrap(harness.tab(world.today[0]))]))
    harness.controller.close()
  }

  /// #156 review: pane pages created outside the activated tab count as loaded and stop counting when they close.
  func testBackgroundPanePagesAreLoadedUntilTheyClose() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    XCTAssertTrue(harness.controller.sidebarController.loadedNodes.contains(world.panes[1]))

    harness.engine.closeTab(try XCTUnwrap(harness.tab(world.panes[1])))

    XCTAssertFalse(harness.controller.sidebarController.loadedNodes.contains(world.panes[1]))
    harness.controller.close()
  }

  // MARK: Focus

  /// Decision 7: the focused pane is current, the other panes are drawn as visible content.
  func testFocusedPaneIsCurrentAndTheOthersContentVisible() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    harness.controller.activate(node: world.panes[0])

    XCTAssertEqual(harness.controller.rowState(for: world.panes[0]), .current)
    XCTAssertEqual(harness.controller.rowState(for: world.panes[1]), .contentVisible)
    XCTAssertEqual(harness.controller.rowState(for: world.today[0]), .normal)
    XCTAssertEqual(harness.controller.sidebarController.resolver.visible, Set(world.panes))
    harness.controller.close()
  }

  /// Decision 7: the split row focuses its first pane, then the last focused one for the window's lifetime.
  func testActivatingTheSplitRowRestoresTheLastFocusedPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.split)
    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[0], "first pane by default")

    harness.controller.activate(node: world.panes[1])
    harness.controller.activate(node: world.today[0])
    harness.controller.activate(node: world.split)

    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[1])
    XCTAssertEqual(harness.controller.currentTab, harness.tab(world.panes[1]))
    XCTAssertEqual(harness.split.focusedIndex, 1)
    harness.controller.close()
  }

  /// A mouse-down inside another pane focuses it through the window's local monitor, and the page becomes first
  /// responder.
  func testClickInSecondPaneFocusesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.showWindow(nil)
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    let window = try XCTUnwrap(harness.controller.window)
    let card = harness.split.paneCards[1]
    let point = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
    let down = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

    NSApp.sendEvent(down)                                      // local monitors run here, not in NSWindow.sendEvent

    let right = try XCTUnwrap(harness.tab(world.panes[1]))
    XCTAssertEqual(harness.controller.currentTab, right)
    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[1])
    XCTAssertEqual(harness.split.focusedIndex, 1)
    XCTAssertTrue(window.firstResponder === harness.engine.contentView(for: right))
    harness.controller.close()
  }

  /// The single card is hidden under a split, so toasts move to the split container and back.
  func testToastsStayOnScreenOverASplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let toast = try XCTUnwrap(harness.controller.toasts.view)

    harness.controller.activate(node: world.panes[0])
    XCTAssertTrue(toast.superview === harness.split)
    XCTAssertTrue(harness.split.subviews.last === toast, "the toast draws above the panes and dividers")

    harness.controller.activate(node: world.today[0])
    XCTAssertTrue(toast.superview === harness.controller.rootView.card)
    harness.controller.close()
  }

  // MARK: Visibility (decision 10)

  /// Switching from a split to a plain tab reports every pane as hidden and gives the page back to the single card.
  func testSwitchingToAPlainTabReportsEveryHiddenPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.hidden = []

    harness.controller.activate(node: world.today[0])

    XCTAssertEqual(Set(harness.hidden), Set(world.panes))
    XCTAssertEqual(harness.hidden.count, 2)
    XCTAssertEqual(harness.controller.visibleNodes, [world.today[0]])
    XCTAssertTrue(harness.split.isHidden)
    XCTAssertFalse(harness.controller.rootView.card.isHidden)
    XCTAssertTrue(harness.controller.rootView.card.contentView === harness.page(world.today[0]))
    XCTAssertEqual(harness.split.paneCount, 0, "the split lets go of its pages")
    XCTAssertEqual(harness.controller.rowState(for: world.panes[1]), .normal)
    harness.controller.close()
  }

  /// Moving focus inside a split hides nothing; closing the window reports every pane.
  func testFocusInsideASplitHidesNothingAndWindowCloseStampsEveryPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.hidden = []

    harness.controller.activate(node: world.panes[1])
    XCTAssertEqual(harness.hidden, [])

    harness.controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    XCTAssertEqual(Set(harness.hidden), Set(world.panes))
    harness.controller.close()
  }

  // MARK: URL bar, Toolbar and Cmd-L (BH-125, KB-074)

  /// Cmd-L commits navigate the focused pane only; the sidebar URL bar follows it.
  func testCmdLNavigatesTheFocusedPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let target = Self.url("typed")

    harness.controller.commandBar.onOpen?(target, .currentTab)

    XCTAssertEqual(harness.tab(world.panes[1]).flatMap { harness.engine.snapshot(of: $0)?.url }, target)
    XCTAssertEqual(harness.tab(world.panes[0]).flatMap { harness.engine.snapshot(of: $0)?.url }, Self.url("s0"))
    XCTAssertEqual(harness.controller.urlBar.url, target)
    harness.controller.close()
  }

  /// With the Toolbar on, each pane card shows its own URL; the sidebar URL bar shows the focused pane's.
  func testToolbarShowsEachPanesOwnURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.toolbarSetting.isVisible = true
    harness.controller.activate(node: world.panes[0])

    let cards = harness.split.paneCards
    XCTAssertTrue(cards.allSatisfy(\.showsToolbar))
    XCTAssertEqual(cards[0].toolbar.urlBar.url, Self.url("s0"))
    XCTAssertEqual(cards[1].toolbar.urlBar.url, Self.url("s1"))

    harness.engine.navigate(try XCTUnwrap(harness.tab(world.panes[1])), to: Self.url("next"))

    XCTAssertEqual(cards[1].toolbar.urlBar.url, Self.url("next"))
    XCTAssertTrue(cards[1].toolbar.backButton.isEnabled)
    XCTAssertFalse(cards[0].toolbar.backButton.isEnabled)
    XCTAssertEqual(harness.controller.urlBar.url, Self.url("s0"), "the sidebar URL bar stays on the focused pane")
    harness.controller.close()
  }

  /// Back on a pane's Toolbar acts on that pane and focuses it; the URL bar and history follow the new focus.
  func testToolbarBackActsOnItsPaneAndFocusesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.toolbarSetting.isVisible = true
    harness.controller.activate(node: world.panes[0])
    let right = try XCTUnwrap(harness.tab(world.panes[1]))
    harness.engine.navigate(right, to: Self.url("next"))

    harness.split.paneCards[1].toolbar.backButton.performClick(nil)

    XCTAssertEqual(harness.engine.snapshot(of: right)?.url, Self.url("s1"))
    XCTAssertEqual(harness.tab(world.panes[0]).flatMap { harness.engine.snapshot(of: $0)?.url }, Self.url("s0"))
    XCTAssertEqual(harness.controller.currentTab, right)
    XCTAssertEqual(harness.controller.urlBar.url, Self.url("s1"))
    XCTAssertTrue(harness.split.paneCards[1].toolbar.forwardButton.isEnabled)
    harness.controller.close()
  }

  // MARK: Source writes and changes

  /// Decision 5: a divider drag writes the model once, on mouse-up.
  func testDividerCommitWritesTheModelOnce() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    harness.changes = 0
    let divider = try XCTUnwrap(harness.split.dividers.first)

    divider.beginDrag()
    divider.drag(to: harness.split.bounds.width * 0.4)
    divider.drag(to: harness.split.bounds.width * 0.6)
    XCTAssertEqual(harness.changes, 0, "nothing reaches the source during the drag")
    divider.endDrag()

    XCTAssertEqual(harness.changes, 1)
    guard case .split(_, let layout)? = harness.source.node(world.split) else { return XCTFail("split gone") }
    XCTAssertEqual(layout.widthFactors.count, 2)
    XCTAssertEqual(layout.widthFactors[0], harness.split.liveFactors[0], accuracy: 1e-9)
    XCTAssertGreaterThan(layout.widthFactors[0], 0.5)
    harness.settle()
    XCTAssertEqual(harness.changes, 1, "the re-show after the commit writes nothing")
    harness.controller.close()
  }

  /// An orientation change from the source re-lays out the shown split.
  func testSourceOrientationChangeRelayoutsTheShownSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    XCTAssertEqual(harness.split.axis, .sideBySide)

    try harness.source.setSplitOrientation(world.split, .vertical)
    harness.settle()

    XCTAssertEqual(harness.split.axis, .stacked)
    XCTAssertEqual(harness.split.focusedIndex, 1)
    XCTAssertEqual(harness.controller.currentTab, harness.tab(world.panes[1]))
    harness.controller.close()
  }

  /// Decision 6, CF-18: separating a pane keeps its engine tab; a split left with one pane shows it as a plain tab.
  func testSeparatedPaneKeepsItsEngineTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let tabs = harness.engine.tabIDs
    harness.hidden = []

    try harness.source.separatePane(world.panes[1])
    harness.settle()

    XCTAssertEqual(harness.engine.tabIDs, tabs)
    XCTAssertTrue(harness.split.isHidden)
    XCTAssertTrue(harness.controller.rootView.card.contentView === harness.page(world.panes[0]))
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0]])
    XCTAssertEqual(harness.hidden, [world.panes[1]])
    harness.controller.close()
  }

  /// User decision 4: Cmd-W archives a Today pane alone; the split shrinks and the next pane in it takes focus.
  func testCmdWOnATodayPaneFocusesTheNextPaneOfTheShrunkSplit() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    harness.controller.closeTab(nil)
    harness.settle()

    XCTAssertNil(harness.source.node(world.panes[1]))
    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[2])
    XCTAssertEqual(harness.split.paneCount, 2)
    XCTAssertEqual(harness.split.focusedIndex, 1)
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0], world.panes[2]])
    harness.controller.close()
  }

  // MARK: Closed Pinned panes (decision 6)

  private static func makePinnedSplitWorld() throws -> (SidebarModel.Sidebar, split: UUID, panes: [UUID], other: UUID) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    let other = try sidebar.addTab(url: url("o"), title: "O", in: .today(space))
    return (sidebar, split, panes, other)
  }

  /// A closed Pinned pane shows a placeholder, stays closed when the split shows again, and reopens on click.
  func testClosedPinnedPaneShowsAPlaceholderThatReopensOnClick() throws {
    let world = try Self.makePinnedSplitWorld()
    let harness = Harness(world.0)
    harness.controller.activate(node: world.panes[0])

    harness.controller.close(node: world.panes[1])                // the pane row's hover X

    XCTAssertNil(harness.tab(world.panes[1]))
    XCTAssertEqual(harness.source.children(of: .split(world.split)), world.panes, "the pane row stays")
    XCTAssertTrue(harness.split.paneCards[1].emptyStateView is SplitPanePlaceholderView)
    XCTAssertNil(harness.split.paneCards[1].contentView)
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0]])

    harness.controller.activate(node: world.other)
    harness.controller.activate(node: world.split)
    XCTAssertNil(harness.tab(world.panes[1]), "showing the split again does not reopen the closed pane")
    let placeholder = try XCTUnwrap(harness.split.paneCards[1].emptyStateView as? SplitPanePlaceholderView)

    XCTAssertTrue(placeholder.accessibilityPerformPress())

    let reopened = try XCTUnwrap(harness.tab(world.panes[1]))
    XCTAssertEqual(harness.controller.currentTab, reopened)
    XCTAssertNil(harness.split.paneCards[1].emptyStateView)
    XCTAssertTrue(harness.split.paneCards[1].contentView === harness.page(world.panes[1]))
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes))
    harness.controller.close()
  }

  /// Cmd-W on the focused Pinned pane moves focus to the open pane next to it; closing the last open pane empties
  /// the content area.
  func testCmdWOnPinnedPanesMovesFocusThenEmptiesTheContent() throws {
    let world = try Self.makePinnedSplitWorld()
    let harness = Harness(world.0)
    harness.controller.activate(node: world.panes[1])

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.controller.currentTab, harness.tab(world.panes[0]))
    XCTAssertEqual(harness.split.focusedIndex, 0)
    XCTAssertTrue(harness.split.paneCards[1].emptyStateView is SplitPanePlaceholderView)

    harness.controller.closeTab(nil)

    XCTAssertNil(harness.controller.currentTab)
    XCTAssertTrue(harness.split.isHidden)
    XCTAssertNil(harness.controller.rootView.card.contentView)
    XCTAssertEqual(harness.controller.visibleNodes, [])
    XCTAssertTrue(harness.engine.tabIDs.isEmpty, "both pane pages are closed")

    harness.controller.activate(node: world.split)
    XCTAssertNotNil(harness.tab(world.panes[0]), "with every pane closed, the split opens afresh")
    XCTAssertNotNil(harness.tab(world.panes[1]))
    harness.controller.close()
  }
}
