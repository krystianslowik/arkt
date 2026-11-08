import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// The Settings adapter must share its editor; these tests do not substitute for AppSession composition or UI tests.
@MainActor
struct LinkRoutingSettingsRowsTests {
  private let firstSpace = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let secondSpace = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  private let route = LinkRouting.Route(condition: .contains("literal/Path"), destination: .littleArkt)

  @Test func twoConsumersKeepEditsAndOrderedDuplicatesAcrossReopen() async {
    let store = RoutingRowsStore(initial: LinkRouting(routes: [route, route]))
    let model = LinkRoutingSettingsModel(state: store)
    let first = model.settingsRows
    let second = model.settingsRows
    await first.load()
    #expect(first.destination() == .littleArkt)
    first.setDestination(.space(firstSpace))
    #expect(await first.flush())
    #expect(second.destination() == .space(firstSpace))
    second.setDestination(.space(secondSpace))
    #expect(await second.flush())
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings == LinkRouting(routes: [route, route], defaultDestination: .space(secondSpace)))
  }

  @Test func allDestinationsRoundTripWithoutTitleIdentity() async {
    let store = RoutingRowsStore(initial: LinkRouting(routes: [route, route]))
    let model = LinkRoutingSettingsModel(state: store)
    let rows = model.settingsRows
    await rows.load()
    for destination in [SettingsLinkDestination.mostRecentSpace, .space(firstSpace), .space(secondSpace), .littleArkt] {
      rows.setDestination(destination)
      #expect(await rows.flush())
      let reopened = LinkRoutingSettingsModel(state: store)
      await reopened.load()
      #expect(reopened.settingsRows.destination() == destination)
      #expect(reopened.settings.routes == [route, route])
    }
  }

  @Test func concurrentConsumersWaitForTheSameLoad() async {
    let stored = LinkRouting(routes: [route], defaultDestination: .space(firstSpace))
    let store = PausedRoutingRowsStore(initial: stored)
    let model = LinkRoutingSettingsModel(state: store)
    let first = model.settingsRows
    let second = model.settingsRows
    let firstLoad = Task { await first.load() }
    await store.waitForLoad()
    let secondLoad = Task { await second.load() }
    #expect(second.destination() == nil)
    await store.resume()
    await firstLoad.value
    await secondLoad.value
    #expect(first.destination() == .space(firstSpace))
    #expect(second.destination() == .space(firstSpace))
  }

  @Test func failedLoadCannotWriteDefaultAndCanRetry() async {
    let stored = LinkRouting(routes: [route, route], defaultDestination: .space(secondSpace))
    let store = RoutingRowsStore(initial: stored, failLoad: true)
    let model = LinkRoutingSettingsModel(state: store)
    let rows = model.settingsRows
    await rows.load()
    #expect(rows.destination() == nil)
    #expect(rows.hasLoadError())
    rows.setDestination(.littleArkt)
    #expect(await rows.flush() == false)
    #expect(await store.value == stored)
    await rows.load()
    #expect(!rows.hasLoadError())
    #expect(rows.destination() == .space(secondSpace))
  }
}

private actor RoutingRowsStore: LinkRoutingSettingsStoring {
  enum Failure: Error { case read }
  private(set) var value: LinkRouting
  private var failLoad: Bool
  init(initial: LinkRouting, failLoad: Bool = false) { value = initial; self.failLoad = failLoad }
  func loadLinkRouting() async throws -> LinkRouting {
    if failLoad { failLoad = false; throw Failure.read }
    return value
  }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    change(&value)
    return value
  }
}

private actor PausedRoutingRowsStore: LinkRoutingSettingsStoring {
  private let value: LinkRouting
  private var paused: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private var shouldPause = true
  init(initial: LinkRouting) { value = initial }
  func waitForLoad() async {
    if paused != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func resume() { paused?.resume(); paused = nil }
  func loadLinkRouting() async throws -> LinkRouting {
    if shouldPause {
      shouldPause = false
      await withCheckedContinuation { continuation in
        paused = continuation
        started?.resume()
        started = nil
      }
    }
    return value
  }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    var copy = value
    change(&copy)
    return copy
  }
}
