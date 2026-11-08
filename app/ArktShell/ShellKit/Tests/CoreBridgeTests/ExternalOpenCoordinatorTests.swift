import CoreBridge
import Foundation
import SidebarModel
import ShellUI
import Testing

// Contract for the App-owned, main-actor receiver. This type does not exist yet.
@MainActor
struct ExternalOpenCoordinatorTests {
  private let a = URL(string: "https://example.test/a")!
  private let b = URL(string: "https://example.test/b")!
  private let c = URL(string: "https://example.test/c")!

  @Test func retainsBeforeStartAndDuringReadIncludingRepeatedEvents() async {
    let coordinator = ExternalOpenCoordinator<String>()
    let read = HeldRead()
    var delivered: [URL] = []
    var outcomes: [String] = []
    coordinator.receive([a, b])
    coordinator.receive([a])
    #expect(coordinator.state == .waiting)
    #expect(coordinator.pendingCount == 3)
    let start = Task { await coordinator.start(read: { try await read.run() }, deliver: { url in
      delivered.append(url); return url.absoluteString
    }, onResult: { _, result in outcomes.append(result) }) }
    await read.waitUntilStarted()
    coordinator.receive([c])
    #expect(coordinator.state == .loading)
    #expect(coordinator.pendingCount == 4)
    #expect(delivered.isEmpty)
    read.succeed()
    #expect(await start.value)
    #expect(coordinator.state == .ready)
    #expect(coordinator.pendingCount == 0)
    #expect(delivered == [a, b, a, c])
    #expect(outcomes == [a, b, a, c].map(\.absoluteString))
  }

  @Test func failedReadRetainsRequestsAndExplicitRetryDeliversOnce() async {
    let coordinator = ExternalOpenCoordinator<String>()
    let read = HeldRead()
    var results: [String] = []
    coordinator.receive([a])
    let start = Task { await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                               onResult: { _, result in results.append(result) }) }
    await read.waitUntilStarted()
    coordinator.receive([b])
    read.fail()
    #expect(await !start.value)
    #expect(coordinator.state == .failed)
    #expect(coordinator.pendingCount == 2)
    #expect(results.isEmpty)
    coordinator.receive([c])
    let retry = Task { await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                               onResult: { _, result in results.append(result) }) }
    await read.waitUntilStarted()
    let entered = Signal()
    let joinedRetry = Task {
      entered.fire()
      return await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                     onResult: { _, result in results.append(result) })
    }
    await entered.wait()
    #expect(read.count == 2)
    read.succeed()
    #expect(await retry.value)
    #expect(await joinedRetry.value)
    #expect(read.count == 2)
    #expect(results == [a, b, c].map(\.absoluteString))
    #expect(coordinator.pendingCount == 0)
  }

  @Test func concurrentStartsAndReentrantArrivalDrainInOrderOnce() async {
    let coordinator = ExternalOpenCoordinator<String>()
    let read = HeldRead()
    var delivered: [URL] = []
    var results: [String] = []
    let deliver: @MainActor (URL) -> String = { url in
      delivered.append(url)
      if url == a { coordinator.receive([self.c]) }
      return url.absoluteString
    }
    let report: @MainActor (URL, String) -> Void = { _, result in results.append(result) }
    coordinator.receive([a, b])
    let first = Task { await coordinator.start(read: { try await read.run() }, deliver: deliver, onResult: report) }
    await read.waitUntilStarted()
    let entered = Signal()
    let second = Task {
      entered.fire()
      return await coordinator.start(read: { try await read.run() }, deliver: deliver, onResult: report)
    }
    await entered.wait()
    #expect(read.count == 1)
    read.succeed()
    #expect(await first.value)
    #expect(await second.value)
    #expect(read.count == 1)
    #expect(delivered == [a, b, c])
    #expect(results == [a, b, c].map(\.absoluteString))
    #expect(coordinator.pendingCount == 0)
    #expect(await coordinator.start(read: { throw ReadFailure.failed }, deliver: deliver, onResult: report))
    #expect(read.count == 1)
    coordinator.receive([b])
    #expect(delivered == [a, b, c, b])
  }

  @Test func deliveryUsesCurrentSharedEditorAndReportsEveryOutcome() async {
    let store = ImmediateRoutingStore()
    let editor = LinkRoutingSettingsModel(state: store)
    let coordinator = ExternalOpenCoordinator<SettingsLinkDestination?>()
    var results: [SettingsLinkDestination?] = []
    coordinator.receive([a])
    let ready = await coordinator.start(read: {
      await editor.load()
      guard editor.isLoaded else { throw ReadFailure.failed }
    }, deliver: { editor.destination(for: $0) }, onResult: { _, result in results.append(result) })
    #expect(ready)
    editor.setDefaultDestination(.mostRecentSpace)
    coordinator.receive([b])
    #expect(results == [.littleArkt, .mostRecentSpace])
  }

  @Test func reportsUnresolvedOutcomesWithoutImplicitRetry() async {
    enum Outcome: Equatable { case dispatched, ignored, unresolved, missingSpace(UUID?) }
    let coordinator = ExternalOpenCoordinator<Outcome>()
    var results: [(URL, Outcome)] = []
    let missing = UUID()
    coordinator.receive([a, b, c])
    #expect(await coordinator.start(read: {}, deliver: { url in
      url == a ? Outcome.unresolved : url == b ? Outcome.missingSpace(missing) : Outcome.ignored
    }, onResult: { results.append(($0, $1)) }))
    #expect(results.map(\.0) == [a, b, c])
    #expect(results.map(\.1) == [.unresolved, .missingSpace(missing), .ignored])
    #expect(coordinator.pendingCount == 0)
  }
}

private enum ReadFailure: Error { case failed }

@MainActor
private final class Signal {
  private var fired = false
  private var waiter: CheckedContinuation<Void, Never>?
  func fire() { fired = true; waiter?.resume(); waiter = nil }
  func wait() async {
    if fired { return }
    await withCheckedContinuation { waiter = $0 }
  }
}

@MainActor
private final class HeldRead {
  private var started = Signal()
  private var continuation: CheckedContinuation<Void, any Error>?
  private(set) var count = 0
  func run() async throws {
    count += 1
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      started.fire()
    }
  }
  func waitUntilStarted() async { await started.wait() }
  func succeed() { finish(.success(())) }
  func fail() { finish(.failure(ReadFailure.failed)) }
  private func finish(_ result: Result<Void, any Error>) {
    let pending = continuation
    continuation = nil
    started = Signal()
    pending?.resume(with: result)
  }
}

private actor ImmediateRoutingStore: LinkRoutingSettingsStoring {
  private var value = LinkRouting(routes: [])
  func loadLinkRouting() async throws -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws -> LinkRouting {
    change(&value)
    return value
  }
}
