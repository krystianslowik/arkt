import Archive
import Foundation
import Synchronization
import Testing
@testable import Persistence
import SidebarModel

@MainActor
struct SidebarAutosaverTests {
  let sleeper = ManualSleeper()
  let store = RecordingStore()

  func makeAutosaver() -> SidebarAutosaver {
    SidebarAutosaver(
      store: store, delay: .milliseconds(500), retryDelays: [.seconds(1), .seconds(2)],
      now: { Date(timeIntervalSinceReferenceDate: 0) }, sleep: sleeper.sleep)
  }

  @Test func coalescesChangesInsideTheWindow() async {
    let saver = makeAutosaver()
    let (a, b, c) = (TestSidebars.make("a"), TestSidebars.make("b"), TestSidebars.make("c"))
    saver.scheduleSave(a)
    saver.scheduleSave(b)
    saver.scheduleSave(c)
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(sleeper.parkedDurations == [.milliseconds(500)])
    #expect(store.saved.isEmpty)
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 1 }
    #expect(store.saved == [c])
    #expect(!saver.hasPendingChanges)
  }

  @Test func scheduleSaveNeverWaitsForTheStore() async {
    let saver = makeAutosaver()
    store.block()
    let (a, b) = (TestSidebars.make("a"), TestSidebars.make("b"))
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.started == 1 }  // the write is now stuck inside the store
    saver.scheduleSave(b)  // synchronous: returning at all proves the main actor is free
    #expect(saver.hasPendingChanges)
    #expect(store.saved.isEmpty)
    store.unblock()
    await waitUntil { store.saved == [a] }
    await waitUntil { sleeper.parkedCount == 1 }  // b gets its own window after the write
    sleeper.resumeNext()
    await waitUntil { store.saved == [a, b] }
    #expect(store.maxInFlight == 1)
  }

  @Test func changeAfterAWriteOpensANewWindow() async {
    let saver = makeAutosaver()
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 1 }
    saver.scheduleSave(TestSidebars.make("b"))
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(store.saved.count == 1)
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 2 }
  }

  @Test func flushWritesPendingImmediatelyAndCancelsTheTimer() async {
    let saver = makeAutosaver()
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(await saver.flush())
    #expect(store.saved == [a])
    await waitUntil { sleeper.parkedCount == 0 }
    for _ in 0..<100 { await Task.yield() }
    #expect(store.saved == [a])
  }

  @Test func flushWithNothingPendingWritesNothing() async {
    let saver = makeAutosaver()
    #expect(await saver.flush())
    #expect(store.started == 0)
  }

  @Test func failedWriteRetriesTheNewestValueAfterBackoff() async {
    let saver = makeAutosaver()
    store.failNext(1)
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { sleeper.parkedCount == 1 && store.started == 1 }
    #expect(sleeper.parkedDurations == [.seconds(1)])
    #expect(saver.lastError != nil)
    let b = TestSidebars.make("b")
    saver.scheduleSave(b)  // during backoff: no second timer
    #expect(sleeper.parkedCount == 1)
    sleeper.resumeNext()
    await waitUntil { store.saved == [b] }
    await waitUntil { saver.lastError == nil }  // cleared once the save returns to the main actor
  }

  @Test func backoffGrowsThenRepeatsTheLastDelay() async {
    let saver = makeAutosaver()
    store.failNext(3)
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    var seen: [Duration] = []
    for attempt in 1...3 {
      await waitUntil { sleeper.parkedCount == 1 && store.started == attempt }
      seen += sleeper.parkedDurations
      sleeper.resumeNext()
    }
    #expect(seen == [.seconds(1), .seconds(2), .seconds(2)])
    await waitUntil { store.saved.count == 1 }
  }

  @Test func flushDuringBackoffMakesOneAttemptAndReturns() async {
    let saver = makeAutosaver()
    store.failNext(1)
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { sleeper.parkedCount == 1 && store.started == 1 }
    #expect(await saver.flush())
    #expect(store.saved == [a])
    await waitUntil { sleeper.parkedCount == 0 }
  }

  @Test func flushReportsAFailedAttempt() async {
    let saver = makeAutosaver()
    store.failNext(5)
    saver.scheduleSave(TestSidebars.make("a"))
    #expect(await saver.flush() == false)
    #expect(saver.hasPendingChanges)
    #expect(saver.lastError != nil)
  }

  @Test func flushWaitsForTheInFlightWriteThenWritesTheNewest() async {
    let saver = makeAutosaver()
    store.block()
    let (a, b) = (TestSidebars.make("a"), TestSidebars.make("b"))
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.started == 1 }
    saver.scheduleSave(b)
    let flush = Task { await saver.flush() }
    for _ in 0..<100 { await Task.yield() }
    #expect(store.started == 1)  // no second write overlaps the one in flight
    store.unblock()
    #expect(await flush.value)
    #expect(store.saved == [a, b])  // the older in-flight value never lands after the newer one
    #expect(store.maxInFlight == 1)
    await waitUntil { sleeper.parkedCount == 0 }
  }

  @Test func changeDuringAFlushWriteIsNotWrittenConcurrently() async {
    let saver = makeAutosaver()
    store.block()
    let (a, b) = (TestSidebars.make("a"), TestSidebars.make("b"))
    saver.scheduleSave(a)
    let flush = Task { await saver.flush() }
    await waitUntil { store.started == 1 }
    saver.scheduleSave(b)
    for _ in 0..<100 { await Task.yield() }
    await waitUntil { sleeper.parkedDurations == [SidebarAutosaver.defaultFlushTimeout] }  // no debounce timer armed
    store.unblock()
    #expect(await flush.value == false)  // b arrived after the flush started and is still unsaved
    await waitUntil { sleeper.parkedDurations == [.milliseconds(500)] }
    sleeper.resumeNext()
    await waitUntil { store.saved == [a, b] }
    #expect(store.maxInFlight == 1)
  }

  @Test func flushGivesUpAfterItsTimeoutWithoutCancellingTheWrite() async {
    let saver = makeAutosaver()
    store.block()
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    let flush = Task { await saver.flush() }
    await waitUntil { store.started == 1 && sleeper.parkedCount == 1 }
    #expect(sleeper.parkedDurations == [.seconds(1)])
    sleeper.resume(.seconds(1))
    #expect(await flush.value == false)  // bounded: termination is not held hostage by a stuck disk
    store.unblock()
    await waitUntil { store.saved == [a] }  // the write itself still completes
  }

  @Test func writesThroughTheRealStoreOffTheMainThread() async throws {
    let database = try ArktDatabase.inMemory()
    let realStore = SidebarStore(database: database)
    let saver = SidebarAutosaver(store: realStore, sleep: sleeper.sleep)
    let sidebar = TestSidebars.make("real")
    saver.scheduleSave(sidebar)
    #expect(await saver.flush())  // SidebarStore.save traps if it runs on the main thread
    #expect(try await realStore.load() == sidebar)
  }

  @Test func needsFlushCoversPendingAndInFlightWrites() async {
    let saver = makeAutosaver()
    #expect(!saver.needsFlush)
    store.block()
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    #expect(saver.needsFlush)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.started == 1 }
    #expect(!saver.hasPendingChanges)
    #expect(saver.needsFlush)  // the write is still in flight
    store.unblock()
    await waitUntil { store.saved == [a] && !saver.needsFlush }
  }

  @Test func backoffThatEndsAsFlushCancelsItMakesNoExtraAttempt() async {
    let retry = UncancellableSleeper()
    let manual = sleeper
    let saver = SidebarAutosaver(
      store: store, delay: .milliseconds(500), retryDelays: [.seconds(1)], flushTimeout: .seconds(60),
      now: { Date(timeIntervalSinceReferenceDate: 0) },
      sleep: { duration in
        if duration == .seconds(1) { await retry.park() } else { try await manual.sleep(duration) }
      })
    store.failNext(2)
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.started == 1 && retry.parkedCount == 1 }
    let flush = Task { await saver.flush() }
    await waitUntil { retry.cancelledCount == 1 }
    retry.resumeAll()  // the sleep returns normally although its task was cancelled
    #expect(await flush.value == false)  // flush's own single attempt hit the second failure
    #expect(store.started == 2)  // the cancelled loop did not attempt again
  }

  /// #213: a crash between the archive write and the sidebar save never loses archived items in either order:
  /// (1) when the archive write fails or has not finished yet, `beforeSave` prevents the post-archive sidebar from
  ///     being saved, so a crash leaves the items in `SidebarStore`;
  /// (2) when the archive write lands first and the process crashes before `SidebarStore.save`, `ArchiveStore` holds
  ///     the items and `SidebarStore.load()` replays the pending removals idempotently on launch.
  @Test func crashBetweenArchiveWriteAndSidebarSaveLosesNoItems() async throws {
    let database = try ArktDatabase.inMemory()
    let sidebarStore = SidebarStore(database: database)
    let archiveStore = ArchiveStore(database: database)

    var initial = Sidebar()
    let space = initial.addSpace(title: "Work")
    let pinned = try initial.addTab(url: URL(string: "https://p.example")!, title: "Pinned", in: .pinned(space))
    let today0 = try initial.addTab(url: URL(string: "https://t0.example")!, title: "T0", in: .today(space))
    let today1 = try initial.addTab(url: URL(string: "https://t1.example")!, title: "T1", in: .today(space))
    _ = try await sidebarStore.save(initial, at: Date(timeIntervalSinceReferenceDate: 10))

    // Case 1: Archive write fails when the sidebar autosaver tries to save, then the app crashes before retry.
    var afterArchive = initial
    let archivedT0 = try Archiver.archive(today0, from: &afterArchive, reason: .manual,
                                          at: Date(timeIntervalSinceReferenceDate: 20))
    let saver = SidebarAutosaver(
      store: sidebarStore, delay: .milliseconds(500), retryDelays: [.seconds(1)],
      now: { Date(timeIntervalSinceReferenceDate: 20) }, sleep: sleeper.sleep,
      beforeSave: { false })
    saver.scheduleSave(afterArchive)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { sleeper.parkedDurations == [.seconds(1)] }
    // Simulate a crash here (before the archive write succeeds): the on-disk sidebar still has `today0`.
    let recoveredBeforeArchiveWrite = try #require(try await sidebarStore.load())
    #expect(recoveredBeforeArchiveWrite.nodes[today0] != nil, "sidebar save waited for the archive write")

    // Case 2: The archive write lands first, and the app crashes before the sidebar save runs.
    _ = try await archiveStore.add([archivedT0], onConflict: .replace)
    // Simulate a crash here (between the archive write and the sidebar save) and reload on next launch:
    let archivedOnLaunch = try await archiveStore.items().items
    #expect(archivedOnLaunch == [archivedT0], "the archived item is durable in ArchiveStore")
    let sidebarOnLaunch = try #require(try await sidebarStore.load())
    #expect(sidebarOnLaunch.nodes[today0] == nil, "pending archive removal is replayed idempotently on launch")
    #expect(sidebarOnLaunch.nodes[pinned] != nil && sidebarOnLaunch.nodes[today1] != nil)
    // Replaying again (idempotent) or re-adding with `.replace` loses nothing.
    _ = try await archiveStore.add([archivedT0], onConflict: .replace)
    #expect(try await archiveStore.items().items == [archivedT0])
    #expect(try await sidebarStore.load() == afterArchive)

    // Once the sidebar save completes, the pending removal marker is cleared.
    saver.beforeSave = { true }
    sleeper.resumeNext()
    await waitUntil { !saver.hasPendingChanges }
    #expect(try await sidebarStore.load() == afterArchive)
  }
}

/// A sleep that ignores cancellation (it only records it), modelling a sleep that finished as it was cancelled.
final class UncancellableSleeper: Sendable {
  private struct State {
    var parked: [CheckedContinuation<Void, Never>] = []
    var cancelled = 0
  }

  private let state = Mutex(State())

  var parkedCount: Int { state.withLock { $0.parked.count } }
  var cancelledCount: Int { state.withLock { $0.cancelled } }

  func park() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in state.withLock { $0.parked.append(continuation) } }
    } onCancel: {
      state.withLock { $0.cancelled += 1 }
    }
  }

  func resumeAll() {
    let parked = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      defer { state.parked = [] }
      return state.parked
    }
    for continuation in parked { continuation.resume() }
  }
}
