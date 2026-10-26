import ShellUI
import SidebarModel

/// The first run's saved state, with the profile's data (onboarding spec, section 13): the version of the flow the
/// user finished (written on Start browsing and on a confirmed Skip setup) and the step reached so far.
public struct OnboardingRecord: Codable, Equatable, Sendable {
  /// The flow's version; a record below it shows the first run on a profile with no Space.
  public static let currentVersion = 1

  public var onboardingCompletedVersion = 0
  /// The step reached, saved as the user moves on; nil once finished.
  public var progress: OnboardingFlow.Snapshot?

  public init() {}

  public var isCompleted: Bool { onboardingCompletedVersion >= Self.currentVersion }

  /// Shown automatically only when the flow was never finished and the profile has no Space, or a run was left
  /// mid-flow (an import may have added Spaces since).
  public func showsAutomatically(profileHasSpaces: Bool) -> Bool {
    !isCompleted && (!profileHasSpaces || progress != nil)
  }
}

/// Serializes onboarding record writes and lets termination wait for the whole chain. The write closure owns the
/// persistence boundary and its error reporting; this type stays independent of the database.
@MainActor
public final class OnboardingRecordStore {
  public private(set) var record: OnboardingRecord
  /// True while any requested record write is still queued or running.
  public var needsFlush: Bool { writing > 0 }

  private let write: (OnboardingRecord) async -> Void
  private var lastSave: Task<Void, Never>?
  private var writing = 0

  public init(record: OnboardingRecord, write: @escaping (OnboardingRecord) async -> Void) {
    self.record = record
    self.write = write
  }

  public func saveProgress(_ snapshot: OnboardingFlow.Snapshot) {
    guard !record.isCompleted else { return }
    record.progress = snapshot
    save()
  }

  public func markCompleted() {
    record.onboardingCompletedVersion = OnboardingRecord.currentVersion
    record.progress = nil
    save()
  }

  /// Waits for the last requested save, which itself waits for every earlier save. At the deadline this returns
  /// false while the write continues in the background, so termination is never held indefinitely.
  public func flush(
    atMost timeout: Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) async -> Bool {
    guard let lastSave else { return true }
    let attempt = Task<Bool, Never> {
      await lastSave.value
      return true
    }
    return await FlushRace.run(timeout: timeout, sleep: sleep, attempt: attempt)
  }

  private func save() {
    let (value, write, previous) = (record, write, lastSave)
    writing += 1
    lastSave = Task { [weak self] in
      await previous?.value
      await write(value)
      self?.writing -= 1
    }
  }
}
