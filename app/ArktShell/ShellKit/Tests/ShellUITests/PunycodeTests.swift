import Testing
@testable import ShellUI

/// The RFC 3492 codec under `HostDisplay` (#697): the RFC's own sample strings, and the inputs a hostile host can
/// carry (bad digits, overflow, a lone delimiter).
struct PunycodeTests {
  private func scalars(_ values: [UInt32]) -> [Unicode.Scalar] { values.map { Unicode.Scalar($0)! } }

  /// RFC 3492, section 7.1, samples A, B, L and S.
  static let samples: [(name: String, unicode: [UInt32], encoded: String)] = [
    ("Arabic (Egyptian)",
     [0x0644, 0x064A, 0x0647, 0x0645, 0x0627, 0x0628, 0x062A, 0x0643, 0x0644, 0x0645, 0x0648, 0x0634, 0x0639, 0x0631,
      0x0628, 0x064A, 0x061F],
     "egbpdaj6bu4bxfgehfvwxn"),
    ("Chinese (simplified)",
     [0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D, 0x6587],
     "ihqwcrb4cv8a8dqg056pqjye"),
    ("Japanese with basic letters",
     [0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148, 0x751F],
     "3B-ww4c5e180e575a65lsy2b"),
    ("Only basic code points",
     [0x002D, 0x003E, 0x0020, 0x0024, 0x0031, 0x002E, 0x0030, 0x0030, 0x0020, 0x003C, 0x002D],
     "-> $1.00 <--"),
  ]

  @Test(arguments: samples.indices)
  func encodesAndDecodesTheRFCSamples(index: Int) {
    let sample = Self.samples[index]
    #expect(Punycode.encode(scalars(sample.unicode)) == sample.encoded, "\(sample.name)")
    #expect(Punycode.decode(sample.encoded) == scalars(sample.unicode), "\(sample.name)")
  }

  @Test func decodingIgnoresTheCaseOfDigits() {
    #expect(Punycode.decode("MNCHEN-3YA") == Array("M\u{00FC}NCHEN".unicodeScalars))
  }

  @Test(arguments: [
    "zz",                      // ends in the middle of a variable-length integer
    "-",                       // a delimiter with nothing after it decodes to nothing, which is not a label
    "mnchen-3y!",              // a character that is not a base 36 digit
    "99999999999999999999",    // a delta that overflows
    "mnchen-\u{00FC}a",        // a non-basic code point among the digits
    "\u{00FC}-3ya",            // a non-basic code point in the basic part
    "a-b8c",                   // decodes to a surrogate or beyond U+10FFFF
  ])
  func rejectsMalformedInput(input: String) {
    if let decoded = Punycode.decode(input) {
      // A decode that succeeds must at least round trip; anything else is a non-canonical encoding.
      #expect(Punycode.encode(decoded) == input, "\(input) decoded to \(decoded)")
    }
  }

  @Test func rejectsTheSpecificMalformedInputs() {
    #expect(Punycode.decode("zz") == nil)
    #expect(Punycode.decode("mnchen-3y!") == nil)
    #expect(Punycode.decode("99999999999999999999") == nil)
    #expect(Punycode.decode("mnchen-\u{00FC}a") == nil)
    #expect(Punycode.decode("\u{00FC}-3ya") == nil)
  }

  /// A long run of digits must end quickly: the decoder bails out on overflow instead of looping.
  @Test func aVeryLongInputEndsWithoutHanging() {
    let long = String(repeating: "9", count: 10_000)
    #expect(Punycode.decode(long) == nil)
    let longValid = String(repeating: "a", count: 5_000) + "-" + "3ya"
    #expect(Punycode.decode(longValid)?.count == 5_001)
  }

  @Test func roundTripsAnArbitraryLabel() throws {
    let label = Array("bücher-ünd-straße-日本".unicodeScalars)
    let encoded = try #require(Punycode.encode(label))
    #expect(Punycode.decode(encoded) == label)
  }
}
