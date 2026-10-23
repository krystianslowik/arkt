import Archive
import Foundation
import SidebarModel
import Synchronization

/// Archives and restores sidebar items (decision 11: the model first, then an outbox to the archive store).
///
/// `archive` removes the nodes from the sidebar synchronously, so the user action never waits on disk, and queues an
/// add of the entries; `restore` inserts into the model first and then queues a remove of the entry. The outbox is a
/// FIFO of store operations drained by a single writer, one at a time, so a restore followed by a re-archive of the
/// same id always reaches the store as add, remove, add and the new entry survives. Consecutive adds go as one
/// `.replace` batch, right away (not debounced).
///
/// On failure the operation stays at the head of the outbox and the writer retries after `retryDelays` (the last one
/// repeats), so an archived item never vanishes because the store was unavailable. A failed remove is retried the
/// same way, except for ids a later queued add of the same id supersedes: that `.replace` add overwrites the entry
/// anyway, so those ids are dropped and the add goes next instead of waiting behind a retry. Outside a flush, a remove
/// that keeps failing therefore holds back every add queued behind it (FIFO) until it succeeds.
///
/// Restoring an entry whose add was never sent (queued behind a write in flight or a retrying remove) only drops it
/// from the outbox: no store call can have written it. When an add holding the id was sent (in flight, failed or
/// written) or a remove of the id failed, the entry may be in the store and the restore queues a remove as usual.
/// `onPendingItemsChange` reports every change of `pendingItems`, so the Archive window can list them (#88).
///
/// `flush()` is for termination: it stops a retry wait, waits for a write in flight, then sends the outbox in order
/// until it is empty or an add fails, bounded by `flushTimeout`. A remove that fails during the flush is dropped (a
/// harmless duplicate in the archive), so it cannot hold back an add queued behind it at quit.
///
/// Crash and quit durability (#213): `archive` and `removeSpace` enqueue their entries into the outbox before
/// `source.onDidChange` fires, and `flushPendingAdds()` gates `SidebarAutosaver.beforeSave` so the on-disk sidebar
/// never gets ahead of the archive store. If the process dies before the archive write lands, the items remain in
/// `SidebarStore`; if it dies after the archive write and before `SidebarStore.save`, `ArchiveStore` holds the entries
/// and `SidebarStore.load()` replays the pending removals idempotently on launch.
@MainActor
public final class ArchiveCoordinator {
  public enum RestoreError: Error, Equatable, Sendable {
    /// The sidebar has no Space to put the item in.
    case noSpaceForRestore
  }

  /// Injected time: `Task.sleep(for:)` in the app, a manual sleeper in tests.
  public typealias Sleep = @Sendable (Duration) async throws -> Void

  nonisolated public static let retryDelays: [Duration] = [
    .seconds(1), .seconds(2), .seconds(5), .seconds(15), .seconds(30),
  ]
  nonisolated public static let defaultFlushTimeout: Duration = .seconds(1)

  /// One store call waiting in the outbox.
  private enum Operation {
    case add([ArchivedItem])
    case remove([NodeID])
  }

  /// Archived entries not yet written to the store, oldest first.
  public var pendingItems: [ArchivedItem] {
    outbox.flatMap { operation -> [ArchivedItem] in
      if case .add(let items) = operation { items } else { [] }
    }
  }

  /// Called on the main actor after `pendingItems` changed: an archive, a restore that dropped a pending entry, or a
  /// write that landed. One observer: the Archive window's list model sets it.
  public var onPendingItemsChange: (@MainActor () -> Void)?

  /// True while an add or remove is unsent or a write is still running. Termination must check this (or always
  /// flush).
  public var hasPendingWrites: Bool { !outbox.isEmpty || writer != nil }

  private let source: ModelSidebarSource
  private let store: any ArchiveStoring
  private let now: @MainActor () -> Date
  private let flushTimeout: Duration
  private let sleep: Sleep

  /// Store operations in the order they must reach the store; only the writer sends them.
  private var outbox: [Operation] = []
  /// Ids restored and not archived again since; restoring one of them again is a no-op.
  private var restoredIDs: Set<NodeID> = []
  /// Ids this coordinator may have left in the store: sent in an add, or named by a remove that failed. A
  /// successful remove takes them out. Restoring a pending entry whose id is not here needs no store remove.
  private var mayBeStored: Set<NodeID> = []
  /// The one write loop (or flush attempt) in progress.
  private var writer: Task<Void, Never>?
  private var consecutiveFailures = 0
  /// True while the write loop sleeps between retries; only then may `flush` cancel it.
  private var isBackingOff = false
  /// Set by `flush`: the write loop stops after its current attempt instead of backing off.
  private var stopRequested = false

  public init(
    source: ModelSidebarSource,
    store: any ArchiveStoring,
    now: @escaping @MainActor () -> Date = { Date() },
    flushTimeout: Duration = ArchiveCoordinator.defaultFlushTimeout,
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.source = source
    self.store = store
    self.now = now
    self.flushTimeout = flushTimeout
    self.sleep = sleep
  }

