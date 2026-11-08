import Foundation
import Persistence
import SidebarModel
import Testing

// The same pure Core protocol consumed by CoreBridge must be implemented by the real typed SQL store.
struct LinkRoutingEditorStoreTests {
  @Test func editorUpdatesUseTypedStoreAndSurviveDatabaseReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.sqlite")
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let space = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let first = LinkRouting.Route(condition: .contains("Example.test/Path"), destination: .space(space))
    let second = LinkRouting.Route(condition: .matches("https://Example.test/Path/?q=One#Top"), destination: .littleArkt)
    do {
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      let store: any LinkRoutingSettingsStoring = SettingsStore(database: database)
      #expect(try await store.loadLinkRouting() == LinkRouting(routes: []))
      _ = try await store.updateLinkRouting(at: date) { $0.routes.append(first) }
      _ = try await store.updateLinkRouting(at: date) { $0.routes.append(second); $0.defaultDestination = .mostRecentSpace }
      _ = try await store.updateLinkRouting(at: date) { $0.routes.append(first) }
    }
    do {
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      let store: any LinkRoutingSettingsStoring = SettingsStore(database: database)
      let loaded = try await store.loadLinkRouting()
      #expect(loaded == LinkRouting(routes: [first, second, first], defaultDestination: .mostRecentSpace))
      #expect(try await SettingsStore(database: database).load(LinkRouting.self) == loaded)
      #expect(loaded.resolution(for: URL(string: "https://Example.test/Path/?q=One#Top")!) == .ambiguous([first, second, first]))
      _ = try await store.updateLinkRouting(at: date) { $0.routes.removeFirst(); $0.defaultDestination = .space(space) }
    }
    let database = try ArktDatabase.open(at: url)
    defer { try? database.close() }
    let store: any LinkRoutingSettingsStoring = SettingsStore(database: database)
    #expect(try await store.loadLinkRouting() == LinkRouting(routes: [second, first], defaultDestination: .space(space)))
  }
}
