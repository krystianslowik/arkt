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
    reopened.favoriteBadges = changed
    #expect(AppSettings(defaults: defaults).favoriteBadges == changed)
    reopened.resetToDefaults()
    #expect(reopened.favoriteBadges == original)
    #expect(AppSettings(defaults: defaults).favoriteBadges == original)
  }

  @Test func changesAndResetNotifyObservers() throws {
    let name = "dev.arkt.tests.badges.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let original = settings.favoriteBadges
    let observer = Recorder()
    settings.addObserver(observer)

    settings.favoriteBadges.twitterBadgeEnabled.toggle()
    #expect(observer.values == [settings.favoriteBadges])
    #expect(settings.favoriteBadges.whatsAppBadgeEnabled == original.whatsAppBadgeEnabled)
    settings.favoriteBadges.whatsAppBadgeEnabled.toggle()
    #expect(observer.values.count == 2)
    settings.favoriteBadges = settings.favoriteBadges
    #expect(observer.values.count == 2)
    settings.resetToDefaults()
    #expect(observer.values.count == 3)
    #expect(observer.values.last == original)
    #expect(defaults.object(forKey: AppSettings.Key.twitterBadgeEnabled) == nil)
    #expect(defaults.object(forKey: AppSettings.Key.whatsAppBadgeEnabled) == nil)
  }

  private final class Recorder: AppSettingsObserver {
    var values: [FavoriteBadgePreferences] = []
    func appSettingsDidChange(_ settings: AppSettings) { values.append(settings.favoriteBadges) }
  }
}
