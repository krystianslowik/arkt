import Foundation
import Testing
@testable import ShellUI

/// Pinned tabs (BH-055, BH-057): the pure side of pin/unpin and reset — which node the command acts on, the menu
/// title, the toast text, and the rule that keeps a pinned (or Favorite) node's stored URL off live navigation.
@MainActor
struct PinnedTabLogicTests {
  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private func makeSidebar() -> (StubSidebar, SpaceID) {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    return (sidebar, space)
  }

  // MARK: The node the pin command acts on (KB-012)

  @Test func aTodayTabPinsItself() {
    let (sidebar, space) = makeSidebar()
    let tab = sidebar.addTab(url: Self.url("t"), title: "T", in: .today(space))
    #expect(ShellWindowController.pinnableNode(tab, in: sidebar) == tab)
  }

  @Test func aPinnedTabUnpinsItself() {
    let (sidebar, space) = makeSidebar()
    let tab = sidebar.addTab(url: Self.url("p"), title: "P", in: .pinned(space))
    #expect(ShellWindowController.pinnableNode(tab, in: sidebar) == tab)
  }

  /// A focused pane pins its whole split (BH-115); the split itself keeps both panes.
  @Test func aPanePinsItsSplit() {
    let (sidebar, space) = makeSidebar()
    let split = sidebar.addSplit(in: .today(space))
    let pane = sidebar.addTab(url: Self.url("s"), title: "S", in: .split(split))
    #expect(ShellWindowController.pinnableNode(pane, in: sidebar) == split)
    let pinnedSplit = sidebar.addSplit(in: .pinned(space))
    let pinnedPane = sidebar.addTab(url: Self.url("s2"), title: "S2", in: .split(pinnedSplit))
    #expect(ShellWindowController.pinnableNode(pinnedPane, in: sidebar) == pinnedSplit)
  }

  /// Favorites, foldered tabs and nodes without a sidebar place have no pin toggle.
  @Test func favoritesFoldersAndUnknownNodesAreNotPinnable() {
    let (sidebar, space) = makeSidebar()
    let favorite = sidebar.addTab(url: Self.url("f"), title: "F", in: .favorites(profile: "default"))
    let folder = sidebar.addFolder(title: "F", in: .pinned(space))
    let foldered = sidebar.addTab(url: Self.url("g"), title: "G", in: .folder(folder))
    #expect(ShellWindowController.pinnableNode(favorite, in: sidebar) == nil)
    #expect(ShellWindowController.pinnableNode(foldered, in: sidebar) == nil)
    #expect(ShellWindowController.pinnableNode(NodeID(), in: sidebar) == nil)
  }

  // MARK: Menu title and toast text (BH-055)

  @Test func theMenuTitleFollowsThePinState() {
    #expect(ShellWindowController.pinMenuTitle(isPinned: false) == "Pin Tab")
    #expect(ShellWindowController.pinMenuTitle(isPinned: true) == "Unpin Tab")
  }

  /// [S] toast strings (BH-055); no browser name in user-facing copy.
  @Test func theToastNamesTheSpace() {
    #expect(ShellWindowController.pinToastText(pinned: true, spaceTitle: "Work") == "Pinned Tab to Work")
    #expect(ShellWindowController.pinToastText(pinned: false, spaceTitle: "Work") == "Un-Pinned Tab from Work")
  }

  // MARK: The stored URL of a pinned or Favorite node (BH-057, BH-048)

  /// Only Today nodes track the page's URL; pinned and Favorite nodes keep the pinned URL so Reset (BH-057) and
  /// reopening (BH-068's direction) can return to it. The title still follows the page (BH-062).
  @Test func onlyTodayNodesTrackTheLiveURL() {
    let space = SpaceID()
    #expect(ShellWindowController.writesLiveURL(toSection: .today(space)))
    #expect(!ShellWindowController.writesLiveURL(toSection: .pinned(space)))
    #expect(!ShellWindowController.writesLiveURL(toSection: .favorites(profile: "default")))
    #expect(!ShellWindowController.writesLiveURL(toSection: nil))
  }
}
