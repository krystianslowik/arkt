import Foundation
import Testing
@testable import ShellUI

/// The shared host display rule (#697): a host shows in Unicode only when every label passes the spoof check;
/// otherwise the whole host keeps its encoded `xn--` form. The policy follows Chromium's IDN display policy
/// (`docs/idn.md`, `components/url_formatter/spoof_checks/idn_spoof_checker.cc`).
struct HostDisplayTests {
  /// The encoded form of a Unicode host, label by label, built with the codec under test (`PunycodeTests` pins the
  /// codec to RFC 3492). Used for inputs Foundation refuses to encode.
  private func ace(_ host: String) -> String {
    host.split(separator: ".", omittingEmptySubsequences: false).map { label in
      label.unicodeScalars.allSatisfy(\.isASCII) ? String(label) : "xn--" + Punycode.encode(Array(label.unicodeScalars))!
    }.joined(separator: ".")
  }

  // MARK: Real internationalized domains show in Unicode

  @Test(arguments: [
    ("xn--mnchen-3ya.de", "m\u{00FC}nchen.de"),                           // Latin with a diacritic
    ("xn--e1afmkfd.xn--p1ai", "\u{043F}\u{0440}\u{0438}\u{043C}\u{0435}\u{0440}.\u{0440}\u{0444}"),   // Cyrillic, Cyrillic TLD
    ("xn--9dbne9b.co.il", "\u{05E9}\u{05DC}\u{05D5}\u{05DD}.co.il"),       // Hebrew, right to left
    ("xn--mgbh0fb.eg", "\u{0645}\u{062B}\u{0627}\u{0644}.eg"),             // Arabic
    ("xn--wgv71a119e.jp", "\u{65E5}\u{672C}\u{8A9E}.jp"),                  // Han
    ("xn--abc-li4boevd.jp", "abc\u{30B9}\u{30C8}\u{30A2}.jp"),             // ASCII Latin with Katakana
    ("xn--3e0b707e.kr", "\u{D55C}\u{AD6D}.kr"),                            // Hangul
    ("xn--fsqu00a.xn--0zwm56d", "\u{4F8B}\u{5B50}.\u{6D4B}\u{8BD5}"),      // Han, Han TLD
    ("xn--o3cw4h.th", "\u{0E44}\u{0E17}\u{0E22}.th"),                      // Thai
    ("xn--hxargifdar.gr", "\u{03B5}\u{03BB}\u{03BB}\u{03B7}\u{03BD}\u{03B9}\u{03BA}\u{03AC}.gr"),     // Greek
    ("xn--h2brj9c.in", "\u{092D}\u{093E}\u{0930}\u{0924}.in"),             // Devanagari
    ("xn--54b7fta0cc0wh.bd", "\u{09AC}\u{09BE}\u{0982}\u{09B2}\u{09BE}\u{09E7}\u{09E8}.bd"),          // Bengali digits
    ("xn--abc-x68do18h.com", "abc\u{4E2D}\u{6587}.com"),                   // ASCII Latin with Han
    ("xn--orn-ooa.is", "\u{00FE}orn.is"),                                  // thorn under Iceland's TLD
    ("xn--n1aahb.ru", "\u{0441}\u{043E}\u{0441}\u{043E}.ru"),              // Latin-looking Cyrillic under .ru
    ("xn--n1aahb.xn--p1ai", "\u{0441}\u{043E}\u{0441}\u{043E}.\u{0440}\u{0444}"),                     // ...and under .rf
    ("xn--mxapd.gr", "\u{03B9}\u{03BA}\u{03B1}.gr"),                       // Latin-looking Greek under .gr
    ("www.xn--mnchen-3ya.de", "www.m\u{00FC}nchen.de"),
    ("xn--mnchen-3ya.de.", "m\u{00FC}nchen.de."),                          // a fully qualified name keeps its dot
    ("XN--MNCHEN-3YA.DE", "m\u{00FC}nchen.de"),                            // ACE is case-insensitive
  ])
  func aRealUnicodeDomainShowsInUnicode(encoded: String, shown: String) {
    #expect(HostDisplay.text(forHost: encoded) == shown)
  }

