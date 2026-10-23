import Foundation
import Testing
@testable import ShellUI

@MainActor
struct CommandBarOpenTabsTests {
  @Test func collectsTabsInsideFoldersAndFirstPaneOfSplits() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    func url(_ s: String) -> URL { URL(string: s)! }
    let pinnedTab = sidebar.addTab(url: url("https://a.dev"), title: "A", in: .pinned(space))
    let folder = sidebar.addFolder(title: "Trips", in: .pinned(space))
    let lisbon = sidebar.addTab(url: url("https://lisbon.dev"), title: "Lisbon", in: .folder(folder))
    let inner = sidebar.addFolder(title: "Inner", in: .folder(folder))
    let flights = sidebar.addTab(url: url("https://flights.dev"), title: "Flights", in: .folder(inner))
    let split = sidebar.addSplit(in: .today(space))
    let left = sidebar.addTab(url: url("https://left.dev"), title: "Left", in: .split(split))
    _ = sidebar.addTab(url: url("https://right.dev"), title: "Right", in: .split(split))
    let today = sidebar.addTab(url: url("https://today.dev"), title: "Today", in: .today(space))

    let tabs = CommandBarResults.openTabs(in: sidebar, space: space)
    #expect(tabs.map(\.node) == [pinnedTab, lisbon, flights, left, today])
    #expect(tabs.map(\.title) == ["A", "Lisbon", "Flights", "Left", "Today"])
  }

  @Test func emptySpaceHasNoTabs() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    #expect(CommandBarResults.openTabs(in: sidebar, space: space).isEmpty)
  }
}
