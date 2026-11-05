import Foundation

/// The link to selected text that Copy URL offers (BH-193, #404): the page's URL with a text directive
/// (`#:~:text=`, the URL Fragment Text Directives spec), which Chromium and Safari scroll to and highlight. Arc's
/// generator is unpublished ([S] gives the offer string only), so the shape is ours: a selection of up to
/// `wholeWordLimit` words is quoted whole; a longer one becomes `text=start,end` from its first and last
/// `rangeWords` words, which keeps the link short and still finds the passage.
public enum TextFragment {
  /// Selections with at most this many words are quoted whole.
  public static let wholeWordLimit = 8
  /// Words taken from each end of a longer selection.
  public static let rangeWords = 4

  /// `url` with a text directive for `text`; nil for blank text or a URL that is not http(s). The URL's own
  /// fragment stays; an existing directive is replaced.
  public static func link(to text: String, in url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return nil }
    let directive: String
    if words.count <= wholeWordLimit {
      directive = encode(words.joined(separator: " "))
    } else {
      let start = words.prefix(rangeWords).joined(separator: " ")
      let end = words.suffix(rangeWords).joined(separator: " ")
      directive = encode(start) + "," + encode(end)
    }
    var base = url.absoluteString
    var fragment = ""
    if let hash = base.firstIndex(of: "#") {
      fragment = String(base[base.index(after: hash)...])
      base = String(base[..<hash])
      if let marker = fragment.range(of: ":~:") { fragment = String(fragment[..<marker.lowerBound]) }
    }
    return URL(string: base + "#" + fragment + ":~:text=" + directive)
  }

  /// A fragment-safe term: the directive's separators (`-`, `,`, `&`) and the percent sign are encoded, as the spec
  /// requires, along with everything a fragment may not hold.
  static func encode(_ term: String) -> String {
    term.addingPercentEncoding(withAllowedCharacters: allowed) ?? term
  }

  private static let allowed: CharacterSet = {
    var set = CharacterSet.urlFragmentAllowed
    set.remove(charactersIn: "-,&%#")
    return set
  }()
}
