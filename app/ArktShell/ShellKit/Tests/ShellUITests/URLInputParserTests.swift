import Foundation
import Testing
@testable import ShellUI

struct URLInputParserTests {
  @Test(arguments: [
    ("example.com", "https://example.com"),
    ("https://example.com/a?b=1", "https://example.com/a?b=1"),
    ("http://localhost:3000", "http://localhost:3000"),
    ("localhost:3000", "http://localhost:3000"),
    ("sub.domain.co.uk/path", "https://sub.domain.co.uk/path"),
    ("  example.com  ", "https://example.com"),
    // A "://" later in the input is not a scheme (only a leading scheme is).
    ("example.com/login?next=https://x", "https://example.com/login?next=https://x"),
    ("localhost:3000/?cb=http://a", "http://localhost:3000/?cb=http://a"),
    ("HTTPS://Example.com", "HTTPS://Example.com"),
    // IP literals open over http (no certificate would match a bare IP).
    ("192.168.1.1", "http://192.168.1.1"),
    ("8.8.8.8:53/dns", "http://8.8.8.8:53/dns"),
    ("127.0.0.1:8080", "http://127.0.0.1:8080"),
    ("[::1]", "http://[::1]"),
    ("[2001:db8::1]:8443/x", "http://[2001:db8::1]:8443/x"),
    // IDN: non-ASCII labels and punycode TLDs (Foundation IDNA-encodes the host).
    ("münchen.de", "https://xn--mnchen-3ya.de"),
    ("пример.рф", "https://xn--e1afmkfd.xn--p1ai"),
    ("example.xn--p1ai", "https://example.xn--p1ai"),
    // #96: a trailing dot (fully qualified name) is kept, like Chromium's canonical host.
    ("example.com.", "https://example.com."),
    ("example.com./a", "https://example.com./a"),
    ("example.com.:8080", "https://example.com.:8080"),
    // #96: underscores are allowed in labels other than the TLD (net::IsCanonicalizedHostCompliant).
    ("my_host.example.com", "https://my_host.example.com"),
    ("_dmarc.example.com", "https://_dmarc.example.com"),
    // #96: user-info navigates when it has a password or the input has more than the host (omnibox Parse).
    ("user:pass@example.com", "https://user:pass@example.com"),
    ("user@example.com/inbox", "https://user@example.com/inbox"),
    ("user@example.com:8443", "https://user@example.com:8443"),
    ("admin:pw@192.168.1.1", "http://admin:pw@192.168.1.1"),
    ("https://user@example.com", "https://user@example.com"),
    // #96: a single 0 octet has no leading zero.
    ("0.0.0.0", "http://0.0.0.0"),
    ("10.0.0.1", "http://10.0.0.1"),
    // #499: engine-internal and local schemes always navigate; the engine decides whether it can open them.
    ("chrome://settings/content", "chrome://settings/content"),
    ("CHROME://Extensions", "CHROME://Extensions"),
    ("chrome-extension://abcdefghijklmnop/popup.html", "chrome-extension://abcdefghijklmnop/popup.html"),
    ("about:blank", "about:blank"),
    ("about:version", "about:version"),
    ("view-source:https://example.com", "view-source:https://example.com"),
    ("file:///Users/me/a.html", "file:///Users/me/a.html"),
    ("data:text/html,hello", "data:text/html,hello"),
    ("arkt://settings", "arkt://settings"),
  ])
  func parsesURLs(input: String, expected: String) {
    #expect(URLInputParser.url(from: input)?.absoluteString == expected)
  }

  @Test(arguments: [
    "hello world", "swift", "", "what is example.com", "1.5", "https://", "file.x",
    "ftp://example.com", "javascript:alert(1)",
    // #499: javascript: typed in the bar never runs (Chromium searches for it); empty internal schemes search.
    "JavaScript:alert(1)", "javascript://%0Aalert(1)", "chrome://", "about:", "view-source:", "data:", "file://", "1.2.3", "256.1.1.1", "1.2.3.4.5", "[zz::g]", "[::1",
    "example.com:abc", "-x.com.-", "a..b.com",
    // #96: only one trailing dot; a dot alone is not a host.
    "example.com..", ".", ".com",
    // #96: underscores never in the TLD.
    "example.c_m", "example._com",
    // #96: "user@host" alone reads as an email address (omnibox Parse: search by default); empty user-info.
    "user@example.com", "@example.com", "user:@example.com",
    // #96: IPv4 parts with a leading zero (Chromium reads them as octal); rejected, so they stay queries.
    "010.0.0.1", "192.168.01.1", "08.0.0.1", "1.2.3.00",
  ])
  func rejectsQueries(input: String) {
    #expect(URLInputParser.url(from: input) == nil)
  }

  @Test func internalSchemesCountAsExplicit() {
    #expect(URLInputParser.hasExplicitScheme("chrome://settings/content"))
    #expect(URLInputParser.hasExplicitScheme("about:blank"))
    #expect(URLInputParser.hasExplicitScheme("view-source:https://example.com"))
    #expect(!URLInputParser.hasExplicitScheme("javascript:alert(1)"))
    #expect(!URLInputParser.hasExplicitScheme("example.com"))
  }

  @Test func searchURLEncodesQuery() {
    #expect(URLInputParser.searchURL(for: "a b&c").absoluteString == "https://www.google.com/search?q=a%20b%26c")
  }

  @Test func searchURLEncodesReservedQueryCharacters() {
    #expect(URLInputParser.searchURL(for: "c++ x=1?#").absoluteString
      == "https://www.google.com/search?q=c%2B%2B%20x%3D1%3F%23")
  }
}
