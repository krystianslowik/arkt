import EngineAPI
import Foundation

/// What a change to the list was, for a view that retargets its own piece.
public enum DownloadsChange: Equatable, Sendable {
  case created(DownloadItem)
  case updated(DownloadItem)
  case removed(DownloadID)
  /// The Library was opened and the dot cleared.
  case seen
}

/// A subscription to the model; delivery stops on `cancel()` or when it is released.
@MainActor
public final class DownloadsObservation {
  private var onCancel: (@MainActor () -> Void)?
  init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }
  public func cancel() { onCancel?(); onCancel = nil }
  isolated deinit { onCancel?() }
}

/// The shell's view of the engine's downloads (design/downloads): one per app, shared by every window's Library button,
/// the popover and the Library window. It mirrors the engine's list, works out the ring's state and the unseen dot,
/// turns Cancel into cancel-and-remove, keeps the VoiceOver announcements to 25, 50 and 75 percent and the end, and
/// pushes the saved location to the engine. It holds no timers and draws nothing, so everything here is testable with the
/// in-memory engine and no window.
@MainActor
public final class DownloadsModel: AppSettingsObserver {
  public let engine: any EngineDownloads
  /// The list in creation order.
  public private(set) var items: [DownloadItem]
  /// Said politely to VoiceOver: a quarter, a half, three quarters, finished, failed or blocked. Never every tick.
  public var onAnnouncement: (@MainActor (String) -> Void)?
  /// A plain notice for a toast ("Saved to Downloads. The chosen folder is unavailable.").
  public var onNotice: (@MainActor (String) -> Void)?

  private let settings: AppSettings?
  private var observation: EngineObservation?
  private var handlers: [(key: UUID, deliver: @MainActor (DownloadsChange) -> Void)] = []
  /// Items that finished, failed or were held since the Library was last opened.
  private var unseen: Set<DownloadID> = []
  private var announcedBucket: [DownloadID: Int] = [:]
  private var announcedEnd: Set<DownloadID> = []

  public init(engine: any EngineDownloads, settings: AppSettings? = nil) {
    self.engine = engine
    self.settings = settings
    items = engine.downloads
    for item in items where item.state.isFinished { announcedEnd.insert(item.id) }
    applyLocation()
    settings?.addObserver(self)
    observation = engine.observeDownloads { [weak self] event in self?.handle(event) }
  }

  // MARK: Reading

  /// The list, newest first.
  public var newestFirst: [DownloadItem] { items.reversed() }

  /// The newest `limit` downloads (the popover lists six).
  public func recent(limit: Int = 6) -> [DownloadItem] { Array(newestFirst.prefix(limit)) }

  public var activeItems: [DownloadItem] { items.filter { $0.state.isActive } }

  public func item(_ id: DownloadID) -> DownloadItem? { items.first { $0.id == id } }

  /// The Library button's state: the whole's progress while anything runs, else a dot for what finished, failed or is
  /// held since the Library was opened.
  public var ringState: DownloadsRingState {
    let active = activeItems
    if !active.isEmpty {
      let known = active.compactMap { item in item.totalBytes.map { (item.receivedBytes, $0) } }
      let total = known.reduce(Int64(0)) { $0 + $1.1 }
      guard total > 0 else { return .active(fraction: nil) }
      let received = known.reduce(Int64(0)) { $0 + min($1.0, $1.1) }
      return .active(fraction: Double(received) / Double(total))
    }
    let pending = items.filter { unseen.contains($0.id) }
    if pending.isEmpty { return .idle }
    return pending.contains { needsAttention($0) } ? .attention : .done
  }

  /// The dot is showing.
  public var hasUnseen: Bool { !unseen.isEmpty }

  private func needsAttention(_ item: DownloadItem) -> Bool {
    if item.dangerType.needsSheet { return true }
    if case .interrupted = item.state { return true }
    return false
  }

  // MARK: Observers

  public func addObserver(_ handler: @escaping @MainActor (DownloadsChange) -> Void) -> DownloadsObservation {
    let key = UUID()
    handlers.append((key, handler))
    return DownloadsObservation { [weak self] in self?.handlers.removeAll { $0.key == key } }
  }

