import Foundation

/// A read-only scratch copy of the Arc profiles under a Chromium `User Data` root (#506).
///
/// The import readers (#508 to #510) open the copies, never Arc's own files, so Arc can keep running and nothing is
/// ever written to its profile. The copy lives in a `0700` directory with `0600` files and is removed on success, on
/// failure (`withSnapshot`) and at launch (`sweepStale`). The type reads file bytes only to copy them; it never
/// opens a database, never decodes content and never touches the Keychain.
public struct ArcProfileSnapshot: Sendable {
  public struct RootNotFound: Error, Equatable {}

  public enum SkipReason: Error, Sendable, Equatable, CustomStringConvertible {
    /// The file does not exist in the profile. Normal for profiles that never used a feature.
    case missing
    /// The copy failed twice, for example because the file stayed locked.
    case copyFailed
    /// The file (or its -wal/-shm) changed during both copy attempts, so a consistent copy was not possible.
    case changedWhileCopying

    public var description: String {
      switch self {
      case .missing: "missing"
      case .copyFailed: "copy failed"
      case .changedWhileCopying: "changed while copying"
      }
    }
  }

  public struct SkippedFile: Sendable, Equatable {
    public let file: String
    public let reason: SkipReason

    public init(file: String, reason: SkipReason) {
      self.file = file
      self.reason = reason
    }
  }

  public struct Profile: Sendable, Equatable {
    /// The source folder name, such as `Default` or `Profile 2`.
    public let name: String
    /// The scratch folder holding the copies, laid out like the source (`Network/Cookies` stays under `Network`).
    public let directory: URL
    /// Relative paths of the copied files, including any `-wal` and `-shm` companions.
    public let copied: [String]
    public let skipped: [SkippedFile]
  }

  /// File operations, injectable so tests can fail or disturb a copy deterministically.
  public struct Operations: Sendable {
    public var copy: @Sendable (_ source: URL, _ destination: URL) throws -> Void

    public init(copy: @escaping @Sendable (URL, URL) throws -> Void) { self.copy = copy }

    public static let live = Operations(copy: { try FileManager.default.copyItem(at: $0, to: $1) })
  }

  /// Prefix of every scratch directory this type creates; `sweepStale` removes only directories with it.
  public static let directoryPrefix = "arkt-arc-snapshot-"

  /// The scratch folder holding every profile copy.
  public let directory: URL
  public let profiles: [Profile]

  // MARK: - Locating

