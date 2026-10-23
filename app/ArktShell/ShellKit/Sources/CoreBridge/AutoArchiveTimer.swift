import Archive
import Foundation

/// Runs `ArchiveCoordinator.runAutoArchive` once at start and then every `interval` (Track E, Task E5d).
///
/// `start()` resolves the auto-archive start (`ArchiveState.autoArchiveStartedAt`, set once on first use) and loads
/// the archive settings from the store, off the main actor, then ticks at once and keeps ticking until `stop()`. The
/// settings are read once per start; there is no settings UI yet (BH-081 to BH-083 are a later track).
///
/// The clock only moves forward: an Arc import that adds a Space resets it to the import time (plan decision 7) and
/// reports that through `clockDidReset(to:)`, which applies to the next tick even while `start()` is still loading.
@MainActor
public final class AutoArchiveTimer {
  public typealias Sleep = ArchiveCoordinator.Sleep

  /// Arc checks idle tabs continuously; a minute is well below the shortest threshold (1 hour, BH-081).
  nonisolated public static let defaultInterval: Duration = .seconds(60)

  /// The start of the auto-archive clock: the later of the stored start and any reset reported meanwhile; nil until
  /// either is known.
  public private(set) var startedAt: Date?
  public private(set) var settings = ArchiveSettings()
  /// True between a successful `start()` and `stop()`.
  public var isRunning: Bool { loop != nil }
  /// Ids never archived this tick: the tabs visible in the window. Read on every tick. BH-076 (media-playing tabs)
  /// joins here once the engine reports audio state.
  public var exempt: @MainActor () -> Set<UUID> = { [] }
  /// Called with what a tick archived, only when it archived something (the BH-085 toast).
  public var onArchived: (@MainActor ([ArchivedItem]) -> Void)?

  private let coordinator: ArchiveCoordinator
  private let state: any ArchiveStateStoring
  private let interval: Duration
  private let now: @MainActor () -> Date
  private let sleep: Sleep
  private var loop: Task<Void, Never>?
  private var isStarting = false
  /// The stored clock start and the settings are loaded; no tick archives before that.
  private var isLoaded = false
  /// Set by `stop()`: no tick archives afterwards, and a `start()` still loading does not begin the loop.
  private var stopRequested = false

  public init(
    coordinator: ArchiveCoordinator,
    state: any ArchiveStateStoring,
    interval: Duration = AutoArchiveTimer.defaultInterval,
    now: @escaping @MainActor () -> Date = { Date() },
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.coordinator = coordinator
    self.state = state
    self.interval = interval
    self.now = now
    self.sleep = sleep
  }

  /// Loads the clock start and the settings, ticks once, then ticks every `interval`. Throws the store's error and
  /// then never ticks. A call while starting or running does nothing; a `stop()` during the load wins.
  public func start() async throws {
    guard loop == nil, !isStarting else { return }
    isStarting = true
    stopRequested = false
    defer { isStarting = false }
    let resolved = try await state.resolveAutoArchiveStart(now: now())
    let loaded = try await state.loadArchiveSettings()
    settings = loaded
    clockDidReset(to: resolved)
    isLoaded = true
    guard !stopRequested else { return }
    tick()
    let (sleep, interval) = (self.sleep, self.interval)
    loop = Task { [weak self] in
      while true {
        do { try await sleep(interval) } catch { return }  // cancelled by stop()
        guard let self, !Task.isCancelled else { return }
        self.tick()
      }
    }
  }

  /// Ends the timer, also while `start()` is still loading; no tick archives afterwards. Termination calls it before
  /// the flush, so nothing is archived between the sidebar write and the outbox write.
  public func stop() {
    stopRequested = true
    loop?.cancel()
    loop = nil
  }

  /// Moves the clock start to `date` when that is later than the current one (an Arc import reset it).
  public func clockDidReset(to date: Date) {
    startedAt = max(startedAt ?? date, date)
  }

  /// One pass now. Archives nothing until `start()` loaded the clock start and the settings. Returns what was
  /// archived.
  @discardableResult
  public func tick() -> [ArchivedItem] {
    guard isLoaded, !stopRequested, let startedAt else { return [] }
    let archived = coordinator.runAutoArchive(startedAt: startedAt, settings: settings, exempt: exempt())
    if !archived.isEmpty { onArchived?(archived) }
    return archived
  }
}
