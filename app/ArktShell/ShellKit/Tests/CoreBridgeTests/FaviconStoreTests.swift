import CoreBridge
import Foundation
import Testing

struct FaviconStoreTests {
  static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])

  /// A fresh temp directory; `body` gets a not-yet-created `Favicons` folder inside it.
  static func withTempDirectory(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FaviconStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root.appendingPathComponent("Favicons", isDirectory: true))
  }

  @Test func savedFaviconsLoadBackForRequestedIDsOnly() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let id = UUID()
      let other = UUID()
      let unrequested = UUID()
      try await store.save([id: Self.png, unrequested: Self.png])
      #expect(await store.loadAll(for: [id, other]) == [id: Self.png])
      #expect(FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("\(id.uuidString).png").path))
    }
  }

  @Test func saveReplacesAnExistingFavicon() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let id = UUID()
      try await store.save([id: Self.png])
      try await store.save([id: Data([1, 2, 3])])
      #expect(await store.loadAll(for: [id]) == [id: Data([1, 2, 3])])
    }
  }

  @Test func loadAllFromAMissingDirectoryIsEmpty() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      #expect(await store.loadAll(for: [UUID()]).isEmpty)
    }
  }

  @Test func pruneRemovesOnlyFaviconsNotKept() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let kept = UUID()
      let dropped = UUID()
      try await store.save([kept: Self.png, dropped: Self.png])
      let unrelated = ["notes.txt", "not-a-uuid.png", "\(UUID().uuidString).jpg"]
      for name in unrelated {
        try Data("x".utf8).write(to: directory.appendingPathComponent(name))
      }
      await store.prune(keeping: [kept])
      #expect(await store.loadAll(for: [kept, dropped]) == [kept: Self.png])
      await store.prune(keeping: [])
      #expect(await store.loadAll(for: [kept]).isEmpty)
      let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
      #expect(left == unrelated.sorted())
    }
  }

  @Test(arguments: [
    "Library/Application Support/Arc/Favicons",
    "Library/Application Support/Arc",
    "Library/Application Support/Arc/",
  ])
  func refusesADirectoryInsideArcsFolder(_ relative: String) {
    // Synthetic path under the temp directory: nothing is created or read.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(relative, isDirectory: true)
    #expect(throws: FaviconStoreError.forbiddenDirectory) { try FaviconStore(directory: directory) }
  }

  @Test func removeDeletesOnlyTheGivenFavicons() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let (kept, removed, missing) = (UUID(), UUID(), UUID())
      try await store.save([kept: Self.png, removed: Self.png])
      await store.remove([removed, missing])
      #expect(await store.loadAll(for: [kept, removed]) == [kept: Self.png])
    }
  }

  /// Calls on one store run one at a time, in the order they are awaited: a later save wins over an earlier one and a
  /// remove in between, and concurrent saves of different ids all land.
  @Test func laterSaveWinsAndConcurrentSavesAllLand() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let id = UUID()
      try await store.save([id: Data([1])])
      await store.remove([id])
      try await store.save([id: Data([2])])
      try await store.save([id: Data([3])])
      #expect(await store.loadAll(for: [id]) == [id: Data([3])])

      let ids = (0..<24).map { _ in UUID() }
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, other) in ids.enumerated() {
          group.addTask { try await store.save([other: Data([UInt8(index)])]) }
        }
        try await group.waitForAll()
      }
      let loaded = await store.loadAll(for: Set(ids))
      #expect(loaded.count == ids.count)
      for (index, other) in ids.enumerated() { #expect(loaded[other] == Data([UInt8(index)])) }
    }
  }

  @Test func savingTheSameBytesLeavesTheFileAlone() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      let id = UUID()
      let file = directory.appendingPathComponent("\(id.uuidString).png")
      try await store.save([id: Self.png])
      let before = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
      try await store.save([id: Self.png])
      let after = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
      #expect(before != nil && before == after)   // an atomic write would have replaced the inode
    }
  }

  @Test func createsTheDirectoryOwnerOnly() async throws {
    try await Self.withTempDirectory { directory in
      let store = try FaviconStore(directory: directory)
      try await store.save([UUID(): Self.png])
      let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
      #expect(mode == 0o700)
    }
  }

  /// A symlink whose target is inside an Arc folder is refused even though the given path does not say "Arc".
  @Test func refusesASymlinkIntoArcsFolder() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FaviconStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let arc = root.appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
    try FileManager.default.createDirectory(at: arc, withIntermediateDirectories: true)
    let link = root.appendingPathComponent("data", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: arc)
    #expect(throws: FaviconStoreError.forbiddenDirectory) {
      try FaviconStore(directory: link.appendingPathComponent("Favicons", isDirectory: true))
    }
    #expect(throws: FaviconStoreError.forbiddenDirectory) { try FaviconStore(directory: link) }
  }

  @Test func acceptsAFolderWhoseNameOnlyStartsWithArc() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Library/Application Support/Arkt/Favicons", isDirectory: true)
    #expect(try FaviconStore(directory: directory).directory == directory)
  }
}
