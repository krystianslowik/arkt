import AppKit
import Foundation
import Testing
@testable import ShellUI

/// The sidebar context menus of design/tab-context-menus (#105): titles, order, separators (""), key equivalents,
/// enabled rules, Option alternates and the actions, per row kind. Built as values, so no window is needed.
@MainActor
struct SidebarContextMenuTests {
  private let sidebar = StubSidebar()
  private let work: SpaceID
  private let personal: SpaceID
  private let url = URL(string: "https://example.com/a")!

  init() {
    work = sidebar.addSpace(title: "Work")
    personal = sidebar.addSpace(title: "Personal")
  }

  private var context: SidebarMenuContext {
    SidebarMenuContext(spaces: [(work, "Work"), (personal, "Personal")])
  }

  private func entries(_ target: SidebarMenuTarget, _ context: SidebarMenuContext? = nil) -> [SidebarMenuEntry] {
    SidebarContextMenu.entries(for: target, in: sidebar, context: context ?? self.context)
  }

  /// Titles of the primary items: Option alternates are hidden until Option is held.
  private func titles(_ entries: [SidebarMenuEntry]) -> [String] {
    entries.filter { !$0.isAlternate }.map(\.title)
  }

  private func entry(_ title: String, in entries: [SidebarMenuEntry]) throws -> SidebarMenuEntry {
    try #require(entries.first { $0.title == title }, "no item \(title)")
  }

  // MARK: 3.1 Today tab