  /// The engine may hand over a host it already decoded; a safe one stays as it is, lowercased.
  @Test func aSafeUnicodeHostFromTheEngineStaysUnicode() {
    #expect(HostDisplay.text(forHost: "m\u{00FC}nchen.de") == "m\u{00FC}nchen.de")
    #expect(HostDisplay.text(forHost: "M\u{00DC}NCHEN.de") == "m\u{00FC}nchen.de")
  }

  // MARK: Look-alike hosts stay encoded

  /// One label mixing Latin with Cyrillic or Greek: the classic homograph.
  @Test(arguments: [
    "xn--pple-43d.com",          // Cyrillic a + "pple"
    "xn--ggle-0nda.com",         // "g" + two Greek omicrons + "gle"
    "xn--mnchen-3ya7029m.com",   // non-ASCII Latin mixed with Han
  ])
  func aMixedScriptLabelStaysEncoded(host: String) {
    #expect(HostDisplay.text(forHost: host) == host)
  }

  /// Mixes that no whole-script rule would catch, because the non-Latin letters do not look Latin: only the
  /// script mixing rule keeps them encoded.
  @Test(arguments: [
    "abc\u{0436}.com",          // Latin and Cyrillic zhe
    "\u{03BB}abc.com",          // Greek lambda and Latin
    "\u{0436}\u{03BB}.com",     // Cyrillic and Greek
    "abc\u{0E44}.com",          // Latin and Thai
    "\u{D55C}\u{30B9}.com",     // Hangul and Katakana
  ])
  func aMixOfScriptsThatDoNotLookLatinStaysEncoded(unicode: String) {
    let encoded = ace(unicode)
    #expect(HostDisplay.text(forHost: encoded) == encoded, "\(unicode)")
  }

  /// The engine's Unicode form of a look-alike is shown encoded too.
  @Test func aMixedScriptUnicodeHostFromTheEngineIsEncoded() {
    #expect(HostDisplay.text(forHost: "\u{0430}pple.com") == "xn--pple-43d.com")
  }

  /// A label made only of Cyrillic (or Greek) letters that look Latin, under a TLD that is not the script's own.
  @Test(arguments: [
    "xn--80ak6aa92e.com",        // "apple" spelled in Cyrillic
    "xn--n1aahb.com",            // "coco" spelled in Cyrillic
    "xn--mxapd.com",             // "ika" spelled in Greek
  ])
  func aWholeScriptConfusableStaysEncoded(host: String) {
    #expect(HostDisplay.text(forHost: host) == host)
  }

  /// One bad label keeps the whole host encoded, so the safe part cannot frame the spoof.
  @Test func oneUnsafeLabelKeepsTheWholeHostEncoded() {
    #expect(HostDisplay.text(forHost: "xn--mnchen-3ya.xn--pple-43d.com") == "xn--mnchen-3ya.xn--pple-43d.com")
    #expect(HostDisplay.text(forHost: "m\u{00FC}nchen.\u{0430}pple.com") == "xn--mnchen-3ya.xn--pple-43d.com")
  }

  @Test(arguments: [
    "abc\u{30CE}def.com",        // Katakana "no" between Latin letters reads as a slash
    "\u{30FC}abc.com",           // the prolonged sound mark reads as a dash at the start
    "ab\u{4E00}c.com",           // Han "one" between Latin letters reads as a dash
    "i\u{0307}nfo.com",          // a dot above on an "i"
    "\u{0131}\u{0301}b.com",     // a dotless i with a combining mark
    "\u{00FE}orn.com",           // thorn outside Iceland and the Faroes
    "\u{0437}1.com",             // only digits and a digit look-alike (Cyrillic ze for 3)
    "\u{09AC}\u{09BE}\u{0982}\u{09B2}\u{09BE}\u{09E7}2.bd",              // Bengali and European digits mixed
    "fa\u{00DF}.de",             // a deviation character
    "\u{1F00}\u{03B8}\u{1FC6}\u{03BD}\u{03B1}\u{03B9}.gr",               // Greek Extended, outside the allowed set
    "\u{01CE}.cn",               // pinyin from Latin Extended-B, outside the allowed set
    "\u{1E01}.com",              // Latin Extended Additional, outside the allowed set
    "\u{AB70}\u{AB71}.com",      // Cherokee: a script the table does not know
  ])
  func aConfusableOrUnusualLabelStaysEncoded(unicode: String) {
    let encoded = ace(unicode)
    #expect(HostDisplay.text(forHost: encoded) == encoded, "\(unicode)")
    #expect(HostDisplay.text(forHost: unicode) == encoded, "\(unicode) from the engine")
  }

