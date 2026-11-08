import Foundation
import Testing
import SidebarModel

/// Sidebar rename (BH-026, #787): a tab's custom title, a folder's title, a split's name, and the storage round trip.
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

  /// #787: a split takes the trimmed name as its title; an empty or nil name clears it, so the row shows its pane
  /// titles again.
  @Test func renamingASplitSetsItsTitleAndAnEmptyNameClearsIt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    try sidebar.rename(split, to: "  Research  ")
    #expect(sidebar.nodes[split]?.kind
      == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5], title: "Research")))
    for name in [nil, "", "  \n"] as [String?] {
      try sidebar.rename(split, to: "Research")
      try sidebar.rename(split, to: name)
      guard case .split(let item)? = sidebar.nodes[split]?.kind else { Issue.record("not a split"); return }
      #expect(item.title == nil, "\(String(describing: name)) clears the name")
    }
  }

  /// The split edits rewrite the split's payload; none of them drops the name.
  @Test func aSplitKeepsItsNameThroughSplitEdits() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tabs = try (0..<3).map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: "T\($0)", in: .today(space))
    }
    let split = try sidebar.createSplit(of: Array(tabs.prefix(2)), orientation: .horizontal)
    try sidebar.rename(split, to: "Research")
    try sidebar.setSplitOrientation(split, .vertical)
    try sidebar.addPane(tabs[2], to: split)
    try sidebar.setSplitWidthFactors(split, [0.2, 0.3, 0.5])
    try sidebar.movePane(tabs[2], to: 0)
    guard case .split(let item)? = sidebar.nodes[split]?.kind else { Issue.record("not a split"); return }
    #expect(item.title == "Research")
    let copy = try #require(sidebar.snapshot(of: split)).withFreshIDs()
    guard case .split(let copied) = copy.kind else { Issue.record("not a split"); return }
    #expect(copied.title == "Research", "a duplicate keeps the name")
  }

  @Test func renamingAnUnknownNodeThrowsAndChangesNothing() throws {
    var sidebar = Sidebar()
    _ = sidebar.addSpace(title: "Work")
    let before = sidebar
    let ghost = NodeID()
    #expect(throws: SidebarError.unknownNode(ghost)) { try sidebar.rename(ghost, to: "X") }
    #expect(sidebar == before)
  }

  /// A split's name is part of the stored sidebar, so it survives a relaunch.
  @Test func theSplitNameSurvivesTheStorageRoundTrip() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    try sidebar.addTab(url: url, title: "A", in: .split(split))
    try sidebar.addTab(url: url, title: "B", in: .split(split))
    try sidebar.rename(split, to: "Research")
    let decoded = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
    #expect(decoded == sidebar)
    guard case .split(let item)? = decoded.nodes[split]?.kind else { Issue.record("not a split"); return }
    #expect(item.title == "Research")
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
