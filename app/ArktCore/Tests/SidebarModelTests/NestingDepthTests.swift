import Foundation
import Testing
import SidebarModel

struct NestingDepthTests {
  static let maximum = Sidebar.maximumNestingDepth

  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  /// A Space whose pinned section holds a chain of `count` nested folders; the last one sits at depth `count`.
  static func chain(_ count: Int) throws -> (Sidebar, SpaceID, [NodeID]) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    var ids: [NodeID] = []
    var location = Location.pinned(space)
    for _ in 0..<count {
      let id = try sidebar.addFolder(title: "F", in: location)
      ids.append(id)
      location = .folder(id)
    }
    return (sidebar, space, ids)
  }

  static func isTooDeep(_ error: SidebarError?) -> Bool {
    if case .nestingTooDeep? = error { return true }
    return false
  }

  @Test func addAcceptsMaximumDepthAndRejectsBeyond() throws {
    let made = try Self.chain(Self.maximum)
    var sidebar = made.0
    let deepest = Location.folder(try #require(made.2.last))
    let addFolder = #expect(throws: SidebarError.self) { try sidebar.addFolder(title: "X", in: deepest) }
    let addTab = #expect(throws: SidebarError.self) { try sidebar.addTab(url: Self.url("x"), title: "X", in: deepest) }
    let addSplit = #expect(throws: SidebarError.self) {
      try sidebar.addSplit(orientation: .vertical, widthFactors: [0.5, 0.5], in: deepest)
    }
    #expect(Self.isTooDeep(addFolder))
    #expect(Self.isTooDeep(addTab))
    #expect(Self.isTooDeep(addSplit))
    #expect(sidebar == made.0)
  }

  @Test func tabInsideSplitCountsTowardDepth() throws {
    let made = try Self.chain(Self.maximum - 1)
    var sidebar = made.0
    let split = try sidebar.addSplit(
      orientation: .horizontal, widthFactors: [0.5, 0.5], in: .folder(try #require(made.2.last)))
    let before = sidebar
    let error = #expect(throws: SidebarError.self) {
      try sidebar.addTab(url: Self.url("x"), title: "X", in: .split(split))
    }
    #expect(Self.isTooDeep(error))
    #expect(sidebar == before)
  }

  @Test func insertRejectsSubtreeThatWouldExceedAndLeavesSidebarUnchanged() throws {
    let made = try Self.chain(Self.maximum - 2)
    var sidebar = made.0
    let deepest = Location.folder(try #require(made.2.last))
    let tab = NodeSnapshot(kind: .tab(TabItem(url: Self.url("t"), title: "T")), createdAt: .distantPast)
    let inner = NodeSnapshot(kind: .folder(FolderItem(title: "Inner")), createdAt: .distantPast, children: [tab])
    let outer = NodeSnapshot(kind: .folder(FolderItem(title: "Outer")), createdAt: .distantPast, children: [inner])
    #expect(throws: SidebarError.nestingTooDeep(tab.id)) { try sidebar.insert(outer, in: deepest) }
    #expect(sidebar == made.0)
    try sidebar.insert(inner, in: deepest)
    #expect(sidebar.children(of: .folder(inner.id)) == [tab.id])
  }

  @Test func moveRejectsSubtreeThatWouldExceedAndLeavesSidebarUnchanged() throws {
    let made = try Self.chain(Self.maximum - 2)
    var sidebar = made.0
    let deepest = Location.folder(try #require(made.2.last))
    let outer = try sidebar.addFolder(title: "Outer", in: .today(made.1))
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(outer))
    try sidebar.addTab(url: Self.url("t"), title: "T", in: .folder(inner))
    let before = sidebar
    #expect(throws: SidebarError.nestingTooDeep(outer)) { try sidebar.move(outer, to: deepest, at: 0) }
    #expect(sidebar == before)
    try sidebar.move(inner, to: deepest, at: 0)
    #expect(sidebar.nodes[inner]?.parent == deepest)
  }

  @Test func formatCapIsTheModelCap() {
    #expect(SidebarStorageFormat.maximumNestingDepth == Sidebar.maximumNestingDepth)
    #expect(Sidebar.maximumNestingDepth == 32)
  }
}
