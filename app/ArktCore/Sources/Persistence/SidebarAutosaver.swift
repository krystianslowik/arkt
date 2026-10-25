import Foundation
import SidebarModel
import Synchronization

/// Anything that can persist a whole sidebar. `SidebarStore` conforms; tests use a recording fake.
public protocol SidebarSaving: Sendable {
  func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome
}

extension SidebarStore: SidebarSaving {}

/// Injected time: `Task.sleep(for:)` in the app, a manual sleeper in tests.
public typealias AutosaveSleep = @Sendable (Duration) async throws -> Void

/// Coalesces sidebar changes and writes the newest one in the background.
///
/// Main-actor facing and synchronous: `scheduleSave` only stores the value and arms a timer, so the main thread never
/// waits on disk; encoding and I/O happen inside the store's `@concurrent` methods. The first change opens a window of
/// `delay` (500 ms); changes inside it coalesce and the newest is written when it closes. Writes never overlap (the
/// timer-driven loop and `flush` share one `writer` slot), and the newest value is replaced synchronously on the main
/// actor, so an older in-flight write can never land after a newer one. A change during a write opens a new window
/// afterwards. A failed write keeps the newest value and retries after `retryDelays` (the last one repeats).
///
/// `flush()` is for app termination: it waits for a write already in flight (never cancels it), then makes exactly one
/// attempt with the newest value. It is bounded by `flushTimeout` (default 1 s): past it, `flush` returns false and the
/// write continues in the background, so a stuck disk can delay quitting by at most that long. `flushBlocking()` is the
/// same write for a quit whose main thread never runs again (SIGTERM, #298).
///
/// Every store call runs off the main actor, and each one starts only after the previous one returned, so the stored
/// sidebar is always the last one submitted, also when `flushBlocking` submits while a write is in flight.
@MainActor
public final class SidebarAutosaver {
  nonisolated public static let defaultDelay: Duration = .milliseconds(500)
  nonisolated public static let defaultRetryDelays: [Duration] = [
    .seconds(1), .seconds(2), .seconds(5), .seconds(15), .seconds(30),
  ]
  nonisolated public static let defaultFlushTimeout: Duration = .seconds(1)

  private let store: any SidebarSaving
  private let delay: Duration
  private let retryDelays: [Duration]
  private let flushTimeout: Duration
  private let now: @Sendable () -> Date
  private let sleep: AutosaveSleep
  /// Runs on the main actor before each save attempt (#213: the app flushes pending archive adds first so the on-disk
  /// sidebar never gets ahead of the archive store). Returning false aborts the save attempt and backs off to retry.
  public var beforeSave: @MainActor () async -> Bool

  private var pending: Sidebar?
  private var timer: Task<Void, Never>?
  /// The one write in progress: the debounced write loop or a flush attempt.
  private var writer: Task<Void, Never>?
  /// The last store call submitted. The next one waits for it, so saves reach the store in submission order.
  private var storeCall: Task<Result<SaveOutcome, any Error>, Never>?
  /// Counts submitted store calls; a failed save is not retried when a newer one was submitted after it.
  private var submissions = 0
  /// True while the write loop sleeps between retries; only then may `flush` cancel it.
  private var isBackingOff = false
  /// Set by `flush`: the write loop stops after its current attempt instead of backing off.
  private var stopRequested = false

  public private(set) var lastError: (any Error)?
  public private(set) var consecutiveFailures = 0
  public var hasPendingChanges: Bool { pending != nil }
  /// True while anything is unsaved or a write is still running. `applicationShouldTerminate` must check this (or
  /// always flush): `hasPendingChanges` alone is false while the last change is being written.
  public var needsFlush: Bool { pending != nil || writer != nil }

  public init(
    store: any SidebarSaving,
    delay: Duration = SidebarAutosaver.defaultDelay,
    retryDelays: [Duration] = SidebarAutosaver.defaultRetryDelays,
    flushTimeout: Duration = SidebarAutosaver.defaultFlushTimeout,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping AutosaveSleep = { try await Task.sleep(for: $0) },
    beforeSave: @escaping @MainActor () async -> Bool = { true }
  ) {
    precondition(!retryDelays.isEmpty, "retryDelays must not be empty")
    self.store = store
    self.delay = delay
    self.retryDelays = retryDelays
    self.flushTimeout = flushTimeout
    self.now = now
    self.sleep = sleep
    self.beforeSave = beforeSave
  }

  /// Records `sidebar` as the newest state. Never blocks and never awaits.
  public func scheduleSave(_ sidebar: Sidebar) {
    pending = sidebar
    if timer == nil, writer == nil { armTimer() }
  }

  /// Writes the newest pending sidebar now: cancels the timer and any retry wait, waits for a write in flight, then
  /// makes exactly one attempt. Returns true when nothing is left unsaved; false when the attempt failed, a change
  /// arrived meanwhile, or `flushTimeout` passed first (the write then finishes in the background). For
  /// `applicationShouldTerminate` (`.terminateLater`).
  ///
  /// Recommended termination handling (do not use `applicationWillTerminate`, which cannot wait):
  ///
  /// ```swift
  /// func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  ///   guard autosaver.needsFlush else { return .terminateNow }
  ///   Task { @MainActor in
  ///     _ = await autosaver.flush()  // bounded by flushTimeout
  ///     sender.reply(toApplicationShouldTerminate: true)  // always true: never block quitting on a failed save
  ///   }
  ///   return .terminateLater
  /// }
  /// ```
  ///
  /// While a `.terminateLater` reply is outstanding AppKit runs the main run loop in `NSModalPanelRunLoopMode`, which
  /// still drains main-actor jobs, so the `Task` above makes progress. Verify manually at app integration.
  @discardableResult
  public func flush() async -> Bool {
    await FlushRace.run(timeout: flushTimeout, sleep: sleep, attempt: Task { await self.flushNow() })
  }

