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
