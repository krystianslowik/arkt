import Foundation
import Testing
@testable import ShellUI

/// The filter state machine behind the pills (design/command-bar/README.md, Filters and Keyboard): cycling, Cmd-1..4,
/// what a filter keeps, and the empty row.
struct CommandBarFilterStateTests {
  private let url = URL(string: "https://example.com")!

  private func result(_ kind: CommandBarResults.Kind, group: CommandBarResults.Group? = nil) -> CommandBarResults.Result {
    var row = CommandBarResults.Result(kind: kind, title: "t", subtitle: "", trailingHint: nil, removalID: nil)
    row.group = group
    return row
  }

  @Test func `Tab cycles forward and wraps, Shift-Tab goes back and wraps`() {
    #expect(CommandBarFilter.all.next == .tabs)
    #expect(CommandBarFilter.tabs.next == .history)
    #expect(CommandBarFilter.history.next == .actions)
    #expect(CommandBarFilter.actions.next == .all)
    #expect(CommandBarFilter.all.previous == .actions)
    #expect(CommandBarFilter.tabs.previous == .all)
  }

  @Test func `Command 1 to 4 pick the pills in order`() {
    #expect(CommandBarFilter(commandDigit: 1) == .all)
    #expect(CommandBarFilter(commandDigit: 2) == .tabs)
    #expect(CommandBarFilter(commandDigit: 3) == .history)
    #expect(CommandBarFilter(commandDigit: 4) == .actions)
    #expect(CommandBarFilter(commandDigit: 0) == nil)
    #expect(CommandBarFilter(commandDigit: 5) == nil)
  }

  @Test func `a filter keeps only its kinds and All keeps everything`() {
    let rows = [result(.switchTo(UUID())), result(.search(url)), result(.action("a")), result(.restore(UUID()))]
    #expect(CommandBarFilter.all.apply(to: rows, query: "x") == rows)
    #expect(CommandBarFilter.tabs.apply(to: rows, query: "x").map(\.kind.name) == ["switch", "restore"])
    #expect(CommandBarFilter.actions.apply(to: rows, query: "x").map(\.kind.name) == ["action"])
  }

  @Test func `a filter that matches nothing shows one empty row naming the filter and the query`() {
    let rows = [result(.search(url))]
    let filtered = CommandBarFilter.history.apply(to: rows, query: "git")
    #expect(filtered.count == 1)
    #expect(filtered.first?.kind.name == "noMatch")
    #expect(filtered.first?.title == "No History match git")
    #expect(filtered.first?.rowKind == .noMatch)
    #expect(CommandBarFilter.actions.apply(to: [], query: "zz").first?.title == "No Actions match zz")
  }

  @Test func `the empty row says what is missing for an empty query too`() {
    #expect(CommandBarFilter.tabs.apply(to: [], query: "").first?.title == "No Tabs")
  }

  @Test func `All never shows the empty row`() {
    #expect(CommandBarFilter.all.apply(to: [], query: "zz").isEmpty)
  }

  @Test func `the empty row is not selectable content: no symbol, no trailing group, no secondary text`() throws {
    let empty = try #require(CommandBarFilter.tabs.apply(to: [], query: "q").first)
    #expect(empty.trailing(isSelected: true).isEmpty)
    #expect(empty.secondaryText.isEmpty)
    #expect(empty.accessibilityLabel(position: 1, of: 1) == "No Tabs match q")
    #expect(!empty.isActionable)
    #expect(result(.search(url)).isActionable)
  }

  @Test func `group headers sit on the first filtered row of each group`() {
    let rows = [result(.pasteAndGo(url), group: .clipboard), result(.switchTo(UUID()), group: .recentTabs),
                result(.switchTo(UUID()), group: .recentTabs), result(.action("a"), group: .actions)]
    #expect(CommandBarResults.groupHeaders(of: rows) == [0: "Clipboard", 1: "Recent tabs", 3: "Actions"])
    let tabsOnly = CommandBarFilter.tabs.apply(to: rows, query: "")
    #expect(CommandBarResults.groupHeaders(of: tabsOnly) == [0: "Recent tabs"], "the header moves to the first kept row")
    #expect(CommandBarResults.groupHeaders(of: [result(.search(url))]).isEmpty)
  }
}