  // MARK: - Archive and restore

  /// Removes `ids` (unknown ones are skipped) from the sidebar in one mutation and queues their entries for the
  /// store before `source.onDidChange` runs (#213). Returns the entries. Whether a node may be archived at all
  /// (pinned, Favorites) is the caller's decision.
  @discardableResult
  public func archive(_ ids: [UUID], reason: ArchiveReason) -> [ArchivedItem] {
    source.archive(ids, reason: reason, at: now(), beforeDidChange: enqueue)
  }

  /// Queues an add of freshly archived `items`; nothing for an empty list.
  private func enqueue(_ items: [ArchivedItem]) {
    guard !items.isEmpty else { return }
    restoredIDs.subtract(items.map(\.id))
    outbox.append(.add(items))
    startWriter(delayFirst: false)
    onPendingItemsChange?()
  }

  /// Removes Space `id` from the sidebar (decision on #86: its pinned and Today items are archived, reason `.manual`)
  /// and queues the entries for the store before `source.onDidChange` runs (#213). Returns the entries; an unknown id
  /// changes nothing.
  @discardableResult
  public func removeSpace(_ id: UUID) -> [ArchivedItem] {
    source.removeSpace(id, at: now(), beforeDidChange: enqueue)
  }

  /// One auto-archive pass (BH-080, BH-084, BH-054, BH-048, BH-083): archives, with reason `.auto`, the Today tabs
  /// `AutoArchivePolicy` picks for `settings`' per-profile thresholds, idle time clamped to `startedAt`, minus
  /// `exempt` (visible tabs; media-playing ones once the engine reports them, BH-076). Returns what was archived;
  /// the caller shows the BH-085 toast when it is not empty.
  @discardableResult
  public func runAutoArchive(startedAt: Date, settings: ArchiveSettings, exempt: Set<UUID>) -> [ArchivedItem] {
    let input = AutoArchiveInput(
      now: now(), startedAt: startedAt, exempt: exempt, threshold: { settings.tabThreshold(forProfile: $0) })
    let ids = AutoArchivePolicy.itemsToArchive(in: source.sidebar, input)
    guard !ids.isEmpty else { return [] }
    return archive(ids, reason: .auto)
  }

  /// Puts `item` back into the sidebar (`Archiver.restore` rules: top of Today in its source Space, folders at the
  /// end of Pinned, fresh ids when an id is taken), then queues its removal from the store, unless it was pending and
  /// never sent (see the type comment). `fallbackSpace` is used when the source Space is gone; when it is nil or gone
  /// too, the first Space is used. Returns nil and changes nothing when `item.id` was already restored and not
  /// archived again since (a repeated click). Throws `.noSpaceForRestore` when the sidebar has no Space, and the
  /// model's `SidebarError`s; nothing changes on throw.
  @discardableResult
  public func restore(_ item: ArchivedItem, fallbackSpace: UUID?) throws -> RestoredItem? {
    guard !restoredIDs.contains(item.id) else { return nil }
    let sidebar = source.sidebar
    let fallback = fallbackSpace.flatMap { sidebar.spaces[$0] == nil ? nil : $0 } ?? sidebar.spaceOrder.first
    guard let fallback else { throw RestoreError.noSpaceForRestore }
    let restored = try source.restore(item, fallbackSpace: fallback)
    restoredIDs.insert(item.id)
    let wasPending = dropUnsentAdds(of: item.id)
    // Queued whenever a store call may have written the entry: a failed add may still have landed, and an extra
    // remove is harmless.
    if !wasPending || mayBeStored.contains(item.id) {
      outbox.append(.remove([item.id]))
      startWriter(delayFirst: false)
    }
    if wasPending { onPendingItemsChange?() }
    return restored
  }

  // MARK: - Flush

  /// Ensures every queued archive add has been written to the store before a sidebar snapshot that dropped those
  /// items is saved (#213). Returns true immediately when no add is pending, and false when an add could not be
  /// written within `flushTimeout` (the sidebar save then backs off and retries so the on-disk sidebar never gets
  /// ahead of the archive store).
  public func flushPendingAdds() async -> Bool {
    guard !pendingItems.isEmpty else { return true }
    return await flush() && pendingItems.isEmpty
  }

  /// Sends everything pending now: stops a retry wait, waits for a write in flight, then sends the outbox in order
  /// until it is empty or an add fails (a failing remove is dropped). Returns true when nothing is left unsent; false
  /// when an add failed, an operation arrived meanwhile, or `flushTimeout` passed first (the write then finishes in the background).
  /// Unsent operations stay queued and the writer keeps retrying.
  @discardableResult
  public func flush() async -> Bool {
    await FlushRace.run(timeout: flushTimeout, sleep: sleep, attempt: Task { await self.flushNow() })
  }

