import ArcImport
import Archive
import Foundation
import SidebarModel
import Synchronization

/// A small sidebar distinguishable by `title` (Space title and a Today tab title).
public enum TestSidebars {
  public static func make(_ title: String) -> Sidebar {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: title)
    _ = try? sidebar.addTab(url: URL(string: "https://example.com/\(title)")!, title: title, in: .today(space))
    return sidebar
  }
}

/// A clock the tests move by hand.
@MainActor
public final class TestClock {
  public var now: Date

  public init(_ now: Date) { self.now = now }
}

/// A manual stand-in for `Task.sleep`: each call parks until the test resumes it, or throws `CancellationError` when
/// its task is cancelled (also when cancelled before it parked). Shared by ArktCore and ShellKit tests (#93).
public final class ManualSleeper: Sendable {
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

  public init() {}

  public var sleep: @Sendable (Duration) async throws -> Void {
    { [self] duration in try await self.park(duration) }
  }
  public var parkedCount: Int { state.withLock { $0.parked.count } }
  public var parkedDurations: [Duration] { state.withLock { $0.parked.map(\.duration) } }

  /// Resumes the oldest parked sleeper.
  public func resumeNext() {
    let parked = state.withLock { $0.parked.isEmpty ? nil : $0.parked.removeFirst() }
    parked?.continuation.resume()
  }

  /// Resumes the parked sleeper with `duration` (the oldest one if several).
  public func resume(_ duration: Duration) {
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

/// A sleep that ignores cancellation (it only records it), modelling a sleep that finished as it was cancelled.
public final class UncancellableSleeper: Sendable {
  private struct State {
    var parked: [CheckedContinuation<Void, Never>] = []
    var cancelled = 0
  }

  private let state = Mutex(State())

  public init() {}

  public var parkedCount: Int { state.withLock { $0.parked.count } }
  public var cancelledCount: Int { state.withLock { $0.cancelled } }

  public func park() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in state.withLock { $0.parked.append(continuation) } }
    } onCancel: {
      state.withLock { $0.cancelled += 1 }
    }
  }

  public func resumeAll() {
    let parked = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      defer { state.parked = [] }
      return state.parked
    }
    for continuation in parked { continuation.resume() }
  }
}

public struct FakeStoreError: Error, Equatable, Sendable {
  public init() {}
}

/// In-memory `ArchiveStoring` that honors the conflict policy, so a repeated `.keepExisting` add writes 0.
public actor FakeArchiveStore: ArchiveStoring {
  public struct AddCall: Equatable, Sendable {
    public var ids: [NodeID]
    public var policy: ArchiveConflictPolicy

    public init(ids: [NodeID], policy: ArchiveConflictPolicy) {
      self.ids = ids
      self.policy = policy
    }
  }

  /// Every store call in arrival order.
  public enum Call: Equatable, Sendable {
    case add([NodeID])
    case remove([NodeID])
    case removeAll
  }

  public private(set) var calls: [Call] = []
  public private(set) var addCalls: [AddCall] = []
  public private(set) var addedItems: [[ArchivedItem]] = []
  public private(set) var removeCalls: [[NodeID]] = []
  public private(set) var stored: [NodeID: ArchivedItem] = [:]
  private var failsAdds = false
  private var failsRemoves = false
  private var holdsAdds = false
  private var heldAdds: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func setFailsAdds(_ fails: Bool) { failsAdds = fails }
  public func setFailsRemoves(_ fails: Bool) { failsRemoves = fails }
  /// While true, `add` parks after recording the call until `releaseAdds()`.
  public func holdAdds() { holdsAdds = true }

  public func releaseAdds() {
    holdsAdds = false
    for held in heldAdds { held.resume() }
    heldAdds = []
  }

  public func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int {
    addCalls.append(AddCall(ids: items.map(\.id), policy: policy))
    calls.append(.add(items.map(\.id)))
    addedItems.append(items)
    if holdsAdds { await withCheckedContinuation { heldAdds.append($0) } }
    if failsAdds { throw FakeStoreError() }
    var written = 0
    for item in items {
      if policy == .keepExisting, stored[item.id] != nil { continue }
      stored[item.id] = item
      written += 1
    }
    return written
  }

  public func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage {
    let items = stored.values.filter(filter.matches).sorted { $0.archivedAt > $1.archivedAt }
    return ArchivePage(items: limit.map { Array(items.prefix($0)) } ?? items, unreadable: 0)
  }

  public func remove(_ ids: [NodeID]) async throws {
    removeCalls.append(ids)
    calls.append(.remove(ids))
    if failsRemoves { throw FakeStoreError() }
    for id in ids { stored[id] = nil }
  }

  public func count(matching filter: ArchiveFilter) async throws -> Int {
    stored.values.filter(filter.matches).count
  }

  public func removeAll() async throws {
    calls.append(.removeAll)
    if failsRemoves { throw FakeStoreError() }
    stored = [:]
  }
}

