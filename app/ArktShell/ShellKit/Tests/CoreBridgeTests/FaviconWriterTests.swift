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

  @Test func remembersWhichIDsItWasToldAbout() async throws {
    try await Self.withStore { store, _ in
      let writer = FaviconWriter(store: store, delay: .seconds(60))
      let (recorded, saved, other) = (UUID(), UUID(), UUID())
      writer.record(Self.a, for: recorded)
      writer.save([saved: Self.a])
      #expect(writer.touched == [recorded, saved])
      #expect(!writer.touched.contains(other))
      await writer.flush()
    }
  }

  @Test func touchedIsClearedAndNoLongerGrowsOnceTheLaunchLoadCompleted() async throws {
    try await Self.withStore { store, _ in
      let writer = FaviconWriter(store: store, delay: .seconds(60))
      writer.record(Self.a, for: UUID())
      writer.launchLoadDidComplete()
      #expect(writer.touched.isEmpty)
      let later = UUID()
      writer.record(Self.b, for: later)
      writer.save([UUID(): Self.a])
      #expect(writer.touched.isEmpty)
      await writer.flush()
      #expect(await store.loadAll(for: [later]) == [later: Self.b])   // writes are unaffected
    }
  }
}
