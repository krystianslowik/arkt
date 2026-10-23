import Foundation
import Testing
@testable import ShellUI

struct CommandBarResultsTests {
  let tab = CommandBarResults.OpenTab(node: UUID(), title: "Example Domain", url: URL(string: "https://example.com")!)

  @Test func urlFirstThenMatchingTabsThenSearch() {
    let results = CommandBarResults.make(query: "example.com", openTabs: [tab])
    #expect(results.map(\.kind.name) == ["open", "switch", "search"])
    #expect(results[1].trailingHint == "Switch to Tab")
  }

  @Test func plainQueryHasSearchLastAndMatchesTitles() {
    let results = CommandBarResults.make(query: "domain", openTabs: [tab])
    #expect(results.map(\.kind.name) == ["switch", "search"])
  }

  @Test func emptyQueryListsOpenTabs() {
    #expect(CommandBarResults.make(query: "", openTabs: [tab]).map(\.kind.name) == ["switch"])
  }

  @Test func matchesHostCaseInsensitively() {
    let results = CommandBarResults.make(query: "EXAMPLE", openTabs: [tab])
    #expect(results.map(\.kind.name) == ["switch", "search"])
  }

  @Test func nonMatchingTabsAreDropped() {
    #expect(CommandBarResults.make(query: "zzz", openTabs: [tab]).map(\.kind.name) == ["search"])
  }

  @Test func capsSwitchResultsAtSix() {
    let tabs = (0..<10).map { CommandBarResults.OpenTab(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).dev")!) }
    let results = CommandBarResults.make(query: "tab", openTabs: tabs)
    #expect(results.filter { $0.kind.name == "switch" }.count == 6)
  }

  @Test func searchResultCarriesSearchURL() {
    let results = CommandBarResults.make(query: "hello world", openTabs: [])
    guard case .search(let url) = results.last?.kind else { Issue.record("no search result"); return }
    #expect(url == URLInputParser.searchURL(for: "hello world"))
  }
}
