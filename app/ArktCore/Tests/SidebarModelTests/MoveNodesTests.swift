import Foundation
import Testing
import SidebarModel

/// Sidebar drag and drop (#104): `moveNodes(_:to:at:)` moves a dragged set as one step. Panes that leave their
/// split shrink it (a split never keeps one pane), a tab's fields (URL, idle clock) travel unchanged, and a refused
/// move leaves the sidebar untouched.
struct MoveNodesTests {
  private static let stamp = Date(timeIntervalSinceReferenceDate: 700_000_000)

  /// One Space with Pinned `[p0, p1]`, Today `[t0, t1, t2, t3]` and a folder in Pinned.
  private struct World {
    var sidebar = Sidebar()
    var space: SpaceID
    var other: SpaceID
    var pinned: [NodeID]
    var today: [NodeID]
    var folder: NodeID
  }

  private func url(_ name: String) -> URL { URL(string: "https://example.com/\(name)")! }

  private func makeWorld() throws -> World {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let other = sidebar.addSpace(title: "Home")
    let pinned = try (0..<2).map {
      try sidebar.addTab(url: url("p\($0)"), title: "p\($0)", lastActiveAt: Self.stamp, in: .pinned(space))
    }
    let today = try (0..<4).map {
      try sidebar.addTab(url: url("t\($0)"), title: "t\($0)", lastActiveAt: Self.stamp, in: .today(space))
    }
    let folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    return World(sidebar: sidebar, space: space, other: other, pinned: pinned, today: today, folder: folder)
  }

  // MARK: Reorder

