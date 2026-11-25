import Foundation
import Testing
@testable import ShellUI

/// The row anatomy of design/command-bar/README.md: slot symbol, secondary text and the selected row's verb per row
/// kind, and the accessibility sentence "<title>, <secondary text>, <kind>, <k> of <n>".
struct CommandBarRowContentTests {
  private let url = URL(string: "https://github.com/acme/atlas/pulls")!

  private func result(_ kind: CommandBarResults.Kind, title: String = "Title",
                      subtitle: String = "") -> CommandBarResults.Result {
    CommandBarResults.Result(kind: kind, title: title, subtitle: subtitle, trailingHint: nil, removalID: nil)
  }

  /// Every verb of the "Selected row" section; the Search for row has none.
  @Test func `each kind has its verb`() {
    #expect(result(.switchTo(UUID())).verb == "Switch to Tab")
    #expect(result(.folder(UUID())).verb == "Show Folder")
    #expect(result(.history(url)).verb == "Open")
    #expect(result(.extensionAction("x")).verb == "Open Extension")
    #expect(result(.open(url)).verb == "Go")
    #expect(result(.pasteAndGo(url)).verb == "Go")
    #expect(result(.suggestion(url)).verb == "Search")
    #expect(result(.search(url)).verb == nil)
  }

  /// Slot symbols: clock for history, magnifier for search, globe for Go, clipboard for Paste and Go, folder, puzzle.
  @Test func `each kind has its symbol`() {
    #expect(result(.history(url)).symbolName == "clock")
    #expect(result(.search(url)).symbolName == "magnifyingglass")
    #expect(result(.suggestion(url)).symbolName == "magnifyingglass")
    #expect(result(.open(url)).symbolName == "globe")
    #expect(result(.pasteAndGo(url)).symbolName == "doc.on.clipboard")
    #expect(result(.folder(UUID())).symbolName == "folder")
    #expect(result(.extensionAction("x")).symbolName == "puzzlepiece.extension")
  }

  /// Go, Search for and suggestion rows have no secondary text; the others show their subtitle.
  @Test func `secondary text`() {
    #expect(result(.open(url), subtitle: "x").secondaryText == "")
    #expect(result(.search(url), subtitle: "Search Google").secondaryText == "")
    #expect(result(.suggestion(url)).secondaryText == "")
    #expect(result(.folder(UUID()), subtitle: "6 tabs").secondaryText == "6 tabs")
    #expect(result(.history(url), subtitle: "a.example/b").secondaryText == "a.example/b")
  }

  @Test func `the accessibility label reads title, secondary text, kind and position`() {
    #expect(result(.switchTo(UUID()), title: "Pull requests", subtitle: "github.com/acme")
      .commandBarLabel(position: 1, of: 5) == "Pull requests, github.com/acme, open tab, 1 of 5")
    #expect(result(.suggestion(url), title: "git rebase").commandBarLabel(position: 2, of: 5)
      == "git rebase, search suggestion, 2 of 5", "no secondary text, no empty comma")
    #expect(result(.folder(UUID()), title: "Reading", subtitle: "6 tabs").commandBarLabel(position: 3, of: 5)
      == "Reading, 6 tabs, folder, 3 of 5")
    #expect(result(.extensionAction("x"), title: "Pilot", subtitle: "Shortcuts").commandBarLabel(position: 4, of: 5)
      == "Pilot, Shortcuts, extension, 4 of 5")
    #expect(result(.pasteAndGo(url), title: "Paste and Go", subtitle: "arkt.dev").commandBarLabel(position: 1, of: 1)
      == "Paste and Go, arkt.dev, paste and go, 1 of 1")
    #expect(result(.history(url), title: "Inbox", subtitle: "mail.example").commandBarLabel(position: 2, of: 2)
      == "Inbox, mail.example, history, 2 of 2")
  }

  @Test func `no accessibility label says Arc`() {
    let kinds: [CommandBarResults.Kind] = [.open(url), .switchTo(UUID()), .search(url), .suggestion(url),
                                           .pasteAndGo(url), .history(url), .folder(UUID()), .extensionAction("x")]
    for kind in kinds {
      let label = result(kind, title: "t").commandBarLabel(position: 1, of: 1)
      #expect(!label.localizedCaseInsensitiveContains("arc "), "\(label)")
    }
  }

  @Test func `a URL shows without its scheme and trailing slash`() {
    #expect(CommandBarTitleMatch.displayURL("https://arkt.dev/changelog") == "arkt.dev/changelog")
    #expect(CommandBarTitleMatch.displayURL("http://example.com/") == "example.com")
    #expect(CommandBarTitleMatch.displayURL("chrome://settings") == "chrome://settings", "other schemes stay")
    #expect(CommandBarTitleMatch.displayURL("example.com") == "example.com")
  }

  /// Each word of the query is bolded where it starts a word, as the matching finds it.
  @Test func `each query word is bolded at its word start`() {
    let title = "Git - Branches in a Nutshell"
    let ranges = CommandBarTitleMatch.wordStartRanges(of: "nut git", in: title).map { String(title[$0]) }
    #expect(ranges == ["Nut", "Git"])
    #expect(CommandBarTitleMatch.wordStartRanges(of: "ranch", in: title).isEmpty, "not inside a word")
    #expect(CommandBarTitleMatch.wordStartRanges(of: "  ", in: title).isEmpty)
    let cjk = "\u{30EC}\u{30A4}\u{30A2}\u{30A6}\u{30C8}\u{30A8}\u{30F3}\u{30B8}\u{30F3}"
    #expect(CommandBarTitleMatch.wordStartRanges(of: "\u{30A8}\u{30F3}\u{30B8}\u{30F3}", in: cjk).count == 1)
  }

  @Test func `a title bolds the part that matches the query`() {
    let title = "Git - Book"
    #expect(CommandBarTitleMatch.wordStartRanges(of: "git", in: title) == [title.startIndex..<title.index(title.startIndex, offsetBy: 3)])
    #expect(CommandBarTitleMatch.wordStartRanges(of: "", in: "Git").isEmpty)
    #expect(CommandBarTitleMatch.wordStartRanges(of: "zzz", in: "Git").isEmpty)
    #expect(CommandBarTitleMatch.wordStartRanges(of: "BOOK", in: title).count == 1, "case insensitive")
  }
}
