import Foundation
import Testing
import SidebarModel

struct NodeSnapshotTests {
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  /// Space "Work": pinned [folder Docs [tab a, tab b], tab c], today [tab d]; a split with two tabs in pinned.
  static func makeSidebar() throws -> (Sidebar, SpaceID, folder: NodeID, split: NodeID) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    try sidebar.addTab(url: url("a"), title: "A", in: .folder(folder))
    try sidebar.addTab(url: url("b"), title: "B", customTitle: "Bee", in: .folder(folder))
    try sidebar.addTab(url: url("c"), title: "C", in: .pinned(space))
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    try sidebar.addTab(url: url("s1"), title: "S1", in: .split(split))
    try sidebar.addTab(url: url("s2"), title: "S2", in: .split(split))
    try sidebar.addTab(url: url("d"), title: "D", in: .today(space))
    return (sidebar, space, folder, split)
  }

  @Test func snapshotCapturesSubtreeInOrder() throws {
    let (sidebar, _, folder, _) = try Self.makeSidebar()
    let snapshot = try #require(sidebar.snapshot(of: folder))
    #expect(snapshot.id == folder)
    #expect(snapshot.kind == .folder(FolderItem(title: "Docs")))
    #expect(snapshot.children.map(\.id) == sidebar.children(of: .folder(folder)))
    #expect(snapshot.children.allSatisfy { $0.children.isEmpty })
    #expect(snapshot.allIDs == [folder] + sidebar.children(of: .folder(folder)))
  }

  @Test func snapshotOfUnknownIDIsNil() throws {
    let (sidebar, _, _, _) = try Self.makeSidebar()
    #expect(sidebar.snapshot(of: NodeID()) == nil)
  }

  @Test func removeThenInsertAtOldIndexRestoresSidebarExactly() throws {
    let (original, space, folder, _) = try Self.makeSidebar()
    var sidebar = original
    let snapshot = try #require(sidebar.snapshot(of: folder))
    let index = try #require(sidebar.children(of: .pinned(space)).firstIndex(of: folder))
    sidebar.remove(folder)
    try sidebar.insert(snapshot, in: .pinned(space), at: index)
    #expect(sidebar == original)
  }

  @Test func insertAppendsWithoutIndexAndClampsLargeIndex() throws {
    let made = try Self.makeSidebar()
    var sidebar = made.0
    let space = made.1
    let a = NodeSnapshot(kind: .tab(TabItem(url: Self.url("x"), title: "X")), createdAt: .distantPast)
    let b = NodeSnapshot(kind: .tab(TabItem(url: Self.url("y"), title: "Y")), createdAt: .distantPast)
    try sidebar.insert(a, in: .today(space))
    try sidebar.insert(b, in: .today(space), at: 99)
    #expect(sidebar.children(of: .today(space)).suffix(2) == [a.id, b.id])
    let c = NodeSnapshot(kind: .tab(TabItem(url: Self.url("z"), title: "Z")), createdAt: .distantPast)
    try sidebar.insert(c, in: .today(space), at: -3)
    #expect(sidebar.children(of: .today(space)).first == c.id)
  }

  @Test func insertRejectsDuplicateIDAndLeavesSidebarUnchanged() throws {
    let (original, space, folder, _) = try Self.makeSidebar()
    var sidebar = original
    let snapshot = try #require(sidebar.snapshot(of: folder))
    #expect(throws: SidebarError.duplicateID(folder)) { try sidebar.insert(snapshot, in: .today(space)) }
    #expect(sidebar == original)
  }

  @Test func insertRejectsFolderInsideSplit() throws {
    let (original, _, _, split) = try Self.makeSidebar()
    var sidebar = original
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "F")), createdAt: .distantPast)
    #expect(throws: SidebarError.invalidDestination(.split(split))) { try sidebar.insert(folder, in: .split(split)) }
    #expect(sidebar == original)
  }

  @Test func insertRejectsChildrenUnderATab() throws {
    let (original, space, _, _) = try Self.makeSidebar()
    var sidebar = original
    let child = NodeSnapshot(kind: .tab(TabItem(url: Self.url("k"), title: "K")), createdAt: .distantPast)
    let parent = NodeSnapshot(
      kind: .tab(TabItem(url: Self.url("p"), title: "P")), createdAt: .distantPast, children: [child])
    #expect(throws: SidebarError.invalidDestination(.folder(parent.id))) {
      try sidebar.insert(parent, in: .today(space))
    }
    #expect(sidebar == original)
  }

  @Test func addSpaceKeepsIDAndRejectsDuplicates() throws {
    var sidebar = Sidebar()
    let space = Space(title: "Kept", profile: "work")
    try sidebar.addSpace(space)
    #expect(sidebar.spaceOrder == [space.id])
    #expect(sidebar.spaces[space.id] == space)
    #expect(throws: SidebarError.duplicateID(space.id)) { try sidebar.addSpace(space) }
    #expect(sidebar.spaceOrder == [space.id])
  }

  @Test func withFreshIDsChangesEveryIDAndKeepsShape() throws {
    let (sidebar, _, folder, _) = try Self.makeSidebar()
    let snapshot = try #require(sidebar.snapshot(of: folder))
    let fresh = snapshot.withFreshIDs()
    #expect(Set(fresh.allIDs).isDisjoint(with: snapshot.allIDs))
    #expect(fresh.allIDs.count == snapshot.allIDs.count)
    #expect(fresh.children.map(\.kind) == snapshot.children.map(\.kind))
    #expect(fresh.createdAt == snapshot.createdAt)
  }

  @Test func nodeSnapshotCodableRoundTripsAllKinds() throws {
    let snapshot = NodeSnapshot(
      kind: .folder(FolderItem(title: "F")), createdAt: Date(timeIntervalSinceReferenceDate: 10.5),
      children: [
        NodeSnapshot(
          kind: .tab(TabItem(url: Self.url("t"), title: "T", customTitle: "Tee", lastActiveAt: .distantPast)),
          createdAt: Date(timeIntervalSinceReferenceDate: 11)),
        NodeSnapshot(
          kind: .split(SplitItem(orientation: .vertical, widthFactors: [0.25, 0.75])),
          createdAt: Date(timeIntervalSinceReferenceDate: 12),
          children: [NodeSnapshot(kind: .tab(TabItem(url: Self.url("s"), title: "S")), createdAt: .distantPast)]),
      ])
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(NodeSnapshot.self, from: data) == snapshot)
  }

  @Test func nodeKindRejectsUnknownType() throws {
    let data = Data(#"{"type":"group","group":{"title":"G"}}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(NodeKind.self, from: data) }
  }

  @Test func insertRejectsIDRepeatedInsideOneSnapshot() throws {
    let (original, space, _, _) = try Self.makeSidebar()
    var sidebar = original
    let repeated = NodeID()
    let tab = { (path: String) in
      NodeSnapshot(id: repeated, kind: .tab(TabItem(url: Self.url(path), title: path)), createdAt: .distantPast)
    }
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "F")), createdAt: .distantPast, children: [tab("1"), tab("2")])
    #expect(throws: SidebarError.duplicateID(repeated)) { try sidebar.insert(folder, in: .today(space)) }
    #expect(sidebar == original)
  }

  @Test func nestedRejectionAfterWrittenSiblingsLeavesSidebarUnchanged() throws {
    let (original, space, _, _) = try Self.makeSidebar()
    var sidebar = original
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])), createdAt: .distantPast,
      children: [
        NodeSnapshot(kind: .tab(TabItem(url: Self.url("ok"), title: "OK")), createdAt: .distantPast),
        NodeSnapshot(kind: .folder(FolderItem(title: "Nope")), createdAt: .distantPast),
      ])
    #expect(throws: SidebarError.invalidDestination(.split(split.id))) {
      try sidebar.insert(split, in: .today(space), at: 0)
    }
    #expect(sidebar == original)
  }

  @Test func insertRejectsMissingSpace() throws {
    let (original, _, _, _) = try Self.makeSidebar()
    var sidebar = original
    let missing = SpaceID()
    let tab = NodeSnapshot(kind: .tab(TabItem(url: Self.url("m"), title: "M")), createdAt: .distantPast)
    #expect(throws: SidebarError.invalidDestination(.pinned(missing))) { try sidebar.insert(tab, in: .pinned(missing)) }
    #expect(throws: SidebarError.invalidDestination(.today(missing))) { try sidebar.insert(tab, in: .today(missing)) }
    #expect(sidebar == original)
  }

  @Test func withFreshIDsRemapsTwoLevelTreeConsistently() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let outer = try sidebar.addFolder(title: "Outer", in: .pinned(space))
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(outer))
    try sidebar.addTab(url: Self.url("deep"), title: "Deep", in: .folder(inner))
    try sidebar.addTab(url: Self.url("top"), title: "Top", in: .folder(outer))
    let snapshot = try #require(sidebar.snapshot(of: outer))
    let fresh = snapshot.withFreshIDs()
    #expect(Set(fresh.allIDs).count == snapshot.allIDs.count)
    #expect(Set(fresh.allIDs).isDisjoint(with: snapshot.allIDs))
    #expect(fresh.children.map(\.kind) == snapshot.children.map(\.kind))
    #expect(fresh.children[0].children.map(\.kind) == snapshot.children[0].children.map(\.kind))
    try sidebar.insert(fresh, in: .today(space))
    #expect(sidebar.snapshot(of: fresh.id) == fresh)
    #expect(sidebar.children(of: .folder(fresh.children[0].id)) == [fresh.children[0].children[0].id])
  }

  @Test func snapshotOfSplitAndTab() throws {
    let (sidebar, space, _, split) = try Self.makeSidebar()
    let splitSnapshot = try #require(sidebar.snapshot(of: split))
    #expect(splitSnapshot.kind == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])))
    #expect(splitSnapshot.children.map(\.id) == sidebar.children(of: .split(split)))
    #expect(splitSnapshot.children.map(\.kind) == [
      .tab(TabItem(url: Self.url("s1"), title: "S1")), .tab(TabItem(url: Self.url("s2"), title: "S2")),
    ])
    let tabID = try #require(sidebar.children(of: .today(space)).first)
    let tabSnapshot = try #require(sidebar.snapshot(of: tabID))
    #expect(tabSnapshot.kind == .tab(TabItem(url: Self.url("d"), title: "D")))
    #expect(tabSnapshot.children.isEmpty)
    #expect(tabSnapshot.createdAt == sidebar.nodes[tabID]?.createdAt)
  }

  @Test func sectionOfFindsTheTopLevelSectionThroughFoldersAndSplits() throws {
    var (sidebar, space, folder, split) = try Self.makeSidebar()
    let inFolder = try #require(sidebar.children(of: .folder(folder)).first)
    let inSplit = try #require(sidebar.children(of: .split(split)).first)
    let today = try #require(sidebar.children(of: .today(space)).first)
    let favorite = try sidebar.addTab(url: Self.url("f"), title: "F", in: .favorites(profile: "p"))
    #expect(sidebar.section(of: folder) == .pinned(space))
    #expect(sidebar.section(of: inFolder) == .pinned(space))
    #expect(sidebar.section(of: inSplit) == .pinned(space))
    #expect(sidebar.section(of: today) == .today(space))
    #expect(sidebar.section(of: favorite) == .favorites(profile: "p"))
    #expect(sidebar.section(of: NodeID()) == nil)
  }
}
