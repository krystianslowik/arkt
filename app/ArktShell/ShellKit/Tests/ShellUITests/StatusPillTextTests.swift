import Foundation
import Testing
@testable import ShellUI

/// How the status pill writes an address (design/status-pill/README.md, "What it shows"; #114, BH-167).
struct StatusPillTextTests {
  private func text(_ string: String) throws -> StatusPillText {
    StatusPillText(try #require(URL(string: string)))
  }

  @Test func httpsHidesTheSchemeAndEmphasizesTheHost() throws {
    let pill = try text("https://www.example.org/docs/page?q=1#top")
    #expect(pill == StatusPillText(prefix: "", host: "www.example.org", rest: "/docs/page?q=1#top"))
  }

  @Test(arguments: [
    ("http://example.org/a", "http://"),
    ("ftp://files.example.org/a", "ftp://"),
    ("file:///srv/docs/a.txt", "file://"),
  ])
  func otherSchemesAreShown(address: String, prefix: String) throws {
    #expect(try text(address).prefix == prefix)
  }

  @Test func aSchemeWithoutAHostShowsItAndEmphasizesWhatFollows() throws {
    let mail = try text("mailto:someone@example.org?subject=Hi")
    #expect(mail == StatusPillText(prefix: "mailto:", host: "someone@example.org?subject=Hi", rest: ""))
    let script = try text("javascript:void(0)")
    #expect(script.prefix == "javascript:")
  }

  @Test func thePortStaysWithTheRestAndAnIPv6HostStaysWhole() throws {
    #expect(try text("http://localhost:8080/x").host == "localhost")
    #expect(try text("http://localhost:8080/x").rest == ":8080/x")
    let v6 = try text("http://[::1]:8080/x")
    #expect(v6.host == "[::1]")
    #expect(v6.rest == ":8080/x")
  }

  /// A host that is punycode is shown as punycode: turning it into Unicode would draw the lookalike the user is
  /// meant to see through.
  @Test func punycodeIsShownAsTheEngineGivesIt() throws {
    let pill = try text("https://xn--pple-43d.example/login")
    #expect(pill.host == "xn--pple-43d.example")
  }

  /// Whatever the URL carries for the host is what shows: no decoding, no case folding, no `www.` trimming.
  @Test(arguments: [
    "https://xn--80ak6aa92e.com/",
    "https://WWW.Example.ORG/Path",
    "https://%61pple.example/",
    "https://pаypal.example/",          // a Cyrillic "а" in the host
  ])
  func theHostIsTheURLsOwnText(address: String) throws {
    let url = try #require(URL(string: address))
    let pill = StatusPillText(url)
    let expected = url.absoluteString.dropFirst("https://".count).prefix { !"/?#:".contains($0) }
    #expect(pill.host == String(expected))
    #expect(pill.fullText == url.absoluteString.dropFirst("https://".count))
  }

  /// `https://bank.example@evil.example/` is evil.example; the user info stays visible before the host.
  @Test func userInfoStaysVisibleBeforeTheHost() throws {
    let pill = try text("https://bank.example@evil.example/login")
    #expect(pill.prefix == "bank.example@")
    #expect(pill.host == "evil.example")
  }

  @Test func charactersThatDrawNothingAreWrittenOut() {
    let sneaky = "evil\u{202E}elpmaxe.com"
    #expect(StatusPillText.safe(sneaky) == "evil<U+202E>elpmaxe.com")
    #expect(StatusPillText.safe("a\u{200B}b") == "a<U+200B>b")
    #expect(StatusPillText.safe("plain-текст.example") == "plain-текст.example")
  }

  @Test func anOverlongAddressIsClippedBeforeLayout() throws {
    let huge = "data:text/plain," + String(repeating: "x", count: 5_000_000)
    let pill = try text(huge)
    #expect(pill.host.count <= StatusPillText.maxCharacters)
  }

  /// The scheme and user info are clipped like the host and the rest: a megabyte of user info must not reach text
  /// measurement.
  @Test func anOverlongUserInfoIsClippedToo() throws {
    let huge = "https://" + String(repeating: "u", count: 1_000_000) + "@evil.example/x"
    let pill = try text(huge)
    #expect(pill.prefix.count <= StatusPillText.maxCharacters)
    #expect(pill.host == "evil.example")
    #expect(pill.fullText.count <= 3 * StatusPillText.maxCharacters)
  }

  @Test func contrastOfTheTextTokensOnThePillSurface() {
    for flavor in [ThemeFlavor.light, .dark] {
      let surface = BrandTokens.surfaceBrand.resolve(flavor)
      for token in [ShellTokens.primaryText, ShellTokens.secondaryText] {
        let text = BrandTokens.composite(token.resolve(flavor), over: surface)
        #expect(Contrast.ratio(text, surface) >= 4.5, "\(flavor)")
      }
    }
  }
}
