import CoreBridge
import Foundation
import SidebarModel
import Testing

// Proposed editor seam: CoreBridge owns the editing model; the store protocol is a pure Core value boundary.
@MainActor
struct LinkRoutingEditorTests {
  private static let space = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private static let otherSpace = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  private static let exact = "https://Example.test/Path/?q=One#Top"
  private static let first = LinkRouting.Route(condition: .contains("Example.test/Path"), destination: .space(space))
  private static let second = LinkRouting.Route(condition: .matches(exact), destination: .littleArkt)

  @Test func addEditRemovePreservesOrderAndLiteralText() async {
    let store = EditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.appendRoute(Self.first)
    model.appendRoute(Self.second)
    let edited = LinkRouting.Route(condition: .contains("?q=One#Top"), destination: .mostRecentSpace)
    model.replaceRoute(at: 0, with: edited)
    #expect(model.settings.routes == [edited, Self.second])
    await model.flush()
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings.routes == [edited, Self.second])
    reopened.removeRoute(at: 0)
    await reopened.flush()
    let afterRemoval = LinkRoutingSettingsModel(state: store)
    await afterRemoval.load()
    #expect(afterRemoval.settings.routes == [Self.second])
  }

  @Test func destinationsAndDefaultSurviveReopening() async {
    let store = EditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    #expect(model.settings == LinkRouting(routes: []))
    let routes: [LinkRouting.Route] = [Self.first, Self.second,
      .init(condition: .contains("/Other"), destination: .mostRecentSpace),
      .init(condition: .matches(Self.exact + "/"), destination: .space(Self.otherSpace))]
    for route in routes { model.appendRoute(route) }
    for destination in [LinkRouting.Destination.space(Self.otherSpace), .mostRecentSpace, .littleArkt] {
      model.setDefaultDestination(destination)
      await model.flush()
      let reopened = LinkRoutingSettingsModel(state: store)
      await reopened.load()
      #expect(reopened.settings == LinkRouting(routes: routes, defaultDestination: destination))
    }
  }

  @Test func competingRoutesRemainConfigurationWithoutChoosingWinner() async {
    let store = EditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.appendRoute(Self.first)
    model.appendRoute(Self.second)
    await model.flush()
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    let routing = reopened.settings
    #expect(routing.routes == [Self.first, Self.second])
    #expect(routing.resolution(for: URL(string: Self.exact)!) == .ambiguous([Self.first, Self.second]))
  }
}

// A value store for the editor contract, not an AppSession forwarding substitute.
private actor EditorStore: LinkRoutingSettingsStoring {
  private var value = LinkRouting(routes: [])
  func loadLinkRouting() async throws -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    change(&value)
    return value
  }
}
