import Foundation
import Synchronization

/// How the shell writes a host (#697): the address bar, the Edit Pin popover's Pinned URL field and page info all
/// show a host through this one rule, so it reads the same everywhere.
///
/// A host shows in Unicode only when every label passes the spoof check below; otherwise the whole host keeps its
/// encoded `xn--` form, so a look-alike cannot pass for another site. The check follows Chromium's IDN display policy
/// (`docs/idn.md` and `components/url_formatter/spoof_checks/idn_spoof_checker.cc` in the Chromium source), which
/// builds on UTS #39 (Unicode Security Mechanisms) and RFC 5893 (Bidi rule for IDNA). Per label:
///
/// 1. It is a valid encoding: canonical RFC 3492 Punycode that round trips, at most 63 octets encoded, NFC and
///    lowercase, with something outside ASCII in it, no hyphen at either end and none in the 3rd and 4th place.
/// 2. Every character is Allowed by UTS #39 (`IdentifierStatus.txt`), less the code points Chromium removes from its
///    allowed set, and falls in a script the table knows (`SpoofCheck+AllowedTable.swift`). Of those, only letters,
///    combining marks and decimal digits pass; the deviation characters U+00DF and U+03C2 are refused.
/// 3. Scripts mix only as UTS #39 "Highly Restrictive" allows: one script, or Latin with Han and Kana (Japanese),
///    with Han and Bopomofo (Chinese) or with Han and Hangul (Korean), and then only ASCII Latin.
/// 4. One numbering system per label; no label of only digits and digit look-alikes.
/// 5. A right-to-left label starts with a letter and ends with a letter or digit (RFC 5893).
/// 6. Chromium's dangerous patterns: Kana and CJK characters that read as slashes or dashes next to other scripts,
///    combining marks after characters outside Latin, Greek and Cyrillic, a dot above on i, j or l, a mark on a
///    dotless i, Kana voiced sound marks, and the same mark twice in a row.
/// 7. Whole-script confusables: a label whose letters all come from a script's Latin look-alike set (Cyrillic "аррӏе")
///    shows in Unicode only under that script's own TLD or one of the ccTLDs Chromium lists for it.
///
/// Then, for the whole host (#731):
///
/// 8. Top domains: when the UTS #39 skeleton of the host, diacritics removed, ends in the skeleton of a top domain
///    (its last two to four labels), the host stays encoded unless it is that domain or a subdomain of it. So
///    "lınkedın.com" (dotless i) and "googlé.com" stay encoded, and "münchen.wikipedia.org" shows in Unicode. As in
///    Chromium's `IDNSpoofChecker::GetSimilarTopDomain`, a few characters are read more than one way (dotless i as i
///    or l, thorn as b or p, U+0153 as ce or oe, U+0142 as l or t, U+04CF as l), each reading giving a skeleton; a
///    host with more than five such characters in the labels compared stays encoded, a real one too. The top domains
///    and the skeleton pieces are precomputed in `SpoofCheck+TopDomains.swift`; a label with a character no top
///    domain's skeleton holds (Han and most other non-Latin text) ends the comparison, and only the labels after it
///    are checked.
///
/// The joiners U+200C and U+200D always stay encoded, as in Chromium: it converts with UTS #46 transitional
/// processing, which refuses them in every context, even after a virama (Sinhala "Sri" with a joiner,
/// `xn--10cl1a0b660p.lk`, stays encoded).
///
/// Where this differs from Chromium. Stricter: one failing label keeps the whole host encoded (Chromium decides label
/// by label); the deviation characters always stay encoded; Allowed punctuation characters (U+00B7, U+0375, U+05F3,
/// U+05F4, U+0F0B, U+30FB) are refused; scripts outside the table are refused; the whole-script check runs on every
/// label and has no exception words; the top-domain check runs on hosts of any length (Chromium builds no skeleton
/// for a host over 32 characters, so "login.accounts.secure.lınkedın.com" would pass there); past five characters
/// with several readings the host stays encoded (Chromium then checks no skeleton at all, so padding a look-alike
/// with dotless i, "ııı.ıı.paypaı.com", would pass there); diacritics are removed in every host (Chromium only in a
/// host of only Latin, Greek and Cyrillic); the other readings are still checked after one names the host's own top
/// domain. Looser: the top domains are Chromium's top bucket (835 domains), not its whole list of about 8,500; a
/// character whose skeleton holds a dot (U+0660, U+06F0) cannot match, so a skeleton's labels are the host's; the
/// bidi rule is checked per label, not across the domain. The Allowed table and confusables.txt come from Unicode 18.0, which may be newer
/// than the ICU data a given Chromium release uses.
public enum HostDisplay {
  /// `host` as the shell shows it: Unicode when it passes the spoof check, the encoded `xn--` form otherwise. The
  /// engine may give either form. A host with no internationalized label is returned exactly as given.
  public static func text(forHost host: String) -> String {
    let isASCII = host.unicodeScalars.allSatisfy(\.isASCII)
    if isASCII, !host.lowercased().split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) { return host }
    // No host of more than 253 code points can be valid: skip the codec and show it percent-encoded.
    if host.unicodeScalars.count > 253 { return Label.percentEncoded(host.lowercased()) }
    if let known = checked.withLock({ $0[host] }) { return known }
    let shown = checkedText(forHost: host)
    checked.withLock { cache in
      if cache.count >= checkedLimit { cache.removeAll(keepingCapacity: true) }
      cache[host] = shown
    }
    return shown
  }

  /// `url`'s host by the rule, else its whole address (`about:blank`, `data:`): what a subtitle or a top bar shows.
  /// Never saved as a tab title; see `savedTitle(for:)`.
  public static func hostOrAddress(_ url: URL) -> String { host(of: url) ?? address(url) }

  /// The title the sidebar model saves for a page with no title of its own: the raw host as the engine gives it, else
  /// the whole address. The model keeps this canonical form, so a later rule, or a title saved before #732, is written
  /// by the rule each time it is shown (`title(_:for:)`) rather than frozen when saved.
  public static func savedTitle(for url: URL) -> String { url.host() ?? url.absoluteString }

  /// A saved tab title as the shell shows it: a title that is the raw host of `url` (`savedTitle(for:)`) is written by
  /// the rule; any other title, a page's own, is returned as it is.
  public static func title(_ title: String, for url: URL) -> String {
    guard let raw = url.host(), !raw.isEmpty, title == raw else { return title }
    return host(of: url) ?? title
  }

  /// The answers for the internationalized hosts seen so far, so a list that writes many rows (command bar results,
  /// folder preview search) decodes and checks each host once. Emptied when full; at most `checkedLimit` entries of
  /// at most 253 characters each.
  private static let checked = Mutex<[String: String]>([:])
  static let checkedLimit = 512

  private static func checkedText(forHost host: String) -> String {
    var parts = host.lowercased().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let fullyQualified = parts.count > 1 && parts.last == ""
    if fullyQualified { parts.removeLast() }
    let labels = parts.map(Label.init)
    let encoded = labels.map(\.encoded).joined(separator: ".")
    let tld = labels.last ?? Label("")
    var safe = encoded.utf8.count <= 253 && labels.allSatisfy { label in
      guard !label.encoded.isEmpty, label.encoded.utf8.count <= 63 else { return false }
      guard label.isInternationalized else { return true }
      guard let unicode = label.unicode else { return false }
      return SpoofCheck.isSafe(unicode, tld: tld)
    }
    if safe, labels.contains(where: \.isInternationalized) {
      let unicode = Array(labels.map(\.text).joined(separator: ".").unicodeScalars)
      safe = SpoofCheck.similarTopDomain(unicode, encoded: encoded) == nil
    }
    let shown = safe ? labels.map(\.text).joined(separator: ".") : encoded
    return fullyQualified ? shown + "." : shown
  }

  /// The host of `url` by the rule; nil for an address without a host (`about:blank`, a file).
  public static func host(of url: URL) -> String? {
    guard let raw = url.host(percentEncoded: true), !raw.isEmpty else { return nil }
    // A percent-encoded host is read as the text it stands for, unless that text holds characters no host name has.
    let decoded = url.host(percentEncoded: false) ?? raw
    let readable = decoded.unicodeScalars.allSatisfy { !$0.isASCII || hostCharacters.contains($0) }
    return text(forHost: readable ? decoded : raw)
  }

  /// `url`'s full text with its host written by the rule; the scheme, user, port, path, query and fragment stay
  /// exactly as they are.
  public static func address(_ url: URL) -> String {
    let full = url.absoluteString
    guard let components = URLComponents(string: full), var string = components.string, string == full,
          let range = components.rangeOfHost, !range.isEmpty, string[range].first != "[",
          let shown = host(of: url), shown != string[range] else { return full }
    string.replaceSubrange(range, with: shown)
    return string
  }

  private static let hostCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:"
    .unicodeScalars)

  /// One label of a lowercased host in both forms.
  struct Label {
    /// The ASCII form: the label itself, or its `xn--` encoding.
    let encoded: String
    /// The code points it stands for; nil when an `xn--` label does not decode to a valid, canonical encoding.
    let unicode: [Unicode.Scalar]?
    /// Whether it is an `xn--` label or holds characters outside ASCII.
    let isInternationalized: Bool

    var text: String { unicode.map { String(String.UnicodeScalarView($0)) } ?? encoded }

    init(_ part: String) {
      let scalars = Array(part.unicodeScalars)
      if scalars.allSatisfy(\.isASCII) {
        encoded = part
        isInternationalized = part.hasPrefix("xn--")
        guard isInternationalized else {
          unicode = scalars
          return
        }
        let body = String(part.dropFirst(4))
        guard body.utf8.count <= 59, body.unicodeScalars.allSatisfy(Self.isACECharacter),
              let decoded = Punycode.decode(body), Punycode.encode(decoded) == body,
              decoded.contains(where: { !$0.isASCII }) else {
          unicode = nil
          return
        }
        unicode = decoded
      } else {
        isInternationalized = true
        // A label past a host's 253 octets can never be valid; percent-encoding it keeps the codec off hostile
        // lengths. Shorter ones get their real encoding, which the length checks then judge.
        if scalars.count <= 253, let body = Punycode.encode(scalars) {
          encoded = "xn--" + body
          unicode = scalars
        } else {
          encoded = Self.percentEncoded(part)
          unicode = nil
        }
      }
    }

    private static let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")

    /// `text` with everything but ASCII letters, digits, hyphens and dots percent-encoded: plain ASCII to show.
    static func percentEncoded(_ text: String) -> String {
      text.addingPercentEncoding(withAllowedCharacters: asciiAlphanumerics) ?? ""
    }

    private static func isACECharacter(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar {
      case "a"..."z", "0"..."9", "-": true
      default: false
      }
    }
  }
}

