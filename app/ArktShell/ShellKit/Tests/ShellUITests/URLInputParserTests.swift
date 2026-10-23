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
  ])
  func parsesURLs(input: String, expected: String) {
    #expect(URLInputParser.url(from: input)?.absoluteString == expected)
  }

  @Test(arguments: [
    "hello world", "swift", "", "what is example.com", "1.5", "https://", "file.x",
    "ftp://example.com", "javascript:alert(1)", "1.2.3", "256.1.1.1", "1.2.3.4.5", "[zz::g]", "[::1",
    "example.com:abc", "-x.com.-", "a..b.com",
  ])
  func rejectsQueries(input: String) {
    #expect(URLInputParser.url(from: input) == nil)
  }

  @Test func searchURLEncodesQuery() {
    #expect(URLInputParser.searchURL(for: "a b&c").absoluteString == "https://www.google.com/search?q=a%20b%26c")
  }

  @Test func searchURLEncodesReservedQueryCharacters() {
    #expect(URLInputParser.searchURL(for: "c++ x=1?#").absoluteString
      == "https://www.google.com/search?q=c%2B%2B%20x%3D1%3F%23")
  }
}
