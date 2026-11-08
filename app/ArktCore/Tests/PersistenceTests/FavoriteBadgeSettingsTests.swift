import Foundation
import Testing
@testable import Persistence

/// The persisted preferences are independent of the window-local live page titles.
struct FavoriteBadgeSettingsTests {
  @Test func preferencesSurviveReopenAndReset() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let changed = FavoriteBadgePreferences(twitterBadgeEnabled: false, whatsAppBadgeEnabled: true)
      let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
      do {
        let database = try ArktDatabase.open(at: url)
        let store = SettingsStore(database: database)
        #expect(try await store.load(FavoriteBadgePreferences.self) == FavoriteBadgePreferences())
        try await store.save(changed, at: date)
        try database.close()
      }
      let reopened = try ArktDatabase.open(at: url)
      defer { try? reopened.close() }
      let store = SettingsStore(database: reopened)
      #expect(try await store.load(FavoriteBadgePreferences.self) == changed)
      let other = FavoriteBadgePreferences(twitterBadgeEnabled: true, whatsAppBadgeEnabled: false)
      try await store.save(other, at: date)
      #expect(try await store.load(FavoriteBadgePreferences.self) == other)
      try await store.save(FavoriteBadgePreferences(), at: date)
      #expect(try await store.load(FavoriteBadgePreferences.self) == FavoriteBadgePreferences())
    }
  }
}
