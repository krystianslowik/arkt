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

  @Test func removeSpaceQueuesItsPinnedAndTodayItems() async throws {
    let harness = try Harness(todayTabs: 2)
    let items = harness.coordinator.removeSpace(harness.space)
    #expect(items.map(\.id) == [harness.pinned] + harness.today)
    #expect(harness.source.spaceOrder.isEmpty)
    #expect(harness.changes == [.spaceRemoved(harness.space)])
    #expect(harness.coordinator.pendingItems == items)
    await harness.drain()
    #expect(await harness.store.addCalls == [.init(ids: items.map(\.id), policy: .replace)])
  }

  /// #213: `pendingItems` is populated before `source.onDidChange` fires, and `flushPendingAdds()` holds back a
  /// sidebar save while the archive write is failing or in flight, so a crash between the two writes never loses
  /// archived items (for both `archive` and `removeSpace`).
  @Test func crashBetweenArchiveWriteAndSidebarSaveLosesNoItems() async throws {
    let harness = try Harness(todayTabs: 2)
    var onDiskSidebar = harness.source.sidebar
    var pendingAtDidChange: [[ArchivedItem]] = []
    harness.source.onDidChange = { [unowned harness] _ in
      harness.didChangeCount += 1
      pendingAtDidChange.append(harness.coordinator.pendingItems)
    }

    // 1. Archive write fails when the sidebar save tries to run, then the app crashes before retry.
    await harness.store.setFailsAdds(true)
    let archivedTab = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    #expect(pendingAtDidChange.last == [archivedTab], "outbox holds the entry before onDidChange schedules a save")
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    // Sidebar save gates on `flushPendingAdds()`: while the archive write fails, the sidebar save does not run.
    let canSaveSidebarWhileFailing = await harness.coordinator.flushPendingAdds()
    #expect(!canSaveSidebarWhileFailing)
    if canSaveSidebarWhileFailing { onDiskSidebar = harness.source.sidebar }
    // Simulate a crash here: `today[0]` is still in the on-disk sidebar, so nothing is lost.
    #expect(onDiskSidebar.nodes[harness.today[0]] != nil)

    // 2. Archive write succeeds (Write 1), then the app crashes before the sidebar save (Write 2) lands.
    await harness.store.setFailsAdds(false)
    #expect(await harness.coordinator.flushPendingAdds())
    // Simulate a crash here, between Write 1 (archive store) and Write 2 (sidebar save):
    #expect(await harness.store.stored[archivedTab.id] == archivedTab, "entry is already durable in the archive store")
    #expect(onDiskSidebar.nodes[archivedTab.id] != nil, "still in the on-disk sidebar until Write 2 lands")
    // Replaying the archive on the next launch is idempotent (`.replace`).
    let relaunchedSource = ModelSidebarSource(sidebar: onDiskSidebar, now: { Self.now })
    let relaunchedCoordinator = ArchiveCoordinator(source: relaunchedSource, store: harness.store, now: { Self.now })
    let rearchived = relaunchedCoordinator.archive([archivedTab.id], reason: .manual)
    await eventually { !relaunchedCoordinator.hasPendingWrites }
    #expect(rearchived == [archivedTab])
    #expect(await harness.store.stored[archivedTab.id] == archivedTab)

    // Now Write 2 lands for `archive`, and `removeSpace` follows the same rule.
    onDiskSidebar = harness.source.sidebar
    await harness.store.setFailsAdds(true)
    let spaceItems = harness.coordinator.removeSpace(harness.space)
    #expect(spaceItems.map(\.id) == [harness.pinned, harness.today[1]])
    #expect(pendingAtDidChange.last == [archivedTab] + spaceItems || pendingAtDidChange.last == spaceItems)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    #expect(await harness.coordinator.flushPendingAdds() == false)
    // Crash before the Space's archive write lands: the Space and its items are still in `onDiskSidebar`.
    #expect(onDiskSidebar.spaces[harness.space] != nil)
    #expect(onDiskSidebar.nodes[harness.pinned] != nil && onDiskSidebar.nodes[harness.today[1]] != nil)

    await harness.store.setFailsAdds(false)
    #expect(await harness.coordinator.flushPendingAdds())
    onDiskSidebar = harness.source.sidebar
    #expect(onDiskSidebar.spaces.isEmpty)
    for item in spaceItems {
      #expect(await harness.store.stored[item.id] == item)
    }
  }

  @Test func removingAnEmptySpaceQueuesNothing() async throws {
    let harness = try Harness(todayTabs: 0)
    let empty = try harness.source.addSpace(title: "Empty")
    #expect(harness.coordinator.removeSpace(empty).isEmpty)
    #expect(harness.source.spaceOrder == [harness.space])
    #expect(!harness.coordinator.hasPendingWrites)
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

  /// The post-write cleanup stops at the first non-add: an add queued behind a remove while the batch was in flight
  /// is not mistaken for a written one, even when it equals a written entry (same id, same clock).
  @Test func anEqualAddQueuedBehindARemoveDuringTheWriteIsStillSent() async throws {
    let harness = try Harness(todayTabs: 3)
    await harness.store.holdAdds()
    let first = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    let middle = try #require(harness.coordinator.archive([harness.today[1]], reason: .manual).first)
    harness.coordinator.archive([harness.today[2]], reason: .manual)
    await eventually { await harness.store.addCalls.count == 1 }
    #expect(await harness.store.addCalls.first?.ids == harness.today)

    _ = try harness.coordinator.restore(first, fallbackSpace: nil)
    let second = try #require(harness.coordinator.archive([first.id], reason: .manual).first)
    #expect(second == first)
    _ = try harness.coordinator.restore(middle, fallbackSpace: nil)
    await harness.store.releaseAdds()
    await harness.drain()

    #expect(await harness.store.calls == [
      .add(harness.today), .remove([first.id]), .add([first.id]), .remove([middle.id]),
    ])
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

  /// #88: an entry whose add was never sent (queued behind a write in flight) cannot be in the store, so restoring it
  /// only drops it from the outbox.
  @Test func restoringAnUnsentPendingItemSendsNoRemove() async throws {
    let harness = try Harness(todayTabs: 2)
    await harness.store.holdAdds()
    let first = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    await eventually { await harness.store.addCalls.count == 1 }
    let second = try #require(harness.coordinator.archive([harness.today[1]], reason: .manual).first)
    #expect(harness.coordinator.pendingItems == [first, second])

    _ = try harness.coordinator.restore(second, fallbackSpace: nil)

    #expect(harness.coordinator.pendingItems == [first])
    #expect(harness.source.node(second.id) != nil)
    await harness.store.releaseAdds()
    await harness.drain()
    #expect(await harness.store.calls == [.add([first.id])])
    #expect(await harness.store.stored[second.id] == nil)
  }

  /// A remove dropped at a flush leaves the entry (here one from an earlier launch) in the store; a later unsent add
  /// of the same id that is restored still sends a remove, so that entry does not linger.
  @Test func restoreAfterADroppedRemoveStillRemoves() async throws {
    let harness = try Harness(todayTabs: 1)
    var other = SidebarModel.Sidebar()
    let otherSpace = other.addSpace(title: "Earlier")
    let tab = try other.addTab(url: Self.url, title: "Earlier", in: .today(otherSpace))
    let item = ArchivedItem(
      reason: .manual, archivedAt: Self.now.addingTimeInterval(-3600), source: .space(harness.space),
      section: .today, snapshot: try #require(other.snapshot(of: tab)))
    _ = try await harness.store.add([item], onConflict: .replace)
    await harness.store.setFailsRemoves(true)
    _ = try harness.coordinator.restore(item, fallbackSpace: nil)
    await eventually { harness.sleeper.parkedDurations == [.seconds(1)] }
    #expect(await harness.coordinator.flush())
    #expect(await harness.store.stored[item.id] != nil)
    await harness.store.setFailsRemoves(false)

    await harness.store.holdAdds()
    harness.coordinator.archive([harness.today[0]], reason: .manual)
    await eventually { await harness.store.addCalls.count == 2 }
    let again = try #require(harness.coordinator.archive([item.id], reason: .manual).first)
    _ = try harness.coordinator.restore(again, fallbackSpace: nil)
    await harness.store.releaseAdds()
    await harness.drain()

    #expect(await harness.store.calls.suffix(2) == [.add([harness.today[0]]), .remove([item.id])])
    #expect(await harness.store.stored[item.id] == nil)
  }

  /// #88: the Archive window refreshes on this: an archive, a restore that drops a pending entry, a landed write.
  @Test func pendingItemsChangeIsReported() async throws {
    let harness = try Harness(todayTabs: 2)
    var reports = 0
    harness.coordinator.onPendingItemsChange = { reports += 1 }
    await harness.store.holdAdds()

    let first = try #require(harness.coordinator.archive([harness.today[0]], reason: .manual).first)
    #expect(reports == 1)
    await eventually { await harness.store.addCalls.count == 1 }
    let second = try #require(harness.coordinator.archive([harness.today[1]], reason: .manual).first)
    #expect(reports == 2)
    _ = try harness.coordinator.restore(second, fallbackSpace: nil)
    #expect(reports == 3)

    await harness.store.releaseAdds()
    await harness.drain()
    #expect(reports == 4)
    #expect(harness.coordinator.pendingItems.isEmpty)

    _ = try harness.coordinator.restore(first, fallbackSpace: nil)  // a stored entry: the pending list is unchanged
    await harness.drain()
    #expect(reports == 4)
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

  // MARK: - Auto-archive (E5d)

  /// Ids of an auto-archive sidebar: Today tabs, pinned tabs, a Favorite and a foldered tab, all in Space "Work"
  /// of `profile` unless noted.
  private struct AutoArchiveIDs {
    var space: UUID
    var today: [UUID]
    var pinned: [UUID]
    var favorite: UUID
    var foldered: UUID
  }

  /// One Space with Today tabs idle `idleHours` (top first), pinned tabs idle `pinnedIdleHours`, a Favorite and a
  /// Today folder holding one tab, both idle 400 h. Idle means `lastActiveAt = now - hours`.
  private static func sidebarWithTodayTabs(
    idleHours: [Double], pinnedIdleHours: [Double] = [], profile: String = "default", now: Date
  ) throws -> (ModelSidebarSource, AutoArchiveIDs) {
    let source = ModelSidebarSource(now: { now })
    let ago = { (hours: Double) in now.addingTimeInterval(-hours * 3600) }
    let ids = try source.mutate { sidebar -> AutoArchiveIDs in
      let space = sidebar.addSpace(title: "Work", profile: profile)
      let old = ago(400)
      let today = try idleHours.map {
        try sidebar.addTab(url: url, title: "T", lastActiveAt: ago($0), in: .today(space), createdAt: old)
      }
      let pinned = try pinnedIdleHours.map {
        try sidebar.addTab(url: url, title: "P", lastActiveAt: ago($0), in: .pinned(space), createdAt: old)
      }
      let favorite = try sidebar.addTab(
        url: url, title: "F", lastActiveAt: old, in: .favorites(profile: profile), createdAt: old)
      let folder = try sidebar.addFolder(title: "Folder", in: .today(space), createdAt: old)
      let foldered = try sidebar.addTab(url: url, title: "In", lastActiveAt: old, in: .folder(folder), createdAt: old)
      return AutoArchiveIDs(space: space, today: today, pinned: pinned, favorite: favorite, foldered: foldered)
    }
    return (source, ids)
  }

  @Test func autoArchiveUsesPolicyClampAndExemptions() async throws {  // BH-080, BH-084, BH-054, BH-048
    let now = Self.now
    let (source, ids) = try Self.sidebarWithTodayTabs(idleHours: [13, 2, 40], pinnedIdleHours: [400], now: now)
    let store = FakeArchiveStore()
    let coordinator = ArchiveCoordinator(source: source, store: store, now: { now })

    let archived = coordinator.runAutoArchive(
      startedAt: now.addingTimeInterval(-100 * 3600), settings: ArchiveSettings(), exempt: [ids.today[2]])

    #expect(archived.map(\.id) == [ids.today[0]])  // 13 h idle; 2 h too fresh; 40 h exempt; pinned never
    #expect(archived.allSatisfy { $0.reason == .auto })
    #expect(archived.allSatisfy { $0.archivedAt == now })
    let sidebar = source.sidebar
    #expect(sidebar.children(of: .today(ids.space)).prefix(2) == [ids.today[1], ids.today[2]])
    for kept in ids.pinned + [ids.favorite, ids.foldered] { #expect(sidebar.nodes[kept] != nil) }
    let drained = coordinator
    await eventually { !drained.hasPendingWrites }
    #expect(await store.addCalls == [.init(ids: [ids.today[0]], policy: .replace)])
  }

  @Test func startedAtClampProtectsFreshImports() throws {  // plan decision 7
    let now = Self.now
    let (source, ids) = try Self.sidebarWithTodayTabs(idleHours: [400, 400], now: now)
    let coordinator = ArchiveCoordinator(source: source, store: FakeArchiveStore(), now: { now })

    let archived = coordinator.runAutoArchive(
      startedAt: now.addingTimeInterval(-3600), settings: ArchiveSettings(), exempt: [])

    #expect(archived.isEmpty)
    #expect(source.sidebar.children(of: .today(ids.space)).prefix(2) == ids.today[...])
    #expect(!coordinator.hasPendingWrites)
  }

  @Test func perProfileThreshold() throws {  // BH-083, BH-179
    let now = Self.now
    let (source, defaultIDs) = try Self.sidebarWithTodayTabs(idleHours: [2], now: now)
    let workTab = try source.mutate { sidebar -> UUID in
      let work = sidebar.addSpace(title: "Other", profile: "work")
      return try sidebar.addTab(
        url: Self.url, title: "W", lastActiveAt: now.addingTimeInterval(-2 * 3600), in: .today(work),
        createdAt: now.addingTimeInterval(-2 * 3600))
    }
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    let coordinator = ArchiveCoordinator(source: source, store: FakeArchiveStore(), now: { now })

    let archived = coordinator.runAutoArchive(startedAt: .distantPast, settings: settings, exempt: [])

    #expect(archived.map(\.id) == [workTab])  // the default profile keeps 12 h
    #expect(source.sidebar.nodes[defaultIDs.today[0]] != nil)
  }

  @Test func neverThresholdArchivesNothing() throws {  // BH-081
    let now = Self.now
    let (source, _) = try Self.sidebarWithTodayTabs(idleHours: [400], now: now)
    var settings = ArchiveSettings()
    settings.setTabThreshold(.never, forProfile: "default", scope: .thisProfile)
    let coordinator = ArchiveCoordinator(source: source, store: FakeArchiveStore(), now: { now })

    #expect(coordinator.runAutoArchive(startedAt: .distantPast, settings: settings, exempt: []).isEmpty)
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
