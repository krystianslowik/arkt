import Archive
import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Synchronization
import Testing

@MainActor
struct ArchiveCoordinatorTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private static let url = URL(string: "https://a.example")!
  /// Distinct from the first backoff (1 s), so the tests can tell the two sleeps apart.
  private static let flushTimeout: Duration = .milliseconds(700)

  /// A source with one Space ("Work") holding a pinned tab and Today tabs `today` (top first), a store, a sleeper
  /// and the coordinator over them, plus every change and `onDidChange` the source reports.
  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let store = FakeArchiveStore()
    let sleeper = ManualSleeper()
    let clock: TestClock
    let coordinator: ArchiveCoordinator
    let space: UUID
    let pinned: UUID
    let today: [UUID]
    var changes: [SidebarChange] = []
    var didChangeCount = 0
    private var observation: SidebarObservation?

    init(todayTabs: Int = 2, withSpace: Bool = true) throws {
      let source = ModelSidebarSource(now: { ArchiveCoordinatorTests.now })
      self.source = source
      let clock = TestClock(ArchiveCoordinatorTests.now)
      self.clock = clock
      if withSpace {
        let space = try source.addSpace(title: "Work")
        self.space = space
        pinned = try source.addTab(url: ArchiveCoordinatorTests.url, title: "P", in: .pinned(space))
        today = try (0..<todayTabs).map { index in
          try source.addTab(url: ArchiveCoordinatorTests.url, title: "T\(index)", in: .today(space))
        }
      } else {
        (space, pinned, today) = (UUID(), UUID(), [])
      }
      coordinator = ArchiveCoordinator(
        source: source, store: store, now: { clock.now },
        flushTimeout: ArchiveCoordinatorTests.flushTimeout, sleep: sleeper.sleep)
      observation = source.observe { [unowned self] in self.changes.append($0) }
      source.onDidChange = { [unowned self] _ in self.didChangeCount += 1 }
    }

    func drain() async {
      await eventually { !self.coordinator.hasPendingWrites }
    }
  }

  // MARK: - Archive

  @Test func archiveRemovesSynchronouslyAndWritesOneReplaceBatch() async throws {
    let harness = try Harness(todayTabs: 3)
    let ids = [harness.today[0], harness.today[2]]

    let items = harness.coordinator.archive(ids, reason: .manual)

    #expect(items.map(\.id) == ids)
    #expect(harness.source.children(of: .today(harness.space)) == [harness.today[1]])
    #expect(harness.changes == [.structure(.today(harness.space))])
    #expect(harness.didChangeCount == 1)
    #expect(harness.coordinator.pendingItems == items)
    #expect(harness.coordinator.hasPendingWrites)

    await harness.drain()
    #expect(await harness.store.addCalls == [.init(ids: ids, policy: .replace)])
    let written = try #require(await harness.store.addedItems.first)
    #expect(written.allSatisfy { $0.reason == .manual })
    #expect(written.allSatisfy { $0.section == .today })
    #expect(written.allSatisfy { $0.source == .space(harness.space) })
    #expect(written.allSatisfy { $0.archivedAt == Self.now })
    #expect(harness.coordinator.pendingItems.isEmpty)
  }

  @Test func unknownIdsAreSkipped() async throws {
    let harness = try Harness()
    #expect(harness.coordinator.archive([UUID()], reason: .manual).isEmpty)
    #expect(harness.didChangeCount == 0)
    #expect(!harness.coordinator.hasPendingWrites)
    #expect(await harness.store.addCalls.isEmpty)
  }

  @Test func storeFailureKeepsItemsPendingAndRetriesAfterTheFirstBackoff() async throws {
    let harness = try Harness()
    await harness.store.setFailsAdds(true)
    let items = harness.coordinator.archive([harness.today[0]], reason: .manual)

    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    #expect(harness.coordinator.pendingItems == items)
    #expect(harness.coordinator.hasPendingWrites)
    #expect(await harness.store.addCalls.count == 1)

    await harness.store.setFailsAdds(false)
    harness.sleeper.resume(.seconds(1))
    await harness.drain()
    #expect(await harness.store.addCalls.count == 2)
    #expect(await harness.store.stored[items[0].id] == items[0])
    #expect(harness.coordinator.pendingItems.isEmpty)
  }

  @Test func backoffFollowsTheRetryDelaysAndTheLastRepeats() async throws {
    let harness = try Harness()
    await harness.store.setFailsAdds(true)
    harness.coordinator.archive([harness.today[0]], reason: .manual)
    for delay in ArchiveCoordinator.retryDelays + [.seconds(30)] {
      await eventually { harness.sleeper.parkedDurations == [delay] }
      harness.sleeper.resume(delay)
    }
    await eventually { await harness.store.addCalls.count == 7 }
    #expect(harness.coordinator.pendingItems.count == 1)
  }

  @Test func archivesDuringAWriteAreWrittenNext() async throws {
    let harness = try Harness(todayTabs: 2)
    await harness.store.holdAdds()
    harness.coordinator.archive([harness.today[0]], reason: .manual)
    await eventually { await harness.store.addCalls.count == 1 }
    harness.coordinator.archive([harness.today[1]], reason: .auto)
    await harness.store.releaseAdds()
    await harness.drain()
    #expect(await harness.store.addCalls.map(\.ids) == [[harness.today[0]], [harness.today[1]]])
  }

  // MARK: - Flush

  @Test func flushWithNothingPendingReturnsTrue() async throws {
    let harness = try Harness()
    #expect(await harness.coordinator.flush())
  }

  @Test func flushWithAFailingStoreReturnsFalseAndKeepsTheItemPending() async throws {
    let harness = try Harness()
    await harness.store.setFailsAdds(true)
    let items = harness.coordinator.archive([harness.today[0]], reason: .manual)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }

    #expect(await harness.coordinator.flush() == false)
    #expect(harness.coordinator.pendingItems == items)
    #expect(harness.coordinator.hasPendingWrites)
    #expect(await harness.store.addCalls.count == 2)  // the writer's attempt, then exactly one flush attempt
  }

  @Test func flushDuringBackoffWritesAtOnce() async throws {
    let harness = try Harness()
    await harness.store.setFailsAdds(true)
    harness.coordinator.archive([harness.today[0]], reason: .manual)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    await harness.store.setFailsAdds(false)

    #expect(await harness.coordinator.flush())
    #expect(!harness.coordinator.hasPendingWrites)
  }

  @Test func flushReturnsFalseAtTheTimeoutWhileTheStoreHangs() async throws {
    let harness = try Harness()
    await harness.store.holdAdds()
    harness.coordinator.archive([harness.today[0]], reason: .manual)
    await eventually { await harness.store.addCalls.count == 1 }

    let flush = Task { await harness.coordinator.flush() }
    await eventually { harness.sleeper.parkedDurations.contains(Self.flushTimeout) }
    harness.sleeper.resume(Self.flushTimeout)
    #expect(await flush.value == false)
    #expect(harness.coordinator.hasPendingWrites)

    await harness.store.releaseAdds()  // the write finishes in the background
    await harness.drain()
    #expect(harness.coordinator.pendingItems.isEmpty)
  }

  @Test func flushDropsAFailingRemoveSoItCannotHoldBackAnAdd() async throws {
    let harness = try Harness()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await harness.drain()
    await harness.store.setFailsRemoves(true)
    _ = try harness.coordinator.restore(item, fallbackSpace: nil)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    let other = try #require(harness.coordinator.archive([harness.today[1]], reason: .manual).first)

    #expect(await harness.coordinator.flush())
    #expect(!harness.coordinator.hasPendingWrites)
    #expect(await harness.store.stored[other.id] == other)
    #expect(await harness.store.removeCalls == [[item.id], [item.id]])
  }

  // MARK: - Restore

  @Test func restorePutsATabAtTheTopOfTodayThenRemovesItFromTheStore() async throws {
    let harness = try Harness(todayTabs: 2)
    let item = try #require(harness.coordinator.archive([harness.today[1]], reason: .manual).first)
    await harness.drain()

    let restored = try #require(try harness.coordinator.restore(item, fallbackSpace: nil))

    #expect(restored.nodeID == item.id)
    #expect(restored.space == harness.space)
    #expect(harness.source.children(of: .today(harness.space)) == [item.id, harness.today[0]])
    await eventually { await harness.store.removeCalls == [[item.id]] }
    #expect(await harness.store.stored[item.id] == nil)
  }

  @Test func restoreWithoutASectionPutsAFolderAtTheEndOfPinned() async throws {  // BH-090
    let harness = try Harness()
    var other = SidebarModel.Sidebar()
    let otherSpace = other.addSpace(title: "Elsewhere")
    let folder = try other.addFolder(title: "F", in: .pinned(otherSpace))
    try other.addTab(url: Self.url, title: "Inside", in: .folder(folder))
    let snapshot = try #require(other.snapshot(of: folder))
    let item = ArchivedItem(reason: .manual, archivedAt: Self.now, source: .space(harness.space), snapshot: snapshot)

    let restored = try #require(try harness.coordinator.restore(item, fallbackSpace: nil))

    #expect(restored.location == .pinned(harness.space))
    #expect(harness.source.children(of: .pinned(harness.space)) == [harness.pinned, folder])
    #expect(harness.source.children(of: .folder(folder)).count == 1)
  }

  @Test func restoreWithAGoneSourceSpaceUsesTheFallback() throws {
    let harness = try Harness(todayTabs: 1)
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    var moved = item
    moved.source = .space(UUID())
    let second = try harness.source.addSpace(title: "Second")

    let restored = try #require(try harness.coordinator.restore(moved, fallbackSpace: second))

    #expect(restored.space == second)
    #expect(harness.source.children(of: .today(second)) == [item.id])
  }

  @Test func aFailingRemoveKeepsTheRestoreAndIsRetriedAfterABackoff() async throws {
    let harness = try Harness()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await harness.drain()
    await harness.store.setFailsRemoves(true)

    _ = try harness.coordinator.restore(item, fallbackSpace: nil)

    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    #expect(await harness.store.removeCalls.count == 1)
    #expect(harness.source.node(item.id) != nil)
    #expect(harness.coordinator.hasPendingWrites)

    await harness.store.setFailsRemoves(false)
    harness.sleeper.resume(.seconds(1))
    await harness.drain()
    #expect(await harness.store.removeCalls == [[item.id], [item.id]])
    #expect(await harness.store.stored[item.id] == nil)
  }

  @Test func aFailedRemoveSupersededByALaterArchiveIsDropped() async throws {
    let harness = try Harness()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await harness.drain()
    await harness.store.holdAdds()
    await harness.store.setFailsRemoves(true)
    harness.coordinator.archive([harness.today[1]], reason: .manual)  // holds the writer
    await eventually { await harness.store.addCalls.count == 2 }
    _ = try harness.coordinator.restore(item, fallbackSpace: nil)
    harness.clock.now += 60
    let again = try #require(harness.coordinator.archive([item.id], reason: .manual).first)

    await harness.store.releaseAdds()
    await harness.drain()

    // The remove failed; the queued `.replace` add of the same id makes a retry pointless, so it went next.
    #expect(await harness.store.calls.suffix(2) == [.remove([item.id]), .add([item.id])])
    #expect(await harness.store.removeCalls.count == 1)
    #expect(harness.sleeper.parkedCount == 0)
    #expect(await harness.store.stored[item.id] == again)
  }

  @Test func restoreThenArchiveAgainKeepsTheNewEntry() async throws {
    let harness = try Harness()
    await harness.store.holdAdds()
    let first = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await eventually { await harness.store.addCalls.count == 1 }

    _ = try harness.coordinator.restore(first, fallbackSpace: nil)
    harness.clock.now += 60
    let second = try #require(harness.coordinator.archive([first.id], reason: .manual).first)
    #expect(second != first)
    await harness.store.releaseAdds()
    await harness.drain()

    #expect(await harness.store.calls == [.add([first.id]), .remove([first.id]), .add([first.id])])
    #expect(await harness.store.stored[first.id] == second)
  }

  @Test func restoringTheSameItemTwiceIsANoOp() async throws {
    let harness = try Harness()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await harness.drain()
    _ = try harness.coordinator.restore(item, fallbackSpace: nil)
    let before = harness.source.sidebar

    #expect(try harness.coordinator.restore(item, fallbackSpace: nil) == nil)
    #expect(harness.source.sidebar == before)
    await harness.drain()
    #expect(await harness.store.removeCalls == [[item.id]])
  }

  @Test func restoringAnIdAlreadyInTheSidebarUsesFreshIds() async throws {
    let harness = try Harness()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await harness.drain()
    try harness.source.mutate { try $0.insert(item.snapshot, in: .today(harness.space)) }

    let restored = try #require(try harness.coordinator.restore(item, fallbackSpace: nil))

    #expect(restored.nodeID != item.id)
    #expect(harness.source.node(item.id) != nil)
    #expect(harness.source.node(restored.nodeID) != nil)
    await eventually { await harness.store.removeCalls == [[item.id]] }
  }

  @Test func restoreWithoutAnySpaceThrows() throws {
    let harness = try Harness(withSpace: false)
    var other = SidebarModel.Sidebar()
    let space = other.addSpace(title: "Gone")
    let tab = try other.addTab(url: Self.url, title: "T", in: .today(space))
    let snapshot = try #require(other.snapshot(of: tab))
    let item = ArchivedItem(reason: .auto, archivedAt: Self.now, source: .space(space), snapshot: snapshot)

    #expect(throws: ArchiveCoordinator.RestoreError.noSpaceForRestore) {
      try harness.coordinator.restore(item, fallbackSpace: nil)
    }
    #expect(harness.didChangeCount == 0)
  }

  @Test func restoringAPendingItemDropsItFromTheOutbox() async throws {
    let harness = try Harness()
    await harness.store.setFailsAdds(true)
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }

    _ = try harness.coordinator.restore(item, fallbackSpace: nil)

    #expect(harness.coordinator.pendingItems.isEmpty)
    await harness.store.setFailsAdds(false)
    harness.sleeper.resume(.seconds(1))
    await harness.drain()
    #expect(await harness.store.addCalls.count == 1)  // the unwritten entry is not sent any more
    #expect(await harness.store.removeCalls == [[item.id]])
  }

  @Test func restoreWaitsForTheWriteInFlightBeforeRemoving() async throws {
    let harness = try Harness()
    await harness.store.holdAdds()
    let item = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await eventually { await harness.store.addCalls.count == 1 }

    _ = try harness.coordinator.restore(item, fallbackSpace: nil)
    for _ in 0..<100 { await Task.yield() }
    #expect(await harness.store.removeCalls.isEmpty)

    await harness.store.releaseAdds()
    await eventually { await harness.store.removeCalls == [[item.id]] }
    #expect(await harness.store.stored[item.id] == nil)  // no stale entry left behind
  }
}

