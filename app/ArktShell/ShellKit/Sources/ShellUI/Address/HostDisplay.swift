import Foundation

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
/// 2. Every character is a letter, a combining mark or a decimal digit of a script the table below knows. Symbols,
///    punctuation, spaces and invisible characters (zero width joiners, soft hyphens, bidi controls, variation
///    selectors, fillers) are refused, as are the deviation characters U+00DF and U+03C2, and the blocks Chromium
///    removes from its allowed set (Latin Extended Additional below U+1E9C, pinyin, Greek Extended).
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
/// Chromium also compares the host's skeleton with a list of top domains; that list is not shipped here, so a
/// single-script look-alike that passes the checks above (a Latin label with diacritics) still shows in Unicode.
public enum HostDisplay {
  /// `host` as the shell shows it: Unicode when it passes the spoof check, the encoded `xn--` form otherwise. The
  /// engine may give either form. A host with no internationalized label is returned exactly as given.
  public static func text(forHost host: String) -> String {
    let isASCII = host.unicodeScalars.allSatisfy(\.isASCII)
    if isASCII, !host.lowercased().split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) { return host }
    var parts = host.lowercased().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let fullyQualified = parts.count > 1 && parts.last == ""
    if fullyQualified { parts.removeLast() }
    let labels = parts.map(Label.init)
    let encoded = labels.map(\.encoded).joined(separator: ".")
    let tld = labels.last ?? Label("")
    let safe = encoded.utf8.count <= 253 && labels.allSatisfy { label in
      guard !label.encoded.isEmpty, label.encoded.utf8.count <= 63 else { return false }
      guard label.isInternationalized else { return true }
      guard let unicode = label.unicode else { return false }
      return SpoofCheck.isSafe(unicode, tld: tld)
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
          encoded = part.addingPercentEncoding(withAllowedCharacters: Self.asciiAlphanumerics) ?? "xn--"
          unicode = nil
        }
      }
    }

    private static let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

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

  /// The characters each script may use, by block. Anything outside these ranges is refused, so an unlisted script
  /// keeps the encoded form. Within a range only letters, marks and decimal digits pass (see `kind(of:)`).
  static let ranges: [(ClosedRange<UInt32>, Script)] = [
    (0x00DF...0x00FF, .latin), (0x0100...0x017E, .latin), (0x01A0...0x01A1, .latin), (0x01AF...0x01B0, .latin),
    (0x0218...0x021B, .latin), (0x0259...0x0259, .latin), (0x1EA0...0x1EF9, .latin),
    (0x0390...0x0390, .greek), (0x03AC...0x03CE, .greek),
    (0x0430...0x045F, .cyrillic), (0x048B...0x052F, .cyrillic),
    (0x0559...0x0559, .armenian), (0x0561...0x0586, .armenian),
    (0x0591...0x05C7, .hebrew), (0x05D0...0x05EA, .hebrew), (0x05EF...0x05F2, .hebrew),
    (0x0610...0x061A, .arabic), (0x0620...0x06FF, .arabic), (0x0750...0x077F, .arabic), (0x08A0...0x08FF, .arabic),
    (0x0780...0x07B1, .thaana),
    (0x0900...0x097F, .devanagari), (0x0980...0x09FF, .bengali), (0x0A00...0x0A7F, .gurmukhi),
    (0x0A80...0x0AFF, .gujarati), (0x0B00...0x0B7F, .oriya), (0x0B80...0x0BFF, .tamil), (0x0C00...0x0C7F, .telugu),
    (0x0C80...0x0CFF, .kannada), (0x0D00...0x0D7F, .malayalam), (0x0D80...0x0DFF, .sinhala),
    (0x0E00...0x0E7F, .thai), (0x0E80...0x0EFF, .lao), (0x0F00...0x0FFF, .tibetan), (0x1000...0x109F, .myanmar),
    (0x10D0...0x10FF, .georgian), (0x1200...0x139F, .ethiopic), (0xAB01...0xAB2F, .ethiopic),
    (0x1780...0x17FF, .khmer),
    (0x3041...0x309F, .hiragana), (0x30A0...0x30FF, .katakana),
    (0x3005...0x3007, .han), (0x3400...0x4DBF, .han), (0x4E00...0x9FFF, .han), (0x20000...0x2A6DF, .han),
    (0x2A700...0x2EBEF, .han), (0x30000...0x323AF, .han),
    (0x3105...0x312F, .bopomofo), (0x31A0...0x31BF, .bopomofo),
    (0xAC00...0xD7A3, .hangul),
  ]

  /// Inside the ranges but refused: kra and the n with apostrophe (obsolete), the deviation characters, the Arabic
  /// tatweel (a stretch with no meaning).
  static let refused: Set<UInt32> = [0x0138, 0x0149, 0x00DF, 0x03C2, 0x0640]

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
  static let digitLookalikes = set("θ२২੨੨૨೩೭շзҙӡउওਤ੩૩౩ဒვპੜკ੫丩ㄐճ৪੪୫૭୨౨")

  /// Kana and CJK characters that read as a slash next to another script.
  static let slashLookalikes: Set<UInt32> = [0x30CE, 0x30F3, 0x30BD, 0x30BE, 0x4E36, 0x4E40, 0x4E41, 0x4E3F]
  /// CJK characters and radicals that read as Latin letters or punctuation next to a non-CJK character.
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
    guard !scalar.isASCII, !refused.contains(scalar.value) else { return nil }
    switch scalar.properties.generalCategory {
    case .lowercaseLetter, .otherLetter, .modifierLetter, .nonspacingMark, .spacingMark, .decimalNumber: break
    default: return nil
    }
    if (0x0300...0x0339).contains(scalar.value) { return .inherited }
    return ranges.first { $0.0.contains(scalar.value) }.map { .script($0.1) }
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
