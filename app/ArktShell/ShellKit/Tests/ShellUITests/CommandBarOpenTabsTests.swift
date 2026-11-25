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

  /// BH-104: open tabs come from every Space, in the order the caller passes (the window puts the current
  /// Space first, so a Space switch refresh reorders, BH-111).
  @Test func collectsTabsAcrossSpacesInTheGivenOrder() throws {
    let sidebar = StubSidebar()
    func url(_ s: String) -> URL { URL(string: s)! }
    let theme = SpaceThemeInfo(baseColors: [], isDark: false)
    let work = sidebar.addSpace(title: "Work", theme: theme)
    let home = sidebar.addSpace(title: "Home", theme: theme)
    let a = sidebar.addTab(url: url("https://a.dev"), title: "A", in: .today(work))
    let b = sidebar.addTab(url: url("https://b.dev"), title: "B", in: .today(home))

    #expect(CommandBarResults.openTabs(in: sidebar, spaces: [home, work]).map(\.node) == [b, a])
    #expect(CommandBarResults.openTabs(in: sidebar, spaces: [work, home]).map(\.node) == [a, b])
  }
}

@MainActor
struct CommandBarFoldersTests {
  /// BH-104: the Pinned section's folders, nested ones included, depth first, with the tabs each holds (a nested
  /// folder's tabs count for the folder around it, a split counts as one) and the latest view inside. Today's folders
  /// are not listed.
  @Test func collectsPinnedFoldersWithTheirTabs() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    func url(_ s: String) -> URL { URL(string: s)! }
    let trips = sidebar.addFolder(title: "Trips", in: .pinned(space))
    let lisbon = sidebar.addTab(url: url("https://lisbon.dev"), title: "Lisbon", in: .folder(trips))
    let inner = sidebar.addFolder(title: "Inner", in: .folder(trips))
    let flights = sidebar.addTab(url: url("https://flights.dev"), title: "Flights", in: .folder(inner))
    let split = sidebar.addSplit(in: .folder(inner))
    _ = sidebar.addTab(url: url("https://left.dev"), title: "Left", in: .split(split))
    _ = sidebar.addTab(url: url("https://right.dev"), title: "Right", in: .split(split))
    _ = sidebar.addFolder(title: "Today folder", in: .today(space))
    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)
    let viewed = [lisbon: early, flights: late]

    let folders = CommandBarResults.folders(in: sidebar, spaces: [space]) { viewed[$0] }
    #expect(folders.map(\.title) == ["Trips", "Inner"])
    #expect(folders.map(\.node) == [trips, inner])
    #expect(folders.map(\.tabCount) == [3, 2])
    #expect(folders.map(\.lastViewed) == [late, late])
  }
}
