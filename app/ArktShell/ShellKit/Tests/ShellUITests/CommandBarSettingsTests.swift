import Foundation
import Testing
@testable import ShellUI

@MainActor
struct CommandBarSettingsTests {
  private func suite() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "CommandBarSettingsTests.\(UUID().uuidString)"))
  }

  @Test func defaultsToSuggestionsOn() throws {
    #expect(CommandBarSettings(defaults: try suite()).searchSuggestionsEnabled)
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
    settings.setSearchSuggestionsEnabled(false)
    #expect(!settings.searchSuggestionsEnabled)
  }
}
