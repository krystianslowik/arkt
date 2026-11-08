import CoreBridge
import Foundation
import SidebarModel
import ShellUI
import Testing

// Contract for the App-owned, main-actor receiver.
@MainActor
struct ExternalOpenCoordinatorTests {
  private let a = URL(string: "https://example.test/a")!
  private let b = URL(string: "https://example.test/b")!
  private let c = URL(string: "https://example.test/c")!

  @Test func retainsBeforeStartAndDuringReadIncludingRepeatedEvents() async throws {
    let coordinator = ExternalOpenCoordinator<String>()
    let read = HeldRead()
    var delivered: [URL] = []
    var outcomes: [String] = []
    coordinator.receive([a, b])
    coordinator.receive([a])
    #expect(coordinator.state == .waiting)
    #expect(coordinator.pendingCount == 3)
    let start = StartAttempt { await coordinator.start(read: { try await read.run() }, deliver: { url in
      delivered.append(url); return url.absoluteString
    }, onResult: { _, result in outcomes.append(result) }) }
    defer { start.cancel(); read.cancel() }
    try await read.waitUntilStarted()
    coordinator.receive([c])
    #expect(coordinator.state == .loading)
    #expect(coordinator.pendingCount == 4)
    #expect(delivered.isEmpty)
    read.succeed()
    #expect(try await start.result())
    #expect(coordinator.state == .ready)
    #expect(coordinator.pendingCount == 0)
    #expect(delivered == [a, b, a, c])
    #expect(outcomes == [a, b, a, c].map(\.absoluteString))
  }

  @Test func failedReadRetainsRequestsAndExplicitRetryDeliversOnce() async throws {
    let coordinator = ExternalOpenCoordinator<String>()
    let read = HeldRead()
    var results: [String] = []
    coordinator.receive([a])
    let start = StartAttempt { await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                               onResult: { _, result in results.append(result) }) }
    defer { start.cancel(); read.cancel() }
    try await read.waitUntilStarted()
    coordinator.receive([b])
    read.fail()
    #expect(try await !start.result())
    #expect(coordinator.state == .failed)
    #expect(coordinator.pendingCount == 2)
    #expect(results.isEmpty)
    coordinator.receive([c])
    let retry = StartAttempt { await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                               onResult: { _, result in results.append(result) }) }
    defer { retry.cancel() }
    try await read.waitUntilStarted()
    var entered = false
    let joinedRetry = StartAttempt {
      entered = true
      return await coordinator.start(read: { try await read.run() }, deliver: { $0.absoluteString },
                                     onResult: { _, result in results.append(result) })
    }
    defer { joinedRetry.cancel() }
    try #require(await advanceUntil { entered })
    #expect(read.count == 2)
    read.succeed()
    #expect(try await retry.result())
    #expect(try await joinedRetry.result())
    #expect(read.count == 2)
    #expect(results == [a, b, c].map(\.absoluteString))
    #expect(coordinator.pendingCount == 0)
  }

  @Test func concurrentStartsAndReentrantArrivalDrainInOrderOnce() async throws {
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
    let first = StartAttempt { await coordinator.start(read: { try await read.run() }, deliver: deliver, onResult: report) }
    defer { first.cancel(); read.cancel() }
    try await read.waitUntilStarted()
    var entered = false
    let second = StartAttempt {
      entered = true
      return await coordinator.start(read: { try await read.run() }, deliver: deliver, onResult: report)
    }
    defer { second.cancel() }
    try #require(await advanceUntil { entered })
    #expect(read.count == 1)
    read.succeed()
    #expect(try await first.result())
    #expect(try await second.result())
    #expect(read.count == 1)
    #expect(delivered == [a, b, c])
    #expect(results == [a, b, c].map(\.absoluteString))
    #expect(coordinator.pendingCount == 0)
    #expect(try await completed { await coordinator.start(read: { throw ReadFailure.failed }, deliver: deliver, onResult: report) })
    #expect(read.count == 1)
    coordinator.receive([b])
    #expect(delivered == [a, b, c, b])
  }

  @Test func resultCallbackArrivalsJoinTailAndReadyStartKeepsCallbacks() async throws {
    let coordinator = ExternalOpenCoordinator<String>()
    var results: [URL] = []
    var values: [String] = []
    coordinator.receive([a, b])
    #expect(try await completed { await coordinator.start(read: {}, deliver: { $0.absoluteString }, onResult: { url, value in
      results.append(url)
      values.append(value)
      if url == self.a { coordinator.receive([self.c]) }
    }) })
    #expect(try await completed { await coordinator.start(read: { throw ReadFailure.failed }, deliver: { _ in "replacement" },
                                    onResult: { _, _ in Issue.record("ready start replaced callbacks") }) })
    coordinator.receive([a])
    #expect(results == [a, b, c, a, c])
    #expect(values == [a, b, c, a, c].map(\.absoluteString))
    #expect(coordinator.pendingCount == 0)
  }

  @Test func deliveryUsesCurrentSharedEditorAndReportsEveryOutcome() async throws {
    let store = ImmediateRoutingStore()
    let editor = LinkRoutingSettingsModel(state: store)
    let coordinator = ExternalOpenCoordinator<SettingsLinkDestination?>()
    var results: [SettingsLinkDestination?] = []
    coordinator.receive([a])
    let ready = try await completed { await coordinator.start(read: {
      await editor.load()
      guard editor.isLoaded else { throw ReadFailure.failed }
    }, deliver: { editor.destination(for: $0) }, onResult: { _, result in results.append(result) }) }
    #expect(ready)
    editor.setDefaultDestination(.mostRecentSpace)
    coordinator.receive([b])
    #expect(results == [.littleArkt, .mostRecentSpace])
  }

  @Test func reportsUnresolvedOutcomesWithoutImplicitRetry() async throws {
    enum Outcome: Equatable { case dispatched, ignored, unresolved, missingSpace(UUID?) }
    let coordinator = ExternalOpenCoordinator<Outcome>()
    var results: [(URL, Outcome)] = []
    let missing = UUID()
    coordinator.receive([a, b, c])
    #expect(try await completed { await coordinator.start(read: {}, deliver: { url in
      url == a ? Outcome.unresolved : url == b ? Outcome.missingSpace(missing) : Outcome.ignored
    }, onResult: { results.append(($0, $1)) }) })
    #expect(results.map(\.0) == [a, b, c])
    #expect(results.map(\.1) == [.unresolved, .missingSpace(missing), .ignored])
    #expect(coordinator.pendingCount == 0)
  }
}

