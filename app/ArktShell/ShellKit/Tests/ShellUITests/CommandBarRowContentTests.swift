import Foundation
import Testing
@testable import ShellUI

/// The row anatomy table of design/command-bar/README.md: slot symbol, secondary text and the trailing group per row
/// kind, and the accessibility sentence "<title>, <host>, <kind>, <k> of <n>".
struct CommandBarRowContentTests {
  private let url = URL(string: "https://github.com/krystianslowik/arkt/pulls")!

  private func result(_ kind: CommandBarResults.Kind, title: String = "Title", subtitle: String = "",
                      hint: String? = nil, keyCaps: [String] = []) -> CommandBarResults.Result {
    var result = CommandBarResults.Result(kind: kind, title: title, subtitle: subtitle, trailingHint: hint,
                                          removalID: nil)
    result.keyCaps = keyCaps
    return result
  }

  @Test func `an open tab says Switch to Tab, and gains a Return key cap when selected`() {
    let tab = result(.switchTo(UUID()), subtitle: "github.com", hint: CommandBarResults.switchHint)
    #expect(tab.trailing(isSelected: false) == [.text("Switch to Tab")])
    #expect(tab.trailing(isSelected: true) == [.text("Switch to Tab"), .keyCap(CommandBarKeyCaps.return)])
    #expect(tab.rowKind == .openTab)
    #expect(tab.symbolName == "square.on.square")
    #expect(tab.secondaryText == "github.com")
  }

  @Test func `a split pane tab keeps its own caption`() {
    let tab = result(.switchTo(UUID()), hint: CommandBarResults.switchToSplitHint)
    #expect(tab.trailing(isSelected: false) == [.text("Switch to Split View")])
  }

  @Test func `a search suggestion has a magnifier, no secondary text and says Search`() {
    let search = result(.search(url), title: "git rebase onto", subtitle: "Search Google")
    #expect(search.symbolName == "magnifyingglass")
    #expect(search.secondaryText.isEmpty, "the engine name is the trailing caption's job, not a second line")
    #expect(search.trailing(isSelected: false) == [.text("Search")])
    #expect(search.trailing(isSelected: true) == [.text("Search"), .keyCap(CommandBarKeyCaps.return)])
    #expect(search.rowKind == .searchSuggestion)
  }

  @Test func `a typed address says Open and shows what it expands to`() {
    let open = result(.open(url), title: "github.com", subtitle: url.absoluteString)
    #expect(open.secondaryText == url.absoluteString)
    #expect(open.trailing(isSelected: false) == [.text("Open")])
    #expect(open.symbolName == "globe")
  }

  @Test func `a site search row shows Return on the selected row only`() {
    let site = result(.siteSearch(url), title: "Search GitHub for git", subtitle: "Search GitHub")
    #expect(site.secondaryText.isEmpty)
    #expect(site.trailing(isSelected: false).isEmpty)
    #expect(site.trailing(isSelected: true) == [.keyCap(CommandBarKeyCaps.return)])
    #expect(site.symbolName == "magnifyingglass")
  }

  @Test func `an action shows its shortcut key caps and a symbol`() {
    let action = result(.action("newSpace"), title: "New Space", subtitle: "Action",
                        keyCaps: [CommandBarKeyCaps.command, CommandBarKeyCaps.shift, "N"])
    #expect(action.symbolName == "bolt")
    #expect(action.secondaryText.isEmpty)
    #expect(action.trailing(isSelected: false) == [.keyCap("\u{2318}"), .keyCap("\u{21E7}"), .keyCap("N")])
    #expect(action.trailing(isSelected: true) == action.trailing(isSelected: false))
  }

  @Test func `an action with no shortcut shows Return when selected`() {
    let action = result(.action("x"), title: "X", subtitle: "Action")
    #expect(action.trailing(isSelected: false).isEmpty)
    #expect(action.trailing(isSelected: true) == [.keyCap(CommandBarKeyCaps.return)])
  }

  @Test func `Paste and Go shows the clipboard URL and Return when selected`() {
    let paste = result(.pasteAndGo(url), title: "Paste and Go", subtitle: url.absoluteString)
    #expect(paste.symbolName == "doc.on.clipboard")
    #expect(paste.secondaryText == url.absoluteString)
    #expect(paste.trailing(isSelected: false).isEmpty)
    #expect(paste.trailing(isSelected: true) == [.keyCap(CommandBarKeyCaps.return)])
  }

  @Test func `an archived result says Restore from Archive`() {
    let archived = result(.restore(UUID()), subtitle: "docs.example.com, Work, archived yesterday",
                          hint: CommandBarResults.restoreHint)
    #expect(archived.symbolName == "archivebox")
    #expect(archived.secondaryText == "docs.example.com, Work, archived yesterday")
    #expect(archived.trailing(isSelected: false) == [.text("Restore from Archive")])
  }

  @Test func `a Space says Switch to Space`() {
    let space = result(.switchSpace(UUID()), title: "Work", subtitle: "Space", hint: CommandBarResults.switchToSpaceHint)
    #expect(space.secondaryText.isEmpty)
    #expect(space.trailing(isSelected: false) == [.text("Switch to Space")])
  }

  @Test func `the accessibility label reads title, host, kind and position`() {
    let tab = result(.switchTo(UUID()), title: "Pull requests", subtitle: "github.com")
    #expect(tab.accessibilityLabel(position: 1, of: 5) == "Pull requests, github.com, open tab, 1 of 5")
    let search = result(.search(url), title: "git rebase", subtitle: "Search Google")
    #expect(search.accessibilityLabel(position: 2, of: 5) == "git rebase, search suggestion, 2 of 5",
            "no secondary text, no empty comma")
    #expect(result(.action("a"), title: "Copy URL").accessibilityLabel(position: 3, of: 5) == "Copy URL, action, 3 of 5")
    #expect(result(.pasteAndGo(url), title: "Paste and Go", subtitle: "arkt.dev").accessibilityLabel(position: 1, of: 1)
            == "Paste and Go, arkt.dev, clipboard, 1 of 1")
    #expect(result(.restore(UUID()), title: "Doc", subtitle: "a, b, c").accessibilityLabel(position: 1, of: 2)
            == "Doc, a, b, c, archived, 1 of 2")
  }

  @Test func `no accessibility label says Arc`() {
    let kinds: [CommandBarResults.Kind] = [.open(url), .switchTo(UUID()), .search(url), .pasteAndGo(url),
                                           .siteSearch(url), .action("a"), .switchSpace(UUID()), .restore(UUID())]
    for kind in kinds {
      let label = result(kind, title: "t").accessibilityLabel(position: 1, of: 1)
      #expect(!label.localizedCaseInsensitiveContains("arc "), "\(label)")
    }
  }

  @Test func `a title bolds the part that matches the query`() {
    #expect(CommandBarTitleMatch.range(of: "git", in: "Git - Book") == "Git - Book".startIndex..<"Git - Book".index("Git - Book".startIndex, offsetBy: 3))
    #expect(CommandBarTitleMatch.range(of: "", in: "Git") == nil)
    #expect(CommandBarTitleMatch.range(of: "zzz", in: "Git") == nil)
    #expect(CommandBarTitleMatch.range(of: "BOOK", in: "Git - Book") != nil, "case insensitive")
  }
}
