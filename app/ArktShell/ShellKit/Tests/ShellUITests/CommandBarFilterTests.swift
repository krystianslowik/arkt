import Foundation
import Testing
@testable import ShellUI

/// The filter pills' counts (design/command-bar/README.md, Filters).
struct CommandBarFilterTests {
  private let url = URL(string: "https://example.com")!

  private func result(_ kind: CommandBarResults.Kind) -> CommandBarResults.Result {
    CommandBarResults.Result(kind: kind, title: "t", subtitle: "", trailingHint: nil, removalID: nil)
  }

  @Test func `the four pills in order`() {
    #expect(CommandBarFilter.allCases == [.all, .tabs, .history, .actions])
    #expect(CommandBarFilter.allCases.map(\.title) == ["All", "Tabs", "History", "Actions"])
  }

  @Test func `All counts every row, the others their own kind`() {
    let results = [result(.switchTo(UUID())), result(.search(url)), result(.siteSearch(url)), result(.action("a")),
                   result(.action("b")), result(.pasteAndGo(url))]
    let counts = CommandBarFilter.counts(of: results)
    #expect(counts[.all] == 6)
    #expect(counts[.tabs] == 1)
    #expect(counts[.history] == 0)
    #expect(counts[.actions] == 2)
  }

  @Test func `archived results belong to All and Tabs`() {
    let results = [result(.restore(UUID())), result(.switchTo(UUID()))]
    #expect(CommandBarFilter.counts(of: results)[.tabs] == 2)
    #expect(CommandBarFilter.tabs.includes(result(.restore(UUID()))))
    #expect(!CommandBarFilter.actions.includes(result(.restore(UUID()))))
  }

  @Test func `suggestions and site search rows belong to All only`() {
    for kind in [CommandBarResults.Kind.search(url), .siteSearch(url), .open(url), .pasteAndGo(url)] {
      let row = result(kind)
      #expect(CommandBarFilter.all.includes(row))
      for filter in [CommandBarFilter.tabs, .history, .actions] { #expect(!filter.includes(row)) }
    }
  }

  @Test func `counts are hidden with an empty query`() {
    #expect(!CommandBarFilter.showsCounts(forQuery: ""))
    #expect(!CommandBarFilter.showsCounts(forQuery: "   "))
    #expect(CommandBarFilter.showsCounts(forQuery: "git"))
  }
}
