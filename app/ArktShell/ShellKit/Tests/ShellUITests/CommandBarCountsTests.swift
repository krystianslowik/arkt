import Foundation
import Testing
@testable import ShellUI

/// The pill counts come from the same pass as the rows (#606): every match of each kind, the caps lifted, the removed
/// suggestions left out, without building a row for each match.
struct CommandBarCountsTests {
  private static func input() -> CommandBarResults.Input {
    var input = CommandBarResults.Input()
    input.openTabs = (1...20).map {
      .init(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).example")!)
    }
    input.history = (1...10).map {
      .init(title: "Tab history \($0)", url: URL(string: "https://h\($0).example/tab")!)
    }
    input.spaces = (1...4).map { .init(id: UUID(), title: "Tab space \($0)") }
    input.archived = (1...5).map { .init(id: UUID(), title: "Tab archived \($0)", subtitle: "a.example") }
    input.actions = (1...5).map { CommandBarAction(id: "a\($0)", title: "Tab action \($0)") }
    return input
  }

  @Test func `one pass gives the capped rows and every match counted`() {
    var input = Self.input()
    input.excluded = ["tab:\(input.openTabs[0].node.uuidString)", "tab:\(input.openTabs[15].node.uuidString)",
                      "history:\(input.history[9].url.absoluteString)", "search:Tab"]
    let made = CommandBarResults.makeWithCounts(query: "Tab", input: input)
    #expect(made.results == CommandBarResults.make(query: "Tab", input: input), "the same rows as make")
    #expect(made.results.filter { $0.rowKind == .openTab }.count == 5, "six shown, one of them removed")
    #expect(made.counts[.tabs] == 18 + 5, "open tabs not removed, and every archived match")
    #expect(made.counts[.history] == 9)
    #expect(made.counts[.actions] == 5)
    #expect(made.counts[.all] == 18 + 5 + 9 + 4 + 5, "no search row: it was removed")
    #expect(CommandBarResults.counts(query: "Tab", input: input) == made.counts)
  }

  @Test func `an address, the search row and a site alias count under All only`() {
    var input = Self.input()
    input.siteSearchEngines = SiteSearchEngines.seeded
    input.archived = []                                  // the store's matches are listed for any query, capped
    let made = CommandBarResults.makeWithCounts(query: "yt", input: input)
    let kinds = Set(made.results.map(\.rowKind))
    #expect(kinds.contains(.siteSearch) && kinds.contains(.searchSuggestion))
    #expect(made.counts == CommandBarFilter.counts(of: made.results), "nothing capped: the rows are the counts")
  }

  @Test func `counts are hidden for an empty query and follow the rows in a scope`() {
    var input = Self.input()
    #expect(CommandBarResults.makeWithCounts(query: " ", input: input).counts == CommandBarFilter.counts(of: []))
    input.scope = .actions
    let made = CommandBarResults.makeWithCounts(query: "Tab", input: input)
    #expect(made.counts[.actions] == 5)
    #expect(made.counts == CommandBarFilter.counts(of: made.results))
  }
}

/// The matcher the rows use answers as `localizedStandardContains` does (#606).
struct CommandBarStandardMatchTests {
  @Test(arguments: ["cafe", "CAFÉ", "é", "straße", "STRASSE", "会议", "ملاحظات", "Ελλ", "ελλ", "xn--", "", " ", "İ"])
  func `same answers as localizedStandardContains`(query: String) {
    let texts = ["Café au lait", "Die Straße", "会议记录和计划", "ملاحظات الاجتماع", "Ελληνικές σημειώσεις",
                 "xn--bcher-kva.example", "", "Istanbul", "İstanbul", "plain ascii"]
    let match = CommandBarResults.StandardMatch(query)
    for text in texts {
      #expect(match.found(in: text) == text.localizedStandardContains(query), "\(text) / \(query)")
    }
  }
}
