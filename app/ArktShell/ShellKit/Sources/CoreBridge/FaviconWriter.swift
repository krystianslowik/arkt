import Foundation

/// Persists favicon changes through a `FaviconStore` (decision 8). Engine changes are coalesced for `delay` and
/// written as one batch (a page that swaps its icon a few times writes once); imported favicons are written at once.
/// Batches run strictly one after another, after the `after` task (the launch prune), so a prune can never remove a
/// favicon written after launch and a later change always lands after an earlier one. Unchanged bytes are skipped
/// by the store.
@MainActor
public final class FaviconWriter {
  public static let defaultDelay: Duration = .milliseconds(500)

  /// Ids this writer was told about since it was made, until `launchLoadDidComplete()`; the launch load skips them,
  /// so a favicon read from disk never replaces a newer one the engine reported meanwhile.
  public private(set) var touched: Set<UUID> = []
  /// False after `launchLoadDidComplete()`: nothing reads `touched` any more, so it stops growing.
  private var tracksTouched = true
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

  public init(store: FaviconStore, delay: Duration = FaviconWriter.defaultDelay, after: Task<Void, Never>? = nil) {
    self.store = store
    self.delay = delay
    self.tail = after
  }

  /// An engine change (nil: cleared). Written with the next batch, at most `delay` from now.
  public func record(_ data: Data?, for id: UUID) {
    if tracksTouched { touched.insert(id) }
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
      if tracksTouched { touched.insert(id) }
      pending.updateValue(data, forKey: id)
    }
    writeBatch()
  }

  /// The launch load has applied its favicons: `touched` is cleared and no longer kept.
  public func launchLoadDidComplete() {
    tracksTouched = false
    touched = []
  }

  /// Writes what is pending and waits for every batch so far.
  public func flush() async {
    writeBatch()
    await tail?.value
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
