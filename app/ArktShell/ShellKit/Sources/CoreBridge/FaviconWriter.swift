import Foundation

/// Persists favicon changes through a `FaviconStore` (decision 8). Engine changes are coalesced for `delay` and
/// written as one batch (a page that swaps its icon a few times writes once); imported favicons are written at once.
/// Batches run strictly one after another, after the `after` task (the launch prune), so a prune can never remove a
/// favicon written after launch and a later change always lands after an earlier one. Unchanged bytes are skipped
/// by the store.
@MainActor
public final class FaviconWriter {
  public static let defaultDelay: Duration = .milliseconds(500)

  /// True while a change is waiting for its batch or a batch is being written.
  public var needsFlush: Bool { !pending.isEmpty || writing > 0 }

  private let store: FaviconStore
  private let delay: Duration
  /// nil value: the favicon was cleared (remove the file).
  private var pending: [UUID: Data?] = [:]
  private var timer: Task<Void, Never>?
  /// The last batch (or the `after` task); every new batch awaits it first.
  private var tail: Task<Void, Never>?
  private var writing = 0
  /// Per running `loadStored` read: the ids reported since it was called, which it leaves out.
  private var reportedDuringReads: [UUID: Set<UUID>] = [:]

  public init(store: FaviconStore, delay: Duration = FaviconWriter.defaultDelay, after: Task<Void, Never>? = nil) {
    self.store = store
    self.delay = delay
    self.tail = after
  }

  /// An engine change (nil: cleared). Written with the next batch, at most `delay` from now.
  public func record(_ data: Data?, for id: UUID) {
    noteReported(id)
    pending.updateValue(data, forKey: id)
    guard timer == nil else { return }
    timer = Task { [weak self, delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.writeBatch()
    }
  }

  /// Favicons to write now (an import), together with any pending changes.
  public func save(_ favicons: [UUID: Data]) {
    for (id, data) in favicons {
      noteReported(id)
      pending.updateValue(data, forKey: id)
    }
    writeBatch()
  }

  /// The stored favicons of `ids`, for the sidebar (the launch load, a restore). Ids reported (recorded or saved)
  /// from this call until the read returns are left out, so a favicon read from disk never replaces a newer one the
  /// engine reported meanwhile; tracking starts at the call, before the read runs. The read does not wait for the
  /// `after` task: the launch prune keeps every sidebar id, and the store runs one call at a time.
  public func loadStored(_ ids: Set<UUID>) -> Task<[UUID: Data], Never> {
    let read = UUID()
    reportedDuringReads[read] = []
    return Task { [store] in
      let loaded = await store.loadAll(for: ids)
      let reported = reportedDuringReads.removeValue(forKey: read) ?? []
      return loaded.filter { !reported.contains($0.key) }
    }
  }

  /// Writes what is pending and waits for every batch so far.
  public func flush() async {
    writeBatch()
    await tail?.value
  }

  private func noteReported(_ id: UUID) {
    for read in reportedDuringReads.keys { reportedDuringReads[read]?.insert(id) }
  }

  private func writeBatch() {
    timer?.cancel()
    timer = nil
    guard !pending.isEmpty else { return }
    let batch = pending
    pending = [:]
    let saves = batch.compactMapValues { $0 }
    let removals = Set(batch.filter { $0.value == nil }.keys)
    let (store, previous) = (store, tail)
    writing += 1
    tail = Task { [weak self] in
      await previous?.value
      do { try await store.save(saves) } catch {}       // best effort: the engine reports favicons again
      await store.remove(removals)
      self?.writing -= 1
    }
  }
}
