import CoreBridge
import Foundation
import SidebarModel
import Testing

@MainActor
struct ArchiveRoutingSnapshotTests {
  @Test func snapshotIsUnavailableBeforeDuringAndAfterAFailedRead() async throws {
    let store = SnapshotRoutingStore()
    let editor = LinkRoutingSettingsModel(state: store)
    #expect(editor.loadedSettings == nil)
    await editor.load()
    #expect(editor.loadedSettings == LinkRouting(routes: []))
    await store.holdNextRead()
    let loading = Task { await editor.load() }
    defer {
      loading.cancel()
      Task { await store.release(failing: true) }
    }
    var started = false
    for _ in 0..<20_000 {
      if await store.isHeld { started = true; break }
      await Task.yield()
    }
    try #require(started, "the controlled read must actually be suspended")
    #expect(editor.loadedSettings == nil, "a previously loaded but currently reloading value is unavailable")
    await store.release(failing: true)
    await loading.value
    #expect(editor.loadedSettings == nil)
    await editor.load()
    #expect(editor.loadedSettings == LinkRouting(routes: []))
  }

  @Test func snapshotContainsCurrentUnsavedEdits() async {
    let editor = LinkRoutingSettingsModel(state: SnapshotRoutingStore())
    await editor.load()
    let route = LinkRouting.Route(condition: .contains("literal"), destination: .space(UUID()))
    editor.appendRoute(route)
    #expect(editor.loadedSettings?.routes == [route])
    #expect(editor.needsFlush)
  }
}

private actor SnapshotRoutingStore: LinkRoutingSettingsStoring {
  private struct ReadFailure: Error {}
  private var value = LinkRouting(routes: [])
  private var hold = false
  private var continuation: CheckedContinuation<LinkRouting, any Error>?
  var isHeld: Bool { continuation != nil }
  func holdNextRead() { hold = true }
  func loadLinkRouting() async throws -> LinkRouting {
    if hold {
      hold = false
      return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    return value
  }
  func release(failing: Bool) {
    hold = false
    let held = continuation
    continuation = nil
    if failing { held?.resume(throwing: ReadFailure()) }
    else { held?.resume(returning: value) }
  }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    change(&value)
    return value
  }
}