private enum ReadFailure: Error { case failed }

/// Finite actor turns, without a wall-clock deadline or sleep.
@MainActor
private func advanceUntil(_ condition: @MainActor () -> Bool) async -> Bool {
  for _ in 0..<10_000 {
    if condition() { return true }
    await Task.yield()
  }
  return condition()
}

@MainActor
private final class StartAttempt {
  private var value: Bool?
  private var task: Task<Void, Never>?

  init(_ operation: @escaping @MainActor () async -> Bool) {
    task = Task { self.value = await operation() }
  }

  func result() async throws -> Bool {
    try #require(await advanceUntil { self.value != nil }, "coordinator start did not finish within actor turns")
    return try #require(value as Bool?)
  }

  func cancel() { task?.cancel() }
}

@MainActor
private func completed(_ operation: @escaping @MainActor () async -> Bool) async throws -> Bool {
  let attempt = StartAttempt(operation)
  defer { attempt.cancel() }
  return try await attempt.result()
}

@MainActor
private final class HeldRead {
  private var continuations: [CheckedContinuation<Void, any Error>] = []
  private var observedStarts = 0
  private var cancelled = false
  private(set) var count = 0

  func run() async throws {
    guard !cancelled else { throw CancellationError() }
    count += 1
    try await withCheckedThrowingContinuation { continuations.append($0) }
  }

  func waitUntilStarted() async throws {
    let expected = observedStarts + 1
    try #require(await advanceUntil { self.count >= expected }, "routing read did not start within actor turns")
    observedStarts = expected
  }

  func succeed() { finish(.success(())) }
  func fail() { finish(.failure(ReadFailure.failed)) }
  func cancel() { cancelled = true; finish(.failure(CancellationError())) }

  private func finish(_ result: Result<Void, any Error>) {
    let pending = continuations
    continuations.removeAll()
    for continuation in pending { continuation.resume(with: result) }
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
