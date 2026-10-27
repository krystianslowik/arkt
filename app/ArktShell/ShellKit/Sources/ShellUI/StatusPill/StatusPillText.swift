import Foundation

/// The address of the link under the pointer, as the status pill writes it (design/status-pill/README.md, "What it
/// shows"): a quiet prefix (the scheme unless it is https, and any user info), the host in emphasis, and the rest (port,
/// path, query, fragment) quiet again.
///
/// It reads the URL's own text and never rewrites it: no percent-decoding, no punycode to Unicode, no lowercasing, no
/// trimming of `www.`. A host that looks like another one must look like it here too, so the user can tell; the user
/// info stays visible before the host for the same reason (`https://bank.example@evil.example/`). Only characters that
/// would draw invisibly or reorder the line (controls, format characters such as the bidirectional overrides and the
/// zero-width ones, line and paragraph separators) are written out as `<U+202E>`, so they cannot hide anything.
struct StatusPillText: Equatable, Sendable {
  /// Scheme (`http://`, `mailto:`) and user info (`user@`); empty for a plain https address.
  var prefix: String
  /// The host, or for an address without one (`mailto:`, `javascript:`, `data:`) the part after the scheme.
  var host: String
  /// Port, path, query and fragment.
  var rest: String

  /// Longest part kept before layout; the pill middle-truncates what is left. A `data:` URL can be megabytes.
  static let maxCharacters = 1024

  init(prefix: String, host: String, rest: String) {
    self.prefix = prefix
    self.host = host
    self.rest = rest
  }

  init(_ url: URL) {
    let text = url.absoluteString
    guard let separator = text.range(of: "://"), Self.isScheme(text[..<separator.lowerBound]) else {
      // No authority: `scheme:rest`. The scheme is always shown, the remainder takes the emphasis.
      if let colon = text.firstIndex(of: ":"), Self.isScheme(text[..<colon]) {
        self.init(prefix: Self.safe(Self.clipped(String(text[...colon]))),
                  host: Self.safe(Self.clipped(String(text[text.index(after: colon)...]))), rest: "")
      } else {
        self.init(prefix: "", host: Self.safe(Self.clipped(text)), rest: "")
      }
      return
    }
    let scheme = text[..<separator.lowerBound]
    let afterScheme = text[separator.upperBound...]
    let authorityEnd = afterScheme.firstIndex { "/?#".contains($0) } ?? afterScheme.endIndex
    var authority = afterScheme[..<authorityEnd]
    let tail = afterScheme[authorityEnd...]

    var prefix = scheme.lowercased() == "https" ? "" : "\(scheme)://"
    if let at = authority.lastIndex(of: "@") {
      prefix += authority[...at]
      authority = authority[authority.index(after: at)...]
    }
    let (host, port) = Self.split(hostAndPort: authority)
    self.init(prefix: Self.safe(Self.clipped(prefix)), host: Self.safe(Self.clipped(String(host))),
              rest: Self.safe(Self.clipped(String(port) + String(tail))))
  }

  /// The whole line, for width measurement and tests.
  var fullText: String { prefix + host + rest }

  // MARK: Parsing

  private static func isScheme(_ text: Substring) -> Bool {
    guard let first = text.first, first.isASCII, first.isLetter else { return false }
    return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
  }

  /// `host:port`, with an IPv6 literal kept whole (`[::1]:8080`).
  private static func split(hostAndPort text: Substring) -> (host: Substring, port: Substring) {
    if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
      let end = text.index(after: close)
      return (text[..<end], text[end...])
    }
    guard let colon = text.lastIndex(of: ":") else { return (text, "") }
    return (text[..<colon], text[colon...])
  }

  /// Keeps the head and the tail of an overlong part; what the pill truncates is the middle anyway.
  private static func clipped(_ text: String) -> String {
    guard text.count > maxCharacters else { return text }
    let half = maxCharacters / 2
    return String(text.prefix(half)) + String(text.suffix(half))
  }

  /// Writes out the characters that draw as nothing or move other text.
  static func safe(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: isInvisible) else { return text }
    var result = ""
    for scalar in text.unicodeScalars {
      if isInvisible(scalar) {
        result += "<U+" + String(scalar.value, radix: 16, uppercase: true).leftPadded(to: 4) + ">"
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .format, .lineSeparator, .paragraphSeparator, .unassigned, .privateUse, .surrogate: true
    default: false
    }
  }
}

private extension String {
  func leftPadded(to length: Int) -> String {
    count >= length ? self : String(repeating: "0", count: length - count) + self
  }
}
