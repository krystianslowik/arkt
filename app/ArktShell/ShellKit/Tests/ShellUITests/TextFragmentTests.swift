import Foundation
import Testing
@testable import ShellUI

/// BH-193 (#404): the link to selected text is the page's URL with a `#:~:text=` directive that finds the selection.
struct TextFragmentTests {
  private func link(_ url: String, _ text: String) -> String? {
    TextFragment.link(to: text, in: URL(string: url)!)?.absoluteString
  }

  @Test func aShortSelectionIsQuotedWhole() {
    #expect(link("https://example.com/a", "quick brown fox") == "https://example.com/a#:~:text=quick%20brown%20fox")
  }

  @Test func whitespaceIsCollapsedAndTrimmed() {
    #expect(link("https://example.com/a", "  quick\n\tbrown   fox ") == "https://example.com/a#:~:text=quick%20brown%20fox")
  }

  /// The directive's own separators and the percent sign are encoded, so the text cannot split the directive.
  @Test func directiveSeparatorsInTheTextAreEncoded() {
    #expect(link("https://example.com/a", "a-b, c&d 50%") == "https://example.com/a#:~:text=a%2Db%2C%20c%26d%2050%25")
  }

  @Test func aLongSelectionBecomesAStartAndAnEnd() {
    let text = "one two three four five six seven eight nine ten eleven twelve"
    #expect(link("https://example.com/a", text)
              == "https://example.com/a#:~:text=one%20two%20three%20four,nine%20ten%20eleven%20twelve")
  }

  @Test func anExistingFragmentIsKept() {
    #expect(link("https://example.com/a#intro", "fox") == "https://example.com/a#intro:~:text=fox")
  }

  @Test func anExistingTextDirectiveIsReplaced() {
    #expect(link("https://example.com/a#intro:~:text=old", "fox") == "https://example.com/a#intro:~:text=fox")
    #expect(link("https://example.com/a#:~:text=old", "fox") == "https://example.com/a#:~:text=fox")
  }

  @Test func nonWordCharactersStayReadable() {
    #expect(link("https://example.com/a", "Zoë's café") == "https://example.com/a#:~:text=Zo%C3%AB's%20caf%C3%A9")
  }

  @Test func blankTextOrANonWebURLGivesNoLink() {
    #expect(link("https://example.com/a", " \n ") == nil)
    #expect(link("file:///tmp/a.html", "fox") == nil)
  }
}
