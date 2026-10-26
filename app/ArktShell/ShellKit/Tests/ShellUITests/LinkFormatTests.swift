import Testing
@testable import ShellUI

/// KB-014, KB-015: the Markdown and quote text stays one well-formed link whatever the title or URL holds.
struct LinkFormatTests {
  @Test func aPlainTitleAndURLMakeALink() {
    #expect(LinkFormat.markdown(title: "Example", url: "https://example.com/a") == "[Example](https://example.com/a)")
  }

  @Test func bracketsAndBackslashesInTheTitleAreEscaped() {
    #expect(LinkFormat.markdown(title: #"Swift [beta] \ notes"#, url: "https://example.com")
              == #"[Swift \[beta\] \\ notes](https://example.com)"#)
  }

  @Test func parenthesesInTheURLAreEncoded() {
    #expect(LinkFormat.markdown(title: "Mercury", url: "https://en.wikipedia.org/wiki/Mercury_(planet)")
              == "[Mercury](https://en.wikipedia.org/wiki/Mercury_%28planet%29)")
  }

  @Test func aQuoteIsTheLinkAfterAQuoteMarker() {
    #expect(LinkFormat.quote(title: "Example", url: "https://example.com/a") == "> [Example](https://example.com/a)")
  }
}
