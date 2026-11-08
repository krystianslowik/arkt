import Foundation
import Testing
@testable import ShellUI

@MainActor
struct CommandBarSettingsTests {
  private func suite() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "CommandBarSettingsTests.\(UUID().uuidString)"))
  }

  @Test func defaultsToSuggestionsOnAndNoticeNotDismissed() throws {
    let settings = CommandBarSettings(defaults: try suite())
    #expect(settings.searchSuggestionsEnabled)
    #expect(settings.searchSuggestionNoticeDismissed == false)
  }

  // BH-113: the notice stays dismissed across launches, under Arc's key.
  @Test func dismissalPersistsUnderArcsKey() throws {
    let defaults = try suite()
    CommandBarSettings(defaults: defaults).dismissSearchSuggestionNotice()
    #expect(defaults.bool(forKey: "commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed"))
    #expect(CommandBarSettings(defaults: defaults).searchSuggestionNoticeDismissed)
  }

  // The suggestions setting persists under Arc's key (`searchSuggestEnabled`, spec settings table).
  @Test func suggestionsTogglePersistsUnderArcsKey() throws {
    let defaults = try suite()
    CommandBarSettings(defaults: defaults).setSearchSuggestionsEnabled(false)
    #expect(defaults.object(forKey: "searchSuggestEnabled") as? Bool == false)
    #expect(CommandBarSettings(defaults: defaults).searchSuggestionsEnabled == false)
  }

  @Test func ephemeralKeepsValuesInMemoryOnly() {
    let settings = CommandBarSettings.ephemeral()
    #expect(settings.searchSuggestionsEnabled)
    #expect(settings.searchSuggestionNoticeDismissed == false)
    settings.dismissSearchSuggestionNotice()
    #expect(settings.searchSuggestionNoticeDismissed)
  }
}

@MainActor
struct CommandBarSettingsObservationTests {
  @Test func changesNotifyUntilObserverIsRemoved() {
    let settings = CommandBarSettings.ephemeral()
    var calls = 0
    let token = settings.observe { calls += 1 }
    settings.setSearchSuggestionsEnabled(false)
    settings.setSearchSuggestionsEnabled(false)
    settings.dismissSearchSuggestionNotice()
    settings.dismissSearchSuggestionNotice()
    #expect(calls == 2)
    settings.removeObserver(token)
    settings.setSearchSuggestionsEnabled(true)
    #expect(calls == 2)
  }
}

@MainActor
struct SearchEngineSettingsTests {
  @Test func defaultPersistenceAndNoOpNotification() throws {
    let name = "SearchEngineSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = CommandBarSettings(defaults: defaults)
    #expect(settings.searchEngine == .google)
    var calls = 0
    let token = settings.observe { calls += 1 }
    settings.setSearchEngine(.google)
    #expect(calls == 0)
    settings.setSearchEngine(.duckDuckGo)
    settings.setSearchEngine(.duckDuckGo)
    #expect(calls == 1)
    #expect(CommandBarSettings(defaults: defaults).searchEngine == .duckDuckGo)
    settings.resetSearchEngine()
    #expect(settings.searchEngine == .google)
    #expect(CommandBarSettings(defaults: defaults).searchEngine == .google)
    #expect(calls == 2)
    settings.resetSearchEngine()
    #expect(calls == 2)
    settings.removeObserver(token)
  }
}
