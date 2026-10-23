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

  /// BH-104: an open tab that is a split pane says "Switch to Split View"; any other says "Switch to Tab".
  @Test func openTabsMarksSplitPanes() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    func url(_ s: String) -> URL { URL(string: s)! }
    let plain = sidebar.addTab(url: url("https://plain.dev"), title: "Plain", in: .today(space))
    let split = sidebar.addSplit(in: .today(space))
    let left = sidebar.addTab(url: url("https://left.dev"), title: "Left", in: .split(split))
    _ = sidebar.addTab(url: url("https://right.dev"), title: "Right", in: .split(split))

    let tabs = CommandBarResults.openTabs(in: sidebar, space: space)
    #expect(tabs.map(\.node) == [plain, left])
    #expect(tabs.map(\.isSplitPane) == [false, true])

    let hints = CommandBarResults.make(query: "", openTabs: tabs).map(\.trailingHint)
    #expect(hints == ["Switch to Tab", "Switch to Split View"])
  }

  @Test func emptySpaceHasNoTabs() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    #expect(CommandBarResults.openTabs(in: sidebar, space: space).isEmpty)
  }
}
