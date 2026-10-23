import Foundation

/// The Arc ids an Arc import has handled before (Track E user decision, 2026-10-23: a re-import adds only Arc items
/// never imported before; items deleted in Arkt are not restored). Arc's own ids, not Arkt's: Space ids from
/// `StorableSidebar.json`'s `spaces`, Favorite ids of the top-level items under a profile's Favorites root (tabs,
/// folders and splits alike). Stored as JSON with sorted arrays, so the stored bytes are deterministic.
public struct ArcImportRecord: Hashable, Sendable, Codable {
  public var spaceIDs: Set<String>
  public var favoriteItemIDs: Set<String>

  public init(spaceIDs: Set<String> = [], favoriteItemIDs: Set<String> = []) {
    self.spaceIDs = spaceIDs
    self.favoriteItemIDs = favoriteItemIDs
  }

  /// Nothing recorded: no import ran yet, or the last one ran before the record existed.
  public var isEmpty: Bool { spaceIDs.isEmpty && favoriteItemIDs.isEmpty }

  public mutating func formUnion(_ other: ArcImportRecord) {
    spaceIDs.formUnion(other.spaceIDs)
    favoriteItemIDs.formUnion(other.favoriteItemIDs)
  }

  private enum CodingKeys: String, CodingKey {
    case spaceIDs
    case favoriteItemIDs
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    spaceIDs = try container.decode(Set<String>.self, forKey: .spaceIDs)
    favoriteItemIDs = try container.decode(Set<String>.self, forKey: .favoriteItemIDs)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(spaceIDs.sorted(), forKey: .spaceIDs)
    try container.encode(favoriteItemIDs.sorted(), forKey: .favoriteItemIDs)
  }
}

/// Where the import record lives. `Persistence.SettingsStore` conforms; CoreBridge tests use a fake.
public protocol ArcImportRecordStoring: Sendable {
  /// The stored record, or an empty one when missing or unreadable.
  func loadArcImportRecord() async throws -> ArcImportRecord
  /// Adds `record`'s ids to the stored ones (a union, never a replacement), in one transaction.
  func recordArcImport(_ record: ArcImportRecord, at date: Date) async throws
}
