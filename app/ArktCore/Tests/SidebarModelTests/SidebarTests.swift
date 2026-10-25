import Foundation
import Testing
import SidebarModel

struct SidebarTests {
  let url = URL(string: "https://example.com/a")!

  func makeSidebar() throws -> Sidebar {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .folder(folder))
    try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    return sidebar
  }

  /// A space whose pinned section holds three tabs x, y, z.
  func makeThreeTabs() throws -> (Sidebar, SpaceID, [NodeID]) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let ids = try ["x", "y", "z"].map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: $0, in: .pinned(space))
    }
    return (sidebar, space, ids)
  }

  // MARK: - Indexed insertion (#293)

  /// Cmd-T opens on top (BH-079, maintainer decision on #293): a tab added at index 0 lands before its
  /// siblings; no index appends, as before.
  @Test func aTabAddedAtIndexZeroLandsOnTop() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let a = try sidebar.addTab(url: url, title: "A", in: .today(space))
    let b = try sidebar.addTab(url: url, title: "B", in: .today(space))
    #expect(sidebar.children(of: .today(space)) == [a, b])
    let c = try sidebar.addTab(url: url, title: "C", in: .today(space), at: 0)
    #expect(sidebar.children(of: .today(space)) == [c, a, b])
  }

  @Test func anOutOfRangeInsertIndexIsClamped() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let a = try sidebar.addTab(url: url, title: "A", in: .today(space))
    let b = try sidebar.addTab(url: url, title: "B", in: .today(space), at: 99)
    #expect(sidebar.children(of: .today(space)) == [a, b])
    let c = try sidebar.addTab(url: url, title: "C", in: .today(space), at: -3)
    #expect(sidebar.children(of: .today(space)) == [c, a, b])
  }

  // MARK: - Structure

  @Test func spacesKeepInsertionOrder() {
    var sidebar = Sidebar()
    let a = sidebar.addSpace(title: "A")
    let b = sidebar.addSpace(title: "B")
    #expect(sidebar.spaceOrder == [a, b])
  }

  @Test func childrenAreOrdered() throws {
    let sidebar = try makeSidebar()
    let space = sidebar.spaceOrder[0]
    let pinned = sidebar.children(of: .pinned(space))
    #expect(pinned.count == 1)
    guard case .folder(let folder) = sidebar.nodes[pinned[0]]?.kind else {
      Issue.record("expected folder"); return
    }
    #expect(folder.title == "Docs")
    #expect(sidebar.children(of: .folder(pinned[0])).count == 1)
    #expect(sidebar.children(of: .today(space)).count == 1)
  }

  @Test func addSplitHoldsTabs() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .vertical, widthFactors: [0.5, 0.5], in: .pinned(space))
    try sidebar.addTab(url: url, title: "L", in: .split(split))
    try sidebar.addTab(url: url, title: "R", in: .split(split))
    #expect(sidebar.children(of: .split(split)).count == 2)
    guard case .split(let value) = sidebar.nodes[split]?.kind else {
      Issue.record("expected split"); return
    }
    #expect(value.orientation == .vertical)
    #expect(value.widthFactors == [0.5, 0.5])
  }

  @Test func favoritesAreSeparatedPerProfile() throws {
    var sidebar = Sidebar()
    let a = try sidebar.addTab(url: url, title: "A", in: .favorites(profile: "default"))
    let b = try sidebar.addTab(url: url, title: "B", in: .favorites(profile: "work"))
    #expect(sidebar.children(of: .favorites(profile: "default")) == [a])
    #expect(sidebar.children(of: .favorites(profile: "work")) == [b])
  }

  // MARK: - Add validation

  @Test func addRejectsUnknownSpace() throws {
    var sidebar = Sidebar()
    let missing = SpaceID()
    #expect(throws: SidebarError.invalidDestination(.pinned(missing))) {
      try sidebar.addFolder(title: "F", in: .pinned(missing))
    }
    #expect(throws: SidebarError.invalidDestination(.today(missing))) {
      try sidebar.addTab(url: url, title: "T", in: .today(missing))
    }
    #expect(sidebar == Sidebar())
  }

  @Test func addRejectsNonFolderAsFolder() throws {
    var (sidebar, _, ids) = try makeThreeTabs()
    let before = sidebar
    let missing = NodeID()
    #expect(throws: SidebarError.invalidDestination(.folder(ids[0]))) {
      try sidebar.addTab(url: url, title: "T", in: .folder(ids[0]))
    }
    #expect(throws: SidebarError.invalidDestination(.folder(missing))) {
      try sidebar.addTab(url: url, title: "T", in: .folder(missing))
    }
    #expect(sidebar == before)
  }

  @Test func addRejectsNonTabInSplit() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    let before = sidebar
    #expect(throws: SidebarError.invalidDestination(.split(split))) {
      try sidebar.addFolder(title: "Inner", in: .split(split))
    }
    #expect(throws: SidebarError.invalidDestination(.split(split))) {
      try sidebar.addSplit(orientation: .vertical, widthFactors: [1], in: .split(split))
    }
    #expect(throws: SidebarError.invalidDestination(.split(folder))) {
      try sidebar.addTab(url: url, title: "T", in: .split(folder))
    }
    #expect(sidebar == before)
  }

  // MARK: - Move

  @Test func moveReordersAndReparents() throws {
    var sidebar = try makeSidebar()
    let space = sidebar.spaceOrder[0]
    let todayTab = sidebar.children(of: .today(space))[0]
    try sidebar.move(todayTab, to: .pinned(space), at: 0)
    #expect(sidebar.children(of: .today(space)).isEmpty)
    #expect(sidebar.children(of: .pinned(space)).first == todayTab)
    #expect(sidebar.nodes[todayTab]?.parent == .pinned(space))
  }

  @Test func moveClampsIndex() throws {
    var sidebar = try makeSidebar()
    let space = sidebar.spaceOrder[0]
    let todayTab = sidebar.children(of: .today(space))[0]
    try sidebar.move(todayTab, to: .pinned(space), at: 99)
    #expect(sidebar.children(of: .pinned(space)).last == todayTab)
    try sidebar.move(todayTab, to: .pinned(space), at: -5)
    #expect(sidebar.children(of: .pinned(space)).first == todayTab)
    #expect(sidebar.children(of: .pinned(space)).count == 2)
  }

  @Test func moveWithinParentUsesIndexBeforeRemoval() throws {
    let (base, space, ids) = try makeThreeTabs()
    let (x, y, z) = (ids[0], ids[1], ids[2])

    var sidebar = base
    try sidebar.move(x, to: .pinned(space), at: 2)
    #expect(sidebar.children(of: .pinned(space)) == [y, x, z])

    sidebar = base
    try sidebar.move(x, to: .pinned(space), at: 3)
    #expect(sidebar.children(of: .pinned(space)) == [y, z, x])

    sidebar = base
    try sidebar.move(z, to: .pinned(space), at: 0)
    #expect(sidebar.children(of: .pinned(space)) == [z, x, y])
  }

  @Test func moveIntoOwnSubtreeThrows() throws {
    var sidebar = try makeSidebar()
    let space = sidebar.spaceOrder[0]
    let outer = sidebar.children(of: .pinned(space))[0]
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(outer))
    let before = sidebar
    #expect(throws: SidebarError.cycle) {
      try sidebar.move(outer, to: .folder(inner), at: 0)
    }
    #expect(throws: SidebarError.cycle) {
      try sidebar.move(outer, to: .folder(outer), at: 0)
    }
    #expect(sidebar == before)
  }

  @Test func moveOfUnknownNodeThrows() throws {
    var sidebar = try makeSidebar()
    let before = sidebar
    let missing = NodeID()
    #expect(throws: SidebarError.unknownNode(missing)) {
      try sidebar.move(missing, to: .favorites(profile: "default"), at: 0)
    }
    #expect(sidebar == before)
  }

  @Test func moveRejectsInvalidDestinations() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .vertical, widthFactors: [0.5, 0.5], in: .pinned(space))
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    let tab = try sidebar.addTab(url: url, title: "T", in: .today(space))
    let missingSpace = SpaceID()
    let before = sidebar

    #expect(throws: SidebarError.invalidDestination(.pinned(missingSpace))) {
      try sidebar.move(tab, to: .pinned(missingSpace), at: 0)
    }
    #expect(throws: SidebarError.invalidDestination(.today(missingSpace))) {
      try sidebar.move(tab, to: .today(missingSpace), at: 0)
    }
    #expect(throws: SidebarError.invalidDestination(.folder(tab))) {
      try sidebar.move(folder, to: .folder(tab), at: 0)
    }
    #expect(throws: SidebarError.invalidDestination(.folder(split))) {
      try sidebar.move(tab, to: .folder(split), at: 0)
    }
    #expect(throws: SidebarError.invalidDestination(.split(folder))) {
      try sidebar.move(tab, to: .split(folder), at: 0)
    }
    #expect(throws: SidebarError.invalidDestination(.split(split))) {
      try sidebar.move(folder, to: .split(split), at: 0)
    }
    #expect(sidebar == before)

    try sidebar.move(tab, to: .split(split), at: 0)
    #expect(sidebar.children(of: .split(split)) == [tab])
  }

  // MARK: - Remove

  @Test func removeDropsDescendants() throws {
    var sidebar = try makeSidebar()
    let space = sidebar.spaceOrder[0]
    let folder = sidebar.children(of: .pinned(space))[0]
    let todayTab = sidebar.children(of: .today(space))[0]
    sidebar.remove(folder)
    #expect(sidebar.children(of: .pinned(space)).isEmpty)
    #expect(sidebar.children(of: .folder(folder)).isEmpty)
    #expect(Set(sidebar.nodes.keys) == [todayTab])
    #expect(sidebar.children(of: .today(space)) == [todayTab])
  }

  @Test func removeSplitRemovesItsTabs() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .vertical, widthFactors: [0.5, 0.5], in: .pinned(space))
    try sidebar.addTab(url: url, title: "L", in: .split(split))
    try sidebar.addTab(url: url, title: "R", in: .split(split))
    sidebar.remove(split)
    #expect(sidebar.nodes.isEmpty)
    #expect(sidebar.children(of: .split(split)).isEmpty)
    #expect(sidebar.children(of: .pinned(space)).isEmpty)
  }

  @Test func removeMiddleSiblingKeepsOrder() throws {
    var (sidebar, space, ids) = try makeThreeTabs()
    sidebar.remove(ids[1])
    #expect(sidebar.children(of: .pinned(space)) == [ids[0], ids[2]])
  }

  // MARK: - Remove pane

  /// A Today tab, a split with `widths.count` panes, then another Today tab.
  func makeSplit(widths: [Double] = [0.5, 0.25, 0.25]) throws -> (Sidebar, SpaceID, NodeID, [NodeID], [NodeID]) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let before = try sidebar.addTab(url: url, title: "Before", in: .today(space))
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: widths, in: .today(space))
    let panes = try (0..<widths.count).map { try sidebar.addTab(url: url, title: "P\($0)", in: .split(split)) }
    let after = try sidebar.addTab(url: url, title: "After", in: .today(space))
    return (sidebar, space, split, panes, [before, after])
  }

  @Test func removePaneDropsItsWidthAndRescalesTheRest() throws {
    var (sidebar, _, split, panes, _) = try makeSplit()
    sidebar.removePane(panes[0])
    #expect(sidebar.nodes[panes[0]] == nil)
    #expect(sidebar.children(of: .split(split)) == [panes[1], panes[2]])
    #expect(sidebar.nodes[split]?.kind == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])))
  }

  @Test func removePaneLeavingOnePaneReplacesTheSplitWithThatTab() throws {
    var (sidebar, space, split, panes, today) = try makeSplit(widths: [0.5, 0.5])
    sidebar.removePane(panes[1])
    #expect(sidebar.nodes[split] == nil)
    #expect(sidebar.children(of: .split(split)).isEmpty)
    #expect(sidebar.children(of: .today(space)) == [today[0], panes[0], today[1]])
    #expect(sidebar.nodes[panes[0]]?.parent == .today(space))
    #expect(Set(sidebar.nodes.keys) == [today[0], panes[0], today[1]])
  }

  @Test func removeTheOnlyPaneRemovesTheSplit() throws {
    var (sidebar, space, split, panes, today) = try makeSplit(widths: [1])
    sidebar.removePane(panes[0])
    #expect(sidebar.nodes[split] == nil)
    #expect(sidebar.children(of: .today(space)) == today)
  }

  @Test func removePaneOfANonPaneIsPlainRemove() throws {
    var (sidebar, space, ids) = try makeThreeTabs()
    sidebar.removePane(ids[1])
    #expect(sidebar.children(of: .pinned(space)) == [ids[0], ids[2]])
  }

  @Test func removeUnknownIsNoOp() throws {
    var sidebar = try makeSidebar()
    let before = sidebar
    sidebar.remove(NodeID())
    #expect(sidebar == before)
  }

  @Test func payloadTypesUseItemNames() {
    let tab = TabItem(url: url, title: "T")
    let folder = FolderItem(title: "F")
    let split = SplitItem(orientation: .horizontal, widthFactors: [1])
    #expect(NodeKind.tab(tab) != .folder(folder))
    #expect(NodeKind.split(split) != .folder(folder))
  }

  @Test func updateTabChangesOnlyGivenFields() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let tab = try sidebar.addTab(url: URL(string: "https://a.example")!, title: "A", in: .today(space))
    let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    try sidebar.updateTab(tab, title: "B", lastActiveAt: when)
    guard case .tab(let item)? = sidebar.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.url == URL(string: "https://a.example")!)
    #expect(item.title == "B")
    #expect(item.lastActiveAt == when)
    #expect(sidebar.children(of: .today(space)) == [tab])          // position untouched
  }

  @Test func updateTabRejectsUnknownAndNonTabNodes() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    let before = sidebar
    #expect(throws: SidebarError.unknownNode(folder)) { try sidebar.updateTab(folder, title: "X") }
    let ghost = NodeID()
    #expect(throws: SidebarError.unknownNode(ghost)) { try sidebar.updateTab(ghost, title: "X") }
    #expect(sidebar == before)
  }

  // MARK: - Space removal

  @Test func removeSpaceDropsTheSpaceAndItsSections() throws {
    var sidebar = try makeSidebar()
    let work = sidebar.spaceOrder[0]
    let other = sidebar.addSpace(title: "Other")
    let kept = try sidebar.addTab(url: url, title: "Kept", in: .today(other))
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [1, 1], in: .today(work))
    let pane = try sidebar.addTab(url: url, title: "P", in: .split(split))
    let favorite = try sidebar.addTab(url: url, title: "F", in: .favorites(profile: "default"))
    let removed = Set(sidebar.nodes.keys).subtracting([kept, favorite])
    sidebar.removeSpace(work)
    #expect(sidebar.spaces[work] == nil)
    #expect(sidebar.spaceOrder == [other])
    #expect(sidebar.children(of: .pinned(work)).isEmpty)
    #expect(sidebar.children(of: .today(work)).isEmpty)
    #expect(removed.contains(pane))
    #expect(removed.allSatisfy { sidebar.nodes[$0] == nil })
    #expect(Set(sidebar.nodes.keys) == [kept, favorite])
    #expect(Set(sidebar.childOrder.keys) == [.today(other), .favorites(profile: "default")])
  }

  @Test func removeUnknownSpaceIsNoOp() throws {
    var sidebar = try makeSidebar()
    let before = sidebar
    sidebar.removeSpace(SpaceID())
    #expect(sidebar == before)
  }
}
