import Archive
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct LinkRoutingSettingsTests {
  static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static let space = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  static let url = URL(string: "https://Example.com/Path?q=One#Top")!
  static let routes: [LinkRouting.Route] = [
    .init(condition: .contains("Example.com/Path"), destination: .space(space)),
    .init(condition: .matches("https://Example.com/Path?q=One#Top"), destination: .littleArkt),
    .init(condition: .contains("?q=One#Top"), destination: .mostRecentSpace),
  ]

  @Test func missingLegacyGroupUsesLittleArktAndKeepsOtherSettings() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let other = ArchiveState(educationBannerDismissed: true)
    try await store.save(other, at: Self.date)
    #expect(try await store.load(LinkRouting.self) == LinkRouting(routes: []))
    #expect(try await store.load(ArchiveState.self) == other)
  }

  @Test func roundTripPreservesTextOrderAndFirstMatchingDestination() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    for destination in [LinkRouting.Destination.littleArkt, .mostRecentSpace, .space(Self.space)] {
      let routing = LinkRouting(routes: Self.routes, defaultDestination: destination)
      try await store.save(routing, at: Self.date)
      let loaded = try await store.load(LinkRouting.self)
      #expect(loaded == routing)
      #expect(loaded.matchingRoutes(for: Self.url) == Self.routes)
      #expect(loaded.resolution(for: Self.url) == .destination(Self.routes[0].destination))
      #expect(loaded.destination(for: Self.url) == Self.routes[0].destination)
      #expect(loaded.matchingRoutes(for: URL(string: "https://example.com/path?q=one#top")!) == [Self.routes[0], Self.routes[2]])
    }
  }

  @Test func replacementAndRemovalSurviveReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.sqlite")
    let other = ArchiveState(educationBannerDismissed: true)
    do {
      let database = try ArktDatabase.open(at: url)
      let store = SettingsStore(database: database)
      try await store.save(other, at: Self.date)
      try await store.save(LinkRouting(routes: Self.routes), at: Self.date)
      try await store.save(LinkRouting(routes: [Self.routes[2]], defaultDestination: .space(Self.space)), at: Self.date)
      try database.close()
    }
    do {
      let database = try ArktDatabase.open(at: url)
      let store = SettingsStore(database: database)
      #expect(try await store.load(LinkRouting.self) == LinkRouting(routes: [Self.routes[2]], defaultDestination: .space(Self.space)))
      try await store.save(LinkRouting(routes: [], defaultDestination: .mostRecentSpace), at: Self.date)
      try database.close()
    }
    let database = try ArktDatabase.open(at: url)
    defer { try? database.close() }
    let store = SettingsStore(database: database)
    #expect(try await store.load(LinkRouting.self) == LinkRouting(routes: [], defaultDestination: .mostRecentSpace))
    #expect(try await store.load(ArchiveState.self) == other)
  }

  @Test func unreadableGroupDefaultsUntilExplicitReplacement() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SettingsStore(database: database)
    let other = ArchiveState(educationBannerDismissed: true)
    try await store.save(other, at: Self.date)
    try await database.writer.write { db in
      try db.execute(sql: "INSERT INTO setting (key, value, updated_at) VALUES (?, ?, 0)",
                     arguments: [LinkRouting.storageKey, Data("not json".utf8)])
    }
    #expect(try await store.load(LinkRouting.self) == LinkRouting(routes: []))
    let replacement = LinkRouting(routes: Self.routes, defaultDestination: .mostRecentSpace)
    try await store.save(replacement, at: Self.date)
    #expect(try await store.load(LinkRouting.self) == replacement)
    #expect(try await store.load(ArchiveState.self) == other)
  }
}
