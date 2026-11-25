import Foundation
import Testing
@testable import ShellUI

/// Pins what Little Arkt's quick lookup lists (#354, docs/design/little-arkt.md "Quick lookup"), so a change to the
/// command bar's own rows (#993) cannot change the lookup: its rows, their captions and its selection moves.
@MainActor
struct LittleArktLookupResultsTests {
  private func tabs(_ count: Int) -> [CommandBarResults.OpenTab] {
    (1...count).map { CommandBarResults.OpenTab(node: NodeID(), title: "Notes \($0)",
                                                 url: URL(string: "https://notes\($0).example/page")!) }
  }

  private func shape(_ results: [CommandBarResults.Result]) -> [String] {
    results.map { "\($0.kind.name)|\($0.title)|\($0.subtitle)|\($0.trailingHint ?? "-")|\($0.accessibilityCaption)" }
  }

  /// An empty query lists the open tabs plainly, at most six, with the Switch to Tab caption.
  @Test func anEmptyQueryListsSixOpenTabs() {
    let rows = CommandBarResults.make(query: "", openTabs: tabs(8))
    #expect(shape(rows) == (1...6).map { "switch|Notes \($0)|notes\($0).example|Switch to Tab|Switch to Tab" })
  }

  /// A typed address: the address row, then the search row; no tab matches.
  @Test func anAddressListsTheAddressThenTheSearch() {
    let rows = CommandBarResults.make(query: "atlas.example/three-days", openTabs: tabs(2))
    #expect(rows.first?.kind == .open(URL(string: "https://atlas.example/three-days")!))
    #expect(shape(rows) == [
      "open|atlas.example/three-days|https://atlas.example/three-days|-|Open",
      "search|atlas.example/three-days|Search Google|-|Search",
    ])
  }

  /// An address with its scheme is a URL for certain: no search row (#96).
  @Test func anExplicitSchemeHasNoSearchRow() {
    let rows = CommandBarResults.make(query: "https://atlas.example", openTabs: [])
    #expect(shape(rows) == ["open|https://atlas.example||-|Open"])
  }

  /// Text matches tabs anywhere in the title (not only at word starts), capped at six, then the search row.
  @Test func textMatchesTabsBySubstringThenSearches() {
    let rows = CommandBarResults.make(query: "otes", openTabs: tabs(8))
    #expect(shape(rows) == (1...6).map { "switch|Notes \($0)|notes\($0).example|Switch to Tab|Switch to Tab" }
      + ["search|otes|Search Google|-|Search"])
  }

  /// A split pane's tab says Switch to Split View.
  @Test func aSplitPaneSaysSwitchToSplitView() {
    let tab = CommandBarResults.OpenTab(node: NodeID(), title: "Pane", url: URL(string: "https://pane.example")!,
                                        isSplitPane: true)
    #expect(CommandBarResults.make(query: "", openTabs: [tab]).first?.trailingHint == "Switch to Split View")
  }

  /// Up and Down always wrap; a page is five rows and stops at the ends.
  @Test func selectionWrapsAndPagesByFive() {
    #expect(CommandBarSelection.step(from: 2, by: 1, count: 3) == 0)
    #expect(CommandBarSelection.step(from: 0, by: -1, count: 3) == 2)
    #expect(CommandBarSelection.step(from: -1, by: -1, count: 3) == 2)
    #expect(CommandBarSelection.step(from: 0, by: 1, count: 0) == nil)
    #expect(CommandBarSelection.page(from: 0, by: 1, count: 20) == 5)
    #expect(CommandBarSelection.page(from: 18, by: 1, count: 20) == 19)
    #expect(CommandBarSelection.page(from: 3, by: -1, count: 20) == 0)
  }
}
