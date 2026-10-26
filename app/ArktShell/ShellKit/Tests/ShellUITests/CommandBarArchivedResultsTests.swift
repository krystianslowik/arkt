import Foundation
import Testing
@testable import ShellUI

/// #111 (BH-087, BH-104): archived matches in the command bar, after open tabs and before the search row, at most
/// three, with the "Restore from Archive" caption.
struct CommandBarArchivedResultsTests {
  let tab = CommandBarResults.OpenTab(node: UUID(), title: "Expense sheet", url: URL(string: "https://open.example")!)

  static func archived(_ count: Int) -> [CommandBarResults.ArchivedMatch] {
    (0..<count).map {
      CommandBarResults.ArchivedMatch(id: UUID(), title: "Expense report \($0)",
                                      subtitle: "sheets.example, Work, archived Sep 22")
    }
  }

  @Test func archivedMatchesFollowOpenTabsAndPrecedeTheSearchRow() {
    let results = CommandBarResults.make(query: "expense", openTabs: [tab], archived: Self.archived(1))
    #expect(results.map(\.kind.name) == ["switch", "restore", "search"])
    #expect(results[1].title == "Expense report 0")
    #expect(results[1].subtitle == "sheets.example, Work, archived Sep 22")
    #expect(results[1].trailingHint == "Restore from Archive")
    #expect(results[1].accessibilityCaption == "Restore from Archive")
  }

  @Test func atMostThreeArchivedMatches() {
    let results = CommandBarResults.make(query: "expense", openTabs: [], archived: Self.archived(5))
    #expect(results.filter { $0.kind.name == "restore" }.count == 3)
  }

  @Test func anEmptyQueryListsNoArchivedItems() {
    #expect(CommandBarResults.make(query: "  ", openTabs: [tab], archived: Self.archived(2)).map(\.kind.name)
      == ["switch"])
  }

  @Test func restoreKindCarriesTheArchivedID() {
    let match = Self.archived(1)[0]
    let results = CommandBarResults.make(query: "expense", openTabs: [], archived: [match])
    #expect(results.first?.kind == .restore(match.id))
  }
}
