import Foundation

/// Read-only mirror of Arc's `StorableArchiveItems.json`:
/// `{version, items: [itemID, ArchivedItem, ...]}` with `ArchivedItem {reason, archivedAt, source, sidebarItem}`.
public struct ArcArchiveFile: Decodable, Sendable {
  public let version: Int
  /// Entries in file order; a bad entry is kept as a failure and never fails the file. A duplicate key or a key
  /// without a value still fails the whole file: the flat key/value list cannot be realigned after either.
  public let items: FlatDictionary<String, ArcLossy<ArcArchivedItem>>

  /// Decodes the file. Dates use the default strategy, which reads Arc's Double seconds since 2001-01-01.
  public static func decode(_ data: Data) throws -> ArcArchiveFile {
    try JSONDecoder().decode(ArcArchiveFile.self, from: data)
  }
}

public struct ArcArchivedItem: Decodable, Sendable {
  /// `"manual"` or `"auto"`; anything else is imported as manual with a warning.
  public let reason: String
  public let archivedAt: Date
  /// `{"space": {"_0": spaceID}}`, `{"littleArc": {}}` or `{"unknown": {}}`.
  public let source: TaggedEnum
  /// Full snapshot; Arc writes `parentID` null and `childrenIds` empty.
  public let sidebarItem: ArcItem
}