/// In-memory `ArchiveStateStoring` that records every clock reset. The resolved start is the last reset, else the
/// stored start (`setStarted`), else `now` (which is then stored, like `SettingsStore`).
public actor FakeArchiveState: ArchiveStateStoring {
  public private(set) var resets: [Date] = []
  public private(set) var educationBannerDismissed = false
  private var started: Date?
  private var settings = ArchiveSettings()
  private var failsResets = false
  private var failsLoads = false
  private var holdsLoads = false
  private var heldLoads: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func setFailsResets(_ fails: Bool) { failsResets = fails }
  public func setFailsLoads(_ fails: Bool) { failsLoads = fails }
  public func setStarted(_ date: Date) { started = date }
  public func setSettings(_ settings: ArchiveSettings) { self.settings = settings }

  /// While true, `resolveAutoArchiveStart` parks until `releaseLoads()`.
  public func holdLoads() { holdsLoads = true }
  public var heldLoadCount: Int { heldLoads.count }

  public func releaseLoads() {
    holdsLoads = false
    for held in heldLoads { held.resume() }
    heldLoads = []
  }

  public func resolveAutoArchiveStart(now: Date) async throws -> Date {
    if holdsLoads { await withCheckedContinuation { heldLoads.append($0) } }
    if failsLoads { throw FakeStoreError() }
    if let last = resets.last { return last }
    if started == nil { started = now }
    return started ?? now
  }

  public func resetAutoArchiveStart(to date: Date) async throws {
    if failsResets { throw FakeStoreError() }
    resets.append(date)
  }

  public func loadArchiveSettings() async throws -> ArchiveSettings {
    if failsLoads { throw FakeStoreError() }
    return settings
  }
}

/// In-memory `ArcImportRecordStoring` that unions like `SettingsStore` and records every write.
public actor FakeArcImportRecordStore: ArcImportRecordStoring {
  public private(set) var stored: ArcImportRecord
  public private(set) var writes: [ArcImportRecord] = []
  private var failsLoads = false
  private var failsWrites = false

  public init(_ stored: ArcImportRecord = ArcImportRecord()) { self.stored = stored }

  public func setFailsLoads(_ fails: Bool) { failsLoads = fails }
  public func setFailsWrites(_ fails: Bool) { failsWrites = fails }

  public func loadArcImportRecord() async throws -> ArcImportRecord {
    if failsLoads { throw FakeStoreError() }
    return stored
  }

  public func recordArcImport(_ record: ArcImportRecord, at date: Date) async throws {
    if failsWrites { throw FakeStoreError() }
    writes.append(record)
    stored.formUnion(record)
  }
}

/// Stands in for the app's autosaver flush: remembers each sidebar it was asked to save and returns `succeeds`.
@MainActor
public final class FakeSidebarPersist {
  public var succeeds = true
  public private(set) var saved: [Sidebar] = []

  public init() {}

  public func persist(_ sidebar: Sidebar) async -> Bool {
    saved.append(sidebar)
    return succeeds
  }
}

/// BH-089: the education banner flag, in memory.
extension FakeArchiveState: ArchiveBannerStoring {
  public func isEducationBannerDismissed() async throws -> Bool { educationBannerDismissed }
  public func dismissEducationBanner(at date: Date) async throws { educationBannerDismissed = true }
}
