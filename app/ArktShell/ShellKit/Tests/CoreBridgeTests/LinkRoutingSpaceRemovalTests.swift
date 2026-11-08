import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

@MainActor
struct LinkRoutingSpaceRemovalTests {
  @Test func removalPreservesOtherRoutesAndDefaultAndRejectsStaleEdit() async {
    let removed = UUID(), other = UUID()
    let a = LinkRouting.Route(condition: .contains("a"), destination: .space(removed))
    let b = LinkRouting.Route(condition: .matches("b"), destination: .space(removed))
    let kept = LinkRouting.Route(condition: .contains("c"), destination: .space(other))
    let initial = LinkRouting(routes: [a, kept, b, kept], defaultDestination: .space(removed))
    let store = RemovalStore(initial)
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    let rows = model.settingsRows
    let before = rows.routes()
    model.removeRoutes(to: removed)
    #expect(model.settings == LinkRouting(routes: [kept, kept], defaultDestination: .space(removed)))
    #expect(!rows.replaceRouteIfUnchanged(0, before, before[0]))
    #expect(model.settings.routes == [kept, kept])
    #expect(await model.flush())
    model.removeRoutes(to: removed)
    #expect(model.needsFlush)
    #expect(await model.flush())
    let reopened = LinkRoutingSettingsModel(state: store)
    await reopened.load()
    #expect(reopened.settings == model.settings)
  }

  @Test func removalDuringSaveFollowsOlderSnapshot() async {
    let id = UUID()
    let route = LinkRouting.Route(condition: .matches("x"), destination: .space(id))
    let store = RemovalStore(LinkRouting(routes: [route]))
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    model.setDefaultDestination(.mostRecentSpace)
    await store.pauseNextWrite()
    let older = Task { await model.flush() }
    await store.waitForWrite()
    model.removeRoutes(to: id)
    let newer = Task { await model.flush() }
    await store.resumeWrite()
    #expect(await older.value)
    #expect(await newer.value)
    #expect(await store.value().routes.isEmpty)
    #expect(!model.needsFlush)
  }

  @Test func failedLoadRetainsPendingRemovalForRetry() async {
    let id = UUID()
    let route = LinkRouting.Route(condition: .contains("x"), destination: .space(id))
    let store = RemovalStore(LinkRouting(routes: [route]))
    await store.failNextLoad()
    let model = LinkRoutingSettingsModel(state: store)
    model.removeRoutes(to: id)
    await model.load()
    #expect(model.lastError != nil)
    #expect(model.needsFlush)
    #expect(await model.flushForTermination())
    #expect(model.flushBlocking())
    await model.load()
    #expect(model.settings.routes.isEmpty)
    #expect(await model.flush())
    #expect(await store.value().routes.isEmpty)
  }

  @Test func guardedEditFailsWhileReloadIsInProgress() async {
    let route = LinkRouting.Route(condition: .contains("original"), destination: .littleArkt)
    let store = RemovalStore(LinkRouting(routes: [route]))
    let model = LinkRoutingSettingsModel(state: store)
    await model.load()
    let rows = model.settingsRows
    let displayed = rows.routes()
    await store.pauseNextLoad()
    let loading = Task { await model.load() }
    await store.waitForLoad()
    #expect(rows.destination() == nil)
    #expect(!rows.replaceRouteIfUnchanged(0, displayed, displayed[0]))
    await store.resumeLoad()
    await loading.value
    #expect(model.settings.routes == [route])
  }

  @Test func removalBeforeLoadCompletesIsApplied() async {
    let id = UUID()
    let route = LinkRouting.Route(condition: .contains("x"), destination: .space(id))
    let store = RemovalStore(LinkRouting(routes: [route]))
    await store.pauseNextLoad()
    let model = LinkRoutingSettingsModel(state: store)
    let loading = Task { await model.load() }
    await store.waitForLoad()
    model.removeRoutes(to: id)
    #expect(model.needsFlush)
    await store.resumeLoad()
    await loading.value
    #expect(model.settings.routes.isEmpty)
    #expect(await model.flush())
    #expect(await store.value().routes.isEmpty)
  }
}

private actor RemovalStore: LinkRoutingSettingsStoring {
  private var stored: LinkRouting
  private enum Failure: Error { case requested }
  private var failLoad = false
  private var holdLoad = false, holdWrite = false
  private var loadContinuation: CheckedContinuation<Void, Never>?
  private var writeContinuation: CheckedContinuation<Void, Never>?
  private var loadStarted: CheckedContinuation<Void, Never>?
  private var writeStarted: CheckedContinuation<Void, Never>?
  init(_ value: LinkRouting) { stored = value }
  func value() -> LinkRouting { stored }
  func failNextLoad() { failLoad = true }
  func pauseNextLoad() { holdLoad = true }
  func pauseNextWrite() { holdWrite = true }
  func waitForLoad() async { if loadContinuation != nil { return }; await withCheckedContinuation { loadStarted = $0 } }
  func waitForWrite() async { if writeContinuation != nil { return }; await withCheckedContinuation { writeStarted = $0 } }
  func resumeLoad() { loadContinuation?.resume(); loadContinuation = nil }
  func resumeWrite() { writeContinuation?.resume(); writeContinuation = nil }
  func loadLinkRouting() async throws -> LinkRouting {
    if failLoad { failLoad = false; throw Failure.requested }
    if holdLoad { holdLoad = false; await withCheckedContinuation { loadContinuation = $0; loadStarted?.resume(); loadStarted = nil } }
    return stored
  }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    if holdWrite { holdWrite = false; await withCheckedContinuation { writeContinuation = $0; writeStarted?.resume(); writeStarted = nil } }
    change(&stored)
    return stored
  }
}
