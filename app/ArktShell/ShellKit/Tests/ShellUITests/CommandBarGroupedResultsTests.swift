import Foundation
import Testing
@testable import ShellUI

/// The grouped results (design/command-bar/README.md, "Row order and what each group searches"): a literal row, then
/// Tabs, Folders, History, Extensions and Search, three rows each, a group with no rows has no header. Synthetic data.
@MainActor
struct CommandBarGroupedResultsTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func tab(_ title: String, _ url: String, viewed minutesAgo: Double? = nil,
                   node: NodeID = NodeID()) -> CommandBarResults.OpenTab {
    CommandBarResults.OpenTab(node: node, title: title, url: URL(string: url)!,
                              lastViewed: minutesAgo.map { now.addingTimeInterval(-60 * $0) })
  }

  private func visit(_ title: String, _ url: String, hoursAgo: Double = 1) -> CommandBarResults.HistoryVisit {
    CommandBarResults.HistoryVisit(title: title, url: URL(string: url)!, visited: now.addingTimeInterval(-3600 * hoursAgo))
  }

  private func input(_ build: (inout CommandBarResults.Input) -> Void = { _ in }) -> CommandBarResults.Input {
    var input = CommandBarResults.Input()
    input.now = now
    build(&input)
    return input
  }

  private func groups(_ rows: [CommandBarResults.Result]) -> [CommandBarResults.Group?] {
    var seen: [CommandBarResults.Group?] = []
    for row in rows where seen.last.map({ $0 != row.group }) ?? true { seen.append(row.group) }
    return seen
  }

  // MARK: Order and caps

  /// The spec's `search` state: every group in its fixed order, the Search for row first in Search.
  @Test func groupsComeInTheFixedOrder() {
    let rows = CommandBarResults.grouped(query: "git", input: input {
      $0.openTabs = [tab("Git - Branches in a Nutshell", "https://git-scm.com/book/en/v2/branches"),
                     tab("acme/atlas", "https://code.example/acme/atlas/pulls")]
      $0.folders = [.init(node: NodeID(), title: "Git reading list", tabCount: 6)]
      $0.history = [visit("Git - Book", "https://git-scm.com/book/en/v2")]
      $0.extensions = [.init(id: "pilot", name: "Git Pilot", description: "Pull request shortcuts")]
      $0.suggestions = ["git rebase onto", "git stash pop"]
    })
    #expect(groups(rows) == [.tabs, .folders, .history, .extensions, .search])
    #expect(rows.map(\.kind.name) == ["switch", "folder", "history", "extension", "search", "suggestion", "suggestion"])
    #expect(rows[4].title == "git")
    #expect(rows[4].kind == .search(URLInputParser.searchURL(for: "git")))
    #expect(rows[5].title == "git rebase onto")
  }

  /// At most three rows per group, so sixteen rows in the worst case.
  @Test func eachGroupShowsAtMostThreeRows() {
    let rows = CommandBarResults.grouped(query: "layout.example", input: input {
      $0.openTabs = (1...9).map { tab("Layout \($0)", "https://layout.example/\($0)") }
      $0.folders = (1...9).map { .init(node: NodeID(), title: "layout.example \($0)", tabCount: $0) }
      $0.history = (1...9).map { visit("Layout page \($0)", "https://layout.example/h\($0)") }
      $0.extensions = (1...9).map { .init(id: "e\($0)", name: "Layout.example tool \($0)", description: "") }
      $0.suggestions = (1...9).map { "layout.example \($0)" }
    })
    #expect(rows.count == 16)
    #expect(rows.first?.kind == .open(URL(string: "https://layout.example")!))
    #expect(rows.first?.group == nil, "the Go row has no header")
    for group in CommandBarResults.Group.allCases {
      #expect(rows.count { $0.group == group } == 3)
    }
  }

  /// A group with no rows has no header: the headers are the groups that have rows.
  @Test func headersMarkTheFirstRowOfEachGroup() {
    let rows = CommandBarResults.grouped(query: "zqxv wplk", input: input())
    #expect(rows.count == 1)
    #expect(CommandBarResults.groupHeaders(of: rows) == [0: "Search"])
  }

  /// Text always gets the Search for row, so a query never ends in an empty list.
  @Test func textAlwaysHasTheSearchForRow() {
    for query in ["zqxv", "https://atlas.example", "atlas.example"] {
      let rows = CommandBarResults.grouped(query: query, input: input { $0.searchSuggestionsEnabled = false })
      #expect(rows.contains { $0.kind == .search(URLInputParser.searchURL(for: query)) }, "\(query)")
    }
  }

  /// A typed address puts the Go row above the groups, with the text as typed and no URL slot.
  @Test func anAddressGetsTheGoRowFirst() {
    let rows = CommandBarResults.grouped(query: "git-scm.com/book", input: input {
      $0.openTabs = [tab("Git - Book", "https://git-scm.com/book/en/v2")]
    })
    #expect(rows.first?.kind == .open(URL(string: "https://git-scm.com/book")!))
    #expect(rows.first?.title == "git-scm.com/book")
    #expect(rows.first?.secondaryText == "")
    #expect(groups(rows) == [nil, .tabs, .search])
  }

  // MARK: Empty field

  /// Paste and Go (with the clipboard address), three recent tabs, three recent history rows; nothing else.
  @Test func theEmptyFieldShowsPasteRecentTabsAndRecentHistory() {
    let current = NodeID()
    let rows = CommandBarResults.grouped(query: "", input: input {
      $0.clipboardURL = URL(string: "https://example.com/notes/launch")
      $0.currentTab = current
      $0.openTabs = [tab("Now", "https://now.example", viewed: 0, node: current),
                     tab("Old", "https://old.example", viewed: 90), tab("Never", "https://never.example"),
                     tab("Recent", "https://recent.example", viewed: 2), tab("Middle", "https://middle.example", viewed: 12)]
      $0.folders = [.init(node: NodeID(), title: "Reading", tabCount: 2)]
      $0.extensions = [.init(id: "x", name: "Tool", description: "")]
      $0.history = [visit("Older", "https://h1.example", hoursAgo: 30), visit("Newest", "https://h2.example", hoursAgo: 1),
                    visit("Mid", "https://h3.example", hoursAgo: 5), visit("Oldest", "https://h4.example", hoursAgo: 80)]
      $0.suggestions = ["ignored"]
    })
    #expect(rows.map(\.title) == ["Paste and Go", "Recent", "Middle", "Old", "Newest", "Mid", "Older"])
    #expect(rows[0].kind == .pasteAndGo(URL(string: "https://example.com/notes/launch")!))
    #expect(rows[0].secondaryText == "example.com/notes/launch")
    #expect(groups(rows) == [nil, .tabs, .history])
  }

  /// Cmd-L's untouched address: a Reload row on top, with no header, the page's host in the URL slot, verb Reload.
  @Test func anUntouchedCmdLAddressGetsTheReloadRowFirst() throws {
    let page = URL(string: "https://docs.example.com/q4-roadmap")!
    let rows = CommandBarResults.grouped(query: "", input: input {
      $0.reloadURL = page
      $0.openTabs = [tab("A", "https://a.example")]
    })
    #expect(rows.map(\.kind.name) == ["reload", "switch"])
    let reload = try #require(rows.first)
    #expect(reload.kind == .reload(page))
    #expect(reload.group == nil)
    #expect(reload.title == "Reload")
    #expect(reload.secondaryText == "docs.example.com")
    #expect(reload.symbolName == "arrow.clockwise")
    #expect(reload.verb == "Reload")
    #expect(reload.accessibilityCaption == "Reload")
    #expect(reload.commandBarLabel(position: 1, of: 2) == "Reload, docs.example.com, reload, 1 of 2")
    #expect(CommandBarResults.groupHeaders(of: rows) == [1: "Tabs"])
    #expect(CommandBarResults.grouped(query: "a", input: input { $0.reloadURL = page }).allSatisfy {
      $0.kind != .reload(page)
    }, "typed text has no Reload row")
  }

  /// No clipboard address: no Paste and Go row. No history (the app has no store yet, #631): no History header and no
  /// gap, the Tabs group is the whole list.
  @Test func noClipboardAddressNoPasteRowAndNoHistoryNoHeader() {
    let rows = CommandBarResults.grouped(query: "  ", input: input { $0.openTabs = [tab("A", "https://a.example")] })
    #expect(rows.map(\.kind.name) == ["switch"])
    #expect(CommandBarResults.groupHeaders(of: rows) == [0: "Tabs"])
  }

  // MARK: Tabs

  /// The current tab is not offered; matching is by word start in the title and the host and path.
  @Test func tabsMatchWordStartsAndSkipTheCurrentTab() {
    let current = NodeID()
    let rows = CommandBarResults.grouped(query: "book", input: input {
      $0.currentTab = current
      $0.openTabs = [tab("Book club", "https://club.example", node: current),
                     tab("Facebook", "https://facebook.example"),
                     tab("Pro Git", "https://git-scm.com/book/en"),
                     tab("Notebook", "https://notes.example")]
    })
    #expect(rows.filter { $0.group == .tabs }.map(\.title) == ["Pro Git"])
  }

  /// A title match beats a URL match, a title prefix beats a word inside it; ties go to the most recently viewed.
  @Test func tabsRankByMatchThenRecency() {
    let rows = CommandBarResults.grouped(query: "plan", input: input {
      $0.openTabs = [tab("Notes", "https://plan.example/notes", viewed: 1),
                     tab("Weekly plan", "https://a.example", viewed: 50),
                     tab("Quarter plan", "https://b.example", viewed: 5),
                     tab("Plan B", "https://c.example", viewed: 500)]
    })
    #expect(rows.filter { $0.group == .tabs }.map(\.title) == ["Plan B", "Quarter plan", "Weekly plan"])
  }

  /// Several words each match a word start somewhere; CJK text matches without spaces.
  @Test func wordsAndCJKMatch() {
    let rows = CommandBarResults.grouped(query: "lay book", input: input {
      $0.openTabs = [tab("Layout", "https://layout.example.jp/book/3"),
                     tab("レイアウトエンジンの設計", "https://jp.example/x")]
    })
    #expect(rows.filter { $0.group == .tabs }.map(\.title) == ["Layout"])
    let cjk = CommandBarResults.grouped(query: "エンジン", input: input {
      $0.openTabs = [tab("レイアウトエンジンの設計", "https://jp.example/x")]
    })
    #expect(cjk.filter { $0.group == .tabs }.count == 1)
  }

  /// A tab row shows host and path without the scheme, and says Switch to Tab.
  @Test func aTabRowShowsHostAndPath() throws {
    let rows = CommandBarResults.grouped(query: "cycle", input: input {
      $0.openTabs = [tab("Cycle 42", "https://linear.app/acme/cycle/42")]
    })
    let row = try #require(rows.first)
    #expect(row.secondaryText == "linear.app/acme/cycle/42")
    #expect(row.verb == "Switch to Tab")
  }

  // MARK: Folders, History, Extensions

  /// Folders match the name only and say how many tabs they hold.
  @Test func foldersMatchTheNameAndCountTabs() {
    let recent = NodeID()
    let rows = CommandBarResults.grouped(query: "read", input: input {
      $0.folders = [.init(node: NodeID(), title: "Reading list", tabCount: 1, lastViewed: now.addingTimeInterval(-900)),
                    .init(node: recent, title: "Reading", tabCount: 6, lastViewed: now.addingTimeInterval(-60)),
                    .init(node: NodeID(), title: "Thread", tabCount: 2)]
    })
    let folders = rows.filter { $0.group == .folders }
    #expect(folders.map(\.title) == ["Reading", "Reading list"])
    #expect(folders.map(\.secondaryText) == ["6 tabs", "1 tab"])
    #expect(folders.first?.kind == .folder(recent))
    #expect(folders.first?.verb == "Show Folder")
  }

  /// History keeps the provider's (frecency) order, drops a page that is an open tab, and shows the time.
  @Test func historySkipsOpenTabsAndKeepsItsOrder() {
    let rows = CommandBarResults.grouped(query: "git", input: input {
      $0.openTabs = [tab("Git - Book", "https://git-scm.com/book")]
      $0.history = [visit("Git cheat sheet", "https://training.example/git", hoursAgo: 40),
                    visit("Git - Book", "https://git-scm.com/book", hoursAgo: 2),
                    visit("Git flow", "https://flow.example", hoursAgo: 1)]
    })
    let history = rows.filter { $0.group == .history }
    #expect(history.map(\.title) == ["Git cheat sheet", "Git flow"])
    #expect(history.first?.verb == "Open")
    #expect(history.first?.timeText != nil)
  }

  /// Extensions match name and description, rank by match then name, and carry their icon.
  @Test func extensionsMatchNameAndDescription() {
    let icon = Data([1, 2, 3])
    let rows = CommandBarResults.grouped(query: "notes", input: input {
      $0.extensions = [.init(id: "b", name: "Sticky", description: "Notes pinned to elements"),
                       .init(id: "a", name: "Notes Pro", description: "", iconPNG: icon),
                       .init(id: "c", name: "Annotate", description: "Draw on pages")]
    })
    let extensions = rows.filter { $0.group == .extensions }
    #expect(extensions.map(\.title) == ["Notes Pro", "Sticky"])
    #expect(extensions.first?.kind == .extensionAction("a"))
    #expect(extensions.first?.iconPNG == icon)
    #expect(extensions.last?.secondaryText == "Notes pinned to elements")
    #expect(extensions.first?.verb == "Open Extension")
  }

  // MARK: Search

  /// Suggestions fill rows below the Search for row, at most two, only with the setting on, never repeating the text.
  @Test func suggestionsFollowTheSetting() {
    let on = CommandBarResults.grouped(query: "git", input: input { $0.suggestions = ["Git", "git a", "git b", "git c"] })
    #expect(on.filter { $0.group == .search }.map(\.title) == ["git", "git a", "git b"])
    #expect(on.last?.kind == .suggestion(URLInputParser.searchURL(for: "git b")))
    #expect(on.last?.verb == "Search")
    let off = CommandBarResults.grouped(query: "git", input: input {
      $0.suggestions = ["git a"]
      $0.searchSuggestionsEnabled = false
    })
    #expect(off.filter { $0.group == .search }.map(\.title) == ["git"])
  }

  /// The Search for row has no verb: its title says it.
  @Test func theSearchForRowHasNoVerb() {
    let rows = CommandBarResults.grouped(query: "zq", input: input())
    #expect(rows.first?.verb == nil)
    #expect(rows.first?.displayTitle == "Search for \u{201C}zq\u{201D}")
  }

  // MARK: Accessibility

  /// "<title>, <secondary text>, <kind>, <k> of <n>".
  @Test func rowsReadTheirKindAndPosition() {
    let rows = CommandBarResults.grouped(query: "git-scm.com/book", input: input {
      $0.openTabs = [tab("Git - Book", "https://git-scm.com/book/en/v2")]
    })
    #expect(rows.map { $0.commandBarLabel(position: 1, of: 3) } == [
      "git-scm.com/book, go to address, 1 of 3",
      "Git - Book, git-scm.com/book/en/v2, open tab, 1 of 3",
      "Search for \u{201C}git-scm.com/book\u{201D}, search for what you typed, 1 of 3",
    ])
  }

  /// The count announced once typing settles.
  @Test func theResultCountAnnouncement() {
    let only = CommandBarResults.grouped(query: "zq", input: input())
    #expect(CommandBarResults.countAnnouncement(for: only) == "No matches. Return searches the web.")
    let more = CommandBarResults.grouped(query: "a.example", input: input())
    #expect(CommandBarResults.countAnnouncement(for: more) == "2 results")
  }

  // MARK: Removal

  /// Cmd-Opt-Delete removes a history row; removed rows stay hidden.
  @Test func removedHistoryStaysHidden() {
    let gone = visit("Git flow", "https://flow.example")
    let rows = CommandBarResults.grouped(query: "git", input: input {
      $0.history = [gone, visit("Git book", "https://book.example")]
      $0.excluded = ["history:https://flow.example"]
    })
    #expect(rows.filter { $0.group == .history }.map(\.title) == ["Git book"])
    #expect(rows.first { $0.group == .history }?.removalID == "history:https://book.example")
    #expect(rows.first { $0.group == .search }?.removalID == nil)
  }

  // MARK: Selection

  /// Up and Down wrap on a fresh press and stop at the ends on a held key.
  @Test func arrowsWrapOnAPressAndStopOnRepeat() {
    #expect(CommandBarSelection.move(from: 2, by: 1, count: 3, isRepeat: false) == 0)
    #expect(CommandBarSelection.move(from: 2, by: 1, count: 3, isRepeat: true) == 2)
    #expect(CommandBarSelection.move(from: 0, by: -1, count: 3, isRepeat: false) == 2)
    #expect(CommandBarSelection.move(from: 0, by: -1, count: 3, isRepeat: true) == 0)
    #expect(CommandBarSelection.move(from: 1, by: 1, count: 3, isRepeat: true) == 2)
    #expect(CommandBarSelection.move(from: 0, by: 1, count: 0, isRepeat: false) == nil)
  }

  /// Tab and Shift-Tab jump to the first row of the next or previous group; the literal row counts as its own.
  @Test func tabJumpsBetweenGroups() {
    let groups: [CommandBarResults.Group?] = [nil, .tabs, .tabs, .history, .history, .search]
    #expect(CommandBarSelection.groupJump(from: 0, forward: true, groups: groups) == 1)
    #expect(CommandBarSelection.groupJump(from: 2, forward: true, groups: groups) == 3)
    #expect(CommandBarSelection.groupJump(from: 4, forward: true, groups: groups) == 5)
    #expect(CommandBarSelection.groupJump(from: 5, forward: true, groups: groups) == nil)
    #expect(CommandBarSelection.groupJump(from: 4, forward: false, groups: groups) == 1)
    #expect(CommandBarSelection.groupJump(from: 1, forward: false, groups: groups) == 0)
    #expect(CommandBarSelection.groupJump(from: 0, forward: false, groups: groups) == nil)
  }
}
