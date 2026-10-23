import CoreBridge
import Foundation
import Testing

@MainActor
struct FaviconWriterTests {
  static let a = Data([0x89, 0x50, 1])
  static let b = Data([0x89, 0x50, 2])

  static func withStore(_ body: (FaviconStore, URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FaviconWriterTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Favicons", isDirectory: true)
    try await body(try FaviconStore(directory: directory), directory)
  }

  @Test func coalescesChangesAndTheLastOneWins() async throws {
    try await Self.withStore { store, _ in
      let writer = FaviconWriter(store: store, delay: .seconds(60))
      let id = UUID()
      writer.record(Self.a, for: id)
      writer.record(Self.b, for: id)
      #expect(writer.needsFlush)
      await writer.flush()
      #expect(!writer.needsFlush)
      #expect(await store.loadAll(for: [id]) == [id: Self.b])
    }
  }

  @Test func writesAfterTheDelayWithoutAFlush() async throws {
    try await Self.withStore { store, _ in
      let writer = FaviconWriter(store: store, delay: .milliseconds(20))
      let id = UUID()
      writer.record(Self.a, for: id)
      for _ in 0..<200 where await store.loadAll(for: [id]).isEmpty { try await Task.sleep(for: .milliseconds(10)) }
      #expect(await store.loadAll(for: [id]) == [id: Self.a])
    }
  }

  @Test func clearedFaviconIsRemoved() async throws {
    try await Self.withStore { store, _ in
      let id = UUID()
      try await store.save([id: Self.a])
      let writer = FaviconWriter(store: store, delay: .seconds(60))
      writer.record(nil, for: id)
      await writer.flush()
      #expect(await store.loadAll(for: [id]).isEmpty)
    }
  }

  /// Writes wait for the launch prune: a favicon recorded for a node created after launch is not pruned, even though
  /// the prune's keep set (taken at launch) does not contain it.
  @Test func writesWaitForTheLaunchTask() async throws {
    try await Self.withStore { store, _ in
      let stale = UUID()
      try await store.save([stale: Self.a])
      let launch = Task {
        try? await Task.sleep(for: .milliseconds(50))
        await store.prune(keeping: [])
      }
      let writer = FaviconWriter(store: store, delay: .seconds(60), after: launch)
      let fresh = UUID()
      writer.record(Self.b, for: fresh)
      await writer.flush()
      #expect(await store.loadAll(for: [stale, fresh]) == [fresh: Self.b])
    }
  }

  @Test func batchesAreWrittenInOrder() async throws {
    try await Self.withStore { store, _ in
      let writer = FaviconWriter(store: store, delay: .seconds(60))
      let id = UUID()
      writer.save([id: Self.a])          // written right away (import)
      writer.record(nil, for: id)
      writer.save([id: Self.b])
      await writer.flush()
      #expect(await store.loadAll(for: [id]) == [id: Self.b])
      writer.save([id: Self.a])
      writer.record(nil, for: id)
      await writer.flush()
      #expect(await store.loadAll(for: [id]).isEmpty)
    }
  }

  /// A stored-favicon read leaves out ids reported (engine record or import save) from the call until it returns:
  /// the sidebar already has their newer favicon (#91: the launch load and the restore load). A later read has them.
  @Test func loadStoredSkipsIDsReportedWhileItRuns() async throws {
    try await Self.withStore { store, _ in
      let (recorded, saved, kept) = (UUID(), UUID(), UUID())
      try await store.save([recorded: Self.a, saved: Self.a, kept: Self.a])
      let writer = FaviconWriter(store: store, delay: .seconds(60))

      let load = writer.loadStored([recorded, saved, kept])
      writer.record(Self.b, for: recorded)
      writer.save([saved: Self.b])
      #expect(await load.value == [kept: Self.a])

      await writer.flush()
      #expect(await writer.loadStored([recorded, saved, kept]).value == [recorded: Self.b, saved: Self.b, kept: Self.a])
    }
  }

  /// The read does not wait for the `after` task (the launch prune): it keeps every sidebar id, and the store runs one
  /// call at a time (#91). Writes still wait for it.
  @Test func loadStoredDoesNotWaitForTheLaunchTask() async throws {
    try await Self.withStore { store, _ in
      let id = UUID()
      try await store.save([id: Self.a])
      let gate = Gate()
      let launch = Task { await gate.wait() }
      let writer = FaviconWriter(store: store, delay: .seconds(60), after: launch)

      #expect(await writer.loadStored([id]).value == [id: Self.a])

      await gate.open()
      await writer.flush()
    }
  }
}

/// Holds `wait()` until `open()`.
private actor Gate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    isOpen = true
    waiting.forEach { $0.resume() }
    waiting = []
  }
}
