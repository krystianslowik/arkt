import Foundation

/// Decides whether command bar input is a URL to open or a query to search.
///
/// Rules, in order:
/// - Input with whitespace is a query.
/// - A leading scheme (`^[A-Za-z][A-Za-z0-9+.-]*://`) must be http or https and have a host; other schemes are
///   queries. A "://" later in the input (`example.com/login?next=https://x`) is not a scheme.
/// - Otherwise the authority (up to the first `/ ? #`) must be `host[:port]` where host is `localhost`, an IPv4
///   dotted quad (each part 0-255), a bracketed IPv6 literal, or a domain name. IP literals and localhost open
///   over http (no certificate would match them); domain names open over https.
/// - Domain names: 2+ labels of letters (any script, for IDN), ASCII digits and inner hyphens; the last label is
///   2+ letters or a punycode `xn--` label. Foundation IDNA-encodes non-ASCII hosts (`münchen.de` ->
///   `xn--mnchen-3ya.de`). So `1.5` and `file.x` stay queries.
public enum URLInputParser {
  /// TODO: the default search engine is a product decision; Arc defaulted to Google.
  public static let searchBase = "https://www.google.com/search?q="

  private static let queryAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: "&+=?#")
    return set
  }()

  /// A URL for input that looks like one, else nil (the input is a search query).
  public static func url(from raw: String) -> URL? {
    let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty, input.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

    if let scheme = leadingScheme(input) {
      guard scheme == "http" || scheme == "https", let url = URL(string: input),
            let host = url.host(), !host.isEmpty else { return nil }
      return url
    }

    let authority = String(input.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
    guard let host = host(ofAuthority: authority) else { return nil }
    if host.lowercased() == "localhost" || isIPv4(host) || host.hasPrefix("[") {
      return URL(string: "http://" + input)
    }
    guard isDomainName(host) else { return nil }
    return URL(string: "https://" + input)
  }

  /// Search URL for a query; `& + = ? #` are escaped so they stay inside the `q` value.
  public static func searchURL(for query: String) -> URL {
    let encoded = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
    return URL(string: searchBase + encoded) ?? URL(string: searchBase)!
  }

  /// The lowercased scheme when the input starts with `scheme://`, else nil.
  private static func leadingScheme(_ input: String) -> String? {
    guard let first = input.first, first.isASCII, first.isLetter else { return nil }
    let scheme = input.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
    return input.dropFirst(scheme.count).hasPrefix("://") ? scheme.lowercased() : nil
  }

  /// The host of `host[:port]` or `[ipv6][:port]`, nil when the shape or the port is invalid.
  /// A bracketed IPv6 host is returned with its brackets.
  private static func host(ofAuthority authority: String) -> String? {
    let host: Substring
    let rest: Substring
    if authority.hasPrefix("[") {
      guard let close = authority.firstIndex(of: "]") else { return nil }
      host = authority[...close]
      rest = authority[authority.index(after: close)...]
      guard isIPv6(String(host.dropFirst().dropLast())) else { return nil }
    } else {
      let parts = authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      host = parts[0]
      rest = parts.count == 2 ? authority[authority.index(before: parts[1].startIndex)...] : ""
    }
    if !rest.isEmpty {
      let port = rest.dropFirst()
      guard rest.first == ":", !port.isEmpty, port.count <= 5, port.allSatisfy({ $0.isASCII && $0.isNumber }),
            let value = Int(port), value <= 65_535 else { return nil }
    }
    return host.isEmpty ? nil : String(host)
  }

  private static func isIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 4 && parts.allSatisfy { part in
      (1...3).contains(part.count) && part.allSatisfy { $0.isASCII && $0.isNumber } && (Int(part) ?? 256) <= 255
    }
  }

  private static func isIPv6(_ literal: String) -> Bool {
    var address = in6_addr()
    return literal.withCString { inet_pton(AF_INET6, $0, &address) } == 1
  }

  private static func isDomainName(_ host: String) -> Bool {
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2, labels.allSatisfy(isLabel), let tld = labels.last else { return false }
    let punycode = tld.lowercased().hasPrefix("xn--") && tld.count > 4
    return punycode || (tld.count >= 2 && tld.allSatisfy(\.isLetter))
  }

  private static func isLabel(_ label: Substring) -> Bool {
    guard let first = label.first, let last = label.last, first != "-", last != "-" else { return false }
    return label.allSatisfy { $0.isLetter || ($0.isASCII && $0.isNumber) || $0 == "-" }
  }
}
