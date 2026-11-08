import Foundation
import Testing
import SidebarModel

struct NodeCustomIconTests {
  @Test func favoriteAndFolderOverridesRoundTripAndClearIndependently() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Example")
    let favorite = try sidebar.addTab(url: #require(URL(string: "https://example.com")), title: "Favorite",
                                      in: .favorites(profile: "default"))
    let folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    let untouched = try sidebar.addFolder(title: "Other", in: .pinned(space))

    sidebar.setNodeIcon(favorite, to: .symbol("star"))
    sidebar.setNodeIcon(folder, to: .emoji("\u{1F680}"))
    #expect(sidebar.nodes[favorite]?.customIcon == .symbol("star"))
    #expect(sidebar.nodes[folder]?.customIcon == .emoji("\u{1F680}"))
    #expect(sidebar.nodes[untouched]?.customIcon == nil)

    var restored = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
    #expect(restored.nodes[favorite]?.customIcon == .symbol("star"))
    #expect(restored.nodes[folder]?.customIcon == .emoji("\u{1F680}"))
    restored.setNodeIcon(favorite, to: nil)
    let cleared = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(restored))
    #expect(cleared.nodes[favorite]?.customIcon == nil)
    #expect(cleared.nodes[folder]?.customIcon == .emoji("\u{1F680}"))
    restored.setNodeIcon(folder, to: nil)
    #expect(try SidebarStorageFormat.decode(SidebarStorageFormat.encode(restored)).nodes[folder]?.customIcon == nil)
  }

  @Test func tabUpdatesAndSnapshotRestoreKeepOverride() throws {
    var sidebar = Sidebar()
    let favorite = try sidebar.addTab(url: #require(URL(string: "https://example.com")), title: "Before",
                                      in: .favorites(profile: "default"))
    sidebar.setNodeIcon(favorite, to: .symbol("star"))
    try sidebar.updateTab(favorite, title: "After")
    #expect(sidebar.nodes[favorite]?.customIcon == .symbol("star"))

    let snapshot = try #require(sidebar.snapshot(of: favorite))
    var restored = Sidebar()
    try restored.insert(snapshot, in: .favorites(profile: "default"))
    #expect(restored.nodes[favorite]?.customIcon == .symbol("star"))
  }

  @Test func existingVersionThreeWithoutOverridesFallsBack() throws {
    let fixture = try #require(Bundle.module.url(forResource: "sidebar-v3", withExtension: "json", subdirectory: "Fixtures"))
    let sidebar = try SidebarStorageFormat.decode(Data(contentsOf: fixture))
    #expect(!sidebar.nodes.isEmpty)
    #expect(sidebar.nodes.values.allSatisfy { $0.customIcon == nil })
    let restored = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
    #expect(restored.nodes.values.allSatisfy { $0.customIcon == nil })
  }
}
