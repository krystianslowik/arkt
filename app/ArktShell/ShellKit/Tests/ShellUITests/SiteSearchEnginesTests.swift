import Foundation
import Testing
@testable import ShellUI

struct SiteSearchEnginesTests {
  let engine = SiteSearchEngine(alias: "yt", name: "YouTube",
                                searchURLTemplate: "https://www.youtube.com/results?search_query=%s")

  @Test func buildsTheSearchURLWithAnEncodedQuery() {
    #expect(engine.url(for: "lofi beats")?.absoluteString
            == "https://www.youtube.com/results?search_query=lofi%20beats")
  }

  @Test func encodesQueryPunctuation() {
    #expect(engine.url(for: "a&b=c")?.absoluteString
            == "https://www.youtube.com/results?search_query=a%26b%3Dc")
  }

  // KB-082: the alias is typed, then Tab scopes; a partial or longer token is not an alias.
  @Test func aliasMatchingIsExactAndCaseInsensitive() {
    let engines = SiteSearchEngines.seeded
    #expect(SiteSearchEngines.engine(aliased: "yt", in: engines)?.name == "YouTube")
    #expect(SiteSearchEngines.engine(aliased: "YT", in: engines)?.name == "YouTube")
    #expect(SiteSearchEngines.engine(aliased: "y", in: engines) == nil)
    #expect(SiteSearchEngines.engine(aliased: "yt2", in: engines) == nil)
  }

  // BH-107: popular site searches are seeded on first run (Arc's `seededPopularSiteSearches`).
  @Test func seedsPopularEnginesWithUniqueAliasesAndValidTemplates() {
    let seeded = SiteSearchEngines.seeded
    #expect(seeded.count >= 3)
    #expect(Set(seeded.map(\.alias)).count == seeded.count)
    for engine in seeded {
      #expect(engine.searchURLTemplate.contains("%s"))
      #expect(engine.url(for: "test") != nil)
    }
  }
}