  // MARK: Invisible and bidi characters

  @Test(arguments: [
    "a\u{200B}b.com",            // zero width space
    "a\u{200C}b.com",            // zero width non-joiner
    "a\u{200D}b.com",            // zero width joiner
    "a\u{00AD}b.com",            // soft hyphen
    "a\u{2060}b.com",            // word joiner
    "a\u{FEFF}b.com",            // byte order mark
    "a\u{034F}b.com",            // combining grapheme joiner
    "a\u{FE0F}b.com",            // variation selector
    "\u{3164}.com",              // Hangul filler
    "a\u{3000}b.com",            // ideographic space
    "m\u{00FC}\u{0308}\u{0308}nchen.de",                                   // the same mark twice in a row
    "\u{0301}abc.com",           // a label that starts with a combining mark
    "mu\u{0308}nchen.de",        // decomposed, not NFC
  ])
  func anInvisibleCharacterKeepsTheHostEncoded(unicode: String) {
    let encoded = ace(unicode)
    #expect(HostDisplay.text(forHost: encoded) == encoded, "\(unicode.unicodeScalars.map { String($0.value, radix: 16) })")
  }

  @Test(arguments: [
    "\u{05E9}\u{05DC}\u{202E}\u{05D5}\u{05DD}.co.il",                     // right-to-left override
    "\u{05E9}\u{05DC}\u{200F}\u{05D5}\u{05DD}.co.il",                     // right-to-left mark
    "abc\u{2067}\u{05E9}\u{05DC}.com",                                    // right-to-left isolate
    "abc\u{05E9}\u{05DC}\u{05D5}\u{05DD}.com",                            // Latin and Hebrew in one label
    "1\u{05E9}\u{05DC}\u{05D5}\u{05DD}.co.il",                            // a right-to-left label must start with a letter
    "\u{05E9}\u{05DC}\u{05D5}\u{05DD}-.co.il",                            // ...and end with a letter or digit
    "\u{0645}\u{062B}\u{0627}\u{0644}\u{05E9}.eg",                         // Arabic and Hebrew mixed
  ])
  func aBidiTrickKeepsTheHostEncoded(unicode: String) {
    let encoded = ace(unicode)
    #expect(HostDisplay.text(forHost: encoded) == encoded, "\(unicode.unicodeScalars.map { String($0.value, radix: 16) })")
  }

  // MARK: Punycode that must stay punycode

  @Test(arguments: [
    "xn--zz.com",                // not a valid encoding
    "xn--.com",                  // an empty encoding
    "xn--abc-.com",              // decodes to plain ASCII: a fake encoded label
    "xn--99999999999999999999.com",                                       // the delta overflows
    "xn--mnchen_3ya.de",         // a character outside the ACE alphabet
    "xn--mnchen-3ya-.de",        // decodes to something else than it re-encodes to
    "xn--bergfhrer-verband-kartenarchiv-q9b-sektion-nordwest-archiv.example",
  ])
  func invalidPunycodeStaysAsItIs(host: String) {
    #expect(HostDisplay.text(forHost: host) == host)
  }

  /// A decoded label with uppercase letters is not what an encoder would write: it stays encoded.
  @Test func anEncodingOfUppercaseLettersStaysEncoded() {
    let encoded = "xn--" + Punycode.encode(Array("M\u{00DC}NCHEN".unicodeScalars))!
    #expect(HostDisplay.text(forHost: encoded + ".de") == encoded.lowercased() + ".de")
  }

