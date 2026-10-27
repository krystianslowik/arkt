import Foundation
import Testing
@testable import ShellUI

/// The empty state (design/command-bar/README.md): Clipboard, Recent tabs (up to four) and Actions, each under a small
/// header, with the first row selected.
struct CommandBarEmptyStateTests {
  private let clip = URL(string: "https://arkt.dev/changelog")!

  private func tab(_ n: Int, viewed: Date? = nil) -> CommandBarResults.OpenTab {
    .init(node: UUID(), title: "Tab \(n)", url: URL(string: "https://t\(n).example")!, lastViewed: viewed)
  }

  private func make(_ configure: (inout CommandBarResults.Input) -> Void) -> [CommandBarResults.Result] {
    var input = CommandBarResults.Input()
    configure(&input)
    return CommandBarResults.make(query: "", input: input)
  }

  @Test func `Clipboard, then Recent tabs, then Actions`() {
    let results = make {
      $0.clipboardURL = clip
      $0.recentTabs = (1...6).map { tab($0) }
      $0.actions = [CommandBarAction(id: "newSpace", title: "New Space"), CommandBarAction(id: "b", title: "B"),
                    CommandBarAction(id: "c", title: "C")]
    }
    #expect(results.map(\.group) == [.clipboard] + Array(repeating: .recentTabs, count: 4)
            + [.actions, .actions])
    #expect(results.first?.kind.name == "pasteAndGo")
    #expect(results.count == 7, "one clipboard row, four recent tabs, two actions")
    #expect(CommandBarResults.groupHeaders(of: results) == [0: "Clipboard", 1: "Recent tabs", 5: "Actions"])
  }

  @Test func `with nothing on the clipboard the first recent tab leads`() {
    let results = make { $0.recentTabs = [tab(1), tab(2)] }
    #expect(results.map(\.group) == [.recentTabs, .recentTabs])
    #expect(CommandBarResults.groupHeaders(of: results) == [0: "Recent tabs"])
  }

  @Test func `without recent tabs the open tabs stand in`() {
    let results = make { $0.openTabs = [tab(1), tab(2), tab(3), tab(4), tab(5)] }
    #expect(results.count == 4)
    #expect(results.allSatisfy { $0.group == .recentTabs })
  }

  @Test func `the plain convenience (Little Arkt's lookup) still lists up to six open tabs with no groups`() {
    let results = CommandBarResults.make(query: "", openTabs: (1...8).map { tab($0) })
    #expect(results.count == 6)
    #expect(results.allSatisfy { $0.group == nil })
  }

  @Test func `a recent tab says when it was viewed`() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let results = make { $0.recentTabs = [tab(1, viewed: now.addingTimeInterval(-12 * 60))]; $0.now = now }
    #expect(results.first?.timeText == "12 min")
    #expect(results.first?.trailing(isSelected: false) == [.text("12 min")])
    #expect(results.first?.trailingHint == CommandBarResults.switchHint, "the caption stays the action")
  }

  @Test func `a recent tab with no time keeps the Switch to Tab caption`() {
    let results = make { $0.recentTabs = [tab(1)] }
    #expect(results.first?.trailingHint == CommandBarResults.switchHint)
  }

  @Test func `the empty state lists no Spaces, archived items or search rows`() {
    let results = make {
      $0.spaces = [.init(id: UUID(), title: "Work")]
      $0.archived = [.init(id: UUID(), title: "A", subtitle: "s")]
      $0.recentTabs = [tab(1)]
    }
    #expect(results.count == 1)
  }

  @Test func `typing leaves the groups: no headers on search results`() {
    var input = CommandBarResults.Input()
    input.openTabs = [tab(1)]
    input.actions = [CommandBarAction(id: "tool", title: "Toggle Toolbar")]
    let results = CommandBarResults.make(query: "t", input: input)
    #expect(results.allSatisfy { $0.group == nil })
    #expect(CommandBarResults.groupHeaders(of: results).isEmpty)
  }

  @Test func `a query also finds matching actions, so the Actions pill has something to count`() {
    var input = CommandBarResults.Input()
    input.actions = [CommandBarAction(id: "tool", title: "Toggle Toolbar"), CommandBarAction(id: "n", title: "New Space")]
    let results = CommandBarResults.make(query: "tool", input: input)
    #expect(results.filter { $0.rowKind == .action }.map(\.title) == ["Toggle Toolbar"])
    #expect(CommandBarFilter.counts(of: results)[.actions] == 1)
  }

  @Test func `an alias or a site name shows a site-search row with a Tab key cap`() {
    var input = CommandBarResults.Input()
    input.siteSearchEngines = SiteSearchEngines.seeded
    let byAlias = CommandBarResults.make(query: "yt", input: input)
    #expect(byAlias.contains { $0.siteSearchEngine?.name == "YouTube" })
    let byName = CommandBarResults.make(query: "git", input: input)
    let row = byName.first { $0.rowKind == .siteSearch }
    #expect(row?.title == "Search GitHub for git")
    #expect(row?.showsTabKeyCap == true)
    #expect(CommandBarResults.make(query: "zzz", input: input).allSatisfy { $0.rowKind != .siteSearch })
    #expect(CommandBarResults.make(query: "g", input: input).allSatisfy { $0.rowKind != .siteSearch }, "one letter is too little")
  }

  @Test func `an exact alias reads Search <site> without repeating itself`() {
    var input = CommandBarResults.Input()
    input.siteSearchEngines = SiteSearchEngines.seeded
    let row = CommandBarResults.make(query: "yt", input: input).first { $0.rowKind == .siteSearch }
    #expect(row?.title == "Search YouTube")
  }
}
