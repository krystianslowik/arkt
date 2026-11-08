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

  @Test func exactDuplicateRoutesSurviveFlushAndReopen() async {
    let store = EditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.appendRoute(Self.first)
    model.appendRoute(Self.first)
    await model.flush()
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings.routes == [Self.first, Self.first])
    reopened.replaceRoute(at: 1, with: Self.second)
    #expect(reopened.settings.routes == [Self.first, Self.second], "duplicate entries remain independently editable")
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

@MainActor
struct LinkRoutingEditorFailureTests {
  private let route = LinkRouting.Route(condition: .contains("literal"), destination: .littleArkt)
  private let other = LinkRouting.Route(condition: .matches("OTHER"), destination: .mostRecentSpace)

  @Test func failedFlushRetainsOrderedDuplicatesAndRetries() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.appendRoute(route)
    model.appendRoute(route)
    model.appendRoute(other)
    await store.failNextWrite()
    #expect(await model.flush() == false)
    #expect(model.lastError != nil)
    #expect(model.settings.routes == [route, route, other])
    #expect(await model.flush() == true)
    #expect(model.lastError == nil)
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings.routes == [route, route, other])
  }

  @Test func failedWriteOfUnchangedSnapshotStillNeedsRetry() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    await store.failNextWrite()
    #expect(!(await model.flush()))
    #expect(model.needsFlush)
    #expect(model.lastError != nil)
    #expect(await model.flush())
    #expect(!model.needsFlush)
    #expect(model.lastError == nil)
  }

  @Test func inFlightEditsAndConcurrentFlushesAreSerialized() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.appendRoute(route)
    await store.pauseNextWrite()
    let first = Task { await model.flush() }
    await store.waitForPausedWrite()
    model.appendRoute(route)
    model.appendRoute(other)
    let second = Task { await model.flush() }
    await store.resumeWrite()
    #expect(await first.value)
    #expect(await second.value)
    #expect(model.settings.routes == [route, route, other])
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings.routes == [route, route, other])
    #expect(await store.maximumConcurrentWrites() == 1)
  }

  @Test func blockingFlushFollowsInFlightOlderSnapshot() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store, flushTimeout: nil)
    await model.load()
    model.appendRoute(route)
    await store.pauseNextWrite()
    let first = Task { await model.flush() }
    await store.waitForPausedWrite()
    model.appendRoute(route)
    model.appendRoute(other)
    let release = Task.detached { await store.resumeWrite() }
    #expect(model.flushBlocking())
    await release.value
    #expect(await first.value)
    #expect(!model.needsFlush)
    #expect(await store.stored().routes == [route, route, other])
  }

  @Test func blockingTimeoutKeepsSnapshotDirtyAndReportsError() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store, flushTimeout: .zero)
    await model.load()
    model.appendRoute(route)
    await store.pauseNextWrite()
    #expect(!model.flushBlocking())
    #expect(model.needsFlush)
    #expect(model.lastError != nil)
    await store.waitForPausedWrite()
    await store.resumeWrite()
    #expect(await model.flush())
    #expect(!model.needsFlush)
    #expect(model.lastError == nil)
    #expect(await store.stored().routes == [route])
  }

  @Test func normalTerminationTimeoutRetainsErrorAndDirtySnapshot() async {
    let store = ControlledEditorStore()
    let model = LinkRoutingSettingsModel(state: store, flushTimeout: .zero)
    await model.load()
    model.appendRoute(route)
    await store.pauseNextWrite()
    #expect(!(await model.flushForTermination()))
    #expect(model.needsFlush)
    #expect(model.lastError != nil)
    await store.waitForPausedWrite()
    await store.resumeWrite()
    #expect(await model.flush())
    #expect(!model.needsFlush)
    #expect(model.lastError == nil)
  }

  @Test func failedLoadCannotFlushDefaultsAndInvalidIndicesAreSafe() async {
    let store = ControlledEditorStore(initial: LinkRouting(routes: [route]))
    await store.failNextLoad()
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    #expect(model.lastError != nil)
    model.appendRoute(other)
    #expect(await model.flush() == false)
    #expect(await store.stored().routes == [route])
    await model.load()
    #expect(model.lastError == nil)
    model.replaceRoute(at: -1, with: other)
    model.removeRoute(at: 1)
    #expect(model.settings.routes == [route])
  }
}

private actor ControlledEditorStore: LinkRoutingSettingsStoring {
  enum Failure: Error { case requested }
  private var value: LinkRouting
  private var failLoad = false
  private var failWrite = false
  private var pauseWrite = false
  private var paused: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private var active = 0
  private var maximum = 0

  init(initial: LinkRouting = LinkRouting(routes: [])) { value = initial }
  func failNextLoad() { failLoad = true }
  func failNextWrite() { failWrite = true }
  func pauseNextWrite() { pauseWrite = true }
  func waitForPausedWrite() async {
    if paused != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func resumeWrite() { paused?.resume(); paused = nil }
  func stored() -> LinkRouting { value }
  func maximumConcurrentWrites() -> Int { maximum }
  func loadLinkRouting() async throws -> LinkRouting {
    if failLoad { failLoad = false; throw Failure.requested }
    return value
  }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    active += 1
    maximum = max(maximum, active)
    defer { active -= 1 }
    if pauseWrite {
      pauseWrite = false
      await withCheckedContinuation { continuation in
        paused = continuation
        started?.resume()
        started = nil
      }
    }
    if failWrite { failWrite = false; throw Failure.requested }
    change(&value)
    return value
  }
}

@MainActor
struct LinkRoutingTerminationTests {
  @Test func routingOnlyEditRequiresTerminationFlush() async {
    let model = LinkRoutingSettingsModel(state: EditorStore())
    await model.load()
    #expect(!model.needsFlush)
    model.setDefaultDestination(.mostRecentSpace)
    #expect(model.needsFlush)
  }

}
