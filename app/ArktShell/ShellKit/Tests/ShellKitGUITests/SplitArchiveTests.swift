import AppKit
import Archive
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Split View S8: Cmd-W archives one Today pane and focuses its sibling (BH-123, user decision 4); Ctrl-Shift--
/// never archives (CF-18); hidden panes and termination stamp every visible pane (decision 10); a restored or
/// relaunched split shows the layout it was stored with (BH-086).
@MainActor
final class SplitArchiveTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with Today `[t0, split, t1]`.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let coordinator: ArchiveCoordinator
    var archived: [[UUID]] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitArchiveTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      coordinator = ArchiveCoordinator(
        source: source, store: DiscardingArchiveStore(), now: { SplitArchiveTests.now })
      controller.onArchive = { [unowned self] ids in
        archived.append(coordinator.archive(ids, reason: .manual).map(\.id))
      }
    }

    var splitView: SplitContainerView { controller.rootView.split }

    func close() { controller.close() }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(
    panes count: Int = 2,
    orientation: SidebarModel.Orientation = .horizontal,
    factors: [Double]? = nil
  ) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let t0 = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let shares = factors ?? Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: orientation, widthFactors: shares, in: .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let t1 = try sidebar.addTab(url: url("t1"), title: "T1", in: .today(space))
    return World(sidebar: sidebar, space: space, today: [t0, t1], split: split, panes: panes)
  }

  private static func lastActive(_ source: ModelSidebarSource, _ id: UUID) -> Date? {
    guard case .tab(let tab)? = source.sidebar.nodes[id]?.kind else { return nil }
    return tab.lastActiveAt
  }

  private static func layout(of id: UUID, in source: ModelSidebarSource) -> SplitLayoutInfo? {
    guard case .split(_, let layout)? = source.node(id) else { return nil }
    return layout
  }

  // MARK: Cmd-W (BH-123)

  /// Cmd-W on one pane of a three-pane Today split archives only that pane, rescales the other factors, and focuses
  /// the sibling after it.
  func testCmdWOnPaneOfThreeArchivesOnlyItAndFocusesSibling() throws {
    let before = [0.5, 0.25, 0.25]
    let world = try Self.makeWorld(panes: 3, factors: before)
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    harness.controller.activate(node: world.panes[1])
    let closed = try XCTUnwrap(harness.controller.engineTab(of: world.panes[1]))
    let kept = try XCTUnwrap(harness.controller.engineTab(of: world.panes[2]))

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [[world.panes[1]]])
    XCTAssertNil(harness.source.node(world.panes[1]))
    XCTAssertFalse(harness.engine.tabIDs.contains(closed))
    XCTAssertTrue(harness.engine.tabIDs.contains(kept))
    XCTAssertEqual(harness.source.children(of: .split(world.split)), [world.panes[0], world.panes[2]])
    let total = before.reduce(0, +)
    let rest = total - before[1]
    let expected = [before[0], before[2]].map { $0 * total / rest }
    let stored = try XCTUnwrap(Self.layout(of: world.split, in: harness.source)).widthFactors
    XCTAssertEqual(stored[0], expected[0], accuracy: 1e-9)
    XCTAssertEqual(stored[1], expected[1], accuracy: 1e-9)
    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[2])
    waitUntil("the shrunk split shown with the sibling focused") {
      harness.splitView.paneCount == 2 && harness.controller.currentTab == kept
    }
    XCTAssertFalse(harness.splitView.isHidden)
    XCTAssertEqual(harness.splitView.focusedIndex, 1)
    XCTAssertEqual(harness.splitView.liveFactors[0], expected[0], accuracy: 1e-9)
    XCTAssertEqual(harness.splitView.liveFactors[1], expected[1], accuracy: 1e-9)
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0], world.panes[2]])
    XCTAssertEqual(
      harness.controller.sidebarController.resolver.visible, [world.panes[0], world.panes[2]],
      "the shrunk split publishes both remaining panes as shown, not only the focused one")
  }

  // MARK: Ctrl-Shift-- (CF-18)

  /// Close this Split Pane separates the focused pane and never archives it: the coordinator's outbox stays empty.
  func testCtrlShiftMinusNeverArchives() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    harness.controller.activate(node: world.panes[0])
    let page = try XCTUnwrap(harness.controller.engineTab(of: world.panes[0]))

    harness.controller.closeSplitPane(nil)

    XCTAssertEqual(harness.archived, [])
    XCTAssertTrue(harness.coordinator.pendingItems.isEmpty)
    XCTAssertEqual(harness.controller.engineTab(of: world.panes[0]), page, "the separated tab keeps its page")
    XCTAssertEqual(
      harness.source.children(of: .today(world.space)),
      [world.today[0], world.panes[1], world.panes[0], world.today[1]])
    XCTAssertNil(harness.source.node(world.split))
  }

  // MARK: Visibility (decision 10)

  /// Leaving a shown split stamps `lastActiveAt` on every pane, the same way `AppSession` wires `onTabHidden`.
  func testHiddenPanesGetLastActiveAtWhenCardSwitches() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    let stamp = Date(timeIntervalSinceReferenceDate: 900_000_000)
    harness.controller.onTabHidden = { [unowned harness] id in harness.source.markInactive([id], at: stamp) }
    harness.controller.activate(node: world.panes[0])
    XCTAssertNil(Self.lastActive(harness.source, world.panes[0]))
    XCTAssertNil(Self.lastActive(harness.source, world.panes[1]))

    harness.controller.activate(node: world.today[1])

    XCTAssertEqual(Self.lastActive(harness.source, world.panes[0]), stamp)
    XCTAssertEqual(Self.lastActive(harness.source, world.panes[1]), stamp)
    XCTAssertNil(Self.lastActive(harness.source, world.today[1]), "the tab now shown is not stamped")
  }

  /// Termination, controller side only. This test does NOT exercise `AppSession.prepareForTermination`: that method
  /// lives in the app target, which has no unit-test bundle (its only test target, `ArktShellUITests`, drives the
  /// built app out of process), so nothing in ShellKit's test targets can call it. `prepareForTermination` stops the
  /// auto-archive timer and calls `source.markInactive(window.visibleNodes, at: .now)`; this test asserts the input
  /// of that call (`visibleNodes` is every pane of the shown split, not only the focused one) and makes the same
  /// `markInactive` call by hand to check that it stamps each pane.
  func testTerminationStampsAllVisiblePanes() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    harness.controller.activate(node: world.panes[1])
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes))

    let stamp = Date(timeIntervalSinceReferenceDate: 900_000_000)
    harness.source.markInactive(harness.controller.visibleNodes, at: stamp)

    for pane in world.panes {
      XCTAssertEqual(Self.lastActive(harness.source, pane), stamp)
    }
  }

  // MARK: Auto-archive (decision 10)

  /// Plan S8 step 4, window side: with a split shown, the set `AppSession.startAutoArchive` hands the timer
  /// (`resolver.visible` plus `nodesHoldingClose`) holds every shown pane, so a pass with every pane idle past the
  /// threshold keeps the split. `AutoArchivePolicy` lets any one exempt pane protect the whole split, so the pass
  /// alone would also keep it if the window published only the focused pane; the set is asserted directly for that.
  /// Once another tab is shown the panes leave the set and the same pass archives the split.
  func testAutoArchiveExemptsEveryShownPane() throws {
    let settings = ArchiveSettings()
    let threshold = try XCTUnwrap(settings.tabThreshold(forProfile: ArchiveSettings.defaultProfile).interval)
    let fresh = Self.now.addingTimeInterval(-60)
    let idle = Self.now.addingTimeInterval(-(threshold + 3600))
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let other = try sidebar.addTab(
      url: Self.url("t0"), title: "T0", lastActiveAt: fresh, in: .today(space), createdAt: fresh)
    let split = try sidebar.addSplit(
      orientation: .horizontal, widthFactors: [1.0 / 3, 1.0 / 3, 1.0 / 3], in: .today(space), createdAt: idle)
    let panes = try (0..<3).map {
      try sidebar.addTab(
        url: Self.url("s\($0)"), title: "S\($0)", lastActiveAt: idle, in: .split(split), createdAt: idle)
    }
    let harness = Harness(sidebar)
    defer { harness.close() }
    func exempt() -> Set<UUID> {  // as AppSession.startAutoArchive builds it
      harness.controller.sidebarController.resolver.visible.union(harness.controller.nodesHoldingClose)
    }
    func pass() -> [UUID] {
      harness.coordinator.runAutoArchive(startedAt: .distantPast, settings: settings, exempt: exempt()).map(\.id)
    }

    harness.controller.activate(node: panes[1])

    XCTAssertEqual(harness.controller.sidebarController.resolver.visible, Set(panes))
    XCTAssertEqual(exempt(), Set(panes))
    XCTAssertEqual(pass(), [])
    XCTAssertEqual(harness.source.children(of: .today(space)), [other, split])

    harness.controller.activate(node: other)

    XCTAssertEqual(exempt(), [other])
    XCTAssertEqual(pass(), [split])
    XCTAssertEqual(harness.source.children(of: .today(space)), [other])
  }

  // MARK: Restore and relaunch (BH-086)

  /// A restored split whose stored factors do not match its panes keeps those factors. Showing it normalizes them
  /// to equal shares and does not write the model back (`SplitLayout.normalized` on a count mismatch).
  func testMismatchedFactorsStayStoredAndNormalizeOnShow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    let factors = [0.2, 0.3, 0.5]
    let left = NodeSnapshot(kind: .tab(TabItem(url: Self.url("l"), title: "L")), createdAt: Self.now)
    let right = NodeSnapshot(kind: .tab(TabItem(url: Self.url("r"), title: "R")), createdAt: Self.now)
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .horizontal, widthFactors: factors)), createdAt: Self.now,
      children: [left, right])
    let item = ArchivedItem(
      reason: .manual, archivedAt: Self.now, source: .space(world.space), section: .today, snapshot: split)
    _ = try XCTUnwrap(harness.coordinator.restore(item, fallbackSpace: world.space))

    harness.controller.activate(node: left.id)

    XCTAssertEqual(harness.splitView.paneCount, 2)
    XCTAssertEqual(harness.splitView.axis, .sideBySide)
    XCTAssertEqual(harness.splitView.liveFactors, [0.5, 0.5])
    guard case .split(let stored)? = harness.source.sidebar.nodes[split.id]?.kind else {
      return XCTFail("restored split missing")
    }
    XCTAssertEqual(stored.widthFactors, factors, "show does not rewrite the stored factors")
  }

  /// BH-086: archiving a split root through `ArchiveCoordinator` and restoring it puts the split back at the top of
  /// Today with its panes in their order. Showing it gives each pane card its own pane's page, with the stored
  /// factors and orientation, and every pane counts as shown.
  func testRestoredSplitShowsWithItsLayout() throws {
    let factors = [0.25, 0.75]
    let world = try Self.makeWorld(orientation: .vertical, factors: factors)
    let harness = Harness(world.sidebar)
    defer { harness.close() }
    let item = try XCTUnwrap(harness.coordinator.archive([world.split], reason: .manual).first)
    XCTAssertNil(harness.source.node(world.split))

    let restored = try XCTUnwrap(harness.coordinator.restore(item, fallbackSpace: world.space))

    XCTAssertEqual(restored.nodeID, world.split)
    XCTAssertEqual(harness.source.children(of: .today(world.space)), [world.split] + world.today, "top of Today")
    XCTAssertEqual(harness.source.children(of: .split(world.split)), world.panes)
    harness.controller.activate(node: world.split)
    XCTAssertFalse(harness.splitView.isHidden)
    XCTAssertEqual(harness.splitView.axis, .stacked)
    XCTAssertEqual(harness.splitView.paneCount, 2)
    let cards = harness.splitView.paneCards
    XCTAssertEqual(cards.count, world.panes.count)
    for (index, (card, pane)) in zip(cards, world.panes).enumerated() {
      let tab = try XCTUnwrap(harness.controller.engineTab(of: pane), "pane \(index) has a page")
      XCTAssertTrue(card.contentView === harness.engine.contentView(for: tab), "pane card \(index) shows its pane")
    }
    XCTAssertEqual(harness.controller.visibleNodes, Set(world.panes))
    XCTAssertEqual(harness.controller.sidebarController.resolver.visible, Set(world.panes))
    XCTAssertEqual(harness.splitView.liveFactors[0], factors[0], accuracy: 1e-9)
    XCTAssertEqual(harness.splitView.liveFactors[1], factors[1], accuracy: 1e-9)
    let layout = try XCTUnwrap(Self.layout(of: world.split, in: harness.source))
    XCTAssertEqual(layout.orientation, .vertical)
    XCTAssertEqual(layout.widthFactors, factors)
  }

  /// A divider commit survives encode and decode, and the split shows those factors after the source is rebuilt.
  func testRelaunchKeepsSplitLayout() throws {
    let world = try Self.makeWorld()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { Self.now })
    try source.setSplitWidthFactors(world.split, [0.25, 0.75])
    try source.setSplitOrientation(world.split, .vertical)
    let decoded = try SidebarStorageFormat.decode(try SidebarStorageFormat.encode(source.sidebar))
    let restored = ModelSidebarSource(sidebar: decoded, now: { Self.now })
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: restored)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    defer { controller.close() }

    controller.activate(node: world.panes[0])

    XCTAssertEqual(controller.rootView.split.axis, .stacked)
    XCTAssertEqual(controller.rootView.split.paneCount, 2)
    XCTAssertEqual(controller.rootView.split.liveFactors[0], 0.25, accuracy: 1e-9)
    XCTAssertEqual(controller.rootView.split.liveFactors[1], 0.75, accuracy: 1e-9)
    guard case .split(_, let layout)? = restored.node(world.split) else {
      return XCTFail("decoded split missing")
    }
    XCTAssertEqual(layout.orientation, .vertical)
    XCTAssertEqual(layout.widthFactors[0], 0.25, accuracy: 1e-9)
    XCTAssertEqual(layout.widthFactors[1], 0.75, accuracy: 1e-9)
  }
}

/// Accepts archive writes and drops them. `SplitArchiveTests` only checks that the outbox was or was not queued.
private actor DiscardingArchiveStore: ArchiveStoring {
  func add(_ items: [ArchivedItem], onConflict _: ArchiveConflictPolicy) async throws -> Int { items.count }

  func items(matching _: ArchiveFilter, limit _: Int?) async throws -> ArchivePage {
    ArchivePage(items: [], unreadable: 0)
  }

  func remove(_: [NodeID]) async throws {}
}
