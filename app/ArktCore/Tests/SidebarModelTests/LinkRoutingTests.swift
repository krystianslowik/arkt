import Foundation
import Testing
import SidebarModel

/// Air Traffic Control's settled matching and destination rules (#113, BH-155, BH-156).
struct LinkRoutingTests {
  private let url = URL(string: "https://example.com/docs")!
  private let space = SpaceID(uuidString: "00000000-0000-0000-0000-000000000001")!

  @Test func matchesRequiresAnEqualURL() {
    let route = LinkRouting.Route(condition: .matches("https://example.com/docs"), destination: .littleArkt)

    #expect(route.matches(url))
    #expect(!route.matches(URL(string: "https://example.com/docs/other")!))
  }

  @Test func containsMatchesTextWithinTheURL() {
    let route = LinkRouting.Route(condition: .contains("example.com"), destination: .littleArkt)

    #expect(route.matches(url))
    #expect(!route.matches(URL(string: "https://other.example/docs")!))
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
