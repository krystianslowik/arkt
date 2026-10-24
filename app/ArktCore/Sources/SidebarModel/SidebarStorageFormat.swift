import Foundation

/// Arkt's on-disk sidebar format.
///
/// Version 1 is nested: each Space carries its pinned and Today trees, and Favorites are listed per profile, so a
/// file cannot express a parent link that disagrees with child order. Decoding rebuilds the sidebar through
/// `addSpace(_:)` and `insert(_:in:at:)`, which enforce every model invariant and keep ids.
/// Deterministic: arrays follow model order, favorites are sorted by profile and keys are sorted. Dates are Double
/// seconds since 2001-01-01 (Swift's default, also Arc's), written in shortest round-trip form.
///
/// Version policy: a document is written as `currentVersion`. A newer version (written by a later Arkt) or an
/// unknown one throws `SidebarDocumentError.unsupportedVersion` and is never read on a best-effort basis, so an older
/// build cannot silently drop data it does not understand. Any new field, even an optional one, requires a version
/// bump; a new version gets a new frozen fixture and an explicit migration from the older versions.
///
/// Version 2 adds `Space.icon`. Version 1 is the same document without that field: decoding it leaves every icon nil
/// and is the whole migration. Nothing else is rewritten.
///
/// Equality: two stored documents hold the same sidebar when their decoded values are equal. Byte equality is only a
/// fast path (the encoding is deterministic for a given build), never the definition.
///
/// Nesting: `JSONDecoder`'s own nesting limit bounds the recursion while parsing and decoding a file; the model's
/// `Sidebar.maximumNestingDepth`, enforced by `insert`, bounds how deep the decoded tree may be, and is reported as
/// `.invalidTree(.nestingTooDeep(id))`.
public enum SidebarStorageFormat {
  public static let currentVersion = 2

  /// Documents this build reads. Version 1 migrates by leaving `Space.icon` nil (the field did not exist).
  public static let readableVersions: Set<Int> = [1, 2]

  /// Same value as `Sidebar.maximumNestingDepth`, the model invariant that decoding enforces through `insert`.
  public static let maximumNestingDepth = Sidebar.maximumNestingDepth

  /// A fresh encoder with the canonical settings. Not stored: `JSONEncoder` is not `Sendable`.
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .deferredToDate
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    return decoder
  }

  public static func encode(_ sidebar: Sidebar) throws -> Data { try makeEncoder().encode(sidebar) }
  public static func decode(_ data: Data) throws -> Sidebar { try makeDecoder().decode(Sidebar.self, from: data) }
}

public enum SidebarDocumentError: Error, Hashable, Sendable {
  /// Written by a newer (or unknown) format. Never guessed at.
  case unsupportedVersion(Int)
  /// The same profile appears twice in `favorites`.
  case duplicateFavoritesProfile(String)
  /// The tree breaks a model rule (duplicate id, a folder in a split, children under a tab, ...).
  case invalidTree(SidebarError)
}

private struct SpaceEntry: Codable {
  var space: Space
  var pinned: [NodeSnapshot]
  var today: [NodeSnapshot]
}

private struct FavoritesEntry: Codable {
  var profile: String
  var items: [NodeSnapshot]
}

extension Sidebar: Codable {
  private enum CodingKeys: String, CodingKey { case version, spaces, favorites }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    // Version 1 has no icon. `Space.icon` decodes as nil when the key is absent; that is the migration.
    guard SidebarStorageFormat.readableVersions.contains(version) else {
      throw SidebarDocumentError.unsupportedVersion(version)
    }
    let spaces = try container.decode([SpaceEntry].self, forKey: .spaces)
    let favorites = try container.decode([FavoritesEntry].self, forKey: .favorites)
    var sidebar = Sidebar()
    var profiles: Set<String> = []
    do {
      for entry in spaces {
        try sidebar.addSpace(entry.space)
        for tree in entry.pinned { try sidebar.insert(tree, in: .pinned(entry.space.id)) }
        for tree in entry.today { try sidebar.insert(tree, in: .today(entry.space.id)) }
      }
      for entry in favorites {
        guard profiles.insert(entry.profile).inserted else {
          throw SidebarDocumentError.duplicateFavoritesProfile(entry.profile)
        }
        for tree in entry.items { try sidebar.insert(tree, in: .favorites(profile: entry.profile)) }
      }
    } catch let error as SidebarError {
      throw SidebarDocumentError.invalidTree(error)
    }
    self = sidebar
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(SidebarStorageFormat.currentVersion, forKey: .version)
    let spaceEntries = spaceOrder.compactMap { id in
      spaces[id].map { SpaceEntry(space: $0, pinned: trees(in: .pinned(id)), today: trees(in: .today(id))) }
    }
    try container.encode(spaceEntries, forKey: .spaces)
    let profiles = Set(childOrder.keys.compactMap { location -> String? in
      if case .favorites(let profile) = location { return profile }
      return nil
    }).sorted()
    try container.encode(
      profiles.map { FavoritesEntry(profile: $0, items: trees(in: .favorites(profile: $0))) }, forKey: .favorites)
  }

  private func trees(in location: Location) -> [NodeSnapshot] {
    children(of: location).compactMap { snapshot(of: $0) }
  }
}