  private func emit(_ change: DownloadsChange) {
    for handler in handlers { handler.deliver(change) }
  }

  /// The Library opened: the dot goes.
  public func markSeen() {
    guard !unseen.isEmpty else { return }
    unseen = []
    emit(.seen)
  }

  // MARK: Commands

  /// Cancel on a row: cancels at once and removes it, with no confirmation (the partial file goes).
  public func cancel(_ id: DownloadID) {
    engine.perform(.cancel, on: id)
    engine.perform(.remove, on: id)
  }

  public func pause(_ id: DownloadID) { engine.perform(.pause, on: id) }
  public func resume(_ id: DownloadID) { engine.perform(.resume, on: id) }
  public func open(_ id: DownloadID) { engine.perform(.open, on: id) }
  public func showInFinder(_ id: DownloadID) { engine.perform(.showInFinder, on: id) }
  public func retry(_ id: DownloadID) { engine.perform(.retry, on: id) }
  public func keep(_ id: DownloadID) { engine.perform(.keepDangerous, on: id) }
  public func discard(_ id: DownloadID) { engine.perform(.discardDangerous, on: id) }
  public func remove(_ id: DownloadID) { engine.perform(.remove, on: id) }

  /// Clear List: removes every finished row from the list and leaves the files. A file held for a decision stays: it
  /// still needs an answer.
  public func clearList() {
    for item in items where item.state.isFinished && !item.dangerType.needsSheet { engine.perform(.remove, on: item.id) }
  }

  // MARK: Engine events

  private func handle(_ event: DownloadEvent) {
    switch event {
    case .downloadCreated(let item):
      items.append(item)
      noteFallback(item)
      noteState(item, previous: nil)
      emit(.created(item))
    case .downloadUpdated(let item):
      guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
      let previous = items[index]
      items[index] = item
      noteState(item, previous: previous)
      emit(.updated(item))
    case .downloadRemoved(let id):
      items.removeAll { $0.id == id }
      unseen.remove(id)
      announcedBucket[id] = nil
      announcedEnd.remove(id)
      emit(.removed(id))
    }
  }

  /// Unseen bookkeeping and the announcements for one change.
  private func noteState(_ item: DownloadItem, previous: DownloadItem?) {
    let wasFinished = previous.map { $0.state.isFinished } ?? false
    let wasBlocked = previous?.dangerType.needsSheet ?? false
    if item.dangerType.needsSheet, !wasBlocked {
      unseen.insert(item.id)
      announce("\(item.filename) blocked")
    }
    switch item.state {
    case .complete where !wasFinished:
      unseen.insert(item.id)
      if announcedEnd.insert(item.id).inserted, !item.dangerType.needsSheet { announce("\(item.filename) finished") }
    case .interrupted where !wasFinished:
      unseen.insert(item.id)
      if announcedEnd.insert(item.id).inserted { announce("\(item.filename) failed") }
    case .cancelled:
      unseen.remove(item.id)                       // the user's own cancel is no news
    case .inProgress:
      let bucket = DownloadsFormat.announcementBucket(fraction: item.fraction)
      if bucket > (announcedBucket[item.id] ?? 0) {
        announcedBucket[item.id] = bucket
        announce("\(item.filename), \(bucket) percent")
      }
    default:
      break
    }
  }

  private func announce(_ text: String) { onAnnouncement?(text) }

  // MARK: Location

  /// A download that did not land in the chosen folder was saved to the default one.
  private func noteFallback(_ item: DownloadItem) {
    guard case .folder(let chosen) = engine.downloadSavePreference, let target = item.targetPath,
          chosen.standardizedFileURL != engine.downloadDefaultFolder.standardizedFileURL,
          target.deletingLastPathComponent().standardizedFileURL != chosen.standardizedFileURL else { return }
    onNotice?("Saved to \(engine.downloadDefaultFolder.lastPathComponent). The chosen folder is unavailable.")
  }

  /// The saved location is the engine's preference.
  private func applyLocation() {
    guard let settings else { return }
    engine.downloadSavePreference = settings.downloadLocation.preference(defaultFolder: engine.downloadDefaultFolder)
  }

  public func appSettingsDidChange(_ settings: AppSettings) { applyLocation() }
}