  /// Arc's standard profile root, `~/Library/Application Support/Arc/User Data`.
  public static func defaultRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)
  }

  /// A directory under `root` is a profile when it holds a `Preferences` or `History` file. Sorted by name.
  public static func profileDirectories(in root: URL) -> [URL] {
    let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return children.filter { child in
      ["Preferences", "History"].contains { FileManager.default.fileExists(atPath: child.appendingPathComponent($0).path) }
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  // MARK: - Snapshot

  /// One entry of the copy list: the label shown when skipped, and the relative paths to try in order.
  private struct Entry {
    let label: String
    let candidates: [String]
    let hasCompanions: Bool
  }

  private static let entries: [Entry] = [
    Entry(label: "History", candidates: ["History"], hasCompanions: true),
    Entry(label: "Login Data", candidates: ["Login Data"], hasCompanions: true),
    Entry(label: "Cookies", candidates: ["Network/Cookies", "Cookies"], hasCompanions: true),
    Entry(label: "Web Data", candidates: ["Web Data"], hasCompanions: true),
    Entry(label: "Bookmarks", candidates: ["Bookmarks"], hasCompanions: false),
    Entry(label: "Preferences", candidates: ["Preferences"], hasCompanions: false),
    Entry(label: "Secure Preferences", candidates: ["Secure Preferences"], hasCompanions: false),
  ]

  /// Copies the profile files under `root` into a new scratch directory inside `scratchParent`.
  ///
  /// Throws `RootNotFound` when `root` is not a directory. Any other failure removes the partial scratch directory
  /// before rethrowing. Files that cannot be copied are reported in `Profile.skipped`, never thrown.
  public static func make(
    root: URL, scratchParent: URL = FileManager.default.temporaryDirectory, operations: Operations = .live
  ) throws -> ArcProfileSnapshot {
    let files = FileManager.default
    var isDirectory: ObjCBool = false
    guard files.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw RootNotFound()
    }
    let scratch = scratchParent.appendingPathComponent(directoryPrefix + UUID().uuidString, isDirectory: true)
    do {
      try createPrivateDirectory(scratch)
      var profiles: [Profile] = []
      for source in profileDirectories(in: root) {
        let destination = scratch.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try createPrivateDirectory(destination)
        profiles.append(try copyProfile(from: source, to: destination, operations: operations))
      }
      return ArcProfileSnapshot(directory: scratch, profiles: profiles)
    } catch {
      try? files.removeItem(at: scratch)
      throw error
    }
  }

  /// Runs `body` on a fresh snapshot and removes the scratch directory afterwards, whether `body` returns or throws.
  public static func withSnapshot<Result>(
    root: URL, scratchParent: URL = FileManager.default.temporaryDirectory, operations: Operations = .live,
    _ body: (ArcProfileSnapshot) async throws -> Result
  ) async throws -> Result {
    let snapshot = try make(root: root, scratchParent: scratchParent, operations: operations)
    defer { snapshot.remove() }
    return try await body(snapshot)
  }

  /// Deletes the scratch directory. Safe to call more than once.
  public func remove() {
    try? FileManager.default.removeItem(at: directory)
  }

  /// Removes scratch directories left behind by a crashed or killed run. Call once at launch, before any snapshot is
  /// made. Returns how many were removed.
  @discardableResult
  public static func sweepStale(scratchParent: URL = FileManager.default.temporaryDirectory) -> Int {
    let files = FileManager.default
    let children = (try? files.contentsOfDirectory(at: scratchParent, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    var removed = 0
    for child in children where child.lastPathComponent.hasPrefix(directoryPrefix) {
      guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
      if (try? files.removeItem(at: child)) != nil { removed += 1 }
    }
    return removed
  }

  // MARK: - Copying

  private static func copyProfile(from source: URL, to destination: URL, operations: Operations) throws -> Profile {
    var copied: [String] = []
    var skipped: [SkippedFile] = []
    for entry in entries {
      guard let path = entry.candidates.first(where: { exists(source.appendingPathComponent($0)) }) else {
        skipped.append(SkippedFile(file: entry.label, reason: .missing))
        continue
      }
      let group = entry.hasCompanions ? [path, path + "-wal", path + "-shm"] : [path]
      switch copyGroup(group, from: source, to: destination, operations: operations) {
      case .success(let names): copied += names
      case .failure(let reason): skipped.append(SkippedFile(file: path, reason: reason))
      }
    }
    return Profile(name: source.lastPathComponent, directory: destination, copied: copied, skipped: skipped)
  }

  private struct Fingerprint: Equatable {
    let size: Int
    let modified: Date?
  }

  private static func fingerprints(_ names: [String], in source: URL) -> [String: Fingerprint] {
    var result: [String: Fingerprint] = [:]
    for name in names {
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.appendingPathComponent(name).path)
      else { continue }
      result[name] = Fingerprint(
        size: (attributes[.size] as? NSNumber)?.intValue ?? -1, modified: attributes[.modificationDate] as? Date)
    }
    return result
  }

  /// Copies a database and its companions as one unit, retrying the whole unit once when a copy fails or a source
  /// file changes while it is being read. Partial copies are removed before a retry and before giving up.
  private static func copyGroup(
    _ names: [String], from source: URL, to destination: URL, operations: Operations
  ) -> Result<[String], SkipReason> {
    var failure: SkipReason = .copyFailed
    for _ in 0..<2 {
      let before = fingerprints(names, in: source)
      var done: [String] = []
      var threw = false
      for name in names where before[name] != nil {
        let target = destination.appendingPathComponent(name)
        do {
          try createPrivateDirectory(target.deletingLastPathComponent())
          try operations.copy(source.appendingPathComponent(name), target)
          try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
          done.append(name)
        } catch {
          threw = true
          try? FileManager.default.removeItem(at: target)
          break
        }
      }
      if !threw, fingerprints(names, in: source) == before { return .success(done) }
      failure = threw ? .copyFailed : .changedWhileCopying
      for name in names { try? FileManager.default.removeItem(at: destination.appendingPathComponent(name)) }
    }
    return .failure(failure)
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  /// Creates `url` (and missing parents) and sets it to `0700`.
  private static func createPrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }
}
