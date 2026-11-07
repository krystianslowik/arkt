import ArcImport
import CoreTestSupport
import CryptoKit
import Foundation
import Synchronization
import Testing

struct ArcProfileSnapshotTests {
  // MARK: - Helpers

  private struct Workspace {
    let base: URL
    let root: URL
    let scratch: URL
    let profile: URL
  }

  private func makeWorkspace(profiles: [String] = ["Default"]) throws -> Workspace {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
    let root = base.appendingPathComponent("User Data", isDirectory: true)
    let scratch = base.appendingPathComponent("scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    for name in profiles {
      _ = try FakeChromiumProfile.make(at: root.appendingPathComponent(name, isDirectory: true))
    }
    return Workspace(base: base, root: root, scratch: scratch, profile: root.appendingPathComponent(profiles[0]))
  }

  private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
  }

  /// Relative path to SHA-256 of every file under `directory`.
  private func hashes(of directory: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    while let url = walker?.nextObject() as? URL {
      guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
      let digest = SHA256.hash(data: try Data(contentsOf: url))
      result[String(url.path.dropFirst(directory.path.count))] = digest.map { String(format: "%02x", $0) }.joined()
    }
    return result
  }

  private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? Int ?? -1) & 0o777
  }

  private func scratchEntries(_ workspace: Workspace) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: workspace.scratch.path)) ?? []).sorted()
  }

  private struct Boom: Error {}

  // MARK: - Locating

  @Test func locatesProfileDirectoriesSortedAndIgnoresOthers() throws {
    let workspace = try makeWorkspace(profiles: ["Profile 2", "Default"])
    try FileManager.default.createDirectory(
      at: workspace.root.appendingPathComponent("Crashpad"), withIntermediateDirectories: true)
    try write("x", to: workspace.root.appendingPathComponent("Local State"))
    let found = ArcProfileSnapshot.profileDirectories(in: workspace.root)
    #expect(found.map(\.lastPathComponent) == ["Default", "Profile 2"])
  }

  // MARK: - Copying

  @Test func copiesProfileFilesAndSkipsMissingOnesWithAReason() throws {
    let workspace = try makeWorkspace()
    try write("wal", to: workspace.profile.appendingPathComponent("History-wal"))
    try write("shm", to: workspace.profile.appendingPathComponent("History-shm"))
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    defer { snapshot.remove() }

    let profile = try #require(snapshot.profiles.first)
    #expect(profile.name == "Default")
    #expect(
      profile.copied.sorted() == [
        "Bookmarks", "History", "History-shm", "History-wal", "Login Data", "Network/Cookies", "Preferences",
        "Secure Preferences",
      ])
    #expect(profile.skipped == [.init(file: "Web Data", reason: .missing)])
    for name in profile.copied {
      let source = workspace.profile.appendingPathComponent(name)
      let copy = profile.directory.appendingPathComponent(name)
      #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
    }
  }

  @Test func legacyCookiesLocationIsUsedWhenNetworkCookiesIsMissing() throws {
    let workspace = try makeWorkspace()
    let network = workspace.profile.appendingPathComponent("Network/Cookies")
    try FileManager.default.moveItem(at: network, to: workspace.profile.appendingPathComponent("Cookies"))
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    #expect(profile.copied.contains("Cookies"))
    #expect(!profile.skipped.contains { $0.file.contains("Cookies") })
  }

  @Test func aProfileWithOnlyPreferencesSkipsEverythingElseWithoutFailing() throws {
    let workspace = try makeWorkspace()
    let only = workspace.root.appendingPathComponent("Profile 1", isDirectory: true)
    try FileManager.default.createDirectory(at: only, withIntermediateDirectories: true)
    try write("{}", to: only.appendingPathComponent("Preferences"))
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first { $0.name == "Profile 1" })
    #expect(profile.copied == ["Preferences"])
    #expect(profile.skipped.map(\.file).sorted() == ["Bookmarks", "Cookies", "History", "Login Data", "Secure Preferences", "Web Data"])
    #expect(profile.skipped.allSatisfy { $0.reason == .missing })
  }

  @Test func missingRootThrowsAndLeavesNoScratch() throws {
    let workspace = try makeWorkspace()
    let missing = workspace.base.appendingPathComponent("nope")
    #expect(throws: ArcProfileSnapshot.RootNotFound.self) {
      try ArcProfileSnapshot.make(root: missing, scratchParent: workspace.scratch)
    }
    #expect(scratchEntries(workspace).isEmpty)
  }

  // MARK: - Read-only guarantee and permissions

  @Test func sourceFilesAreByteIdenticalAndNoFileIsAddedToTheSource() throws {
    let workspace = try makeWorkspace(profiles: ["Default", "Profile 1"])
    try write("wal", to: workspace.profile.appendingPathComponent("History-wal"))
    let before = try hashes(of: workspace.root)
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    #expect(try hashes(of: workspace.root) == before)
    snapshot.remove()
    #expect(try hashes(of: workspace.root) == before)
  }

  @Test func scratchDirectoriesAre0700AndCopiesAre0600() throws {
    let workspace = try makeWorkspace()
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    #expect(try permissions(snapshot.directory) == 0o700)
    #expect(try permissions(profile.directory) == 0o700)
    #expect(try permissions(profile.directory.appendingPathComponent("Network")) == 0o700)
    for name in profile.copied {
      #expect(try permissions(profile.directory.appendingPathComponent(name)) == 0o600)
    }
  }

  @Test func sourcePermissionsAreNotChanged() throws {
    let workspace = try makeWorkspace()
    let history = workspace.profile.appendingPathComponent("History")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: history.path)
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    defer { snapshot.remove() }
    #expect(try permissions(history) == 0o444)
  }

  // MARK: - Cleanup

  @Test func removeDeletesTheScratchDirectory() throws {
    let workspace = try makeWorkspace()
    let snapshot = try ArcProfileSnapshot.make(root: workspace.root, scratchParent: workspace.scratch)
    #expect(FileManager.default.fileExists(atPath: snapshot.directory.path))
    snapshot.remove()
    #expect(scratchEntries(workspace).isEmpty)
  }

  @Test func withSnapshotCleansUpOnSuccess() async throws {
    let workspace = try makeWorkspace()
    let count = try await ArcProfileSnapshot.withSnapshot(root: workspace.root, scratchParent: workspace.scratch) {
      #expect(FileManager.default.fileExists(atPath: $0.directory.path))
      return $0.profiles.count
    }
    #expect(count == 1)
    #expect(scratchEntries(workspace).isEmpty)
  }

  @Test func withSnapshotCleansUpWhenTheBodyThrows() async throws {
    let workspace = try makeWorkspace()
    await #expect(throws: Boom.self) {
      try await ArcProfileSnapshot.withSnapshot(root: workspace.root, scratchParent: workspace.scratch) { _ in
        throw Boom()
      }
    }
    #expect(scratchEntries(workspace).isEmpty)
  }

  @Test func staleSweepRemovesOnlyLeftoverSnapshotDirectories() throws {
    let workspace = try makeWorkspace()
    let stale = workspace.scratch.appendingPathComponent("\(ArcProfileSnapshot.directoryPrefix)\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try write("x", to: stale.appendingPathComponent("History"))
    let unrelated = workspace.scratch.appendingPathComponent("something-else")
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

    let removed = ArcProfileSnapshot.sweepStale(scratchParent: workspace.scratch)
    #expect(removed == 1)
    #expect(scratchEntries(workspace) == ["something-else"])
  }

  // MARK: - Retry

  @Test func aCopyThatFailsOnceIsRetriedOnce() throws {
    let workspace = try makeWorkspace()
    let calls = Mutex(0)
    let operations = ArcProfileSnapshot.Operations(copy: { source, destination in
      let isHistory = source.lastPathComponent == "History"
      if isHistory, calls.withLock({ $0 += 1; return $0 }) == 1 { throw Boom() }
      try FileManager.default.copyItem(at: source, to: destination)
    })
    let snapshot = try ArcProfileSnapshot.make(
      root: workspace.root, scratchParent: workspace.scratch, operations: operations)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    #expect(profile.copied.contains("History"))
    #expect(calls.withLock { $0 } == 2)
  }

  @Test func aCopyThatFailsTwiceIsSkippedWithAReasonAndLeavesNoPartialFile() throws {
    let workspace = try makeWorkspace()
    let calls = Mutex(0)
    let operations = ArcProfileSnapshot.Operations(copy: { source, destination in
      if source.lastPathComponent == "History" {
        calls.withLock { $0 += 1 }
        try Data("partial".utf8).write(to: destination)
        throw Boom()
      }
      try FileManager.default.copyItem(at: source, to: destination)
    })
    let snapshot = try ArcProfileSnapshot.make(
      root: workspace.root, scratchParent: workspace.scratch, operations: operations)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    #expect(calls.withLock { $0 } == 2)
    #expect(!profile.copied.contains("History"))
    #expect(profile.skipped.contains { $0.file == "History" && $0.reason == .copyFailed })
    #expect(!FileManager.default.fileExists(atPath: profile.directory.appendingPathComponent("History").path))
  }

  @Test func aFileChangingDuringTheCopyIsRetriedOnce() throws {
    let workspace = try makeWorkspace()
    let calls = Mutex(0)
    let operations = ArcProfileSnapshot.Operations(copy: { source, destination in
      if source.lastPathComponent == "History", calls.withLock({ $0 += 1; return $0 }) == 1 {
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
      }
      try FileManager.default.copyItem(at: source, to: destination)
    })
    let snapshot = try ArcProfileSnapshot.make(
      root: workspace.root, scratchParent: workspace.scratch, operations: operations)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    let source = workspace.profile.appendingPathComponent("History")
    #expect(profile.copied.contains("History"))
    #expect(calls.withLock { $0 } == 2)
    #expect(try Data(contentsOf: profile.directory.appendingPathComponent("History")) == Data(contentsOf: source))
  }

  @Test func aFileThatKeepsChangingIsSkippedAfterOneRetry() throws {
    let workspace = try makeWorkspace()
    let calls = Mutex(0)
    let operations = ArcProfileSnapshot.Operations(copy: { source, destination in
      if source.lastPathComponent == "History" {
        calls.withLock { $0 += 1 }
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
      }
      try FileManager.default.copyItem(at: source, to: destination)
    })
    let snapshot = try ArcProfileSnapshot.make(
      root: workspace.root, scratchParent: workspace.scratch, operations: operations)
    defer { snapshot.remove() }
    let profile = try #require(snapshot.profiles.first)
    #expect(calls.withLock { $0 } == 2)
    #expect(profile.skipped.contains { $0.file == "History" && $0.reason == .changedWhileCopying })
    #expect(!FileManager.default.fileExists(atPath: profile.directory.appendingPathComponent("History").path))
  }
}
