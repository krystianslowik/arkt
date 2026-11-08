import Foundation
import Testing
@testable import ShellUI

@MainActor
struct FavoriteBadgeSettingsTests {
  @Test func preferencesSurviveReopenAndRealReset() throws {
    let name = "dev.arkt.tests.badges.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let original = settings.favoriteBadges
    let changed = FavoriteBadgePreferences(twitterBadgeEnabled: !original.twitterBadgeEnabled,
                                           whatsAppBadgeEnabled: !original.whatsAppBadgeEnabled)
    let inverse = FavoriteBadgePreferences(twitterBadgeEnabled: original.twitterBadgeEnabled,
                                           whatsAppBadgeEnabled: !original.whatsAppBadgeEnabled)
    settings.favoriteBadges = changed
    let reopened = AppSettings(defaults: defaults)
    #expect(reopened.favoriteBadges == changed)
    reopened.favoriteBadges = inverse
    #expect(AppSettings(defaults: defaults).favoriteBadges == inverse)
    reopened.resetToDefaults()
    #expect(reopened.favoriteBadges == original)
    #expect(AppSettings(defaults: defaults).favoriteBadges == original)
  }
}
