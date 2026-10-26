import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// Which links open a Peek (docs/design/peek.md, "When a Peek opens"; BH-144, BH-145, BH-146, BH-056).
struct PeekRoutingTests {
  static let mail = URL(string: "https://mail.example.com/inbox")!
  static let atlas = URL(string: "https://atlas.example/lisbon")!
  static let mailOther = URL(string: "https://docs.example.com/page")!

  static func link(_ url: URL, from source: URL? = mail, modifiers: EngineLinkModifiers = [],
                   disposition: EngineDisposition = .currentTab) -> EngineLinkActivation {
    EngineLinkActivation(url: url, sourceTab: TabID(), sourceURL: source, modifiers: modifiers,
                         disposition: disposition)
  }

  @Test(arguments: [PeekSourceSection.pinned, .favorites])
  func aCrossSiteLinkInAPinnedTabOrFavoriteOpensAPeek(section: PeekSourceSection) {
    #expect(PeekRouting.route(Self.link(Self.atlas), section: section) == .peek)
  }

  @Test(arguments: [PeekSourceSection.pinned, .favorites])
  func aSameSiteLinkNavigatesInPlace(section: PeekSourceSection) {
    #expect(PeekRouting.route(Self.link(Self.mailOther), section: section) == .navigate)
  }

  @Test func aTodayTabLinkWithoutModifiersNavigates() {
    #expect(PeekRouting.route(Self.link(Self.atlas), section: .today) == .navigate)
  }

  @Test(arguments: [PeekSourceSection.pinned, .favorites, .today, .other])
  func aShiftClickOpensAPeekAnywhere(section: PeekSourceSection) {
    let shift = Self.link(Self.mailOther, modifiers: .shift, disposition: .newWindow)
    #expect(PeekRouting.route(shift, section: section) == .peek)
  }

  @Test func aCommandClickIsLeftToTheEngine() {
    let command = Self.link(Self.atlas, modifiers: .command, disposition: .newBackgroundTab)
    #expect(PeekRouting.route(command, section: .pinned) == .navigate)
  }

  @Test(arguments: [
    "https://meet.google.com/abc-defg-hij",
    "https://us02web.zoom.us/j/123456789",
    "https://teams.microsoft.com/l/meetup-join/19%3ameeting",
  ])
  func aMeetingLinkInAPinnedTabOpensATodayTab(link: String) throws {
    let url = try #require(URL(string: link))
    #expect(PeekRouting.route(Self.link(url), section: .pinned) == .newTab)
  }

  @Test func theCrossSiteSettingOffNavigates() {
    let settings = PeekLinkSettings(opensCrossSiteLinks: false, opensShiftClickedLinks: true)
    #expect(PeekRouting.route(Self.link(Self.atlas), section: .pinned, settings: settings) == .navigate)
  }

  @Test func theShiftSettingOffLeavesShiftClicksToTheEngine() {
    let settings = PeekLinkSettings(opensCrossSiteLinks: true, opensShiftClickedLinks: false)
    let shift = Self.link(Self.atlas, modifiers: .shift, disposition: .newWindow)
    #expect(PeekRouting.route(shift, section: .today, settings: settings) == .navigate)
  }

  @Test func linksInsideAPeekNavigateThePeekAndShiftOpensATodayTab() {
    #expect(PeekRouting.route(Self.link(Self.atlas), section: .peek) == .navigate)
    #expect(PeekRouting.route(Self.link(Self.atlas, modifiers: .shift, disposition: .newWindow), section: .peek)
      == .newTab)
  }

  @Test(arguments: [
    ("https://a.example.com/x", "https://b.example.com/y", true),
    ("https://example.com", "https://www.example.com", true),
    ("https://shop.example.co.uk", "https://news.example.co.uk", true),
    ("https://one.co.uk", "https://two.co.uk", false),
    ("https://example.com", "https://example.org", false),
    ("http://127.0.0.1:8001/a", "http://localhost:8001/b", false),
    ("http://127.0.0.1:8001/a", "http://127.0.0.1:9000/b", true),
  ])
  func sameSiteComparesRegistrableDomains(a: String, b: String, same: Bool) throws {
    #expect(PeekRouting.isSameSite(try #require(URL(string: a)), try #require(URL(string: b))) == same)
  }

  @Test func aSourceWithoutAURLCountsAsCrossSite() {
    #expect(PeekRouting.route(Self.link(Self.atlas, from: nil), section: .pinned) == .peek)
  }

  // MARK: Tabs the engine opened (#345: target=_blank, window.open without features)

  @Test(arguments: [PeekSourceSection.pinned, .favorites])
  func aForegroundTabToAnotherSiteOpenedByAPinnedTabOrFavoriteBecomesAPeek(section: PeekSourceSection) {
    #expect(PeekRouting.routeOpenedTab(url: Self.atlas, openerURL: Self.mail, section: section, isActive: true)
      == .peek)
  }

  @Test(arguments: [PeekSourceSection.today, .peek, .other])
  func aTabOpenedByAnyOtherTabStaysTheEnginesTab(section: PeekSourceSection) {
    #expect(PeekRouting.routeOpenedTab(url: Self.atlas, openerURL: Self.mail, section: section, isActive: true)
      == .navigate)
  }

  @Test func aSameSiteTabABackgroundTabAndAMeetingLinkStayTheEnginesTab() throws {
    #expect(PeekRouting.routeOpenedTab(url: Self.mailOther, openerURL: Self.mail, section: .pinned, isActive: true)
      == .navigate)
    #expect(PeekRouting.routeOpenedTab(url: Self.atlas, openerURL: Self.mail, section: .pinned, isActive: false)
      == .navigate, "a Command-click opens in the background (BH-144: the engine's)")
    let meeting = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
    #expect(PeekRouting.routeOpenedTab(url: meeting, openerURL: Self.mail, section: .pinned, isActive: true)
      == .navigate, "a meeting link is a Today tab (BH-146), which the engine's tab already is")
  }

  @Test func aTabWithoutAWebURLYetStaysTheEnginesTab() throws {
    #expect(PeekRouting.routeOpenedTab(url: nil, openerURL: Self.mail, section: .pinned, isActive: true)
      == .navigate)
    let blank = try #require(URL(string: "about:blank"))
    #expect(PeekRouting.routeOpenedTab(url: blank, openerURL: Self.mail, section: .pinned, isActive: true)
      == .navigate)
  }

  @Test func theCrossSiteSettingOffLeavesOpenedTabsToTheEngine() {
    let settings = PeekLinkSettings(opensCrossSiteLinks: false, opensShiftClickedLinks: true)
    #expect(PeekRouting.routeOpenedTab(url: Self.atlas, openerURL: Self.mail, section: .pinned, isActive: true,
                                       settings: settings) == .navigate)
  }
}
