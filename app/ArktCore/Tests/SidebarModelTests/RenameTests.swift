import Foundation
import Testing
import SidebarModel

/// Sidebar rename (BH-026): a tab's custom title, a folder's title, and the storage round trip.
struct RenameTests {
  let url = URL(string: "https://example.com/a")!

  @Test func renamingATabSetsItsCustomTitleAndKeepsThePageTitle() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: url, title: "Page", in: .today(space))
    try sidebar.rename(tab, to: "  Mine  ")
    guard case .tab(let item)? = sidebar.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.customTitle == "Mine")
    #expect(item.title == "Page")
  }

  /// The page keeps reporting titles; they never replace the name the user chose (BH-026).
  @Test func aLaterPageTitleDoesNotReplaceTheCustomTitle() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: url, title: "Page", in: .today(space))
    try sidebar.rename(tab, to: "Mine")
    try sidebar.updateTab(tab, title: "Page 2")
    guard case .tab(let item)? = sidebar.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.customTitle == "Mine")
    #expect(item.title == "Page 2")
  }

  @Test(arguments: [nil, "", "   \n"])
  func anEmptyNameClearsTheCustomTitle(_ name: String?) throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: url, title: "Page", customTitle: "Mine", in: .today(space))
    try sidebar.rename(tab, to: name)
    guard case .tab(let item)? = sidebar.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.customTitle == nil)
  }

  @Test func renamingAFolderSetsItsTitleAndAnEmptyNameKeepsIt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    try sidebar.rename(folder, to: " Reading ")
    #expect(sidebar.nodes[folder]?.kind == .folder(FolderItem(title: "Reading")))
    try sidebar.rename(folder, to: "  ")
    #expect(sidebar.nodes[folder]?.kind == .folder(FolderItem(title: "Reading")))
  }

  @Test func renamingASplitOrAnUnknownNodeThrowsAndChangesNothing() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let before = sidebar
    #expect(throws: SidebarError.unknownNode(split)) { try sidebar.rename(split, to: "X") }
    let ghost = NodeID()
    #expect(throws: SidebarError.unknownNode(ghost)) { try sidebar.rename(ghost, to: "X") }
    #expect(sidebar == before)
  }

  /// The custom title is part of the stored sidebar, so it survives a relaunch.
  @Test func theCustomTitleSurvivesTheStorageRoundTrip() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: url, title: "Page", in: .today(space))
    try sidebar.rename(tab, to: "Mine")
    let decoded = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
    guard case .tab(let item)? = decoded.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.customTitle == "Mine")
  }
}