/// The per-label spoof check behind `HostDisplay` (see its documentation for the policy and its sources).
enum SpoofCheck {
  enum Script: Hashable, Sendable {
    case latin, greek, cyrillic, armenian, hebrew, arabic, thaana, devanagari, bengali, gurmukhi, gujarati, oriya
    case tamil, telugu, kannada, malayalam, sinhala, thai, lao, tibetan, myanmar, georgian, ethiopic, khmer
    case han, hiragana, katakana, bopomofo, hangul
  }

  /// What a character counts as for script mixing: a script, or neither (ASCII digits and the hyphen; combining
  /// diacritics, which take the script of the letter they sit on).
  enum Kind: Equatable {
    case script(Script)
    case common
    case inherited
  }

  /// Allowed by the table (`SpoofCheck+AllowedTable.swift`) but refused here: the deviation characters, which
  /// IDNA 2003 and IDNA 2008 treat differently (Chromium decides them per TLD; this rule always keeps them encoded).
  static let refused: Set<UInt32> = [0x00DF, 0x03C2]

  // Copied from Chromium's idn_spoof_checker.cc (BSD-3-Clause, see THIRD_PARTY_NOTICES.md): the tables below.

  /// Chromium's `kWholeScriptConfusables`: each script's letters that look Latin, and the ccTLDs where a label of
  /// only those letters is still shown in Unicode (besides a TLD in the script itself).
  static let wholeScriptConfusables: [(script: Script, lookalikes: Set<Unicode.Scalar>, tlds: Set<String>)] = [
    (.armenian, set("ագզէլհյոսւօՙ"), ["am"]),
    (.cyrillic, set("аысԁеԍһіюкјӏморԗԛѕтԝхуъьҽпгѵѡ"), ["bg", "by", "kz", "pyc", "ru", "su", "ua", "uz"]),
    (.ethiopic, set("ሀሠሰስበነተከዐዕዘጠፐꬅ"), ["er", "et"]),
    (.georgian, set("იოყძხჽჿ"), ["ge"]),
    (.greek, set("αικνρυωηοτ"), ["gr"]),
    (.hebrew, set("דוחיןסװײ׳ﬦ"), ["il"]),
    (.bengali, set("০৭"), []),
    (.devanagari, set("ऽ०ॱ"), []),
    (.gujarati, set("ડટ૦૧"), []),
    (.gurmukhi, set("੦੧"), []),
    (.kannada, set("ಽ೦೧"), []),
    (.malayalam, set("ടഠധനറ൦"), []),
    (.oriya, set("ଠ୦୮"), []),
    (.tamil, set("டப௦"), []),
    (.telugu, set("౦౧"), []),
    (.myanmar, set("ခဂငထပဝ၀၂ၔၜ\u{1090}\u{1091}\u{1095}\u{1096}\u{1097}"), ["mm"]),
    (.thai, set("บพเแ๐"), ["th"]),
  ]

