import Foundation
import Testing
import SidebarModel

struct SplitOperationsTests {
  let url = URL(string: "https://example.com/t")!

  /// A space with Pinned `[p0, p1]`, a folder in Pinned holding `[f0]`, and Today `[a, b, c]`.
  struct World {
    var sidebar: Sidebar
    let space: SpaceID
    let pinned: [NodeID]
    let folder: NodeID
    let folderTabs: [NodeID]
    let today: [NodeID]
  }

  func makeWorld() throws -> World {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try ["p0", "p1"].map { try sidebar.addTab(url: url, title: $0, in: .pinned(space)) }
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    let f0 = try sidebar.addTab(url: url, title: "f0", in: .folder(folder))
    let today = try ["a", "b", "c"].map { try sidebar.addTab(url: url, title: $0, in: .today(space)) }
    return World(sidebar: sidebar, space: space, pinned: pinned, folder: folder, folderTabs: [f0], today: today)
  }

  func splitItem(_ sidebar: Sidebar, _ id: NodeID) -> SplitItem? {
    if case .split(let item)? = sidebar.nodes[id]?.kind { item } else { nil }
  }

  /// Adds `count` extra Today tabs and returns their ids.
  func addTodayTabs(_ sidebar: inout Sidebar, _ space: SpaceID, count: Int) throws -> [NodeID] {
    try (0..<count).map { try sidebar.addTab(url: url, title: "x\($0)", in: .today(space)) }
  }

  // MARK: - createSplit

