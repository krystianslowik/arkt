import Foundation
import Testing
@testable import ShellUI

/// The scoped and enriched `make(query:input:)`: Paste and Go (BH-108), action search (BH-106), site search
/// (BH-107), Spaces (BH-104), removal exclusions (BH-109) and the suggestions setting (BH-113).
struct CommandBarResultsScopeTests {
  let tab = CommandBarResults.OpenTab(node: UUID(), title: "Example Domain",
                                      url: URL(string: "https://example.com")!)

  private func input(_ build: (inout CommandBarResults.Input) -> Void) -> CommandBarResults.Input {
    var input = CommandBarResults.Input()
    build(&input)
    return input
  }

  // MARK: Paste and Go (BH-108, GS-035)

  @Test func pasteAndGoIsTheTopSuggestionOnAnEmptyQuery() {
    let results = CommandBarResults.make(query: "", input: input {
      $0.clipboardURL = URL(string: "https://clip.example/a")
    })
    #expect(results.first?.kind == .pasteAndGo(URL(string: "https://clip.example/a")!))
    #expect(results.first?.title == "Paste and Go")
    #expect(results.first?.accessibilityCaption == "Paste and Go")
  }

  @Test func pasteAndGoStaysAboveTheOpenTabs() {
    let results = CommandBarResults.make(query: "", input: input {
      $0.clipboardURL = URL(string: "https://clip.example")
      $0.openTabs = [tab]
    })
    #expect(results.map(\.kind.name) == ["pasteAndGo", "switch"])
  }

  @Test func typedQueryReplacesPasteAndGo() {
    let results = CommandBarResults.make(query: "clip", input: input {
      $0.clipboardURL = URL(string: "https://clip.example")
    })
    #expect(results.contains { $0.kind.name == "pasteAndGo" } == false)
  }

  @Test func noClipboardURLNoPasteAndGo() {
    #expect(CommandBarResults.make(query: "", input: input { _ in }).isEmpty)
  }

  // MARK: Action search (BH-106, KB-081)

  @Test func actionScopeListsTheActions() {
    let results = CommandBarResults.make(query: "", input: input {
      $0.scope = .actions
      $0.actions = [CommandBarAction(id: "newSpace", title: "New Space")]
      $0.openTabs = [tab]
    })
    #expect(results.map(\.kind) == [.action("newSpace")])
    #expect(results.first?.title == "New Space")
    #expect(results.first?.accessibilityCaption == "Action")
  }

  @Test func actionScopeFiltersByQuery() {
    let results = CommandBarResults.make(query: "tool", input: input {
      $0.scope = .actions
      $0.actions = [CommandBarAction(id: "newSpace", title: "New Space"),
                    CommandBarAction(id: "toggleToolbar", title: "Toggle Toolbar")]
    })
    #expect(results.map(\.kind) == [.action("toggleToolbar")])
  }

  // MARK: Site search (BH-107, KB-082)

  private let youTube = SiteSearchEngine(alias: "yt", name: "YouTube",
                                         searchURLTemplate: "https://www.youtube.com/results?search_query=%s")

  @Test func siteScopeOffersOneEngineRow() {
    let results = CommandBarResults.make(query: "lofi", input: input {
      $0.scope = .siteSearch(youTube)
      $0.openTabs = [tab]
    })
    #expect(results.map(\.kind.name) == ["siteSearch"])
    guard case .siteSearch(let url) = results.first?.kind else { Issue.record("no siteSearch row"); return }
    #expect(url.absoluteString == "https://www.youtube.com/results?search_query=lofi")
    #expect(results.first?.subtitle == "Search YouTube")
    #expect(results.first?.accessibilityCaption == "Search")
  }

  @Test func siteScopeWithAnEmptyQueryHasNoRows() {
    #expect(CommandBarResults.make(query: "", input: input { $0.scope = .siteSearch(youTube) }).isEmpty)
  }

  // MARK: Spaces (BH-104)

  @Test func matchingSpacesFollowTheOpenTabs() {
    let other = UUID()
    let results = CommandBarResults.make(query: "example", input: input {
      $0.openTabs = [tab]
      $0.spaces = [CommandBarResults.Space(id: UUID(), title: "Example Space"),
                   CommandBarResults.Space(id: other, title: "Other")]
    })
    #expect(results.map(\.kind.name) == ["switch", "switchSpace", "search"])
    #expect(results[1].trailingHint == "Switch to Space")
    #expect(results[1].accessibilityCaption == "Switch to Space")
  }

  @Test func emptyQueryListsNoSpaces() {
    let results = CommandBarResults.make(query: "", input: input {
      $0.spaces = [CommandBarResults.Space(id: UUID(), title: "Work")]
    })
    #expect(results.isEmpty)
  }

  // MARK: Removal (BH-109, KB-083)

  @Test func removableRowsCarryARemovalID() {
    let results = CommandBarResults.make(query: "domain", input: input { $0.openTabs = [tab] })
    #expect(results.map(\.kind.name) == ["switch", "search"])
    #expect(results[0].removalID == "tab:\(tab.node.uuidString)")
    #expect(results[1].removalID == "search:domain")
  }

  @Test func typedURLAndPasteAndGoAreNotRemovable() {
    let results = CommandBarResults.make(query: "", input: input {
      $0.clipboardURL = URL(string: "https://clip.example")
    })
    #expect(results.first?.removalID == nil)
    let open = CommandBarResults.make(query: "example.com", input: input { _ in })
    #expect(open.first?.kind.name == "open")
    #expect(open.first?.removalID == nil)
  }

  @Test func excludedSuggestionsAreHidden() {
    let results = CommandBarResults.make(query: "domain", input: input {
      $0.openTabs = [tab]
      $0.excluded = ["tab:\(tab.node.uuidString)"]
    })
    #expect(results.map(\.kind.name) == ["search"])
  }

  // MARK: Suggestions setting (BH-113)

  @Test func suggestionsOffDropsTheSearchRow() {
    #expect(CommandBarResults.make(query: "domain", input: input {
      $0.searchSuggestionsEnabled = false
    }).isEmpty)
  }

  @Test func suggestionsOffKeepsTheOtherRows() {
    let results = CommandBarResults.make(query: "domain", input: input {
      $0.openTabs = [tab]
      $0.searchSuggestionsEnabled = false
    })
    #expect(results.map(\.kind.name) == ["switch"])
  }
}
