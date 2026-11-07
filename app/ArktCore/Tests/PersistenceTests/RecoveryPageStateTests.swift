import Foundation
import Testing
@testable import Persistence

struct RecoveryPageStateTests {
  @Test func recordsSurviveDatabaseReopenAndCleanQuitClearing() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let source = UUID()
      let peek = RecoveryPageRecord(title: "Peek", url: URL(string: "https://example.invalid/peek")!,
                                    kind: .peek, sourceNode: source)
      let little = RecoveryPageRecord(title: "Window", url: URL(string: "https://example.invalid/little")!,
                                      kind: .littleArkt, sourceNode: nil)
      let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
      do {
        let database = try ArktDatabase.open(at: url)
        let settings = SettingsStore(database: database)
        try await settings.save(RecoveryPageState(pages: [peek, little]), at: date)
        try database.close()
      }
      do {
        let database = try ArktDatabase.open(at: url)
        let settings = SettingsStore(database: database)
        #expect(try await settings.load(RecoveryPageState.self).pages == [peek, little])
        try await settings.save(RecoveryPageState(pages: []), at: date.addingTimeInterval(1))
        try database.close()
      }
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      #expect(try await SettingsStore(database: database).load(RecoveryPageState.self).pages.isEmpty)
    }
  }
}