  // MARK: Long labels and hosts

  @Test func aSixtyThreeOctetEncodedLabelDecodes() throws {
    let unicode = String(repeating: "b\u{00FC}cher", count: 8)
    let encoded = ace(unicode)
    try #require(encoded.utf8.count <= 63, "\(encoded.utf8.count)")
    #expect(HostDisplay.text(forHost: encoded + ".de") == unicode + ".de")
  }

  @Test func anEncodedLabelOverSixtyThreeOctetsStaysEncoded() throws {
    let unicode = String(repeating: "b\u{00FC}cher", count: 12)
    let encoded = ace(unicode) + ".de"
    try #require(encoded.utf8.count > 66)
    #expect(HostDisplay.text(forHost: encoded) == encoded)
    #expect(HostDisplay.text(forHost: unicode + ".de") == encoded, "from the engine")
  }

  @Test func aHostOverTwoHundredFiftyThreeOctetsStaysEncoded() {
    let label = ace("b\u{00FC}cher")
    let host = Array(repeating: label, count: 25).joined(separator: ".") + ".de"
    #expect(host.utf8.count > 253)
    #expect(HostDisplay.text(forHost: host) == host)
  }

  /// A huge host ends quickly and shows nothing a reader could take for Unicode.
  @Test func aHugeHostEndsQuicklyAndStaysASCII() {
    let host = String(repeating: "\u{0430}", count: 20_000) + ".com"
    let isASCII = HostDisplay.text(forHost: host).unicodeScalars.allSatisfy(\.isASCII)
    #expect(isASCII)
  }

  // MARK: Hosts that are not internationalized

  @Test(arguments: ["example.com", "Example.COM", "localhost", "127.0.0.1", "::1", "", "my_host.example",
                    "xn-mnchen.de", "a.xn"])
  func anASCIIHostIsLeftAlone(host: String) {
    #expect(HostDisplay.text(forHost: host) == host)
  }

  // MARK: Hosts inside addresses

  @Test(arguments: [
    ("https://xn--mnchen-3ya.de/plan", "https://m\u{00FC}nchen.de/plan"),
    ("https://xn--mnchen-3ya.de:8443/a?b=xn--mnchen-3ya#xn--c", "https://m\u{00FC}nchen.de:8443/a?b=xn--mnchen-3ya#xn--c"),
    ("https://user:pw@xn--mnchen-3ya.de/", "https://user:pw@m\u{00FC}nchen.de/"),
    ("https://xn--mnchen-3ya.de/a%20b?q=%C3%BC#%20", "https://m\u{00FC}nchen.de/a%20b?q=%C3%BC#%20"),
    ("https://xn--pple-43d.com/login", "https://xn--pple-43d.com/login"),
    ("https://%D0%B0pple.com/x", "https://xn--pple-43d.com/x"),
    ("https://WWW.Example.COM/Path", "https://WWW.Example.COM/Path"),
    ("http://[::1]:8080/x", "http://[::1]:8080/x"),
    ("about:blank", "about:blank"),
    ("file:///tmp/xn--mnchen-3ya.html", "file:///tmp/xn--mnchen-3ya.html"),
  ])
  func anAddressShowsItsHostByTheRule(address: String, shown: String) throws {
    let url = try #require(URL(string: address))
    #expect(HostDisplay.address(url) == shown)
  }

  @Test func theHostOfAnAddressFollowsTheRule() throws {
    let real = try #require(URL(string: "https://xn--mnchen-3ya.de/"))
    let encodedLookAlike = try #require(URL(string: "https://%D0%B0pple.com/"))
    let blank = try #require(URL(string: "about:blank"))
    #expect(HostDisplay.host(of: real) == "m\u{00FC}nchen.de")
    #expect(HostDisplay.host(of: encodedLookAlike) == "xn--pple-43d.com")
    #expect(HostDisplay.host(of: blank) == nil)
  }
}
