import Foundation

/// A node and its whole subtree, detached from any sidebar. Used by the storage format (D1b), the archive and restore.
public struct NodeSnapshot: Hashable, Sendable, Codable, Identifiable {
  public var id: NodeID
  public var kind: NodeKind
  public var createdAt: Date
  public var children: [NodeSnapshot]
  public var customIcon: SpaceIcon?

  public init(id: NodeID = NodeID(), kind: NodeKind, createdAt: Date, children: [NodeSnapshot] = [],
              customIcon: SpaceIcon? = nil) {
    self.id = id
    self.kind = kind
    self.createdAt = createdAt
    self.children = children
    self.customIcon = customIcon
  }

  /// Every id in the subtree, root first, depth first.
  public var allIDs: [NodeID] { [id] + children.flatMap(\.allIDs) }

  /// Whether a split anywhere in the subtree has a title (#787): the field that needs archive snapshot format 3.
  public var containsSplitTitle: Bool {
    if case .split(let split) = kind, split.title != nil { return true }
    return children.contains { $0.containsSplitTitle }
  }

  /// Whether a node anywhere in the subtree has a custom icon (#339): the field that needs archive snapshot format 2.
  public var containsCustomIcon: Bool {
    customIcon != nil || children.contains { $0.containsCustomIcon }
  }

  /// The subtree as a format that predates split titles reads it (sidebar format 4, archive snapshot format 2): every
  /// split in it unnamed, every other field, the node icons included, kept. A `title` key in such a document was never
  /// part of its format, so it is not read.
  public func withoutSplitTitles() -> NodeSnapshot {
    var copy = self
    if case .split(var split) = kind {
      split.title = nil
      copy.kind = .split(split)
    }
    copy.children = children.map { $0.withoutSplitTitles() }
    return copy
  }

  /// The same subtree with new ids, used when restoring over an id that is already taken.
  public func withFreshIDs() -> NodeSnapshot {
    NodeSnapshot(kind: kind, createdAt: createdAt, children: children.map { $0.withFreshIDs() }, customIcon: customIcon)
  }
}

/// On disk: `{"type": "tab", "tab": {...}}`, `{"type": "folder", "folder": {...}}`, `{"type": "split", "split": {...}}`.
extension NodeKind: Codable {
  private enum CodingKeys: String, CodingKey { case type, tab, folder, split }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "tab": self = .tab(try container.decode(TabItem.self, forKey: .tab))
    case "folder": self = .folder(try container.decode(FolderItem.self, forKey: .folder))
    case "split": self = .split(try container.decode(SplitItem.self, forKey: .split))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "Unknown node type \(type)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .tab(let tab):
      try container.encode("tab", forKey: .type)
      try container.encode(tab, forKey: .tab)
    case .folder(let folder):
      try container.encode("folder", forKey: .type)
      try container.encode(folder, forKey: .folder)
    case .split(let split):
      try container.encode("split", forKey: .type)
      try container.encode(split, forKey: .split)
    }
  }
}
