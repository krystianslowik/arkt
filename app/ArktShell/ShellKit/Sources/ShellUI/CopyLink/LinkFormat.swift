import Foundation

/// The text Copy URL as Markdown (KB-014) and Copy URL as Quote (KB-015) write.
enum LinkFormat {
  /// `[title](url)`. A bracket or backslash in the title is escaped and a parenthesis or space in the URL is
  /// percent-encoded, so a title like "Swift [beta]" or a Wikipedia URL ending in ")" still makes one link.
  static func markdown(title: String, url: String) -> String {
    var escapedTitle = ""
    for character in title {
      if "\\[]".contains(character) { escapedTitle.append("\\") }
      escapedTitle.append(character)
    }
    let escapedURL = url
      .replacingOccurrences(of: "(", with: "%28")
      .replacingOccurrences(of: ")", with: "%29")
      .replacingOccurrences(of: " ", with: "%20")
    return "[\(escapedTitle)](\(escapedURL))"
  }

  /// The Markdown link as a quote line: `> [title](url)`.
  static func quote(title: String, url: String) -> String {
    "> " + markdown(title: title, url: url)
  }
}
