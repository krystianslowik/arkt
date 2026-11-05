import Foundation

/// Which field the Edit Pin popover focuses (#363): Name from a Favorite's Rename..., Pinned URL from Edit Pinned
/// URL...
public enum EditPinFocus: Hashable, Sendable {
  case name
  case url
}

/// What the Edit Pin popover edits: a pinned tab's row or a Favorite's tile.
public enum EditPinKind: Equatable, Sendable {
  case pinnedTab
  case favorite
}

/// The Edit Pin popover's state (design/edit-pin, direction B): the Name and Pinned URL fields, the invalid address
/// line and what Save stores. A value; `EditPinController` shows it and writes the outcome to the sidebar.
struct EditPinForm {
  /// The line under Pinned URL after Save with something that is not a web address.
  static let invalidAddressMessage = "Enter a web address, like example.com"

  /// What Save does: store the changed values (nil for a field left as it was), or show the invalid address line.
  enum Outcome: Equatable {
    /// `name` "" clears the custom title, so the tab shows its page's title again.
    case save(name: String?, url: URL?)
    case invalid
  }

  let kind: EditPinKind
  private let originalName: String
  private let originalURL: URL
  /// The address the tab shows now (its pinned URL when it has no live page), for Use Current Page.
  private let currentPage: URL
  private(set) var name: String
  private(set) var urlText: String
  private(set) var showsInvalidAddress = false
  /// The address `urlText` stands for while it is a prefilled one (the stored URL or Use Current Page's), so an
  /// address the field cannot type back exactly (http, an IP address) is stored as it was.
  private var prefilled: (text: String, url: URL)

  init(kind: EditPinKind, name: String, url: URL, currentPage: URL) {
    self.kind = kind
    originalName = name
    originalURL = url
    self.currentPage = currentPage
    self.name = name
    urlText = Self.text(for: url)
    prefilled = (urlText, url)
  }

  var title: String { kind == .favorite ? "Edit Favorite" : "Edit Pinned Tab" }

  /// The field's text for `url`: an https address without its scheme, as the address bar shows it; any other
  /// address in full. An internationalized host reads in Unicode (`xn--mnchen-3ya.de` as `münchen.de`); Save
  /// encodes it again through `URLInputParser`.
  static func text(for url: URL) -> String {
    var full = url.absoluteString
    if let host = url.host(percentEncoded: true), let range = full.range(of: host) {
      let unicode = Punycode.unicodeHost(host)
      if unicode != host { full.replaceSubrange(range, with: unicode) }
    }
    let prefix = "https://"
    guard url.scheme?.lowercased() == "https", full.lowercased().hasPrefix(prefix) else { return full }
    return String(full.dropFirst(prefix.count))
  }

  mutating func edit(name: String) { self.name = name }

  /// A change to Pinned URL clears the invalid address line.
  mutating func edit(urlText: String) {
    self.urlText = urlText
    showsInvalidAddress = false
  }

  /// Use Current Page: Pinned URL becomes the tab's current address.
  mutating func useCurrentPage() {
    urlText = Self.text(for: currentPage)
    prefilled = (urlText, currentPage)
    showsInvalidAddress = false
  }

  /// Save or Return. Something that is not a web address shows the line and stores nothing.
  mutating func submit() -> Outcome {
    let url: URL
    if urlText == prefilled.text {
      url = prefilled.url
    } else if let parsed = URLInputParser.url(from: urlText) {
      url = parsed
    } else {
      showsInvalidAddress = true
      return .invalid
    }
    // An untouched name stays as it is, even when the page's title has spaces around it: only an edit becomes a
    // custom title, trimmed.
    let newName = name == originalName ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines)
    return .save(name: newName, url: url == originalURL ? nil : url)
  }
}

/// Punycode (RFC 3492) decoding for showing an internationalized host in Unicode. Encoding is Foundation's, when
/// `URLInputParser` builds the URL.
enum Punycode {
  private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

  /// `host` with each `xn--` label decoded; a label that does not decode stays as it is.
  static func unicodeHost(_ host: String) -> String {
    host.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
      guard label.lowercased().hasPrefix("xn--"), let decoded = decode(String(label.dropFirst(4))) else {
        return String(label)
      }
      return decoded
    }.joined(separator: ".")
  }

  /// The Unicode text of a Punycode label without its `xn--` prefix, nil when it is not valid Punycode.
  static func decode(_ input: String) -> String? {
    let scalars = Array(input.unicodeScalars)
    guard scalars.allSatisfy(\.isASCII) else { return nil }
    var output: [Unicode.Scalar] = []
    var start = 0
    if let delimiter = scalars.lastIndex(of: "-") {
      output = Array(scalars[..<delimiter])
      start = delimiter + 1
    }
    var n = initialN, i = 0, bias = initialBias, position = start
    while position < scalars.count {
      let oldI = i
      var w = 1
      var k = base
      while true {
        guard position < scalars.count, let digit = digit(scalars[position]) else { return nil }
        position += 1
        let (step, overflow1) = digit.multipliedReportingOverflow(by: w)
        let (sum, overflow2) = i.addingReportingOverflow(step)
        guard !overflow1, !overflow2 else { return nil }
        i = sum
        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
        if digit < t { break }
        let (product, overflow3) = w.multipliedReportingOverflow(by: base - t)
        guard !overflow3 else { return nil }
        w = product
        k += base
      }
      let count = output.count + 1
      bias = adapt(i - oldI, count: count, first: oldI == 0)
      n += i / count
      i %= count
      guard let scalar = Unicode.Scalar(n) else { return nil }
      output.insert(scalar, at: i)
      i += 1
    }
    var result = ""
    result.unicodeScalars.append(contentsOf: output)
    return result
  }

  private static func digit(_ scalar: Unicode.Scalar) -> Int? {
    switch scalar.value {
    case 0x30...0x39: Int(scalar.value) - 0x30 + 26
    case 0x41...0x5A: Int(scalar.value) - 0x41
    case 0x61...0x7A: Int(scalar.value) - 0x61
    default: nil
    }
  }

  private static func adapt(_ delta: Int, count: Int, first: Bool) -> Int {
    var delta = first ? delta / damp : delta / 2
    delta += delta / count
    var k = 0
    while delta > ((base - tMin) * tMax) / 2 {
      delta /= base - tMin
      k += base
    }
    return k + (base - tMin + 1) * delta / (delta + skew)
  }
}