  /// Chromium's `digit_lookalikes_`: characters that read as digits.
  static let digitLookalikes = set("θ२২੨૨೩೭շзҙӡउওਤ੩૩౩ဒვპੜკ੫丩ㄐճ৪੪୫૭୨౨")

  /// Kana and CJK characters that read as a slash next to another script (from Chromium's `kDangerousPattern`).
  static let slashLookalikes: Set<UInt32> = [0x30CE, 0x30F3, 0x30BD, 0x30BE, 0x4E36, 0x4E40, 0x4E41, 0x4E3F]
  /// CJK characters and radicals that read as Latin letters or punctuation next to a non-CJK character (from
  /// Chromium's `kDangerousPattern`).
  static let cjkLookalikes: Set<UInt32> = [
    0x4E00, 0x3127, 0x4E28, 0x4E5B, 0x4E03, 0x4E05, 0x5341, 0x3007, 0x3112, 0x311A, 0x311F, 0x3128, 0x3129, 0x3108,
    0x31BA, 0x31B3, 0x5DE5, 0x31B2, 0x8BA0, 0x4E01, 0x4E36, 0x4E85, 0x4E8C, 0x4EA0, 0x5196, 0x5B80, 0x5DDB,
  ]

  private static func set(_ string: String) -> Set<Unicode.Scalar> { Set(string.unicodeScalars) }