  @Test func oneNodeMovesLikeMove() throws {
    var world = try makeWorld()
    try world.sidebar.moveNodes([world.today[0]], to: .today(world.space), at: 3)
    #expect(world.sidebar.children(of: .today(world.space))
      == [world.today[1], world.today[2], world.today[0], world.today[3]])
  }

  @Test func aSetKeepsItsOrderAndLandsAtTheProposedIndex() throws {
    var world = try makeWorld()
    // [t0, t1, t2, t3]: t0 and t2 dropped between t3 and the end (index 4, measured before removal).
    try world.sidebar.moveNodes([world.today[0], world.today[2]], to: .today(world.space), at: 4)
    #expect(world.sidebar.children(of: .today(world.space))
      == [world.today[1], world.today[3], world.today[0], world.today[2]])
  }

  @Test func aSetDroppedInsideItselfStaysTogether() throws {
    var world = try makeWorld()
    // Dropped at index 2 (between t1 and t2): t1 and t3 gather there, before t2.
    try world.sidebar.moveNodes([world.today[3], world.today[1]], to: .today(world.space), at: 2)
    #expect(world.sidebar.children(of: .today(world.space))
      == [world.today[0], world.today[3], world.today[1], world.today[2]])
  }

  @Test func repeatedIdsAndDescendantsOfMovedNodesMoveOnce() throws {
    var world = try makeWorld()
    try world.sidebar.move(world.pinned[1], to: .folder(world.folder), at: 0)
    try world.sidebar.moveNodes([world.folder, world.pinned[1], world.folder], to: .today(world.space), at: 0)
    #expect(world.sidebar.children(of: .today(world.space)).first == world.folder)
    #expect(world.sidebar.children(of: .folder(world.folder)) == [world.pinned[1]])
  }

  // MARK: Sections (pin, unpin, favorite, other Space, folder)

  @Test func movingAboveTheDividerPinsAndBelowUnpins() throws {
    var world = try makeWorld()
    try world.sidebar.moveNodes([world.today[1]], to: .pinned(world.space), at: 1)
    #expect(world.sidebar.children(of: .pinned(world.space))
      == [world.pinned[0], world.today[1], world.pinned[1], world.folder])
    try world.sidebar.moveNodes([world.pinned[0]], to: .today(world.space), at: 0)
    #expect(world.sidebar.children(of: .today(world.space)).first == world.pinned[0])
  }

  @Test func aSetMovesToAnotherSpace() throws {
    var world = try makeWorld()
    try world.sidebar.moveNodes([world.today[0], world.pinned[0]], to: .today(world.other), at: 0)
    #expect(world.sidebar.children(of: .today(world.other)) == [world.today[0], world.pinned[0]])
  }

  @Test func aTabDroppedOnAFolderJoinsIt() throws {
    var world = try makeWorld()
    try world.sidebar.moveNodes([world.today[2]], to: .folder(world.folder), at: Int.max)
    #expect(world.sidebar.children(of: .folder(world.folder)) == [world.today[2]])
  }

  @Test func aFolderCannotMoveIntoItself() throws {
    var world = try makeWorld()
    let before = world.sidebar
    #expect(throws: SidebarError.cycle) {
      try world.sidebar.moveNodes([world.today[0], world.folder], to: .folder(world.folder), at: 0)
    }
    #expect(world.sidebar == before)
  }

  @Test func favoritesFullRefusesTheWholeSet() throws {
    var world = try makeWorld()
    for index in 0..<(Sidebar.maximumFavorites - 1) {
      try world.sidebar.addTab(url: url("f\(index)"), title: "f", in: .favorites(profile: "default"))
    }
    let before = world.sidebar
    #expect(throws: SidebarError.favoritesFull("default")) {
      try world.sidebar.moveNodes([world.today[0], world.today[1]], to: .favorites(profile: "default"), at: 0)
    }
    #expect(world.sidebar == before)
  }

  @Test func anUnknownIdRefusesTheWholeSet() throws {
    var world = try makeWorld()
    let before = world.sidebar
    let unknown = NodeID()
    #expect(throws: SidebarError.unknownNode(unknown)) {
      try world.sidebar.moveNodes([world.today[0], unknown], to: .pinned(world.space), at: 0)
    }
    #expect(world.sidebar == before)
  }

  @Test func aSplitIsNotADestination() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    let before = world.sidebar
    #expect(throws: SidebarError.invalidSplit(split)) {
      try world.sidebar.moveNodes([world.today[2]], to: .split(split), at: 0)
    }
    #expect(world.sidebar == before)
  }

  // MARK: Split View integrity (bug class: a drag that breaks a Split View)

  @Test func aPaneLeavingATwoPaneSplitDissolvesItIntoATab() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.moveNodes([world.today[1]], to: .pinned(world.space), at: 0)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .today(world.space)) == [world.today[0], world.today[2], world.today[3]])
    #expect(world.sidebar.children(of: .pinned(world.space)).first == world.today[1])
  }

  @Test func aPaneLeavingALargerSplitShrinksItAndKeepsTheFactorsWhole() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1], world.today[2]])
    try world.sidebar.setSplitWidthFactors(split, [0.5, 0.25, 0.25])
    try world.sidebar.moveNodes([world.today[0]], to: .today(world.space), at: 0)
    #expect(world.sidebar.children(of: .split(split)) == [world.today[1], world.today[2]])
    guard case .split(let item)? = world.sidebar.nodes[split]?.kind else {
      Issue.record("the split is gone")
      return
    }
    #expect(item.widthFactors.count == 2)
    #expect(abs(item.widthFactors.reduce(0, +) - 1) < 1e-9)
  }

  @Test func everyPaneLeavingASplitRemovesIt() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.moveNodes([world.today[0], world.today[1]], to: .today(world.other), at: 0)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .today(world.other)) == [world.today[0], world.today[1]])
  }

  @Test func aWholeSplitMovesIntact() throws {
    var world = try makeWorld()
    let split = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.moveNodes([split], to: .folder(world.folder), at: 0)
    #expect(world.sidebar.children(of: .split(split)) == [world.today[0], world.today[1]])
    #expect(world.sidebar.nodes[split]?.parent == .folder(world.folder))
  }

  @Test func noLocationEverHoldsAOnePaneSplitAfterAnyPaneMove() throws {
    for paneCount in 2...Sidebar.maximumSplitPanes {
      for leaving in 0..<paneCount {
        var sidebar = Sidebar()
        let space = sidebar.addSpace(title: "S")
        let tabs = try (0..<paneCount).map { try sidebar.addTab(url: url("x\($0)"), title: "x", in: .today(space)) }
        let split = try sidebar.createSplit(of: tabs)
        try sidebar.moveNodes([tabs[leaving]], to: .pinned(space), at: 0)
        let panes = sidebar.children(of: .split(split))
        #expect(panes.isEmpty || panes.count >= 2, "\(paneCount) panes, pane \(leaving) left")
      }
    }
  }

  // MARK: Tab fields travel (bug classes: stale URL, lost lastActiveAt)

  @Test func aMoveKeepsEveryTabField() throws {
    var world = try makeWorld()
    try world.sidebar.rename(world.today[0], to: "Custom")
    let before = world.sidebar.nodes[world.today[0]]?.kind
    try world.sidebar.moveNodes([world.today[0]], to: .pinned(world.other), at: 0)
    try world.sidebar.moveNodes([world.today[0]], to: .folder(world.folder), at: 0)
    try world.sidebar.moveNodes([world.today[0]], to: .favorites(profile: "default"), at: 0)
    #expect(world.sidebar.nodes[world.today[0]]?.kind == before)
  }

  @Test func aPaneThatLeavesKeepsItsIdleClockAndSoDoesTheSurvivor() throws {
    var world = try makeWorld()
    _ = try world.sidebar.createSplit(of: [world.today[0], world.today[1]])
    try world.sidebar.moveNodes([world.today[0]], to: .today(world.other), at: 0)
    for id in [world.today[0], world.today[1]] {
      guard case .tab(let tab)? = world.sidebar.nodes[id]?.kind else {
        Issue.record("not a tab")
        continue
      }
      #expect(tab.lastActiveAt == Self.stamp)
    }
  }
}
