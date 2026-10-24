import Foundation
import Testing
@testable import ShellUI

@MainActor
struct SidebarModelStubTests {
  @Test func sampleHasThreeSpacesAndFavorites() {
    let s = StubSidebar.sample()
    #expect(s.spaceOrder.count == 3)
    #expect(s.children(of: .favorites(profile: "default")).count == 6)
    let first = s.spaceOrder[0]
    #expect(!s.children(of: .pinned(first)).isEmpty)
    #expect(!s.children(of: .today(first)).isEmpty)
  }

  @Test func sampleSpacesCarryThemes() throws {
    let s = StubSidebar.sample()
    let spaces = s.spaceOrder.compactMap { s.space($0) }
    #expect(spaces.map(\.title) == ["Personal", "Work", "Dev"])
    #expect(spaces.map(\.theme.isDark) == [false, false, true])
    #expect(spaces.allSatisfy { $0.theme.baseColors.count == 2 && $0.profile == "default" })
  }

  @Test func everySpaceHasAFolderWithTwoTabsInPinned() {
    let s = StubSidebar.sample()
    for space in s.spaceOrder {
      let folders = s.children(of: .pinned(space)).filter {
        if case .folder = s.node($0) { return true } else { return false }
      }
      #expect(folders.count == 1)
      let inside = s.children(of: .folder(folders[0]))
      #expect(inside.count == 2)
      #expect(inside.allSatisfy { if case .tab = s.node($0) { true } else { false } })
    }
  }

  @Test func todayInFirstSpaceStartsWithTwoTabs() {
    let s = StubSidebar.sample()
    let today = s.children(of: .today(s.spaceOrder[0]))
    #expect(today.count >= 2)
    #expect(today.prefix(2).allSatisfy { if case .tab = s.node($0) { true } else { false } })
  }

  @Test func addTabAppendsToTodayAndNotifies() {
    let s = StubSidebar.sample()
    let space = s.spaceOrder[1]
    var changed: [SidebarChange] = []
    let observation = s.observe { changed.append($0) }
    let id = s.addTab(url: URL(string: "https://example.com")!, title: "Example", in: .today(space))
    #expect(s.children(of: .today(space)).last == id)
    #expect(changed == [.structure(.today(space))])
    s.updateTab(id, url: nil, title: "Example Domain")
    #expect(s.node(id) == .tab(id: id, url: URL(string: "https://example.com")!, title: "Example Domain"))
    #expect(changed == [.structure(.today(space)), .node(id)], "a title change is node-level, not structural")
    #expect(s.parent(of: id) == .today(space))
    observation.cancel()
  }

  @Test func updateTabOnUnknownOrNonTabNodeIsIgnored() {
    let s = StubSidebar.sample()
    var changed: [SidebarChange] = []
    let observation = s.observe { changed.append($0) }
    s.updateTab(UUID(), url: nil, title: "x")
    let folder = s.children(of: .pinned(s.spaceOrder[0])).first {
      if case .folder = s.node($0) { return true } else { return false }
    }!
    s.updateTab(folder, url: nil, title: "x")
    #expect(changed.isEmpty)
    observation.cancel()
  }

  @Test func multipleObserversAllReceiveChanges() {
    let s = StubSidebar.sample()
    var first: [SidebarChange] = [], second: [SidebarChange] = []
    let a = s.observe { first.append($0) }
    let b = s.observe { second.append($0) }
    let id = s.addTab(url: URL(string: "https://example.com")!, title: "E", in: .today(s.spaceOrder[0]))
    #expect(first == [.structure(.today(s.spaceOrder[0]))])
    #expect(second == first)
    a.cancel()
    s.updateTab(id, url: nil, title: "F")
    #expect(first.count == 1, "cancelled observers stop receiving")
    #expect(second.last == .node(id))
    b.cancel()
  }

  @Test func releasingTheObservationStopsDelivery() {
    let s = StubSidebar.sample()
    var count = 0
    var observation: SidebarObservation? = s.observe { _ in count += 1 }
    s.addTab(url: URL(string: "https://example.com")!, title: "E", in: .today(s.spaceOrder[0]))
    #expect(count == 1)
    _ = observation
    observation = nil
    s.addTab(url: URL(string: "https://example.com")!, title: "E", in: .today(s.spaceOrder[0]))
    #expect(count == 1)
  }

