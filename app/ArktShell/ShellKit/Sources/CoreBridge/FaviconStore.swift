import Foundation

public enum FaviconStoreError: Error, Equatable, Sendable {
  /// The directory is inside Arc's data folder, which Arkt never writes to.
  case forbiddenDirectory
}

/// Favicons as `<node UUID>.png` files in Arkt's own data folder (decision 8): imported from Arc or reported by the
/// engine, loaded once after launch. Not in SQLite and not in backups. An actor: its file I/O runs off the main
/// actor, one call at a time, so calls awaited in order land in that order.
public actor FaviconStore {
  public nonisolated let directory: URL

  /// Does disk I/O (it resolves symlinks in the existing part of `directory`), so it must not run on the main actor:
  /// create the store from a `@concurrent` function (`AppEnvironment.faviconStore(in:)`). The directory itself is
  /// created by the first `save`.
  public init(directory: URL) throws(FaviconStoreError) {
    // Arkt never writes into Arc's folder (design 5, Track E rules), also not through a symlink that points there.
    guard !Self.isInsideArcFolder(directory), !Self.isInsideArcFolder(Self.resolvingSymlinks(directory)) else {
      throw .forbiddenDirectory
    }
    self.directory = directory
  }

  /// Writes each favicon atomically, replacing an existing one, creating the directory (owner only) when needed. A
  /// favicon whose file already holds the same bytes is not rewritten.
  public func save(_ favicons: [UUID: Data]) throws {
    guard !favicons.isEmpty else { return }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    for (id, data) in favicons {
      let url = fileURL(for: id)
      if let existing = try? Data(contentsOf: url), existing == data { continue }
      try data.write(to: url, options: .atomic)
    }
  }

  /// Removes the favicons of `ids`; ids without a file are ignored. Best effort.
  public func remove(_ ids: Set<UUID>) {
    for id in ids { try? FileManager.default.removeItem(at: fileURL(for: id)) }
  }

  /// The stored favicons of `ids`; ids without a readable file are left out.
  public func loadAll(for ids: Set<UUID>) -> [UUID: Data] {
    var result: [UUID: Data] = [:]
    for id in ids {
      if let data = try? Data(contentsOf: fileURL(for: id)) { result[id] = data }
    }
    return result
  }

  /// Removes `<UUID>.png` files whose id is not in `ids`. Any other file in the directory is left alone. Best
  /// effort: a file that cannot be removed stays for the next prune.
  public func prune(keeping ids: Set<UUID>) {
    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
    for name in names {
      let url = directory.appendingPathComponent(name, isDirectory: false)
      guard url.pathExtension == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
        !ids.contains(id)
      else { continue }
      try? fileManager.removeItem(at: url)
    }
  }

  private func fileURL(for id: UUID) -> URL {
    directory.appendingPathComponent("\(id.uuidString).png", isDirectory: false)
  }

  /// `directory` with symlinks resolved in its longest existing prefix; the missing rest (the folder `save` will
  /// create) is appended unchanged. `resolvingSymlinksInPath()` alone leaves a path with a missing leaf unresolved.
  private static func resolvingSymlinks(_ directory: URL) -> URL {
    var existing = directory.standardizedFileURL
    var missing: [String] = []
    while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
      missing.insert(existing.lastPathComponent, at: 0)
      existing.deleteLastPathComponent()
    }
    return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1, isDirectory: true) }
  }

  /// The trailing slash also catches the Arc folder itself, whose standardized path has none.
  private static func isInsideArcFolder(_ url: URL) -> Bool {
    (url.standardizedFileURL.path.lowercased() + "/").contains("/application support/arc/")
  }
}
