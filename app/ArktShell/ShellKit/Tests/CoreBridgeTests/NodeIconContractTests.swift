import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

@MainActor
struct NodeIconContractTests {
  @Test func modelIconsReachShellAndCommandsNotifyOnlyOnChanges() throws {
    var model = SidebarModel.Sidebar()
    let space = model.addSpace(title: "Example")
    let favorite = try model.addTab(url: #require(URL(string: "https://example.com")), title: "Favorite",
                                    in: .favorites(profile: "default"))
    let folder = try model.addFolder(title: "Folder", in: .pinned(space))
    model.setNodeIcon(favorite, to: .symbol("star"))
    model.setNodeIcon(folder, to: .emoji("\u{1F680}"))
    let source = ModelSidebarSource(sidebar: model)
    #expect(source.nodeIcon(favorite) == .symbol("star"))
    #expect(source.nodeIcon(folder) == .emoji("\u{1F680}"))
    var changes: [SidebarChange] = []
    var saves: [SidebarModel.Sidebar] = []
    let observation = source.observe { changes.append($0) }
    source.onDidChange = { saves.append($0) }

    source.setNodeIcon(favorite, to: .symbol("bolt"))
    source.setNodeIcon(favorite, to: .symbol("bolt"))
    source.setNodeIcon(folder, to: nil)
    source.setNodeIcon(folder, to: nil)
    source.setNodeIcon(UUID(), to: .symbol("star"))
    #expect(source.nodeIcon(favorite) == .symbol("bolt"))
    #expect(source.nodeIcon(folder) == nil)
    #expect(source.sidebar.nodes[favorite]?.customIcon == .symbol("bolt"))
    #expect(source.sidebar.nodes[folder]?.customIcon == nil)
    #expect(changes == [.node(favorite), .node(folder)])
    #expect(saves.count == 2)
    withExtendedLifetime(observation) {}
  }

  @Test func duplicatePreservesOverridesForTheEntireSnapshot() throws {
    let source = ModelSidebarSource()
    let space = try source.addSpace(title: "Example")
    let folder = try source.addFolder(title: "Folder", in: .pinned(space), at: nil)
    let child = try source.addTab(url: #require(URL(string: "https://example.com")), title: "Tab", in: .folder(folder))
    source.mutate { sidebar in
      sidebar.setNodeIcon(folder, to: .symbol("star"))
      sidebar.setNodeIcon(child, to: .emoji("\u{1F680}"))
    }
    let copy = try source.duplicateNode(folder)
    let copiedChild = try #require(source.children(of: .folder(copy)).first)
    #expect(copy != folder && copiedChild != child)
    #expect(source.sidebar.nodes[copy]?.customIcon == .symbol("star"))
    #expect(source.sidebar.nodes[copiedChild]?.customIcon == .emoji("\u{1F680}"))
    #expect(source.nodeIcon(copy) == .symbol("star"))
    #expect(source.nodeIcon(copiedChild) == .emoji("\u{1F680}"))
  }
}