  @Test func splitNodeHoldsTabs() throws {
    let s = StubSidebar.sample()
    let work = s.spaceOrder[1]
    let split = try #require(s.children(of: .today(work)).first {
      if case .split = s.node($0) { return true } else { return false }
    })
    #expect(s.children(of: .split(split)).count == 2)
    #expect(s.parent(of: s.children(of: .split(split))[0]) == .split(split))
  }

  @Test func spaceOfNodeWalksUpThroughContainers() throws {
    let s = StubSidebar.sample()
    let space = s.spaceOrder[0]
    let folder = try #require(s.children(of: .pinned(space)).first {
      if case .folder = s.node($0) { return true } else { return false }
    })
    let inner = s.children(of: .folder(folder))[0]
    #expect(s.spaceID(containing: inner) == space)
    let favorite = s.children(of: .favorites(profile: "default"))[0]
    #expect(s.spaceID(containing: favorite) == nil)
  }

  @Test func addSpaceEmitsSpaceAdded() throws {
    let stub = StubSidebar()
    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }
    let source: any SidebarSource = stub              // through the protocol requirement
    let space = try source.addSpace(title: "New")
    #expect(changes == [.spaceAdded(space)])
    _ = observation
  }

  @Test func spaceEditsEmitTheirSpaceEvent() {
    let stub = StubSidebar()
    let a = stub.addSpace(title: "A")
    let b = stub.addSpace(title: "B")
    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }
    stub.renameSpace(a, to: "A2")
    stub.setIcon(a, to: SpaceIconInfo(symbol: "star"))
    stub.setTheme(a, to: SpaceThemeInfo(baseColors: [], isDark: true))
    stub.setIcon(a, to: SpaceIconInfo(symbol: "star"))          // unchanged: no event
    stub.moveSpace(b, to: 0)
    stub.removeSpace(a)
    #expect(changes == [.spaceChanged(a), .spaceChanged(a), .spaceChanged(a), .spaceMoved(b), .spaceRemoved(a)])
    #expect(stub.spaceOrder == [b])
    _ = observation
  }

  @Test func moveSpaceToItsOwnPlaceOrAnUnknownSpaceEmitsNothing() {
    let stub = StubSidebar()
    let a = stub.addSpace(title: "A")
    let b = stub.addSpace(title: "B")
    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }
    stub.moveSpace(a, to: 0)
    stub.moveSpace(SpaceID(), to: 1)
    stub.moveSpace(a, to: 9)                          // clamped to the end
    #expect(stub.spaceOrder == [b, a])
    #expect(changes == [.spaceMoved(a)])
    _ = observation
  }

  @Test func sectionContainingWalksThroughFolders() {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    let folder = stub.addFolder(title: "F", in: .pinned(space))
    let tab = stub.addTab(url: URL(string: "https://a.example")!, title: "A", in: .folder(folder))
    #expect(stub.section(containing: tab) == .pinned(space))
  }

  /// #94: `StubSidebar.removeNode` and `moveNode` (index-before-removal convention, subtree removal, and cross-location
  /// moves) emit `.structure` only for locations that changed.
  @Test func removeNodeAndMoveNodeFollowIndexBeforeRemovalAndSubtreeRules() {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "S")
    let url = URL(string: "https://a.example")!
    let t0 = stub.addTab(url: url, title: "T0", in: .today(space))
    let t1 = stub.addTab(url: url, title: "T1", in: .today(space))
    let t2 = stub.addTab(url: url, title: "T2", in: .today(space))
    let folder = stub.addFolder(title: "F", in: .pinned(space))
    let subFolder = stub.addFolder(title: "Sub", in: .folder(folder))
    let nestedTab = stub.addTab(url: url, title: "Nested", in: .folder(subFolder))

    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }

    // Same-parent move uses index-before-removal: moving t0 to index 2 places it between t1 and t2.
    stub.moveNode(t0, to: .today(space), at: 2)
    #expect(stub.children(of: .today(space)) == [t1, t0, t2])
    #expect(changes == [.structure(.today(space))])

    // Moving to the same effective position, unknown node, or into own subtree changes nothing and emits nothing.
    changes.removeAll()
    stub.moveNode(t1, to: .today(space), at: 0)
    stub.moveNode(t1, to: .today(space), at: 1)
    stub.moveNode(NodeID(), to: .today(space), at: 0)
    stub.moveNode(folder, to: .folder(folder), at: 0)
    stub.moveNode(folder, to: .folder(subFolder), at: 0)
    #expect(changes.isEmpty)

    // Cross-location move updates parent and emits both locations.
    stub.moveNode(t2, to: .folder(folder), at: 0)
    #expect(stub.children(of: .today(space)) == [t1, t0])
    #expect(stub.children(of: .folder(folder)) == [t2, subFolder])
    #expect(stub.parent(of: t2) == .folder(folder))
    #expect(changes == [.structure(.today(space)), .structure(.folder(folder))])

    // Removing a folder drops its whole subtree and emits only the folder's parent location.
    changes.removeAll()
    stub.removeNode(NodeID())
    #expect(changes.isEmpty)
    stub.removeNode(folder)
    #expect(stub.node(folder) == nil)
    #expect(stub.node(subFolder) == nil)
    #expect(stub.node(nestedTab) == nil)
    #expect(stub.node(t2) == nil)
    #expect(changes == [.structure(.pinned(space))])
    _ = observation
  }
}