  /// `flush()` for a quit whose main thread never runs a main-actor job again (#298: Chromium's SIGTERM path blocks the
  /// main thread right after the quit-start seam, then exits). Submits the newest pending sidebar after the store call
  /// in flight, if any, and blocks the calling thread until it returns or `flushTimeout` passes. Returns true when
  /// nothing is left unsaved; false when the save failed or timed out (the sidebar stays pending; a timed-out save may
  /// still land, and any later save is submitted after it). Does not run `beforeSave`: the caller flushes what must
  /// reach the disk first (#213: `ArchiveCoordinator.flushBlocking()`).
  @discardableResult
  public func flushBlocking() -> Bool {
    timer?.cancel()
    timer = nil
    defer { if pending != nil, timer == nil, writer == nil { armTimer() } }  // a cancelled quit keeps saving
    guard let sidebar = pending else {
      guard let inFlight = storeCall else { return true }
      return BlockingFlush.run(timeout: flushTimeout) { await inFlight.value.isSuccess } ?? false
    }
    let call = submitSave(sidebar, at: now()).call
    switch BlockingFlush.run(timeout: flushTimeout, { await call.value }) {
    case .success?:
      pending = nil
      lastError = nil
      consecutiveFailures = 0
      return true
    case .failure(let error)?:
      lastError = error
      consecutiveFailures += 1
      return false
    case nil:
      return false
    }
  }

  private func flushNow() async -> Bool {
    timer?.cancel()
    timer = nil
    while let running = writer {
      stopRequested = true
      if isBackingOff { running.cancel() }
      await running.value
    }
    stopRequested = false
    timer?.cancel()
    timer = nil
    guard pending != nil else { return true }
    let attempt = Task { await self.writeOnce() }
    writer = attempt
    await attempt.value
    return pending == nil
  }

  private func armTimer() {
    let (sleep, delay) = (self.sleep, self.delay)
    timer = Task { [weak self] in
      do { try await sleep(delay) } catch { return }  // cancelled by flush
      guard !Task.isCancelled else { return }  // flush cancelled it after the sleep ended
      self?.timerFired()
    }
  }

  private func timerFired() {
    timer = nil
    guard writer == nil, pending != nil else { return }
    writer = Task { [weak self] in await self?.writeLoop() }
  }

  /// Takes the newest value and saves it after `beforeSave()` succeeds. Returns false and keeps the value pending when
  /// `beforeSave()` or the store save fails, unless a newer value arrived meanwhile.
  private func attemptSave() async -> Bool {
    guard pending != nil else { return true }
    guard await beforeSave() else {
      consecutiveFailures += 1
      return false
    }
    guard let sidebar = pending else { return true }
    pending = nil
    let (call, number) = submitSave(sidebar, at: now())
    let result = await call.value
    // `flushBlocking` submitted a newer value after this one: its outcome is the one that counts.
    guard number == submissions else { return true }
    switch result {
    case .success:
      lastError = nil
      consecutiveFailures = 0
      return true
    case .failure(let error):
      if pending == nil { pending = sidebar }  // keep the newest value, never an older one
      lastError = error
      consecutiveFailures += 1
      return false
    }
  }

  /// Starts a store call for `sidebar` off the main actor, after the previous one returned. Detached: it must run while
  /// the main thread is blocked in `flushBlocking`.
  private func submitSave(_ sidebar: Sidebar, at date: Date)
    -> (call: Task<Result<SaveOutcome, any Error>, Never>, number: Int)
  {
    let (store, previous) = (self.store, storeCall)
    let call = Task.detached { () -> Result<SaveOutcome, any Error> in
      _ = await previous?.value
      do {
        return .success(try await store.save(sidebar, at: date))
      } catch {
        return .failure(error)
      }
    }
    storeCall = call
    submissions += 1
    return (call, submissions)
  }

  private func writeOnce() async {
    _ = await attemptSave()
    finishWrite()
  }

  private func writeLoop() async {
    while pending != nil {
      if await attemptSave() { break }
      if stopRequested { break }
      let wait = retryDelays[min(consecutiveFailures - 1, retryDelays.count - 1)]
      isBackingOff = true
      do { try await sleep(wait) } catch {
        isBackingOff = false
        break  // cancelled by flush
      }
      isBackingOff = false
      if Task.isCancelled { break }  // flush cancelled it just as the sleep ended: flush makes the attempt
    }
    finishWrite()
  }

  /// Frees the writer slot; a change that arrived during the write gets its own window.
  private func finishWrite() {
    writer = nil
    if pending != nil, timer == nil, !stopRequested { armTimer() }
  }
}

extension Result {
  fileprivate var isSuccess: Bool {
    if case .success = self { true } else { false }
  }
}
