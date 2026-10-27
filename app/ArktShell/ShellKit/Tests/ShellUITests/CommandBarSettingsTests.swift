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