  @Test func todayTabMenuMatchesTheDesign() throws {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    let menu = entries(.rows([tab]))
    #expect(titles(menu) == ["Rename", "Duplicate", "Pin Tab", "Move To", "", "Copy Link", "", "Archive Below",
                             "Archive"])
    #expect(try entry("Pin Tab", in: menu).keyEquivalent == "d")
    #expect(try entry("Pin Tab", in: menu).modifiers == .command)
    #expect(try entry("Archive", in: menu).keyEquivalent == "w")
    #expect(try entry("Rename", in: menu).action == .rename(tab))
    #expect(try entry("Duplicate", in: menu).action == .duplicate([tab]))
    #expect(try entry("Pin Tab", in: menu).action == .pinToggle([tab]))
    #expect(try entry("Archive", in: menu).action == .archive([tab]))
    #expect(try entry("Copy Link", in: menu).action == .copyLinks([tab], markdown: false))
  }

  @Test func copyLinkHasAMarkdownOptionAlternate() throws {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    let menu = entries(.rows([tab]))
    let index = try #require(menu.firstIndex { $0.title == "Copy Link" })
    let alternate = menu[index + 1]
    #expect(alternate.title == "Copy Link as Markdown")
    #expect(alternate.isAlternate)
    #expect(alternate.modifiers == .option)
    #expect(alternate.action == .copyLinks([tab], markdown: true))
  }

  /// BH-077: Archive Below needs a Today tab below this one.
  @Test func archiveBelowIsEnabledOnlyWithATabBelow() throws {
    let top = sidebar.addTab(url: url, title: "A", in: .today(work))
    let bottom = sidebar.addTab(url: url, title: "B", in: .today(work))
    #expect(try entry("Archive Below", in: entries(.rows([top]))).isEnabled)
    #expect(try entry("Archive Below", in: entries(.rows([top]))).action == .archiveBelow(top))
    #expect(try !entry("Archive Below", in: entries(.rows([bottom]))).isEnabled)
  }

  /// Move To: Favorites, a separator, then every Space in order with the row's own Space disabled (design 3.1).
  @Test func moveToListsFavoritesThenTheSpacesWithTheCurrentOneDisabled() throws {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    let submenu = try #require(try entry("Move To", in: entries(.rows([tab]))).submenu)
    #expect(submenu.map(\.title) == ["Favorites", "", "Work", "Personal"])
    #expect(submenu[0].action == .moveToFavorites([tab]))
    #expect(!submenu[2].isEnabled)
    #expect(submenu[3].isEnabled)
    #expect(submenu[3].action == .moveToSpace([tab], personal))
  }

  // MARK: 3.2 Pinned tab

  @Test func pinnedTabMenuMatchesTheDesignAndKeepsSeparateFromPinnedTab() throws {
    let tab = sidebar.addTab(url: url, title: "P", in: .pinned(work))
    let menu = entries(.rows([tab]))
    #expect(titles(menu) == ["Rename", "Duplicate", "Unpin Tab", "", "Back to Pinned URL",
                             "Replace Pin with Current Page", "Separate From Pinned Tab", "Edit Pinned URL", "",
                             "Move To", "", "Copy Link", "", "Close and Keep Pinned"])
    #expect(try entry("Close and Keep Pinned", in: menu).action == .archive([tab]))
    #expect(try entry("Close and Keep Pinned", in: menu).keyEquivalent == "w")
    #expect(try !entry("Edit Pinned URL", in: menu).isEnabled, "not built yet: shown disabled (OQ6)")
  }

  /// BH-057, BH-060, BH-061: the reset family needs a page that left its pinned URL.
  @Test func theResetFamilyFollowsTheNavigatedState() throws {
    let tab = sidebar.addTab(url: url, title: "P", in: .pinned(work))
    let resting = entries(.rows([tab]))
    let navigated = entries(.rows([tab]), SidebarMenuContext(spaces: [(work, "Work")], navigatedPins: [tab]))
    for title in ["Back to Pinned URL", "Replace Pin with Current Page", "Separate From Pinned Tab"] {
      #expect(try !entry(title, in: resting).isEnabled)
      #expect(try entry(title, in: navigated).isEnabled)
    }
    #expect(try entry("Back to Pinned URL", in: navigated).action == .resetPinned(tab))
  }

  /// A tab inside a pinned folder is pinned through its folder: no Unpin Tab.
  @Test func aFolderedPinnedTabHasNoPinToggle() {
    let folder = sidebar.addFolder(title: "F", in: .pinned(work))
    let tab = sidebar.addTab(url: url, title: "P", in: .folder(folder))
    #expect(!titles(entries(.rows([tab]))).contains("Unpin Tab"))
  }

  // MARK: 3.3 Favorite

  @Test func favoriteMenuMatchesTheDesign() throws {
    let favorite = sidebar.addTab(url: url, title: "F", in: .favorites(profile: "default"))
    let menu = entries(.favorite(favorite))
    #expect(titles(menu) == ["Rename", "Change Icon", "", "Back to Pinned URL", "Edit Pinned URL", "", "Copy Link",
                             "", "Remove from Favorites", "Close and Keep Favorite"])
    #expect(try entry("Remove from Favorites", in: menu).action == .removeFromFavorites(favorite))
    #expect(try entry("Close and Keep Favorite", in: menu).action == .archive([favorite]))
    #expect(try !entry("Back to Pinned URL", in: menu).isEnabled)
    #expect(try !entry("Rename", in: menu).isEnabled, "a tile shows no title to edit in place")
  }

  // MARK: 3.4 Folder

  @Test func folderMenuMatchesTheDesign() throws {
    let folder = sidebar.addFolder(title: "F", in: .pinned(work))
    let menu = entries(.rows([folder]))
    #expect(titles(menu) == ["Rename", "Change Icon", "", "Duplicate", "Share", "", "Copy All Links",
                             "Paste URL as New Tab", "", "Move To", "Delete"])
    #expect(try !entry("Share", in: menu).isEnabled)
    #expect(try !entry("Change Icon", in: menu).isEnabled)
    #expect(try entry("Delete", in: menu).action == .deleteFolder(folder))
    #expect(try entry("Copy All Links", in: menu).action == .copyLinks([folder], markdown: false))
    let alternate = try entry("Copy All as Markdown Links", in: menu)
    #expect(alternate.isAlternate)
    #expect(alternate.action == .copyLinks([folder], markdown: true))
    let moveTo = try #require(try entry("Move To", in: menu).submenu)
    #expect(moveTo.map(\.title) == ["Work", "Personal"], "folders cannot be Favorites")
  }

  @Test func pasteURLAsNewTabNeedsAURLOnTheClipboard() throws {
    let folder = sidebar.addFolder(title: "F", in: .pinned(work))
    #expect(try !entry("Paste URL as New Tab", in: entries(.rows([folder]))).isEnabled)
    let withURL = SidebarMenuContext(spaces: [(work, "Work")], clipboardHasURL: true)
    let item = try entry("Paste URL as New Tab", in: entries(.rows([folder]), withURL))
    #expect(item.isEnabled)
    #expect(item.action == .pasteURLAsNewTab(.folder(folder)))
  }

  // MARK: 3.5 Split and 3.6 pane

  @Test func splitMenuMatchesTheDesign() throws {
    let split = sidebar.addSplit(in: .today(work))
    sidebar.addTab(url: url, title: "L", in: .split(split))
    sidebar.addTab(url: url, title: "R", in: .split(split))
    let menu = entries(.rows([split]))
    #expect(titles(menu) == ["Rename", "Duplicate Split View", "", "Separate All Tabs",
                             "Convert to Vertical Split View", "", "Pin Tab", "Move To", "Share Split View"])
    #expect(try !entry("Rename", in: menu).isEnabled, "a split has no stored title yet")
    #expect(try entry("Separate All Tabs", in: menu).action == .separateSplit(split))
    #expect(try entry("Pin Tab", in: menu).action == .pinToggle([split]))
  }

  @Test func paneMenuMatchesTheDesign() throws {
    let split = sidebar.addSplit(in: .today(work))
    let left = sidebar.addTab(url: url, title: "L", in: .split(split))
    let right = sidebar.addTab(url: url, title: "R", in: .split(split))
    let menu = entries(.rows([left]))
    #expect(titles(menu) == ["Mute", "Duplicate Split View", "Archive Below", "Share", "",
                             "Remove Tab from Split View", "Archive"])
    #expect(try !entry("Mute", in: menu).isEnabled, "a pane without a page has nothing to mute")
    #expect(try entry("Duplicate Split View", in: menu).action == .duplicateSplit(split))
    #expect(try entry("Archive Below", in: menu).isEnabled)
    #expect(try !entry("Archive Below", in: entries(.rows([right]))).isEnabled)
    #expect(try entry("Remove Tab from Split View", in: menu).action == .removePane(left))
    #expect(try entry("Archive", in: menu).action == .archive([left]))
  }

  // MARK: Mute (#364, BH-126)

  @Test func paneMuteTogglesForALoadedPane() throws {
    let split = sidebar.addSplit(in: .today(work))
    let left = sidebar.addTab(url: url, title: "L", in: .split(split))
    sidebar.addTab(url: url, title: "R", in: .split(split))
    var loaded = context
    loaded.loadedTabs = [left]
    let mute = try entry("Mute", in: entries(.rows([left]), loaded))
    #expect(mute.isEnabled)
    #expect(mute.action == .toggleMute(left))

    loaded.audio = [left: .muted]
    let menu = entries(.rows([left]), loaded)
    #expect(titles(menu).first == "Unmute")
    #expect(try entry("Unmute", in: menu).action == .toggleMute(left))
  }

  @Test func todayTabOffersMuteOnlyWhilePlayingOrMuted() throws {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    var playing = context
    playing.loadedTabs = [tab]
    #expect(!titles(entries(.rows([tab]), playing)).contains("Mute"), "a silent tab keeps the design's menu")

    playing.audio = [tab: .playing]
    #expect(titles(entries(.rows([tab]), playing)) == ["Rename", "Duplicate", "Pin Tab", "Move To", "", "Mute", "",
                                                       "Copy Link", "", "Archive Below", "Archive"])
    #expect(try entry("Mute", in: entries(.rows([tab]), playing)).action == .toggleMute(tab))

    playing.audio = [tab: .muted]
    #expect(try entry("Unmute", in: entries(.rows([tab]), playing)).isEnabled)
  }

  /// A row that shows sound has a page, so its Mute is never shown disabled: a disabled item takes the click and
  /// sends nothing (#364, menu clicks that did not reach the shell).
  @Test(arguments: [TabAudio.playing, .muted])
  func soundingRowMuteIsEnabledWithoutLoadedState(_ audio: TabAudio) throws {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    let split = sidebar.addSplit(in: .today(work))
    let pane = sidebar.addTab(url: url, title: "L", in: .split(split))
    sidebar.addTab(url: url, title: "R", in: .split(split))
    var sounding = context
    sounding.audio = [tab: audio, pane: audio]
    #expect(try entry(audio.toggleTitle, in: entries(.rows([tab]), sounding)).isEnabled)
    #expect(try entry(audio.toggleTitle, in: entries(.rows([pane]), sounding)).isEnabled)
  }

  @Test func pinnedTabOffersMuteWhilePlaying() throws {
    let tab = sidebar.addTab(url: url, title: "P", in: .pinned(work))
    var playing = context
    playing.loadedTabs = [tab]
    playing.audio = [tab: .playing]
    let menu = titles(entries(.rows([tab]), playing))
    let moveTo = try #require(menu.firstIndex(of: "Move To"))
    #expect(Array(menu[moveTo...(moveTo + 3)]) == ["Move To", "", "Mute", ""])
  }

  @Test func audioStateFollowsMuteFirst() {
    #expect(TabAudio(isAudible: false, isMuted: false) == .silent)
    #expect(TabAudio(isAudible: true, isMuted: false) == .playing)
    #expect(TabAudio(isAudible: true, isMuted: true) == .muted)
    #expect(TabAudio(isAudible: false, isMuted: true) == .muted, "a muted tab shows its state so it can be unmuted")
    #expect(TabAudio.playing.toggleTitle == "Mute")
    #expect(TabAudio.muted.toggleTitle == "Unmute")
    #expect(TabAudio.silent.toggleTitle == "Mute")
  }

  // MARK: 3.7 Multi-selection

  @Test func multiSelectionMenuMatchesTheDesign() throws {
    let ids = (0..<3).map { sidebar.addTab(url: url, title: "T\($0)", in: .today(work)) }
    let menu = entries(.rows(ids))
    #expect(titles(menu) == ["Open in Split View", "New Folder", "", "Duplicate", "Pin Tabs", "Move To", "",
                             "Copy Links", "", "Archive"])
    #expect(try entry("Open in Split View", in: menu).action == .openInSplitView(ids))
    #expect(try entry("New Folder", in: menu).action == .newFolder(ids))
    #expect(try entry("Archive", in: menu).action == .archive(ids))
    #expect(try entry("Pin Tabs", in: menu).action == .pinToggle(ids))
  }

  /// BH-116, BH-117: Open in Split View takes 2 to 4 plain tabs.
  @Test func openInSplitViewNeedsTwoToFourPlainTabs() throws {
    let ids = (0..<5).map { sidebar.addTab(url: url, title: "T\($0)", in: .today(work)) }
    #expect(try entry("Open in Split View", in: entries(.rows(Array(ids.prefix(4))))).isEnabled)
    #expect(try !entry("Open in Split View", in: entries(.rows(ids))).isEnabled)
    let split = sidebar.addSplit(in: .today(work))
    sidebar.addTab(url: url, title: "L", in: .split(split))
    #expect(try !entry("Open in Split View", in: entries(.rows([ids[0], split]))).isEnabled)
  }

  @Test func aSelectionOfPinnedTabsOffersUnpinTabs() throws {
    let ids = (0..<2).map { sidebar.addTab(url: url, title: "P\($0)", in: .pinned(work)) }
    #expect(titles(entries(.rows(ids))).contains("Unpin Tabs"))
  }

  // MARK: 3.8 Empty area

  @Test func emptyAreaMenuMatchesTheDesign() throws {
    let menu = entries(.empty(work))
    #expect(titles(menu) == ["New Tab", "New Folder", "Paste URL as New Tab", "", "Clear Today Tabs"])
    #expect(try entry("New Tab", in: menu).keyEquivalent == "t")
    #expect(try entry("New Tab", in: menu).action == .newTab)
    #expect(try entry("New Folder", in: menu).action == .newEmptyFolder(work))
    #expect(try entry("Paste URL as New Tab", in: menu).action == .pasteURLAsNewTab(.today(work)))
    #expect(try !entry("Clear Today Tabs", in: menu).isEnabled, "the Space has no Today tabs")
    sidebar.addTab(url: url, title: "T", in: .today(work))
    let filled = try entry("Clear Today Tabs", in: entries(.empty(work)))
    #expect(filled.isEnabled)
    #expect(filled.action == .clearToday(work))
  }

  // MARK: Look (design section 7)

  /// Plain native items only: no item carries a key the menu bar does not own (the bar is the only place a key
  /// equivalent fires from when no menu is open).
  @Test func onlyMenuBarKeysAreShown() {
    let tab = sidebar.addTab(url: url, title: "T", in: .today(work))
    let keys = Set((entries(.rows([tab])) + entries(.empty(work))).map(\.keyEquivalent).filter { !$0.isEmpty })
    #expect(keys == ["d", "w", "t"])
  }
}
