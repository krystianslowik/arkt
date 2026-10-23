import Archive
import ArcImport
import CoreBridge
@_exported import CoreTestSupport
import CryptoKit
import Foundation
import SidebarModel
import Testing

/// A temp folder laid out like Arc's data folder, holding copies of the synthetic fixtures (never real Arc data):
/// `StorableSidebar.json`, optionally `StorableArchiveItems.json` (the fixture, or `archive` bytes), and one favicon
/// in `SidebarItemsFaviconCache/`.
/// Removed on deinit. `unchanged()` proves the import only read it.
final class ArcFixtureFolder {
  /// The Beta Space's Today tab; the one fixture tab with a favicon file.
  static let faviconTabID = "A0000000-0000-4000-8000-000000000221"
  static let favicon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x2A])
  static let alphaID = "A0000000-0000-4000-8000-0000000000A1"
  static let betaID = "A0000000-0000-4000-8000-0000000000B1"
  /// The two top-level Favorites (default profile).
  static let mailFavoriteID = "A0000000-0000-4000-8000-000000000311"
  static let calendarFavoriteID = "A0000000-0000-4000-8000-000000000312"
  /// Every title and URL fragment in the fixture that a counts-only text must never contain.
  static let userStrings = [
    "Alpha", "Beta", "Reading", "Example", "Renamed", "example.com", "http", "mail", "wiki", "news", "articles",
  ]

  let url: URL
  private let digests: [String: SHA256.Digest]

  /// `mutateGlobal` edits the sidebar file's global container (as `[String: Any]`) before it is written.
  init(
    sidebar: Data? = nil, includeArchive: Bool = true, archive: Data? = nil,
    mutateGlobal: ((inout [String: Any]) throws -> Void)? = nil
  ) throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArcFixtureFolder-\(UUID().uuidString)", isDirectory: true)
    let favicons = url.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true)
    try FileManager.default.createDirectory(at: favicons, withIntermediateDirectories: true)
    var sidebarData = try sidebar ?? Self.fixture("StorableSidebar-synthetic")
    if let mutateGlobal { sidebarData = try Self.mutated(sidebarData, mutateGlobal) }
    try sidebarData.write(to: url.appendingPathComponent("StorableSidebar.json"))
    if includeArchive {
      try (archive ?? Self.fixture("StorableArchiveItems-synthetic"))
        .write(to: url.appendingPathComponent("StorableArchiveItems.json"))
    }
    try Self.favicon.write(
      to: favicons.appendingPathComponent(ArcFaviconCache.fileName(forItemID: Self.faviconTabID)))
    digests = try Self.digests(of: url)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  var files: ArcSourceFiles { ArcSourceFiles(directory: url) }

  /// Same files with the same bytes as when the folder was made.
  func unchanged() throws -> Bool { try Self.digests(of: url) == digests }

  static func fixture(_ name: String) throws -> Data {
    let file = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: file)
  }

  private static func digests(of directory: URL) throws -> [String: SHA256.Digest] {
    var result: [String: SHA256.Digest] = [:]
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    while let file = enumerator?.nextObject() as? URL {
      guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
      result[file.path] = SHA256.hash(data: try Data(contentsOf: file))
    }
    return result
  }

  private static func mutated(_ data: Data, _ change: (inout [String: Any]) throws -> Void) throws -> Data {
    var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var sidebar = try #require(root["sidebar"] as? [String: Any])
    var containers = try #require(sidebar["containers"] as? [Any])
    var global = try #require(containers[1] as? [String: Any])
    try change(&global)
    containers[1] = global
    sidebar["containers"] = containers
    root["sidebar"] = sidebar
    return try JSONSerialization.data(withJSONObject: root)
  }

  // MARK: Global container edits (flat `[k0, v0, k1, v1, ...]` arrays)

  /// Drops the entry under `id` from the flat array `field`.
  static func removeEntry(_ id: String, in field: String, of global: inout [String: Any]) throws {
    var flat = try #require(global[field] as? [Any])
    let index = try #require(stride(from: 0, to: flat.count, by: 2).first { flat[$0] as? String == id })
    flat.removeSubrange(index...(index + 1))
    global[field] = flat
  }

  /// Rewrites the object stored under `id` in the flat array `field`.
  static func mutateEntry(
    _ id: String, in field: String, of global: inout [String: Any], _ change: (inout [String: Any]) -> Void
  ) throws {
    var flat = try #require(global[field] as? [Any])
    let index = try #require(stride(from: 0, to: flat.count, by: 2).first { flat[$0] as? String == id })
    var value = try #require(flat[index + 1] as? [String: Any])
    change(&value)
    flat[index + 1] = value
    global[field] = flat
  }

  /// Appends `key, value` to the flat array `field`.
  static func appendEntry(_ key: Any, _ value: Any, in field: String, of global: inout [String: Any]) throws {
    var flat = try #require(global[field] as? [Any])
    flat.append(key)
    flat.append(value)
    global[field] = flat
  }
}
