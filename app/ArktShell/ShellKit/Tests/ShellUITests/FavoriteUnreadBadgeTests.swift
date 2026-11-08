import Foundation
import Testing
@testable import ShellUI

/// Synthetic title-count contracts, not claims about any site's current title format (#338).
@MainActor
struct FavoriteUnreadBadgeTests {
  private func badge(_ address: String, _ title: String, twitter: Bool = true, whatsApp: Bool = true) -> String? {
    FavoriteUnreadBadge.text(url: URL(string: address)!, pageTitle: title,
                             twitterBadgeEnabled: twitter, whatsAppBadgeEnabled: whatsApp)
  }

  @Test func supportedHostsUseThePageTitleCount() {
    for address in ["https://app.slack.com/", "https://x.com/", "https://twitter.com/",
                    "https://calendar.google.com/", "https://mail.google.com/", "https://web.whatsapp.com/"] {
      #expect(badge(address, "(1) Inbox") == "1")
      #expect(badge(address, "(42) Inbox") == "42")
    }
  }

  @Test func countDisappearingClearsTheBadge() {
    let address = "https://mail.google.com/"
    let titles = ["(1) Inbox", "Inbox", "(0) Inbox", "", "(2) Inbox"]
    #expect(titles.map { badge(address, $0) } == ["1", nil, nil, nil, "2"])
  }

  @Test func malformedCountsAndLookalikeHostsDoNotShowBadges() {
    for title in ["(-1) Inbox", "(1x) Inbox", "() Inbox", "(1.5) Inbox", "(999999999999999999999999999999) Inbox"] {
      #expect(badge("https://mail.google.com/", title) == nil)
    }
    for address in ["https://mail.google.com.example.org/", "https://notx.com/",
                    "https://slack.com.example.org/", "https://web.whatsapp.com.example.org/"] {
      #expect(badge(address, "(1) Inbox") == nil)
    }
  }

  @Test func displayCapsLargeCountsAt99Plus() {
    let address = "https://mail.google.com/"
    #expect(badge(address, "(99) Inbox") == "99")
    #expect(badge(address, "(100) Inbox") == "99+")
    #expect(badge(address, "(9999) Inbox") == "99+")
  }

  @Test func settingsGateOnlyTheirOwnServices() {
    #expect(badge("https://x.com/", "(1) Inbox", twitter: false) == nil)
    #expect(badge("https://twitter.com/", "(1) Inbox", twitter: false) == nil)
    #expect(badge("https://web.whatsapp.com/", "(1) Inbox", whatsApp: false) == nil)
    #expect(badge("https://x.com/", "(1) Inbox", whatsApp: false) == "1")
    #expect(badge("https://web.whatsapp.com/", "(1) Inbox", twitter: false) == "1")
    #expect(badge("https://mail.google.com/", "(1) Inbox", twitter: false, whatsApp: false) == "1")
  }

  @Test func hostsAreCaseInsensitiveButMustMatchExactly() {
    #expect(badge("https://MAIL.GOOGLE.COM/", "(1) Inbox") == "1")
    for address in ["https://slack.com/", "https://team.slack.com/", "https://foo.x.com/",
                    "https://whatsapp.com/", "https://sub.mail.google.com/", "https://x.com.example.org/"] {
      #expect(badge(address, "(1) Inbox") == nil)
    }
  }

  @Test func onlyWellFormedLeadingAsciiCountsAreAccepted() {
    let address = "https://mail.google.com/"
    for title in ["Inbox (1)", " (1) Inbox", "(1 Inbox", "(+1) Inbox", "(１) Inbox", "(1 2) Inbox"] {
      #expect(badge(address, title) == nil)
    }
    #expect(badge(address, "(01) Inbox") == "1")
    #expect(badge(address, "(9223372036854775807) Inbox") == "99+")
    #expect(badge(address, "(9223372036854775808) Inbox") == nil)
  }

}
