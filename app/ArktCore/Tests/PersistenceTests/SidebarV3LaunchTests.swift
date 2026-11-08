import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct SidebarV3LaunchTests {
  @Test func frozenV3SnapshotSurvivesLaunchSaveAndReopen() async throws {
    // This frozen document predates node icons; its version is the sidebar format, not the SQL schema version.
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("SidebarModelTests/Fixtures/sidebar-v3.json")
    let body = try Data(contentsOf: fixture)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("arkt-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      let location = DatabaseLocation(directory: directory)
      do {
        let queue = try DatabaseQueue(path: location.databaseURL.path)
        defer { try? queue.close() }
        try ArktDatabase.migrator.migrate(queue)
        try await queue.write { db in
          try db.execute(
            sql: "INSERT INTO sidebar_snapshot (id, format_version, saved_at, sha256, body) VALUES (1, 3, 0, ?, ?)",
            arguments: [SidebarStore.sha256(body), body])
        }
      }
      let state = try await ArktLaunch.openAndLoad(location, now: Date(timeIntervalSinceReferenceDate: 800_000_000))
      defer { try? state.database.close() }
      #expect(state.outcome == .opened)
      let sidebar = try #require(state.sidebar)
      let alpha = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
      let folder = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000101"))
      let tab = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000102"))
      #expect(sidebar.nodes.count == 7)
      #expect(sidebar.nodes.values.allSatisfy { $0.customIcon == nil })
      #expect(sidebar.spaces[alpha]?.title == "Alpha")
      #expect(sidebar.spaces[alpha]?.icon == .symbol("star"))
      #expect(sidebar.spaces[alpha]?.theme?.opacity == 0.8)
      #expect(sidebar.children(of: .folder(folder)) == [tab])
      #expect(sidebar.nodes[tab]?.kind == .tab(TabItem(
        url: URL(string: "https://example.com/a")!, title: "A", customTitle: "Renamed A")))
      #expect(sidebar.nodes[tab]?.createdAt == Date(timeIntervalSinceReferenceDate: 783_000_001.5))

      // Launch only loads; the normal store save writes the current format when a sidebar is saved.
      let saveDate = Date(timeIntervalSinceReferenceDate: 800_000_001)
      #expect(try await SidebarStore(database: state.database).save(sidebar, at: saveDate) == .written)
      let stored = try await state.database.writer.read { try SidebarStore.fetchStored($0) }
      let saved = try #require(stored)
      #expect(saved.formatVersion == 4)
      let savedBody = try #require(saved.body)
      let json = try #require(try JSONSerialization.jsonObject(with: savedBody) as? [String: Any])
      #expect(json["version"] as? Int == 4)
      var expected = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
      expected["version"] = 4
      #expect((json as NSDictionary) == (expected as NSDictionary))
      try state.database.close()
      let reopened = try await ArktLaunch.openAndLoad(location, now: Date(timeIntervalSinceReferenceDate: 800_000_002))
      defer { try? reopened.database.close() }
      #expect(reopened.outcome == .opened)
      #expect(reopened.sidebar == sidebar)
    }
  }
}
