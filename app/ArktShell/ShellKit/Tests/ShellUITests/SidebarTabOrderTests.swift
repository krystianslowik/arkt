import Foundation
import Testing
@testable import ShellUI

/// Cmd-1 ... Cmd-9 (BH-014, BH-015, KB-020, KB-021) and next / previous tab in sidebar order (BH-016, KB-028,
/// KB-029) over the sidebar's displayed order: Favorites, then Pinned, then Today.
@MainActor
struct SidebarTabOrderTests {
  private let source: StubSidebar
  private let space: SpaceID
  private let favorites: [NodeID]
  private let pinned: [NodeID]
  private let folder: NodeID
  private let folderTabs: [NodeID]
  private let split: NodeID
  private let panes: [NodeID]
  private let today: [NodeID]

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  init() {
    let source = StubSidebar()
    let space = source.addSpace(title: "Work", theme: StubSidebar.defaultTheme)
    let profile = SidebarLocation.favorites(profile: "default")
    favorites = (0..<2).map { source.addTab(url: Self.url("f\($0)"), title: "F\($0)", in: profile) }
    pinned = [source.addTab(url: Self.url("p0"), title: "P0", in: .pinned(space))]
    let folder = source.addFolder(title: "Folder", in: .pinned(space))
    folderTabs = (0..<2).map { source.addTab(url: Self.url("d\($0)"), title: "D\($0)", in: .folder(folder)) }
    let split = source.addSplit(in: .today(space))
    panes = (0..<2).map { source.addTab(url: Self.url("s\($0)"), title: "S\($0)", in: .split(split)) }
    today = (0..<5).map { source.addTab(url: Self.url("t\($0)"), title: "T\($0)", in: .today(space)) }
    self.source = source
    self.space = space
    self.folder = folder
    self.split = split
  }

  private func order(favorites: Bool = true, collapsed: Set<NodeID> = []) -> SidebarTabOrder {
    SidebarTabOrder(source: source, profile: "default", space: space, includeFavorites: favorites,
                    collapsedFolders: collapsed)
  }

  private func items(favorites: Bool = true, collapsed: Set<NodeID> = []) -> [NodeID] {
    order(favorites: favorites, collapsed: collapsed).items
  }

  @Test func `the order runs favorites, pinned through open folders, then today with a split as one item`() {
    #expect(items() == favorites + pinned + folderTabs + [split] + today)
  }

  @Test func `a collapsed folder hides its tabs and favorites can be left out`() {
    #expect(items(favorites: false, collapsed: [folder]) == pinned + [split] + today)
  }

  @Test func `no space leaves only the favorites`() {
    #expect(SidebarTabOrder(source: source, profile: "default", space: nil, includeFavorites: true,
                            collapsedFolders: []).items == favorites)
  }

  // MARK: Cmd-1 ... Cmd-9

  @Test func `cmd n counts favorites first by default`() {
    let settings = TabNavigationSettings()
    #expect(order().item(number: 1, settings: settings) == favorites[0])
    #expect(order().item(number: 3, settings: settings) == pinned[0])
    #expect(order().item(number: 6, settings: settings) == split)
  }

  @Test func `cmd n past the end does nothing`() {
    let short = SidebarTabOrder(items: Array(items().prefix(3)))
    #expect(short.item(number: 5, settings: TabNavigationSettings()) == nil)
    #expect(short.item(number: 0, settings: TabNavigationSettings()) == nil)
  }

  @Test func `cmd nine is the last item unless the ninth tab setting is on`() {
    let all = order()
    #expect(all.item(number: 9, settings: TabNavigationSettings()) == today.last)
    var ninth = TabNavigationSettings()
    ninth.ninthOpensNinth = true
    #expect(all.item(number: 9, settings: ninth) == all.items[8])
    #expect(SidebarTabOrder(items: Array(all.items.prefix(4))).item(number: 9, settings: ninth) == nil)
  }

  // MARK: Next / previous

  @Test func `next and previous step one item and stop at the ends`() {
    let all = order()
    #expect(all.neighbour(of: pinned[0], forward: true) == folderTabs[0])
    #expect(all.neighbour(of: pinned[0], forward: false) == favorites[1])
    #expect(all.neighbour(of: favorites[0], forward: false) == nil)
    #expect(all.neighbour(of: today.last, forward: true) == nil)
  }

  @Test func `a pane steps from its split`() {
    let all = order()
    #expect(all.neighbour(of: panes[1], forward: true) == today[0])
    #expect(all.neighbour(of: panes[0], forward: false) == folderTabs[1])
  }

  @Test func `without a current item next starts at the top and previous at the bottom`() {
    let all = order()
    #expect(all.neighbour(of: nil, forward: true) == favorites[0])
    #expect(all.neighbour(of: nil, forward: false) == today.last)
  }

  @Test func `a current tab hidden in a collapsed folder steps from that folder's place`() {
    let all = order(collapsed: [folder])
    #expect(all.neighbour(of: folderTabs[1], forward: true) == split)
    #expect(all.neighbour(of: folderTabs[0], forward: false) == pinned[0])
  }
}
