import Foundation
import Testing
@testable import Persistence

struct RecoveryPageStateTests {
  @Test func recordsSurviveDatabaseReopenAndCleanQuitClearing() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let source = UUID()
      let peek = RecoveryPageRecord(title: "Peek", url: URL(string: "https://example.invalid/peek")!,
                                    kind: .peek, sourceNode: source)
      let little = RecoveryPageRecord(title: "Window", url: URL(string: "https://example.invalid/little")!,
                                      kind: .littleArkt, sourceNode: nil)
      let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
      do {
        let database = try ArktDatabase.open(at: url)
        let settings = SettingsStore(database: database)
        try await settings.save(RecoveryPageState(pages: [peek, little]), at: date)
        try database.close()
      }
      do {
        let database = try ArktDatabase.open(at: url)
        let settings = SettingsStore(database: database)
        #expect(try await settings.load(RecoveryPageState.self).pages == [peek, little])
        try await settings.save(RecoveryPageState(pages: []), at: date.addingTimeInterval(1))
        try database.close()
      }
      let database = try ArktDatabase.open(at: url)
      defer { try? database.close() }
      #expect(try await SettingsStore(database: database).load(RecoveryPageState.self).pages.isEmpty)
    }
  }
}

@MainActor
struct RecoveryPageWriterTests {
  private func state(_ title: String) -> RecoveryPageState {
    RecoveryPageState(pages: [RecoveryPageRecord(title: title, url: URL(string: "https://example.invalid")!,
                                                 kind: .littleArkt)])
  }

  @Test func writesInSubmissionOrderAndFlushesNewest() async {
    let store = ControlledRecoveryStore()
    let writer = RecoveryPageWriter(store: store, initial: .defaultValue)
    writer.schedule(state("first"))
    await store.waitForFirst()
    writer.schedule(state("second"))
    #expect(await store.titles == ["first"])
    await store.releaseFirst()
    #expect(await writer.flush())
    let titles = await store.titles
    #expect(titles.first == "first")
    #expect(titles.last == "second")
    #expect(!writer.needsFlush)
  }

  @Test func failedWriteStaysPendingAndFlushRetries() async {
    let store = ControlledRecoveryStore(failFirst: true)
    let writer = RecoveryPageWriter(store: store, initial: .defaultValue)
    writer.schedule(state("retry"))
    await store.waitForFirst()
    await store.releaseFirst()
    for _ in 0..<10_000 {
      if writer.lastWriteFailed { break }
      await Task.yield()
    }
    #expect(writer.lastWriteFailed)
    #expect(writer.needsFlush)
    #expect(await writer.flush())
    #expect(!writer.needsFlush)
    #expect(!writer.lastWriteFailed)
  }
}

private actor ControlledRecoveryStore: RecoveryPageSaving {
  enum Failure: Error { case first }
  private(set) var titles: [String] = []
  private var started: CheckedContinuation<Void, Never>?
  private var gate: CheckedContinuation<Void, Never>?
  private var firstStarted = false
  private let failFirst: Bool
  init(failFirst: Bool = false) { self.failFirst = failFirst }

  func saveRecoveryPages(_ state: RecoveryPageState) async throws {
    titles.append(state.pages.first?.title ?? "")
    if titles.count == 1 {
      firstStarted = true
      started?.resume()
      started = nil
      await withCheckedContinuation { gate = $0 }
      if failFirst { throw Failure.first }
    }
  }

  func waitForFirst() async {
    if firstStarted { return }
    await withCheckedContinuation { started = $0 }
  }

  func releaseFirst() { gate?.resume(); gate = nil }
}
