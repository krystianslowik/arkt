@testable import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// Sidebar drag and drop (#104) through the adapter: `moveNodes` is one mutation, and `moveNode` of a pane no longer
/// leaves a one-pane split behind (the bug class "a drag that breaks a Split View").
@MainActor
struct SidebarDragSourceTests {
  private static let stamp = Date(timeIntervalSinceReferenceDate: 700_000_000)

  private struct World {
    let source: ModelSidebarSource
    let space: UUID
    let today: [UUID]
  }

  private func makeWorld(tabs: Int = 4) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let today = try (0..<tabs).map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: "t\($0)",
                         lastActiveAt: Self.stamp, in: .today(space))
    }
    return World(source: ModelSidebarSource(sidebar: sidebar, now: { Self.stamp }), space: space, today: today)
  }

  @Test func moveNodesIsOneMutation() throws {
    let world = try makeWorld()
    var saves = 0
    world.source.onDidChange = { _ in saves += 1 }
    try world.source.moveNodes([world.today[0], world.today[2]], to: .pinned(world.space), at: 0)
    #expect(saves == 1)
    #expect(world.source.children(of: .pinned(world.space)) == [world.today[0], world.today[2]])
    #expect(world.source.children(of: .today(world.space)) == [world.today[1], world.today[3]])
  }

  @Test func moveNodesMapsAFullFavoritesSection() throws {
    let world = try makeWorld()
    for index in 0..<SidebarModel.Sidebar.maximumFavorites {
      _ = try world.source.addTab(url: URL(string: "https://f.example/\(index)")!, title: "f",
                                  in: .favorites(profile: "default"))
    }
    #expect(throws: SidebarMoveError.favoritesFull) {
      try world.source.moveNodes([world.today[0]], to: .favorites(profile: "default"), at: 0)
    }
  }

  @Test func moveNodesIntoASplitIsRefused() throws {
    let world = try makeWorld()
    let split = try world.source.addToSplit(.existing(world.today[1]), target: world.today[0], at: 1,
                                            orientation: .horizontal).split
    #expect(throws: SidebarMoveError.invalid) {
      try world.source.moveNodes([world.today[2]], to: .split(split), at: 0)
    }
  }

  @Test func aPaneMovedOutOfATwoPaneSplitLeavesNoSplit() throws {
    let world = try makeWorld()
    let split = try world.source.addToSplit(.existing(world.today[1]), target: world.today[0], at: 1,
                                            orientation: .horizontal).split
    try world.source.moveNode(world.today[1], to: .pinned(world.space), at: 0)
    #expect(world.source.node(split) == nil)
    #expect(world.source.parent(of: world.today[0]) == .today(world.space))
    #expect(world.source.children(of: .pinned(world.space)) == [world.today[1]])
  }

  @Test func aMoveKeepsTheStoredURLAndIdleClock() throws {
    let world = try makeWorld()
    try world.source.moveNodes([world.today[0]], to: .favorites(profile: "default"), at: 0)
    try world.source.moveNodes([world.today[0]], to: .pinned(world.space), at: 0)
    guard case .tab(let tab)? = world.source.sidebar.nodes[world.today[0]]?.kind else {
      Issue.record("not a tab")
      return
    }
    #expect(tab.url == URL(string: "https://example.com/0")!)
    #expect(tab.lastActiveAt == Self.stamp)
  }

  @Test func theDefaultMoveNodesOfAForwardingSourceMovesEachNodeInOrder() throws {
    let stub = StubSidebar()
    let space = try stub.addSpace(title: "S")
    let tabs = try (0..<3).map { try stub.addTab(url: URL(string: "https://s.example/\($0)")!, title: "s",
                                                in: .today(space)) }
    try stub.moveNodes([tabs[0], tabs[1]], to: .pinned(space), at: 0)
    #expect(stub.children(of: .pinned(space)) == [tabs[0], tabs[1]])
  }
}
