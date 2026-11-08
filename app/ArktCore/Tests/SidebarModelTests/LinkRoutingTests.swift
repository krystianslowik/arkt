import Foundation
import Testing
import SidebarModel

/// Air Traffic Control's settled matching and destination rules (#113, BH-155, BH-156).
struct LinkRoutingTests {
  private let url = URL(string: "https://example.com/docs")!
  private let space = SpaceID(uuidString: "00000000-0000-0000-0000-000000000001")!

  @Test func matchesRequiresAnEqualURL() {
    let route = LinkRouting.Route(condition: .matches("https://example.com/docs"), destination: .littleArkt)

    #expect(route.applies(to: url))
    #expect(!route.applies(to: URL(string: "https://example.com/docs/other")!))
  }

  @Test func containsMatchesTextWithinTheURL() {
    let route = LinkRouting.Route(condition: .contains("example.com"), destination: .littleArkt)

    #expect(route.applies(to: url))
    #expect(!route.applies(to: URL(string: "https://other.example/docs")!))
  }

  @Test func equalityDoesNotNormalizeCaseSlashQueryOrFragment() {
    let route = LinkRouting.Route(condition: .matches("https://example.com/docs"), destination: .littleArkt)

    for text in [
      "https://Example.com/docs", "https://example.com/docs/",
      "https://example.com/docs?q=1", "https://example.com/docs#top",
    ] {
      #expect(!route.applies(to: URL(string: text)!))
    }
  }

  @Test func containsIsCaseInsensitiveAcrossURLText() {
    let url = URL(string: "https://EXAMPLE.com/Docs?Token=One#Top")!
    for text in ["example.COM", "/dOCS", "?TOKEN=oNE", "#tOP"] {
      #expect(LinkRouting.Condition.contains(text).applies(to: url))
    }
    #expect(!LinkRouting.Condition.contains("/other").applies(to: url))
  }

  @Test func containsPreservesEmptyLiteralMatching() {
    #expect(LinkRouting.Condition.contains("").applies(to: url))
  }

  @Test func unmatchedLinkCanDefaultToMostRecentSpace() {
    let routing = LinkRouting(routes: [], defaultDestination: .mostRecentSpace)

    #expect(routing.destination(for: url) == .mostRecentSpace)
  }

  @Test func matchingRouteResolvesToItsSpace() {
    let route = LinkRouting.Route(condition: .contains("example.com"), destination: .space(space))
    let routing = LinkRouting(routes: [route])

    #expect(routing.destination(for: url) == .space(space))
  }

  @Test func matchingRouteCanResolveToMostRecentSpace() {
    let route = LinkRouting.Route(condition: .matches("https://example.com/docs"), destination: .mostRecentSpace)
    let routing = LinkRouting(routes: [route])

    #expect(routing.destination(for: url) == .mostRecentSpace)
  }

  @Test func unmatchedLinkDefaultsToLittleArkt() {
    let route = LinkRouting.Route(condition: .contains("other.example"), destination: .space(space))
    let routing = LinkRouting(routes: [route])

    #expect(routing.destination(for: url) == .littleArkt)
  }

  @Test func unmatchedLinkUsesTheConfiguredDefault() {
    let routing = LinkRouting(routes: [], defaultDestination: .space(space))

    #expect(routing.destination(for: url) == .space(space))
  }

  @Test func nonmatchingRulesDoNotHideTheOnlyMatch() {
    let match = LinkRouting.Route(condition: .contains("example.com"), destination: .space(space))
    let other = LinkRouting.Route(condition: .contains("other.example"), destination: .mostRecentSpace)

    #expect(LinkRouting(routes: [other, match]).destination(for: url) == .space(space))
    #expect(LinkRouting(routes: [match, other]).destination(for: url) == .space(space))
  }
}

extension LinkRoutingTests {
  @Test func firstMatchingRouteWinsOverLaterMoreSpecificRoute() {
    let first = LinkRouting.Route(condition: .contains("example"), destination: .space(space))
    let second = LinkRouting.Route(condition: .matches(url.absoluteString), destination: .mostRecentSpace)
    let nonmatch = LinkRouting.Route(condition: .contains("elsewhere"), destination: .littleArkt)
    let routing = LinkRouting(routes: [nonmatch, first, second])

    #expect(routing.matchingRoutes(for: url) == [first, second])
    #expect(routing.resolution(for: url) == .destination(first.destination))
    #expect(routing.destination(for: url) == first.destination)
    #expect(LinkRouting(routes: [second, first]).destination(for: url) == second.destination)
  }

  @Test func multipleMatchesWithSameDestinationResolveUniquely() {
    let first = LinkRouting.Route(condition: .contains("example"), destination: .space(space))
    let second = LinkRouting.Route(condition: .contains("example.com"), destination: .space(space))
    let routing = LinkRouting(routes: [first, second])

    #expect(routing.matchingRoutes(for: url) == [first, second])
    #expect(routing.destination(for: url) == .space(space))
  }
}