  static func kind(of scalar: Unicode.Scalar) -> Kind? {
    switch scalar {
    case "a"..."z": return .script(.latin)
    case "0"..."9", "-": return .common
    default: break
    }
    guard !scalar.isASCII, !refused.contains(scalar.value), let kind = allowedKind(of: scalar.value) else { return nil }
    // The Allowed set also holds a few punctuation and format characters (U+00B7, U+05F3, U+30FB, U+200C, U+200D);
    // only letters, marks and decimal digits pass here.
    switch scalar.properties.generalCategory {
    case .lowercaseLetter, .uppercaseLetter, .otherLetter, .modifierLetter, .nonspacingMark, .spacingMark,
         .decimalNumber:
      return kind
    default:
      return nil
    }
  }

  /// The row of `allowedTable` holding `value`, by binary search.
  private static func allowedKind(of value: UInt32) -> Kind? {
    var low = 0
    var high = allowedTable.count - 1
    while low <= high {
      let middle = (low + high) / 2
      let row = allowedTable[middle]
      if value < row.first {
        high = middle - 1
      } else if value > row.last {
        low = middle + 1
      } else {
        return row.kind
      }
    }
    return nil
  }

  private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: true
    default: false
    }
  }

  /// Whether `label` (decoded, from an internationalized label) may show in Unicode under the TLD `tld`.
  static func isSafe(_ label: [Unicode.Scalar], tld: HostDisplay.Label) -> Bool {
    guard let first = label.first, let last = label.last, label.contains(where: { !$0.isASCII }) else { return false }
    let string = String(String.UnicodeScalarView(label))
    guard Array(string.precomposedStringWithCanonicalMapping.unicodeScalars) == label,
          Array(string.lowercased().unicodeScalars) == label else { return false }
    guard first != "-", last != "-", !(label.count >= 4 && label[2] == "-" && label[3] == "-") else { return false }

    var kinds: [Kind] = []
    for scalar in label {
      guard let kind = kind(of: scalar) else { return false }
      kinds.append(kind)
    }
    let scripts = Set(kinds.compactMap { if case .script(let script) = $0 { script } else { nil } })
    return !isMark(first)
      && allowsMix(of: scripts, in: label)
      && hasOneNumberingSystem(label)
      && passesBidiRule(label, kinds: kinds, scripts: scripts)
      && passesTLDSpecificCharacters(label, tld: tld)
      && !hasDangerousPattern(label, kinds: kinds)
      && !isWholeScriptConfusable(label, kinds: kinds, tld: tld)
      && !isDigitLookalike(label)
  }

  /// UTS #39 Highly Restrictive, with Chromium's Latin restriction: Latin mixes only as ASCII.
  private static func allowsMix(of scripts: Set<Script>, in label: [Unicode.Scalar]) -> Bool {
    guard scripts.count > 1 else { return true }
    let japanese: Set<Script> = [.latin, .han, .hiragana, .katakana]
    let chinese: Set<Script> = [.latin, .han, .bopomofo]
    let korean: Set<Script> = [.latin, .han, .hangul]
    guard scripts.isSubset(of: japanese) || scripts.isSubset(of: chinese) || scripts.isSubset(of: korean) else {
      return false
    }
    return !scripts.contains(.latin) || !label.contains { !$0.isASCII && kind(of: $0) == .script(.latin) }
  }

  private static func hasOneNumberingSystem(_ label: [Unicode.Scalar]) -> Bool {
    let zeros = Set(label.compactMap { scalar -> UInt32? in
      guard scalar.properties.generalCategory == .decimalNumber,
            let value = scalar.properties.numericValue else { return nil }
      return scalar.value - UInt32(value)
    })
    return zeros.count <= 1
  }

  /// RFC 5893 for a right-to-left label: it starts with a letter and ends with a letter or digit, then only marks.
  /// Mixing with a left-to-right script is already refused by `allowsMix`.
  private static func passesBidiRule(_ label: [Unicode.Scalar], kinds: [Kind], scripts: Set<Script>) -> Bool {
    guard !scripts.isDisjoint(with: [.hebrew, .arabic, .thaana]) else { return true }
    func isLetter(_ index: Int) -> Bool {
      if case .script = kinds[index] { return label[index].properties.isAlphabetic && !isMark(label[index]) }
      return false
    }
    guard isLetter(0), let end = label.lastIndex(where: { !isMark($0) }) else { return false }
    return isLetter(end) || label[end].properties.generalCategory == .decimalNumber
  }

  /// Thorn and eth only under Iceland's and the Faroes' TLDs, schwa only under Azerbaijan's.
  private static func passesTLDSpecificCharacters(_ label: [Unicode.Scalar], tld: HostDisplay.Label) -> Bool {
    guard label.count > 1 else { return true }
    if label.contains(where: { $0 == "\u{00FE}" || $0 == "\u{00F0}" }), !["is", "fo"].contains(tld.encoded) {
      return false
    }
    return !label.contains("\u{0259}") || tld.encoded == "az"
  }

  // Follows Chromium's kDangerousPattern in idn_spoof_checker.cc (BSD-3-Clause, see THIRD_PARTY_NOTICES.md).
  private static func hasDangerousPattern(_ label: [Unicode.Scalar], kinds: [Kind]) -> Bool {
    func isKana(_ i: Int) -> Bool { kinds[i] == .script(.hiragana) || kinds[i] == .script(.katakana) }
    func isJapanese(_ i: Int) -> Bool { isKana(i) || kinds[i] == .script(.han) }
    func isCJK(_ i: Int) -> Bool { isJapanese(i) || kinds[i] == .script(.bopomofo) }
    func isLGC(_ i: Int) -> Bool { [.script(.latin), .script(.greek), .script(.cyrillic)].contains(kinds[i]) }
    let count = label.count
    for (i, scalar) in label.enumerated() {
      let value = scalar.value
      let hasLeft = i > 0
      let hasRight = i < count - 1
      if slashLookalikes.contains(value), hasLeft, hasRight, !isJapanese(i - 1), !isJapanese(i + 1) { return true }
      if value == 0x30FD || value == 0x30FE, !hasLeft || kinds[i - 1] != .script(.katakana) { return true }
      if value == 0x30FC, !hasLeft || !isKana(i - 1) { return true }
      if cjkLookalikes.contains(value), (hasLeft && !isCJK(i - 1)) || (hasRight && !isCJK(i + 1)) { return true }
      if (0x0300...0x0339).contains(value), !hasLeft || !isLGC(i - 1) { return true }
      if (0x0300...0x0339).contains(value), hasLeft, label[i - 1] == "\u{0131}" { return true }
      if value == 0x3099 || value == 0x309A { return true }
      if value == 0x0307, hasLeft, ["i", "j", "l"].contains(label[i - 1]) { return true }
      if isMark(scalar), hasLeft, label[i - 1] == scalar { return true }
    }
    // Hiragana he/be/pe in an otherwise Katakana label, and Katakana he/be/pe in an otherwise Hiragana one.
    if count >= 3 {
      let inner = label[1..<(count - 1)]
      let hiraganaHe = inner.filter { (0x3078...0x307A).contains($0.value) }.count
      let katakanaHe = inner.filter { (0x30D8...0x30DA).contains($0.value) }.count
      let others = { (range: ClosedRange<UInt32>, script: Script) in
        label.indices.allSatisfy { range.contains(label[$0].value) || kinds[$0] == .script(script) }
      }
      if hiraganaHe == 1, others(0x3078...0x307A, .katakana) { return true }
      if katakanaHe == 1, others(0x30D8...0x30DA, .hiragana) { return true }
    }
    return false
  }

  private static func isWholeScriptConfusable(_ label: [Unicode.Scalar], kinds: [Kind],
                                              tld: HostDisplay.Label) -> Bool {
    let tldKinds = (tld.unicode ?? []).map(kind(of:))
    return wholeScriptConfusables.contains { entry in
      let letters = label.indices.filter { kinds[$0] == .script(entry.script) }.map { label[$0] }
      guard !letters.isEmpty, letters.allSatisfy(entry.lookalikes.contains) else { return false }
      let tldIsInScript = tldKinds.contains(.script(entry.script))
      return !tldIsInScript && !entry.tlds.contains(tld.encoded)
    }
  }

  // MARK: Top domains (#731)

  /// The most characters with several readings in the labels compared, and the most skeletons, as in Chromium's
  /// skeleton generator. Past either limit the host is not checked reading by reading: it stays encoded.
  static let maxCharactersWithSeveralReadings = 5
  static let maxSkeletons = 128
  /// What `similarTopDomain` returns for a host past those limits: it cannot be cleared, so it stays encoded.
  static let tooManyReadings = "(too many readings)"
  /// The most labels at the end of a host compared with the top domains (Chromium's `kNumberOfLabelsToCheck`).
  static let labelsToCheck = 4

  /// The top domain `host` (Unicode, lowercased, no trailing dot) looks like but is not, `tooManyReadings` when it has
  /// too many characters with several readings to check, or nil. `encoded` is the host's ASCII form, which a top
  /// domain or its subdomain equals.
  static func similarTopDomain(_ host: [Unicode.Scalar], encoded: String) -> String? {
    var found: String?
    let checkedEveryReading = forEachSkeleton(of: host) { skeleton, labelStarts in
      guard let domain = topDomain(in: skeleton, labelStarts: labelStarts) else { return true }
      if encoded == domain || encoded.hasSuffix("." + domain) { return true }
      found = domain
      return false
    }
    return checkedEveryReading ? found : tooManyReadings
  }

  /// The skeletons `similarTopDomain` compares: of the host's last labels, at most four, after the last label holding
  /// a character that no top domain's skeleton holds; one per reading of its characters; none for fewer than two
  /// labels, or past the limits on readings.
  static func skeletons(of host: [Unicode.Scalar]) -> [String] {
    var result: [String] = []
    forEachSkeleton(of: host) { skeleton, _ in
      result.append(String(decoding: skeleton, as: UTF8.self))
      return true
    }
    return result
  }

  /// The top domain whose skeleton is the end of `skeleton`: its last four, three or two labels, longest first.
  static func topDomain(matching skeleton: String) -> String? {
    let bytes = Array(skeleton.utf8)
    var labelStarts = [0]
    for (offset, byte) in bytes.enumerated() where byte == UInt8(ascii: ".") { labelStarts.append(offset + 1) }
    if labelStarts.count > labelsToCheck { labelStarts.removeFirst(labelStarts.count - labelsToCheck) }
    return topDomain(in: bytes, labelStarts: labelStarts)
  }

  /// Calls `body` with each skeleton of the end of `host` and the offsets where its labels start, until it returns
  /// false. One buffer is reused for every skeleton. Returns false, without calling `body`, when the labels compared
  /// have more characters with several readings, or more combinations of readings, than the limits allow.
  @discardableResult
  private static func forEachSkeleton(of host: [Unicode.Scalar],
                                      _ body: (_ skeleton: [UInt8], _ labelStarts: [Int]) -> Bool) -> Bool {
    // The readings of each character of the last labels, from the end, up to a label that cannot match.
    var labels: [[[String]]] = []
    var end = host.endIndex
    while labels.count < labelsToCheck, end >= host.startIndex {
      let start = host[..<end].lastIndex(of: ".").map { $0 + 1 } ?? host.startIndex
      var label: [[String]] = []
      label.reserveCapacity(end - start)
      for scalar in host[start..<end] {
        guard let readings = skeletonReadings(of: scalar.value) else { break }
        label.append(readings)
      }
      guard label.count == end - start else { break }
      labels.insert(label, at: 0)
      end = start - 1
    }
    guard labels.count >= 2 else { return true }

    // The characters read more than one way. Every combination of their readings is checked; past the limits none is,
    // so a look-alike cannot pass by padding the host with more such characters.
    var varying: [(label: Int, character: Int)] = []
    var combinations = 1
    for (labelIndex, label) in labels.enumerated() {
      for (characterIndex, readings) in label.enumerated() where readings.count > 1 {
        varying.append((labelIndex, characterIndex))
        combinations *= readings.count
        if varying.count > maxCharactersWithSeveralReadings || combinations > maxSkeletons { return false }
      }
    }
    var chosen = labels.map { [Int](repeating: 0, count: $0.count) }
    var skeleton: [UInt8] = []
    skeleton.reserveCapacity(host.count * 2)
    var labelStarts: [Int] = []
    for _ in 0..<maxSkeletons {
      skeleton.removeAll(keepingCapacity: true)
      labelStarts.removeAll(keepingCapacity: true)
      for (labelIndex, label) in labels.enumerated() {
        if labelIndex > 0 { skeleton.append(UInt8(ascii: ".")) }
        labelStarts.append(skeleton.count)
        for (characterIndex, readings) in label.enumerated() {
          skeleton.append(contentsOf: readings[chosen[labelIndex][characterIndex]].utf8)
        }
      }
      guard body(skeleton, labelStarts) else { return true }
      // The next combination of readings, counting through them like an odometer; done when it wraps around.
      var digit = varying.count - 1
      while digit >= 0 {
        let (labelIndex, characterIndex) = varying[digit]
        chosen[labelIndex][characterIndex] += 1
        if chosen[labelIndex][characterIndex] < labels[labelIndex][characterIndex].count { break }
        chosen[labelIndex][characterIndex] = 0
        digit -= 1
      }
      if digit < 0 { return true }
    }
    return true
  }

  /// The top domain whose skeleton is `skeleton` from one of `labelStarts` to its end, trying all but the last start,
  /// in order: a skeleton of one label never matches.
  private static func topDomain(in skeleton: [UInt8], labelStarts: [Int]) -> String? {
    for start in labelStarts.dropLast() {
      if let domain = topDomain(withSkeleton: skeleton[start...]) { return domain }
    }
    return nil
  }

  /// Binary search of `topDomains`, which is sorted by the skeleton's UTF-8 bytes.
  private static func topDomain(withSkeleton key: ArraySlice<UInt8>) -> String? {
    var low = 0
    var high = topDomains.count - 1
    while low <= high {
      let middle = (low + high) / 2
      let row = topDomains[middle].skeleton.utf8
      if row.elementsEqual(key) { return topDomains[middle].domain }
      if row.lexicographicallyPrecedes(key) {
        low = middle + 1
      } else {
        high = middle - 1
      }
    }
    return nil
  }

  /// The readings of one character from `skeletonPieces`, by binary search.
  private static func skeletonReadings(of value: UInt32) -> [String]? {
    var low = 0
    var high = skeletonPieces.count - 1
    while low <= high {
      let middle = (low + high) / 2
      let row = skeletonPieces[middle]
      if value < row.scalar {
        high = middle - 1
      } else if value > row.scalar {
        low = middle + 1
      } else {
        return row.readings
      }
    }
    return nil
  }

  private static func isDigitLookalike(_ label: [Unicode.Scalar]) -> Bool {
    var hasLookalike = false
    for scalar in label {
      if ("0"..."9").contains(scalar) { continue }
      guard digitLookalikes.contains(scalar) else { return false }
      hasLookalike = true
    }
    return hasLookalike
  }
}
