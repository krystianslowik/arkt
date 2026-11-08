import ShellUI

import CoreBridge
import Foundation
import Persistence
import SidebarModel
import Testing

@MainActor
struct LinkRoutingTerminationSQLiteTests {
  @Test func blockingTerminationPersistsLatestSnapshotWithoutAnotherMainActorJob() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.sqlite")
    let route = LinkRouting.Route(condition: .contains("literal"), destination: .littleArkt)
    let other = LinkRouting.Route(condition: .matches("other"), destination: .mostRecentSpace)
    let expected = LinkRouting(routes: [route, other, route], defaultDestination: .mostRecentSpace)
    do {
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      let model = LinkRoutingSettingsModel(state: SettingsStore(database: database), flushTimeout: nil)
      await model.load()
      model.appendRoute(route)
      model.appendRoute(other)
      model.appendRoute(route)
      model.setDefaultDestination(.mostRecentSpace)
      #expect(model.needsFlush)
      #expect(model.flushBlocking())
      #expect(!model.needsFlush)
    }
    let reopened = try ArktDatabase.open(at: url)
    defer { try? reopened.close() }
    #expect(try await SettingsStore(database: reopened).loadLinkRouting() == expected)
  }

  @Test func removalPersistsThroughTypedSQLiteReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.sqlite")
    let id = UUID(), other = UUID()
    let removed = LinkRouting.Route(condition: .matches("deleted"), destination: .space(id))
    let kept = LinkRouting.Route(condition: .contains("kept"), destination: .space(other))
    let expected = LinkRouting(routes: [kept, kept], defaultDestination: .space(id))
    do {
      let database = try ArktDatabase.open(at: url)
      let model = LinkRoutingSettingsModel(state: SettingsStore(database: database), flushTimeout: nil)
      await model.load()
      for route in [removed, kept, removed, kept] { model.appendRoute(route) }
      model.setDefaultDestination(.space(id))
      #expect(await model.flush())
      model.removeRoutes(to: id)
      #expect(model.flushBlocking())
      try database.close()
    }
    let reopened = try ArktDatabase.open(at: url)
    defer { try? reopened.close() }
    #expect(try await SettingsStore(database: reopened).loadLinkRouting() == expected)
  }

  @Test func failedBlockingWriteKeepsDirtySnapshotAndError() async throws {
    let database = try ArktDatabase.inMemory()
    let model = LinkRoutingSettingsModel(state: SettingsStore(database: database), flushTimeout: nil)
    await model.load()
    model.setDefaultDestination(.mostRecentSpace)
    try database.close()
    #expect(!model.flushBlocking())
    #expect(model.needsFlush)
    #expect(model.lastError != nil)
  }

}

@MainActor
struct LinkRoutingSettingsAdapterTests {
  @Test func routesPreserveIdentityAndLiteralThroughAdapter() async throws {
    let database = try ArktDatabase.inMemory()
    defer { try? database.close() }
    let model = LinkRoutingSettingsModel(state: SettingsStore(database: database))
    await model.load()
    let rows = model.settingsRows
    let missing = UUID()
    let original = SettingsLinkRoute(condition: .contains("  Mixed/路径  "), destination: .space(missing))
    rows.appendRoute(original)
    rows.appendRoute(original)
    let edited = SettingsLinkRoute(condition: .matches("  Long/路径  "), destination: .space(missing))
    rows.replaceRoute(1, edited)
    #expect(rows.routes() == [original, edited])
    let saved = await rows.flush()
    #expect(saved)
    let stored = try await SettingsStore(database: database).loadLinkRouting()
    #expect(stored.routes == [.init(condition: .contains("  Mixed/路径  "), destination: .space(missing)),
                              .init(condition: .matches("  Long/路径  "), destination: .space(missing))])
  }
}
