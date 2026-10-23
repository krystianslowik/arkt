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
}
