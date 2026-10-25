import Archive
import Foundation
import Testing
import SidebarModel

struct ArchiverTests {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  struct World {
    var sidebar = Sidebar()
    var work: SpaceID
    var folder: NodeID
    var nested: NodeID
    var today: [NodeID]
    var favorite: NodeID
  }

  static func makeWorld() throws -> World {
    var sidebar = Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(work))
    let nested = try sidebar.addTab(url: url("n"), title: "Nested", in: .folder(folder))
    let t1 = try sidebar.addTab(url: url("1"), title: "One", customTitle: "Uno", in: .today(work))
    let t2 = try sidebar.addTab(url: url("2"), title: "Two", in: .today(work))
    let favorite = try sidebar.addTab(url: url("f"), title: "Fav", in: .favorites(profile: "default"))
    return World(sidebar: sidebar, work: work, folder: folder, nested: nested, today: [t1, t2], favorite: favorite)
  }

  static func tab(_ path: String) -> NodeSnapshot {
    NodeSnapshot(kind: .tab(TabItem(url: url(path), title: path.uppercased())), createdAt: now)
  }

  // MARK: Archive

  /// BH-071: Cmd-W on a Today tab removes it from the sidebar and archives it with reason manual.
  @Test func archivingATodayTabRemovesItAndRecordsTheSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(world.sidebar.nodes[world.today[0]] == nil)
    #expect(world.sidebar.children(of: .today(world.work)) == [world.today[1]])
    #expect(item.id == world.today[0])
    #expect(item.reason == .manual)
    #expect(item.archivedAt == Self.now)
    #expect(item.source == .space(world.work))
    #expect(item.section == .today)
  }

  @Test func archivingAFolderSnapshotsTheWholeSubtree() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.snapshot.allIDs == [world.folder, world.nested])
    #expect(world.sidebar.nodes[world.nested] == nil)
    #expect(item.section == .pinned)
  }

  @Test func nestedNodeSourceIsItsSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.nested, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.source == .space(world.work))
    #expect(item.section == .pinned)
  }

  @Test func favoriteSourceIsUnknownAndSectionKeepsTheProfile() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.favorite, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.source == .unknown)
    #expect(item.section == .favorites(profile: "default"))
  }

  @Test func archivingAnUnknownNodeThrows() throws {
    var world = try Self.makeWorld()
    let id = NodeID()
    #expect(throws: SidebarError.unknownNode(id)) {
      try Archiver.archive(id, from: &world.sidebar, reason: .auto, at: Self.now)
    }
  }

  /// User decision 4, PARITY(NEEDS-RUNTIME-CHECK BH-123): archiving one pane archives just that tab and the split
  /// shrinks; a split left with one pane becomes that plain tab, in the split's place.
  @Test func archivingAPaneShrinksTheSplitAndCollapsesTheLastPane() throws {
    var world = try Self.makeWorld()
    let split = try world.sidebar.addSplit(
      orientation: .horizontal, widthFactors: [0.5, 0.25, 0.25], in: .today(world.work))
    let panes = try ["l", "m", "r"].map {
      try world.sidebar.addTab(url: Self.url($0), title: $0, in: .split(split))
    }
    let item = try Archiver.archive(panes[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.section == .today)
    #expect(item.source == .space(world.work))
    #expect(item.snapshot.allIDs == [panes[0]])
    #expect(world.sidebar.children(of: .split(split)) == [panes[1], panes[2]])
    #expect(world.sidebar.nodes[split]?.kind == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])))

    try Archiver.archive(panes[2], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(world.sidebar.nodes[split] == nil)
    #expect(world.sidebar.children(of: .today(world.work)) == world.today + [panes[1]])
    #expect(world.sidebar.nodes[panes[1]]?.parent == .today(world.work))
  }

  /// A pane archived out of a split is a plain tab. Restoring it uses the tab rule: top of Today, not back into the
  /// split that kept the other panes.
  @Test func restoredPaneComesBackAsPlainTab() throws {
    var world = try Self.makeWorld()
    let split = try world.sidebar.addSplit(
      orientation: .horizontal, widthFactors: [1.0 / 3, 1.0 / 3, 1.0 / 3], in: .today(world.work))
    let panes = try ["l", "m", "r"].map {
      try world.sidebar.addTab(url: Self.url($0), title: $0, in: .split(split))
    }
    let item = try Archiver.archive(panes[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.snapshot.children.isEmpty)
    guard case .tab = item.snapshot.kind else {
      Issue.record("a pane archives as a tab")
      return
    }
    #expect(world.sidebar.children(of: .split(split)) == [panes[1], panes[2]])

    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)

    #expect(restored == RestoredItem(nodeID: panes[0], space: world.work, location: .today(world.work)))
    #expect(world.sidebar.children(of: .today(world.work)).first == panes[0])
    #expect(world.sidebar.nodes[panes[0]]?.parent == .today(world.work))
    #expect(world.sidebar.children(of: .split(split)) == [panes[1], panes[2]])
  }

  /// Plan S8 step 9, model level: an archived split whose factors do not match its pane count restores at the top of
  /// Today with its panes in order and its factors exactly as archived; restore does not rewrite them. The
  /// normalization on show is not asserted here: it is `SplitLayout.normalized` (`SplitLayoutTests`) and, through a
  /// window, `SplitArchiveTests.testMismatchedFactorsStayStoredAndNormalizeOnShow`.
  @Test func archivedSplitWithMismatchedFactorsRestoresWithStoredFactors() throws {
    var world = try Self.makeWorld()
    let factors = [0.2, 0.3, 0.5]
    let left = NodeSnapshot(kind: .tab(TabItem(url: Self.url("l"), title: "Left")), createdAt: Self.now)
    let right = NodeSnapshot(kind: .tab(TabItem(url: Self.url("r"), title: "Right")), createdAt: Self.now)
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .vertical, widthFactors: factors)), createdAt: Self.now,
      children: [left, right])
    let item = ArchivedItem(
      reason: .manual, archivedAt: Self.now, source: .space(world.work), section: .today, snapshot: split)

    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)

    #expect(restored.nodeID == split.id)
    #expect(restored.location == .today(world.work))
    #expect(world.sidebar.children(of: .split(split.id)) == [left.id, right.id])
    guard case .split(let stored)? = world.sidebar.nodes[split.id]?.kind else {
      Issue.record("restored root is not a split")
      return
    }
    #expect(stored.orientation == .vertical)
    #expect(stored.widthFactors == factors)
    #expect(world.sidebar.children(of: .today(world.work)).first == split.id)
  }

  // MARK: Restore

  /// BH-086: a restored tab returns to its original Space (top of Today [I]) with its original id.
  @Test func restoredTabGoesToTheTopOfTodayInItsSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[1], from: &world.sidebar, reason: .auto, at: Self.now)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored == RestoredItem(nodeID: world.today[1], space: world.work, location: .today(world.work)))
    #expect(world.sidebar.children(of: .today(world.work)) == [world.today[1], world.today[0]])
  }

  /// BH-086, BH-090: a restored folder returns to its Space's Pinned section (appended [I]) with its children.
  @Test func restoredFolderGoesToTheEndOfPinned() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored.location == .pinned(world.work))
    #expect(world.sidebar.children(of: .pinned(world.work)).last == world.folder)
    #expect(world.sidebar.children(of: .folder(world.folder)) == [world.nested])
  }

  /// A tab archived from Pinned (here from inside a folder) returns to the end of Pinned [I], not into the folder.
  @Test func restoredPinnedTabGoesToTheEndOfPinned() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.nested, from: &world.sidebar, reason: .manual, at: Self.now)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored == RestoredItem(nodeID: world.nested, space: world.work, location: .pinned(world.work)))
    #expect(world.sidebar.children(of: .pinned(world.work)) == [world.folder, world.nested])
    #expect(world.sidebar.children(of: .folder(world.folder)).isEmpty)
  }

  /// A folder archived from Today returns to the top of Today [I].
  @Test func restoredTodayFolderGoesToTheTopOfToday() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "Loose", in: .today(world.work))
    let item = try Archiver.archive(folder, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.section == .today)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored.location == .today(world.work))
    #expect(world.sidebar.children(of: .today(world.work)).first == folder)
  }

  /// A Favorite returns to the end of its profile's Favorites [I]; it has no Space.
  @Test func restoredFavoriteGoesToTheEndOfItsProfileFavorites() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.favorite, from: &world.sidebar, reason: .manual, at: Self.now)
    let other = try world.sidebar.addTab(url: Self.url("g"), title: "G", in: .favorites(profile: "default"))
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored == RestoredItem(nodeID: world.favorite, space: nil, location: .favorites(profile: "default")))
    #expect(world.sidebar.children(of: .favorites(profile: "default")) == [other, world.favorite])
  }

  /// A split in Today archives as one unit (both panes in one entry) and restores to the top of Today [I].
  @Test func splitInTodayArchivesAndRestoresAsOneUnit() throws {
    var world = try Self.makeWorld()
    let split = try world.sidebar.addSplit(
      orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(world.work))
    let left = try world.sidebar.addTab(url: Self.url("l"), title: "Left", in: .split(split))
    let right = try world.sidebar.addTab(url: Self.url("r"), title: "Right", in: .split(split))
    let item = try Archiver.archive(split, from: &world.sidebar, reason: .auto, at: Self.now)
    #expect(item.snapshot.allIDs == [split, left, right])
    #expect(item.title == "Left | Right")
    #expect(item.url == nil)
    #expect(world.sidebar.nodes[left] == nil && world.sidebar.nodes[right] == nil)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored.location == .today(world.work))
    #expect(world.sidebar.children(of: .today(world.work)).first == split)
    #expect(world.sidebar.children(of: .split(split)) == [left, right])
  }

  /// Without a recorded section (e.g. an imported entry) the default rules apply: folders to the end of Pinned,
  /// everything else to the top of Today, in the source Space when it exists.
  @Test func itemWithoutASectionUsesTheDefaultRules() throws {
    var world = try Self.makeWorld()
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "Imported")), createdAt: Self.now)
    let folderItem = ArchivedItem(reason: .auto, archivedAt: Self.now, source: .space(world.work), snapshot: folder)
    let restoredFolder = try Archiver.restore(folderItem, into: &world.sidebar, fallbackSpace: SpaceID())
    #expect(restoredFolder.location == .pinned(world.work))
    #expect(world.sidebar.children(of: .pinned(world.work)).last == folder.id)
    let tab = ArchivedItem(reason: .auto, archivedAt: Self.now, source: .space(world.work), snapshot: Self.tab("i"))
    let restoredTab = try Archiver.restore(tab, into: &world.sidebar, fallbackSpace: SpaceID())
    #expect(restoredTab.location == .today(world.work))
    #expect(world.sidebar.children(of: .today(world.work)).first == tab.id)
  }

  /// BH-138 [I]: Little Arc items, unknown sources and items whose Space is gone restore into `fallbackSpace` with
  /// the default rules, even when a Pinned section was recorded.
  @Test func littleArcAndMissingSpaceUseTheFallback() throws {
    var world = try Self.makeWorld()
    let little = ArchivedItem(reason: .manual, archivedAt: Self.now, source: .littleArc, snapshot: Self.tab("l"))
    #expect(try Archiver.restore(little, into: &world.sidebar, fallbackSpace: world.work).space == world.work)
    let gone = ArchivedItem(
      reason: .auto, archivedAt: Self.now, source: .space(SpaceID()), section: .pinned, snapshot: Self.tab("g"))
    let restoredGone = try Archiver.restore(gone, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restoredGone.location == .today(world.work))
    let badFallback = SpaceID()
    let other = ArchivedItem(reason: .auto, archivedAt: Self.now, source: .unknown, snapshot: Self.tab("o"))
    let before = world.sidebar
    #expect(throws: SidebarError.invalidDestination(.today(badFallback))) {
      try Archiver.restore(other, into: &world.sidebar, fallbackSpace: badFallback)
    }
    #expect(world.sidebar == before)
  }

  /// An invalid subtree (a folder inside a split) fails partway through; nothing of it may remain.
  @Test func failedRestoreLeavesTheSidebarUnchanged() throws {
    var world = try Self.makeWorld()
    let inner = NodeSnapshot(kind: .folder(FolderItem(title: "Bad")), createdAt: Self.now)
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .vertical, widthFactors: [1])), createdAt: Self.now, children: [inner])
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "Outer")), createdAt: Self.now, children: [split])
    let item = ArchivedItem(reason: .manual, archivedAt: Self.now, source: .space(world.work), snapshot: folder)
    let before = world.sidebar
    #expect(throws: SidebarError.invalidDestination(.split(split.id))) {
      try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    }
    #expect(world.sidebar == before)
  }

  /// A subtree deeper than `Sidebar.maximumNestingDepth` is rejected as a whole.
  @Test func tooDeepRestoreThrowsAndLeavesTheSidebarUnchanged() throws {
    var world = try Self.makeWorld()
    var chain = NodeSnapshot(kind: .folder(FolderItem(title: "leaf")), createdAt: Self.now)
    let tooDeep = chain.id
    for level in 1..<(Sidebar.maximumNestingDepth + 1) {
      chain = NodeSnapshot(kind: .folder(FolderItem(title: "\(level)")), createdAt: Self.now, children: [chain])
    }
    let item = ArchivedItem(reason: .manual, archivedAt: Self.now, source: .space(world.work), snapshot: chain)
    let before = world.sidebar
    #expect(throws: SidebarError.nestingTooDeep(tooDeep)) {
      try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    }
    #expect(world.sidebar == before)
  }

  @Test func restoreOverATakenIDUsesFreshIDs() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    _ = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    let again = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(again.nodeID != world.today[0])
    #expect(world.sidebar.children(of: .today(world.work)).count == 3)
  }

  /// Only a nested descendant's id is taken: the whole subtree, root included, gets fresh ids.
  @Test func takenDescendantIDGivesTheWholeSubtreeFreshIDs() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    let squatter = NodeSnapshot(
      id: world.nested, kind: .tab(TabItem(url: Self.url("x"), title: "X")), createdAt: Self.now)
    try world.sidebar.insert(squatter, in: .today(world.work))
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored.nodeID != world.folder)
    #expect(world.sidebar.nodes[world.folder] == nil)
    let children = world.sidebar.children(of: .folder(restored.nodeID))
    #expect(children.count == 1)
    #expect(children.first != world.nested)
    #expect(world.sidebar.section(of: world.nested) == .today(world.work))
  }

  @Test func titleAndURLComeFromTheSnapshot() throws {
    var world = try Self.makeWorld()
    let tab = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(tab.title == "Uno")
    #expect(tab.url == Self.url("1"))
    let folder = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(folder.title == "Docs")
    #expect(folder.url == nil)
  }

  // MARK: Space removal

  /// Decision on #86: a removed Space's pinned items and Today items go to the Archive; the Space and its nodes go.
  @Test func removingASpaceArchivesPinnedThenTodayItems() throws {
    var world = try Self.makeWorld()
    let other = world.sidebar.addSpace(title: "Other")
    let items = Archiver.removeSpace(world.work, from: &world.sidebar, at: Self.now)
    #expect(items.map(\.id) == [world.folder] + world.today)
    #expect(items.map(\.section) == [ArchivedSection.pinned, .today, .today])
    #expect(Set(items.map(\.source)) == [.space(world.work)])
    #expect(Set(items.map(\.reason)) == [.manual])
    #expect(Set(items.map(\.archivedAt)) == [Self.now])
    #expect(items[0].snapshot.allIDs == [world.folder, world.nested])
    #expect(world.sidebar.spaceOrder == [other])
    #expect(Set(world.sidebar.nodes.keys) == [world.favorite])
  }

  /// The source Space is gone, so a restore uses the default rules in the fallback Space: a folder to Pinned, a tab
  /// to the top of Today.
  @Test func itemsOfARemovedSpaceRestoreIntoTheFallbackSpace() throws {
    var world = try Self.makeWorld()
    let other = world.sidebar.addSpace(title: "Other")
    let items = Archiver.removeSpace(world.work, from: &world.sidebar, at: Self.now)
    let folder = try Archiver.restore(items[0], into: &world.sidebar, fallbackSpace: other)
    let tab = try Archiver.restore(items[1], into: &world.sidebar, fallbackSpace: other)
    #expect(folder.location == .pinned(other))
    #expect(tab.location == .today(other))
    #expect(world.sidebar.children(of: .folder(world.folder)) == [world.nested])
  }

  @Test func removingAnUnknownSpaceArchivesNothing() throws {
    var world = try Self.makeWorld()
    let before = world.sidebar
    #expect(Archiver.removeSpace(SpaceID(), from: &world.sidebar, at: Self.now).isEmpty)
    #expect(world.sidebar == before)
  }

  @Test func removingAnEmptySpaceArchivesNothing() throws {
    var world = try Self.makeWorld()
    let empty = world.sidebar.addSpace(title: "Empty")
    #expect(Archiver.removeSpace(empty, from: &world.sidebar, at: Self.now).isEmpty)
    #expect(world.sidebar.spaceOrder == [world.work])
  }
}
