import Foundation
import SidebarModel

/// A shell-owned page whose source, when present, is a persisted sidebar node UUID.
public struct RecoveryPageRecord: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case littleArkt, peek }
  public var title: String
  public var url: URL
  public var kind: Kind
  public var sourceNode: UUID?

  public init(title: String, url: URL, kind: Kind, sourceNode: UUID? = nil) {
    self.title = title
    self.url = url
    self.kind = kind
    self.sourceNode = sourceNode
  }
}

public struct RecoveryPageState: SettingsGroup, Equatable {
  public static let storageKey = "recovery.pages"
  public static var defaultValue: Self { Self(pages: []) }
  public var pages: [RecoveryPageRecord]
  public init(pages: [RecoveryPageRecord] = []) { self.pages = pages }
}

/// Serializes submissions even when a blocking quit flush races an earlier write.
public protocol RecoveryPageSaving: Sendable {
  func saveRecoveryPages(_ state: RecoveryPageState) async throws
}

extension SettingsStore: RecoveryPageSaving {
  public func saveRecoveryPages(_ state: RecoveryPageState) async throws {
    try await save(state, at: .now)
  }
}

@MainActor
public final class RecoveryPageWriter {
  private let store: any RecoveryPageSaving
  private let timeout: Duration
  private var current: RecoveryPageState
  private var lastCall: Task<Bool, Never>?
  private var generation = 0
  private var savedGeneration = 0
  private var submission = 0
  public var onFailure: (@MainActor () -> Void)?
  public private(set) var lastWriteFailed = false
  public var needsFlush: Bool { generation != savedGeneration }

  public init(store: any RecoveryPageSaving, initial: RecoveryPageState, timeout: Duration = .seconds(1)) {
    self.store = store
    self.current = initial
    self.timeout = timeout
  }

  public func schedule(_ state: RecoveryPageState) {
    guard state != current else { return }
    current = state
    generation += 1
    let (call, number) = submit(state)
    Task { [weak self] in
      let success = await call.value
      self?.complete(number, success: success)
    }
  }

  public func flush() async -> Bool {
    guard needsFlush else { return true }
    let (call, number) = submit(current)
    let attempt = Task { await call.value }
    let success = await FlushRace.run(timeout: timeout, sleep: { try await Task.sleep(for: $0) }, attempt: attempt)
    complete(number, success: success)
    return success && !needsFlush
  }

  public func flushBlocking() -> Bool {
    guard needsFlush else { return true }
    let (call, number) = submit(current)
    let success = BlockingFlush.run(timeout: timeout) { await call.value } ?? false
    complete(number, success: success)
    return success && !needsFlush
  }

  private func submit(_ state: RecoveryPageState) -> (Task<Bool, Never>, Int) {
    let previous = lastCall
    let store = self.store
    submission += 1
    let number = submission
    let call = Task.detached { () -> Bool in
      _ = await previous?.value
      do { try await store.saveRecoveryPages(state); return true } catch { return false }
    }
    lastCall = call
    return (call, number)
  }

  private func complete(_ number: Int, success: Bool) {
    guard number == submission else { return }
    lastWriteFailed = !success
    if success { savedGeneration = generation } else { onFailure?() }
  }
}