// MARK: - Helpers

/// A clock the tests move by hand.
@MainActor
final class TestClock {
  var now: Date

  init(_ now: Date) { self.now = now }
}

/// Yields until `condition` holds; records an issue if it never does.
@MainActor
private func eventually(
  _ condition: @MainActor () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<20_000 {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}

/// A manual stand-in for `Task.sleep` (as in ArktCore's persistence tests): each call parks until the test resumes
/// it, or throws `CancellationError` when its task is cancelled (also when cancelled before it parked).
final class ManualSleeper: Sendable {
  private struct Parked {
    let id: Int
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var nextID = 0
    var parked: [Parked] = []
    var cancelledEarly: Set<Int> = []
  }

  private let state = Mutex(State())

  var sleep: @Sendable (Duration) async throws -> Void { { [self] duration in try await self.park(duration) } }
  var parkedCount: Int { state.withLock { $0.parked.count } }
  var parkedDurations: [Duration] { state.withLock { $0.parked.map(\.duration) } }

  /// Resumes the parked sleeper with `duration` (the oldest one if several).
  func resume(_ duration: Duration) {
    let parked = state.withLock { state -> Parked? in
      guard let index = state.parked.firstIndex(where: { $0.duration == duration }) else { return nil }
      return state.parked.remove(at: index)
    }
    parked?.continuation.resume()
  }

  private func park(_ duration: Duration) async throws {
    let id = state.withLock { state -> Int in
      state.nextID += 1
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = state.withLock { state -> Bool in
          if state.cancelledEarly.remove(id) != nil { return true }
          state.parked.append(Parked(id: id, duration: duration, continuation: continuation))
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      let parked = state.withLock { state -> Parked? in
        if let index = state.parked.firstIndex(where: { $0.id == id }) { return state.parked.remove(at: index) }
        state.cancelledEarly.insert(id)
        return nil
      }
      parked?.continuation.resume(throwing: CancellationError())
    }
  }
}
