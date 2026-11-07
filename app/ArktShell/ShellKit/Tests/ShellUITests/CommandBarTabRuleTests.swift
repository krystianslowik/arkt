import Foundation
import Testing
@testable import ShellUI

/// The maintainer's decision on #371: Tab is smart. It scopes the search when the selected row shows a Tab key cap
/// (a site-search row), and when the field is empty on a bar just opened for a new tab (the hint strip shows Tab for
/// action search, #322); otherwise it cycles the filters.
struct CommandBarTabRuleTests {
  private let youTube = SiteSearchEngine(alias: "yt", name: "YouTube",
                                         searchURLTemplate: "https://www.youtube.com/results?search_query=%s")
  private let url = URL(string: "https://example.com")!

  private func row(_ kind: CommandBarResults.Kind, engine: SiteSearchEngine? = nil) -> CommandBarResults.Result {
    var row = CommandBarResults.Result(kind: kind, title: "t", subtitle: "", trailingHint: nil, removalID: nil)
    row.siteSearchEngine = engine
    return row
  }

  private func decide(scope: CommandBarResults.Scope = .normal, queryIsEmpty: Bool = false, isNewTab: Bool = true,
                      selected: CommandBarResults.Result? = nil) -> CommandBarTabAction {
    CommandBarTabAction.decide(scope: scope, queryIsEmpty: queryIsEmpty, isNewTab: isNewTab, selected: selected)
  }

  @Test func `a selected site-search row with a Tab key cap scopes to its site`() {
    #expect(decide(selected: row(.siteSearch(url), engine: youTube)) == .scopeSite(youTube))
    #expect(row(.siteSearch(url), engine: youTube).showsTabKeyCap)
  }

  @Test func `the cap wins over the empty-field rule`() {
    #expect(decide(queryIsEmpty: true, selected: row(.siteSearch(url), engine: youTube)) == .scopeSite(youTube))
  }

  @Test func `a site-search row in a scope has no Tab key cap`() {
    #expect(!row(.siteSearch(url)).showsTabKeyCap)
  }

  @Test func `an empty field on a new-tab bar enters action search`() {
    #expect(decide(queryIsEmpty: true, selected: row(.switchTo(UUID()))) == .scopeActions)
    #expect(decide(queryIsEmpty: true, selected: nil) == .scopeActions)
  }

  @Test func `an empty field outside a new-tab bar cycles the filters`() {
    #expect(decide(queryIsEmpty: true, isNewTab: false, selected: nil) == .cycleFilter)
  }

  @Test func `anything else cycles the filters`() {
    #expect(decide(selected: row(.search(url))) == .cycleFilter)
    #expect(decide(selected: row(.switchTo(UUID()))) == .cycleFilter)
    #expect(decide(selected: nil) == .cycleFilter)
  }

  @Test func `inside a scope Tab is consumed and changes nothing`() {
    #expect(decide(scope: .actions, selected: row(.action("a"))) == .consume)
    #expect(decide(scope: .siteSearch(youTube), selected: row(.siteSearch(url))) == .consume)
  }

  @Test func `the hint strip advertises the Tab that will happen`() {
    #expect(CommandBarTabAction.hint(scope: .normal, queryIsEmpty: true, isNewTab: true, selected: nil)
            == CommandBarHints.Item(keyCaps: ["tab"], caption: "Actions"))
    #expect(CommandBarTabAction.hint(scope: .normal, queryIsEmpty: false, isNewTab: true,
                                     selected: row(.siteSearch(url), engine: youTube))
            == CommandBarHints.Item(keyCaps: ["tab"], caption: "Search site"))
    #expect(CommandBarTabAction.hint(scope: .normal, queryIsEmpty: false, isNewTab: true,
                                     selected: row(.search(url))) == nil, "a cycling Tab is covered by Cmd 1-4")
    #expect(CommandBarTabAction.hint(scope: .actions, queryIsEmpty: true, isNewTab: true, selected: nil) == nil)
  }

  @Test func `a site-search row shows its Tab key cap, then Return when selected`() {
    let site = row(.siteSearch(url), engine: youTube)
    #expect(site.trailing(isSelected: false) == [.keyCap("tab")])
    #expect(site.trailing(isSelected: true) == [.keyCap("tab"), .keyCap(CommandBarKeyCaps.return)])
  }
}
