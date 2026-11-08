import CoreBridge
import Foundation
import SidebarModel
import Testing
@testable import ShellUI

@MainActor
struct SettingsReadinessReviewTests {
  @Test func duplicateSpaceTitlesHaveDistinctReadableDestinationsWithoutChangingIDs() {
    let first = UUID(), second = UUID(), third = UUID()
    let spaces = [(first, "Shared"), (second, "Shared"), (third, "Unique")].map { id, title in
      SettingsSpaceSummary(id: id, title: title, profile: "default", gradient: [], icon: nil, pinned: 0, today: 0)
    }
    let choices = SettingsLinkDestination.spaceChoices(spaces)
    #expect(choices.map(\.0) == ["Shared (Space 1)", "Shared (Space 2)", "Unique"])
    #expect(choices.map(\.1) == [.space(first), .space(second), .space(third)])
  }

  @Test func settingsInitializationDoesNotReloadAnAlreadyLoadedEditor() async throws {
    let store = CountingRoutingStore()
    let model = LinkRoutingSettingsModel(state: store)
    let rows = model.settingsRows
    await rows.load()
    await rows.load()
    let loads = await store.loadCount
    #expect(loads == 1, "rebuilding Settings rows must not start another read that blocks editing")
    let route = LinkRouting.Route(condition: .contains("literal"), destination: .littleArkt)
    model.appendRoute(route)
    #expect(await rows.flush())
    let saved = await store.snapshot()
    #expect(saved.routes == [route])
  }
}

private actor CountingRoutingStore: LinkRoutingSettingsStoring {
  private var value = LinkRouting(routes: [])
  private(set) var loadCount = 0
  func loadLinkRouting() async throws -> LinkRouting { loadCount += 1; return value }
  func snapshot() -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    change(&value)
    return value
  }
}