  @Test func createSplitTakesFirstTabsPlace() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [b, a])
    #expect(world.sidebar.children(of: .today(world.space)) == [split, c])
    #expect(world.sidebar.children(of: .split(split)) == [b, a])
    #expect(splitItem(world.sidebar, split) == SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5]))
    #expect(world.sidebar.nodes[split]?.parent == .today(world.space))
    #expect(world.sidebar.nodes[a]?.parent == .split(split))
  }

  @Test func createSplitInPinnedStaysPinned() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.pinned[1], world.today[0]], orientation: .vertical)
    #expect(world.sidebar.children(of: .pinned(world.space)) == [world.pinned[0], split, world.folder])
    #expect(world.sidebar.section(of: split) == .pinned(world.space))
    #expect(world.sidebar.children(of: .split(split)) == [world.pinned[1], world.today[0]])
    #expect(world.sidebar.children(of: .today(world.space)) == [world.today[1], world.today[2]])
    #expect(splitItem(world.sidebar, split)?.orientation == .vertical)
  }

  @Test func createSplitPullsPaneOutOfAnotherSplitAndCollapsesIt() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let old = try world.sidebar.createSplit(of: [a, b])
    let new = try world.sidebar.createSplit(of: [c, b])
    #expect(world.sidebar.nodes[old] == nil)
    #expect(world.sidebar.children(of: .split(old)).isEmpty)
    #expect(world.sidebar.children(of: .today(world.space)) == [a, new])
    #expect(world.sidebar.nodes[a]?.parent == .today(world.space))
    #expect(world.sidebar.children(of: .split(new)) == [c, b])
  }

  @Test func createSplitPullingFromALargerSplitRescalesIt() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let old = try world.sidebar.createSplit(of: [a, b, c])
    try world.sidebar.setSplitWidthFactors(old, [0.5, 0.25, 0.25])
    let new = try world.sidebar.createSplit(of: [world.pinned[0], a])
    #expect(world.sidebar.children(of: .split(old)) == [b, c])
    #expect(splitItem(world.sidebar, old)?.widthFactors == [0.5, 0.5])
    #expect(world.sidebar.children(of: .split(new)) == [world.pinned[0], a])
  }

  @Test func createSplitWithFirstTabInASplitLandsAfterThatSplit() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let old = try world.sidebar.createSplit(of: [a, b, c])
    let new = try world.sidebar.createSplit(of: [b, world.pinned[0]])
    #expect(world.sidebar.children(of: .today(world.space)) == [old, new])
    #expect(world.sidebar.children(of: .split(old)) == [a, c])
    #expect(world.sidebar.children(of: .split(new)) == [b, world.pinned[0]])
  }

  @Test func createSplitRejectsOneOrFiveTabsDuplicatesAndNonTabs() throws {
    var world = try makeWorld()
    let extra = try addTodayTabs(&world.sidebar, world.space, count: 2)
    let before = world.sidebar
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    #expect(throws: SidebarError.invalidSplit(a)) { try world.sidebar.createSplit(of: [a]) }
    #expect(throws: SidebarError.invalidSplit(a)) { try world.sidebar.createSplit(of: [a, b, c] + extra) }
    #expect(throws: SidebarError.invalidSplit(b)) { try world.sidebar.createSplit(of: [a, b, b]) }
    #expect(throws: SidebarError.invalidSplit(world.folder)) { try world.sidebar.createSplit(of: [a, world.folder]) }
    #expect(throws: (any Error).self) { try world.sidebar.createSplit(of: []) }
    let missing = NodeID()
    #expect(throws: SidebarError.unknownNode(missing)) { try world.sidebar.createSplit(of: [a, missing]) }
    #expect(world.sidebar == before)
  }

  // MARK: - addPane and the cap

  @Test func addPaneEqualizesAndCapsAtFour() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b])
    try world.sidebar.setSplitWidthFactors(split, [0.75, 0.25])
    try world.sidebar.addPane(c, to: split)
    #expect(world.sidebar.children(of: .split(split)) == [a, b, c])
    let third: Double = 1.0 / 3
    #expect(splitItem(world.sidebar, split)?.widthFactors == [third, third, third])
    try world.sidebar.addPane(world.pinned[0], to: split, at: 0)
    #expect(world.sidebar.children(of: .split(split)) == [world.pinned[0], a, b, c])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.25, 0.25, 0.25, 0.25])
    #expect(world.sidebar.children(of: .split(split)).count == Sidebar.maximumSplitPanes)
    let before = world.sidebar
    #expect(throws: SidebarError.splitFull(split)) { try world.sidebar.addPane(world.pinned[1], to: split) }
    #expect(world.sidebar == before)
  }

  @Test func addPaneRejectsNonTabsPanesOfTheSameSplitAndNonSplits() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b])
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(world.folder)) { try world.sidebar.addPane(world.folder, to: split) }
    #expect(throws: SidebarError.invalidSplit(a)) { try world.sidebar.addPane(a, to: split) }
    #expect(throws: SidebarError.invalidSplit(world.folder)) { try world.sidebar.addPane(c, to: world.folder) }
    let missing = NodeID()
    #expect(throws: SidebarError.unknownNode(missing)) { try world.sidebar.addPane(missing, to: split) }
    #expect(throws: SidebarError.unknownNode(missing)) { try world.sidebar.addPane(c, to: missing) }
    #expect(world.sidebar == before)
  }

  @Test func moveIntoFullSplitThrowsSplitFull() throws {
    var world = try makeWorld()
    let extra = try addTodayTabs(&world.sidebar, world.space, count: 1)
    let split = try world.sidebar.createSplit(of: world.today + extra)
    let before = world.sidebar
    #expect(throws: SidebarError.splitFull(split)) {
      try world.sidebar.move(world.pinned[0], to: .split(split), at: 0)
    }
    #expect(world.sidebar == before)
    // Reordering inside a full split is still allowed.
    try world.sidebar.move(world.today[0], to: .split(split), at: 4)
    #expect(world.sidebar.children(of: .split(split)) == [world.today[1], world.today[2], extra[0], world.today[0]])
  }

  @Test func insertOfFivePaneSnapshotStillLoads() throws {
    var world = try makeWorld()
    let date = Date(timeIntervalSinceReferenceDate: 0)
    let panes = (0..<5).map { _ in
      NodeSnapshot(id: NodeID(), kind: .tab(TabItem(url: url, title: "T")), createdAt: date, children: [])
    }
    let split = NodeSnapshot(
      id: NodeID(), kind: .split(SplitItem(orientation: .horizontal, widthFactors: [0.2, 0.2, 0.2, 0.2, 0.2])),
      createdAt: date, children: panes)
    try world.sidebar.insert(split, in: .today(world.space))
    #expect(world.sidebar.children(of: .split(split.id)).count == 5)
  }

  // MARK: - separatePane, separateSplit, expandPane

  @Test func separatePaneLandsAfterSplitAndRescales() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b, c])
    try world.sidebar.setSplitWidthFactors(split, [0.5, 0.25, 0.25])
    try world.sidebar.separatePane(a)
    #expect(world.sidebar.children(of: .today(world.space)) == [split, a])
    #expect(world.sidebar.nodes[a]?.parent == .today(world.space))
    #expect(world.sidebar.children(of: .split(split)) == [b, c])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.5, 0.5])
  }

  @Test func separatePaneOfTwoCollapsesToSurvivorThenSeparated() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b])
    try world.sidebar.separatePane(a)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .today(world.space)) == [b, a, c])
    #expect(world.sidebar.nodes[b]?.parent == .today(world.space))
    #expect(world.sidebar.nodes[a]?.parent == .today(world.space))
  }

  @Test func separatePaneRejectsANonPane() throws {
    var world = try makeWorld()
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(world.today[0])) { try world.sidebar.separatePane(world.today[0]) }
    let missing = NodeID()
    #expect(throws: SidebarError.unknownNode(missing)) { try world.sidebar.separatePane(missing) }
    #expect(world.sidebar == before)
  }

  @Test func separateSplitPutsPanesInPlaceInOrder() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [world.pinned[1], b, a])
    let panes = try world.sidebar.separateSplit(split)
    #expect(panes == [world.pinned[1], b, a])
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .pinned(world.space)) == [world.pinned[0], world.pinned[1], b, a, world.folder])
    #expect(world.sidebar.children(of: .today(world.space)) == [c])
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(c)) { try world.sidebar.separateSplit(c) }
    #expect(world.sidebar == before)
  }

  @Test func expandPaneKeepsFocusedFirst() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b, c])
    try world.sidebar.expandPane(b)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .today(world.space)) == [b, a, c])
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(b)) { try world.sidebar.expandPane(b) }
    #expect(world.sidebar == before)
  }

  // MARK: - movePane, widths, orientation

  @Test func movePaneReordersFactorsWithPanes() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b, c])
    try world.sidebar.setSplitWidthFactors(split, [0.5, 0.25, 0.25])
    try world.sidebar.movePane(a, to: 3)
    #expect(world.sidebar.children(of: .split(split)) == [b, c, a])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.25, 0.25, 0.5])
    try world.sidebar.movePane(a, to: 1)
    #expect(world.sidebar.children(of: .split(split)) == [b, a, c])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.25, 0.5, 0.25])
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(world.pinned[0])) { try world.sidebar.movePane(world.pinned[0], to: 0) }
    #expect(world.sidebar == before)
  }

  @Test func setSplitWidthFactorsNormalizesAndRejectsBadInput() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.setSplitWidthFactors(split, [2, 6])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.25, 0.75])
    try world.sidebar.setSplitWidthFactors(split, [2, 2])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.5, 0.5])
    let before = world.sidebar
    for bad: [Double] in [[1], [1, 1, 1], [0, 1], [-1, 2], [.nan, 1], [.infinity, 1],
                          [.greatestFiniteMagnitude, .greatestFiniteMagnitude]] {
      #expect(throws: SidebarError.invalidSplit(split)) { try world.sidebar.setSplitWidthFactors(split, bad) }
    }
    #expect(throws: SidebarError.invalidSplit(world.today[2])) {
      try world.sidebar.setSplitWidthFactors(world.today[2], [1])
    }
    #expect(world.sidebar == before)
  }

  @Test func setSplitOrientationChangesOnlyOrientation() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.setSplitWidthFactors(split, [0.25, 0.75])
    var expected = world.sidebar
    try world.sidebar.setSplitOrientation(split, .vertical)
    #expect(splitItem(world.sidebar, split) == SplitItem(orientation: .vertical, widthFactors: [0.25, 0.75]))
    try expected.setSplitOrientation(split, .vertical)
    #expect(world.sidebar == expected)
    try world.sidebar.setSplitOrientation(split, .horizontal)
    #expect(splitItem(world.sidebar, split)?.orientation == .horizontal)
    let before = world.sidebar
    let missing = NodeID()
    #expect(throws: SidebarError.unknownNode(missing)) { try world.sidebar.setSplitOrientation(missing, .vertical) }
    #expect(throws: SidebarError.invalidSplit(world.folder)) {
      try world.sidebar.setSplitOrientation(world.folder, .vertical)
    }
    #expect(world.sidebar == before)
  }

  // MARK: - removePane after the refactor

  @Test func removePaneUnchanged() throws {
    var world = try makeWorld()
    let (a, b, c) = (world.today[0], world.today[1], world.today[2])
    let split = try world.sidebar.createSplit(of: [a, b, c])
    try world.sidebar.setSplitWidthFactors(split, [0.5, 0.25, 0.25])
    world.sidebar.removePane(a)
    #expect(world.sidebar.nodes[a] == nil)
    #expect(world.sidebar.children(of: .split(split)) == [b, c])
    #expect(splitItem(world.sidebar, split)?.widthFactors == [0.5, 0.5])
    world.sidebar.removePane(c)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.nodes[c] == nil)
    #expect(world.sidebar.children(of: .today(world.space)) == [b])
    #expect(world.sidebar.nodes[b]?.parent == .today(world.space))
    world.sidebar.removePane(b)
    #expect(world.sidebar.children(of: .today(world.space)).isEmpty)
  }
}
