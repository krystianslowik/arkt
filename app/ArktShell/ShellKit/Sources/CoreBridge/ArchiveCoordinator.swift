import Archive
import Foundation
import SidebarModel
import Synchronization

/// Archives and restores sidebar items (decision 11: the model first, then an outbox to the archive store).
///
/// `archive` removes the nodes from the sidebar synchronously, so the user action never waits on disk, and queues the
/// entries. A single writer sends each batch to the store right away (`.replace`, not debounced); on failure the
/// entries stay in memory and the writer retries after `retryDelays` (the last one repeats), so an archived item
/// never vanishes because the store was unavailable. `restore` inserts into the model first and only then removes the
/// entry from the store; a failed remove leaves a harmless duplicate in the archive and is not retried.
///
/// `flush()` is for termination: it stops a retry wait, waits for a write in flight and makes one attempt, bounded
/// by `flushTimeout`. Residual risk (documented in the plan): a crash after the sidebar save but before a failing
/// archive write finally succeeds loses that entry.
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

  /// Archived entries not yet written to the store, oldest first.
  public private(set) var pendingItems: [ArchivedItem] = []
  /// True while an entry is unwritten or a write is still running. Termination must check this (or always flush).
  public var hasPendingWrites: Bool { !pendingItems.isEmpty || writer != nil }

  private let source: ModelSidebarSource
  private let store: any ArchiveStoring
  private let now: @MainActor () -> Date
  private let flushTimeout: Duration
  private let sleep: Sleep

  /// The one write loop (or flush attempt) in progress.
  private var writer: Task<Void, Never>?
  /// The store write in progress; a restore waits for it before removing, so a late add cannot resurrect an entry.
  private var inFlight: Task<Bool, Never>?
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
  /// store. Returns the entries. Whether a node may be archived at all (pinned, Favorites) is the caller's decision.
  @discardableResult
  public func archive(_ ids: [UUID], reason: ArchiveReason) -> [ArchivedItem] {
    let items = source.archive(ids, reason: reason, at: now())
    guard !items.isEmpty else { return [] }
    pendingItems += items
    startWriter(delayFirst: false)
    return items
  }

  /// Puts `item` back into the sidebar (`Archiver.restore` rules: top of Today in its source Space, folders at the
  /// end of Pinned, fresh ids when an id is taken), then removes it from the store. `fallbackSpace` is used when the
  /// source Space is gone; when it is nil or gone too, the first Space is used. Throws `.noSpaceForRestore` when the
  /// sidebar has no Space, and the model's `SidebarError`s; nothing changes on throw.
  public func restore(_ item: ArchivedItem, fallbackSpace: UUID?) throws -> RestoredItem {
    let sidebar = source.sidebar
    let fallback = fallbackSpace.flatMap { sidebar.spaces[$0] == nil ? nil : $0 } ?? sidebar.spaceOrder.first
    guard let fallback else { throw RestoreError.noSpaceForRestore }
    let restored = try source.restore(item, fallbackSpace: fallback)
    pendingItems.removeAll { $0.id == item.id }
    let (store, write, id) = (store, inFlight, item.id)
    Task {
      _ = await write?.value
      try? await store.remove([id])  // a failure leaves a harmless duplicate in the archive
    }
    return restored
  }

  // MARK: - Flush

  /// Writes everything pending now: stops a retry wait, waits for a write in flight, then makes exactly one attempt.
  /// Returns true when nothing is left unwritten; false when the attempt failed, an entry arrived meanwhile, or
  /// `flushTimeout` passed first (the write then finishes in the background). Unwritten entries stay pending and the
  /// writer keeps retrying.
  @discardableResult
  public func flush() async -> Bool {
    let attempt = Task { await self.flushNow() }
    let race = FlushRace()
    let (sleep, timeout) = (self.sleep, self.flushTimeout)
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      race.arm(continuation)
      let deadline = Task {
        do { try await sleep(timeout) } catch { return }
        race.finish(false)
      }
      Task {
        let written = await attempt.value
        deadline.cancel()
        race.finish(written)
      }
    }
  }

  private func flushNow() async -> Bool {
    while let running = writer {
      stopRequested = true
      if isBackingOff { running.cancel() }
      await running.value
    }
    stopRequested = false
    guard !pendingItems.isEmpty else { return true }
    let attempt = Task { await self.attemptWrite() }
    writer = Task { _ = await attempt.value }
    let written = await attempt.value
    writer = nil
    startWriter(delayFirst: !written)  // keeps retrying what is still pending, after a backoff when this failed
    return written && pendingItems.isEmpty
  }

  // MARK: - Writer

  private func startWriter(delayFirst: Bool) {
    guard writer == nil, !pendingItems.isEmpty else { return }
    writer = Task { [weak self] in await self?.writeLoop(delayFirst: delayFirst) }
  }

  private func writeLoop(delayFirst: Bool) async {
    var backOff = delayFirst
    while !pendingItems.isEmpty {
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
      if await attemptWrite() {
        backOff = false
        continue  // entries archived during the write go next
      }
      if stopRequested { break }
      backOff = true
    }
    writer = nil
  }

  /// Sends a snapshot of the pending entries; on success drops exactly those entries (an entry restored and archived
  /// again meanwhile is a different value and stays).
  private func attemptWrite() async -> Bool {
    let batch = pendingItems
    guard !batch.isEmpty else { return true }
    let store = self.store
    let write = Task { () -> Bool in
      do {
        _ = try await store.add(batch, onConflict: .replace)
        return true
      } catch {
        return false
      }
    }
    inFlight = write
    let written = await write.value
    inFlight = nil
    if written {
      let done = Set(batch)
      pendingItems.removeAll { done.contains($0) }
      consecutiveFailures = 0
    } else {
      consecutiveFailures += 1
    }
    return written
  }
}

/// Resumes the `flush` continuation exactly once: with the attempt's result or, at the deadline, with false.
private final class FlushRace: Sendable {
  private let continuation = Mutex<CheckedContinuation<Bool, Never>?>(nil)

  func arm(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation.withLock { $0 = continuation }
  }

  func finish(_ written: Bool) {
    continuation.withLock { $0.take() }?.resume(returning: written)
  }
}
