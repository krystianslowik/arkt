import CoreBridge
import Foundation
import ShellUI
import Testing

/// Rename, duplicate and New Folder (#105: BH-026, BH-027, BH-094, KB-040) on both `SidebarSource`s.
@MainActor
struct TabActionsContractTests {
  private static let urlA = URL(string: "https://a.example/page")!
  private static let urlB = URL(string: "https://b.example/page")!

  private func title(_ source: any SidebarSource, _ id: NodeID) -> String? {
    switch source.node(id) {
    case .tab(_, _, let title)?, .folder(_, let title)?: title
    case .split?, nil: nil
    }
  }

  // MARK: Rename (BH-026)

  @Test(arguments: SourceKind.allCases)
  func renamingATabShowsTheCustomTitleAndPageTitlesNoLongerReplaceIt(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let tab = try source.addTab(url: Self.urlA, title: "Page", in: .today(space))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    source.renameNode(tab, to: " Mine ")
    #expect(title(source, tab) == "Mine")
    #expect(changes == [.node(tab)])
    source.updateTab(tab, url: nil, title: "Page 2")
    #expect(title(source, tab) == "Mine", "a page title never replaces the custom title")
    source.renameNode(tab, to: nil)
    #expect(title(source, tab) == "Page 2", "clearing the custom title shows the latest page title")
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func renamingAFolderChangesItsTitleAndAnEmptyNameKeepsIt(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let folder = try source.addFolder(title: "Docs", in: .pinned(space), at: nil)
    source.renameNode(folder, to: "Reading")
    #expect(title(source, folder) == "Reading")
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    source.renameNode(folder, to: "   ")
    #expect(title(source, folder) == "Reading")
    #expect(changes.isEmpty)
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func renamingASplitOrAnUnknownNodeChangesNothing(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    let (split, _) = try source.addToSplit(.new(url: Self.urlB, title: "B"), target: a, at: 1,
                                           orientation: .horizontal)
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    source.renameNode(split, to: "X")
    source.renameNode(NodeID(), to: "X")
    #expect(changes.isEmpty)
    _ = observation
  }

  // MARK: Duplicate (BH-027, BH-095)

  @Test(arguments: SourceKind.allCases)
  func duplicatingATabPutsACopyRightAfterItWithTheSameURLAndTitle(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    let b = try source.addTab(url: Self.urlB, title: "B", in: .today(space))
    source.renameNode(a, to: "Mine")
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let copy = try source.duplicateNode(a)
    #expect(copy != a)
    #expect(source.children(of: .today(space)) == [a, copy, b])
    guard case .tab(_, let url, let copyTitle)? = source.node(copy) else { Issue.record("not a tab"); return }
    #expect(url == Self.urlA)
    #expect(copyTitle == "Mine", "the custom title comes along")
    #expect(changes == [.structure(.today(space))])
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func duplicatingAFolderCopiesItsTabsWithNewIDs(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let folder = try source.addFolder(title: "Docs", in: .pinned(space), at: nil)
    let inner = try source.addTab(url: Self.urlA, title: "A", in: .folder(folder))
    let copy = try source.duplicateNode(folder)
    #expect(source.children(of: .pinned(space)) == [folder, copy])
    #expect(title(source, copy) == "Docs")
    let copied = source.children(of: .folder(copy))
    #expect(copied.count == 1)
    #expect(copied.first != inner)
    #expect(source.children(of: .folder(folder)) == [inner], "the original keeps its tab")
  }

  @Test(arguments: SourceKind.allCases)
  func duplicatingAnUnknownNodeThrows(kind: SourceKind) throws {
    let source = kind.make()
    #expect(throws: (any Error).self) { try source.duplicateNode(NodeID()) }
  }

  // MARK: New Folder (KB-040, BH-094)

  @Test(arguments: SourceKind.allCases)
  func addFolderInsertsAtTheGivenIndex(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.urlA, title: "A", in: .pinned(space))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let folder = try source.addFolder(title: "New Folder", in: .pinned(space), at: 0)
    #expect(source.children(of: .pinned(space)) == [folder, a])
    #expect(title(source, folder) == "New Folder")
    #expect(changes == [.structure(.pinned(space))])
    _ = observation
  }
}