  private func flushNow() async -> Bool {
    while let running = writer {
      stopRequested = true
      if isBackingOff { running.cancel() }
      await running.value
    }
    stopRequested = false
    guard !outbox.isEmpty else { return true }
    let attempt = Task { () -> Bool in
      while !self.outbox.isEmpty {
        guard await self.sendNext(droppingFailedRemove: true) else { return false }
      }
      return true
    }
    writer = Task { _ = await attempt.value }
    let written = await attempt.value
    writer = nil
    startWriter(delayFirst: !written)  // keeps retrying what is still queued, after a backoff when this failed
    return written && outbox.isEmpty
  }

  // MARK: - Writer

  private func startWriter(delayFirst: Bool) {
    guard writer == nil, !outbox.isEmpty else { return }
    writer = Task { [weak self] in await self?.writeLoop(delayFirst: delayFirst) }
  }

  private func writeLoop(delayFirst: Bool) async {
    var backOff = delayFirst
    while !outbox.isEmpty {
      if backOff {
        let delay = Self.retryDelays[min(max(consecutiveFailures, 1) - 1, Self.retryDelays.count - 1)]
        isBackingOff = true
        do { try await sleep(delay) } catch {
          isBackingOff = false
          break  // cancelled by flush
        }
        isBackingOff = false
        if Task.isCancelled || stopRequested { break }  // flush makes the attempt
      }
      if await sendNext(droppingFailedRemove: false) {
        backOff = false
        continue  // operations queued during the write go next
      }
      if stopRequested { break }
      backOff = true
    }
    // Unconditional: this loop is the writer. Only `flushNow` installs another one, and it waits for this loop to
    // finish first, so this never clears a newer writer.
    writer = nil
  }

  /// Sends the operation at the head of the outbox (the leading adds as one batch). Returns false when it failed and
  /// is still queued; with `droppingFailedRemove` (flush) a failed remove is dropped instead.
  private func sendNext(droppingFailedRemove: Bool) async -> Bool {
    guard let head = outbox.first else { return true }
    switch head {
    case .add:
      return await sendLeadingAdds()
    case .remove(let ids):
      return await sendRemove(ids, droppingOnFailure: droppingFailedRemove)
    }
  }

  /// Sends a snapshot of the leading adds; on success drops exactly those entries from them (an entry restored
  /// meanwhile is already gone, and a re-archived one sits behind its remove).
  private func sendLeadingAdds() async -> Bool {
    let leading = outbox.prefix { if case .add = $0 { true } else { false } }.count
    let batch = pendingItems(inFirst: leading)
    mayBeStored.formUnion(batch.map(\.id))
    let store = self.store
    let written = await Task { () -> Bool in
      do {
        _ = try await store.add(batch, onConflict: .replace)
        return true
      } catch {
        return false
      }
    }.value
    guard written else { return recordFailure() }
    // Only the adds still leading the outbox: during the write a restore can put a remove in front of a newer add
    // (even one equal to a written entry), so the count taken before the write is stale.
    let done = Set(batch)
    for index in outbox.indices {
      guard case .add(let items) = outbox[index] else { break }
      outbox[index] = .add(items.filter { !done.contains($0) })
    }
    dropEmptyAdds()
    consecutiveFailures = 0
    if !batch.isEmpty { onPendingItemsChange?() }
    return true
  }

  /// Sends the head remove. On failure, ids that a later queued add of the same id supersedes are dropped (that
  /// `.replace` add overwrites the entry); the rest stay at the head for a retry after a backoff, or are dropped too
  /// when `droppingOnFailure`.
  private func sendRemove(_ ids: [NodeID], droppingOnFailure: Bool) async -> Bool {
    let store = self.store
    let removed = await Task { () -> Bool in
      do {
        try await store.remove(ids)
        return true
      } catch {
        return false
      }
    }.value
    if removed {
      outbox.removeFirst()
      mayBeStored.subtract(ids)
      consecutiveFailures = 0
      return true
    }
    mayBeStored.formUnion(ids)
    let superseded = Set(pendingItems.map(\.id))
    let remaining = ids.filter { !superseded.contains($0) }
    guard remaining.isEmpty || droppingOnFailure else {
      outbox[0] = .remove(remaining)
      return recordFailure()
    }
    outbox.removeFirst()
    return true
  }

  private func recordFailure() -> Bool {
    consecutiveFailures += 1
    return false
  }

  private func pendingItems(inFirst count: Int) -> [ArchivedItem] {
    outbox.prefix(count).flatMap { operation -> [ArchivedItem] in
      if case .add(let items) = operation { items } else { [] }
    }
  }

  /// Removes `id` from every add not yet sent; an add in flight is a snapshot and is not affected. True when an add
  /// held it.
  private func dropUnsentAdds(of id: NodeID) -> Bool {
    var dropped = false
    for index in outbox.indices {
      guard case .add(let items) = outbox[index] else { continue }
      let kept = items.filter { $0.id != id }
      dropped = dropped || kept.count != items.count
      outbox[index] = .add(kept)
    }
    dropEmptyAdds()
    return dropped
  }

  private func dropEmptyAdds() {
    outbox.removeAll { operation in
      if case .add(let items) = operation { items.isEmpty } else { false }
    }
  }
}
