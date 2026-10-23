import Foundation
import Testing
@testable import ShellUI

/// GS-043: what a row's hover close button does, and what it says, by the row's section and kind.
@MainActor
struct RowCloseActionTests {
  private let sidebar = StubSidebar()
  private let space: SpaceID
  private let url = URL(string: "https://example.com")!

  init() { space = sidebar.addSpace(title: "Work") }

  @Test func todayTabArchives() {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(space))
    #expect(RowCloseAction.resolve(tab, in: sidebar) == .archiveTab)
  }

  @Test func pinnedTabClosesAndKeepsThePin() {
    let tab = sidebar.addTab(url: url, title: "P", in: .pinned(space))
    #expect(RowCloseAction.resolve(tab, in: sidebar) == .closeKeepPinned)
  }

  @Test func tabsInsideFoldersFollowTheirSection() {
    let pinnedFolder = sidebar.addFolder(title: "F", in: .pinned(space))
    let pinned = sidebar.addTab(url: url, title: "P", in: .folder(pinnedFolder))
    let todayFolder = sidebar.addFolder(title: "G", in: .today(space))
    let today = sidebar.addTab(url: url, title: "T", in: .folder(todayFolder))
    #expect(RowCloseAction.resolve(pinned, in: sidebar) == .closeKeepPinned)
    #expect(RowCloseAction.resolve(today, in: sidebar) == .archiveTab)
  }

  /// User decision 4: a pane closes just itself, so it reads like a tab of its section.
  @Test func splitPanesActLikeTabsOfTheirSection() {
    let todaySplit = sidebar.addSplit(in: .today(space))
    let todayPane = sidebar.addTab(url: url, title: "L", in: .split(todaySplit))
    let pinnedSplit = sidebar.addSplit(in: .pinned(space))
    let pinnedPane = sidebar.addTab(url: url, title: "R", in: .split(pinnedSplit))
    #expect(RowCloseAction.resolve(todayPane, in: sidebar) == .archiveTab)
    #expect(RowCloseAction.resolve(pinnedPane, in: sidebar) == .closeKeepPinned)
  }

  @Test func splitRowsArchiveOrCloseTheWholeSplit() {
    let todaySplit = sidebar.addSplit(in: .today(space))
    let pinnedSplit = sidebar.addSplit(in: .pinned(space))
    #expect(RowCloseAction.resolve(todaySplit, in: sidebar) == .archiveSplit)
    #expect(RowCloseAction.resolve(pinnedSplit, in: sidebar) == .closeKeepPinned)
  }

  @Test func favoritesClose() {
    let favorite = sidebar.addTab(url: url, title: "F", in: .favorites(profile: "default"))
    #expect(RowCloseAction.resolve(favorite, in: sidebar) == .closeFavorite)
  }

  @Test func foldersAndUnknownNodesHaveNoCloseButton() {
    let folder = sidebar.addFolder(title: "F", in: .today(space))
    #expect(RowCloseAction.resolve(folder, in: sidebar) == nil)
    #expect(RowCloseAction.resolve(NodeID(), in: sidebar) == nil)
  }

  /// GS-043 [S] hover strings for Today and pinned; the split and Favorite strings are [I].
  @Test func tooltipsPerKind() {
    #expect(RowCloseAction.archiveTab.tooltip == "Archive this tab")
    #expect(RowCloseAction.closeKeepPinned.tooltip == "Close and Keep Pinned")
    #expect(RowCloseAction.archiveSplit.tooltip == "Archive this split")
    #expect(RowCloseAction.closeFavorite.tooltip == "Close this tab")
  }

  @Test func accessibilityActionNames() {
    #expect(RowCloseAction.archiveTab.accessibilityName == "Archive")
    #expect(RowCloseAction.archiveSplit.accessibilityName == "Archive")
    #expect(RowCloseAction.closeKeepPinned.accessibilityName == "Close")
    #expect(RowCloseAction.closeFavorite.accessibilityName == "Close")
  }
}
