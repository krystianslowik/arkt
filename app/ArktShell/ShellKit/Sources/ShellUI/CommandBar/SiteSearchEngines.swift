import Foundation

/// A site-search engine the command bar scopes a query to (BH-107, KB-082): type the alias, press Tab, and the
/// rest of the query goes to that engine's search URL. Tab is the only trigger; Arc's Space trigger is behind
/// flags (`migratedToTabOnlySiteSearchTrigger`).
public struct SiteSearchEngine: Sendable, Equatable {
  /// The token that scopes the query ("yt").
  public let alias: String
  /// Display name ("YouTube"), shown in the scope chip and the result's subtitle.
  public let name: String
  /// The search URL with `%s` where the encoded query goes (Chromium's keyword URL convention).
  public let searchURLTemplate: String

  public init(alias: String, name: String, searchURLTemplate: String) {
    self.alias = alias
    self.name = name
    self.searchURLTemplate = searchURLTemplate
  }

  /// The engine's search URL for `query`; nil when the encoding or the template makes no URL.
  public func url(for query: String) -> URL? {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=")
    guard let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
    return URL(string: searchURLTemplate.replacingOccurrences(of: "%s", with: escaped))
  }
}

public enum SiteSearchEngines {
  /// BH-107: popular site searches seeded on first run (Arc's `seededPopularSiteSearches`). Real engines
  /// (Chromium's keyword store) replace this list behind the same type later.
  public static let seeded: [SiteSearchEngine] = [
    SiteSearchEngine(alias: "yt", name: "YouTube",
                     searchURLTemplate: "https://www.youtube.com/results?search_query=%s"),
    SiteSearchEngine(alias: "wiki", name: "Wikipedia",
                     searchURLTemplate: "https://en.wikipedia.org/w/index.php?search=%s"),
    SiteSearchEngine(alias: "gh", name: "GitHub",
                     searchURLTemplate: "https://github.com/search?q=%s"),
    SiteSearchEngine(alias: "so", name: "Stack Overflow",
                     searchURLTemplate: "https://stackoverflow.com/search?q=%s"),
  ]

  /// The engine `text` names exactly, case-insensitively; nil for a partial or unknown alias.
  public static func engine(aliased text: String, in engines: [SiteSearchEngine]) -> SiteSearchEngine? {
    engines.first { $0.alias.caseInsensitiveCompare(text) == .orderedSame }
  }

  /// The engine a typed alias or site name offers a Tab-scoped row for: the alias exactly, or a name that starts with
  /// the text (two letters at least, so "g" does not offer GitHub). Case-insensitive; the first match in list order.
  public static func engine(matching text: String, in engines: [SiteSearchEngine]) -> SiteSearchEngine? {
    if let exact = engine(aliased: text, in: engines) { return exact }
    guard text.count >= 2 else { return nil }
    return engines.first { $0.name.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }
  }
}
