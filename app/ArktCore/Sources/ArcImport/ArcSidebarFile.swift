import Foundation

/// Read-only mirror of Arc's `StorableSidebar.json` (Swift Codable output).
/// Only the fields the importer needs are declared; everything else is ignored.
public struct ArcSidebarFile: Decodable, Sendable {
  public struct Sidebar: Decodable, Sendable {
    public let containers: FlatDictionary<TaggedEnum, ArcContainer>
  }

  public let version: Int
  public let sidebar: Sidebar

  /// Decodes the file. Dates use the default strategy, which reads Arc's
  /// Double seconds since 2001-01-01.
  public static func decode(_ data: Data) throws -> ArcSidebarFile {
    try JSONDecoder().decode(ArcSidebarFile.self, from: data)
  }

  /// The container stored under the `{"global": {}}` key, if any.
  public var globalContainer: ArcContainer? {
    sidebar.containers.pairs.first { $0.key.caseName == "global" }?.value
  }
}

public struct ArcContainer: Decodable, Sendable {
  /// Spaces in file order (which is space order). A space that fails to decode
  /// is kept as a failure so the rest of the file still imports.
  public let spaces: FlatDictionary<String, ArcLossy<ArcSpace>>
  /// Items in file order. A bad item is kept as a failure, never fails the file.
  public let items: FlatDictionary<String, ArcLossy<ArcItem>>
  /// Favorites root item id per profile; keys are profile objects such as `{"default": true}`.
  /// Empty when the field is missing.
  public let topAppsContainerIDs: FlatDictionary<JSONValue, String>

  private enum CodingKeys: String, CodingKey { case spaces, items, topAppsContainerIDs }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    spaces = try container.decode(FlatDictionary<String, ArcLossy<ArcSpace>>.self, forKey: .spaces)
    items = try container.decode(FlatDictionary<String, ArcLossy<ArcItem>>.self, forKey: .items)
    topAppsContainerIDs = try container.decodeIfPresent(
      FlatDictionary<JSONValue, String>.self, forKey: .topAppsContainerIDs) ?? FlatDictionary()
  }

  public func space(_ id: String) -> ArcSpace? { spaces[id]?.value }
  public func item(_ id: String) -> ArcItem? { items[id]?.value }

  public var decodedSpaces: [ArcSpace] { spaces.values.compactMap(\.value) }
  public var decodedItems: [ArcItem] { items.values.compactMap(\.value) }

  public var spaceFailures: [ArcDecodeFailure] { Self.failures(in: spaces) }
  public var itemFailures: [ArcDecodeFailure] { Self.failures(in: items) }

  private static func failures<T>(in dict: FlatDictionary<String, ArcLossy<T>>) -> [ArcDecodeFailure] {
    dict.pairs.compactMap { pair in
      pair.value.failureReason.map { ArcDecodeFailure(id: pair.key, reason: $0) }
    }
  }
}

/// A value that either decoded or failed; decoding this never throws.
public struct ArcLossy<Value: Decodable & Sendable>: Decodable, Sendable {
  public let value: Value?
  /// Description of the decoding error when `value` is nil.
  public let failureReason: String?

  public init(from decoder: Decoder) throws {
    do {
      value = try Value(from: decoder)
      failureReason = nil
    } catch {
      value = nil
      failureReason = String(describing: error)
    }
  }
}

/// An entry (space or item) that could not be decoded.
public struct ArcDecodeFailure: Hashable, Sendable {
  public let id: String
  public let reason: String
}

public struct ArcSpace: Decodable, Sendable {
  public let id: String
  public let title: String
  public let profile: JSONValue
  /// Current form: keys `{"pinned": {}}` and `{"unpinned": {"_0": {"shared": {}}}}`.
  public let newContainerIDs: FlatDictionary<TaggedEnum, String>?
  /// Legacy form: keys `"pinned"` and `"unpinned"`.
  public let containerIDs: FlatDictionary<String, String>?
  public let customInfo: JSONValue?
}

public struct ArcItem: Decodable, Sendable {
  public let id: String
  public let parentID: String?
  public let childrenIds: [String]
  /// User-set name; nil means use the content title.
  public let title: String?
  public let createdAt: Date?
  public let data: TaggedEnum

  private enum CodingKeys: String, CodingKey {
    case id, parentID, childrenIds, title, createdAt, data
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
    childrenIds = try container.decodeIfPresent([String].self, forKey: .childrenIds) ?? []
    title = try container.decodeIfPresent(String.self, forKey: .title)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    data = try container.decode(TaggedEnum.self, forKey: .data)
  }

  // Case bodies are written without `_0`: `{"tab": {"savedURL": ...}}`.

  /// The `tab` payload, or nil when this item is not a tab. Throws if malformed.
  public var tabData: ArcTabData? {
    get throws { try payload(ArcTabData.self, ifCase: "tab") }
  }

  /// The `splitView` payload, or nil when this item is not a split view. Throws if malformed.
  public var splitViewData: ArcSplitViewData? {
    get throws { try payload(ArcSplitViewData.self, ifCase: "splitView") }
  }

  /// The container kind, or nil when this item is not an `itemContainer`. Throws if malformed.
  public var containerType: ArcContainerType? {
    get throws { try payload(ItemContainerData.self, ifCase: "itemContainer")?.containerType }
  }

  private func payload<T: Decodable>(_ type: T.Type, ifCase name: String) throws -> T? {
    guard data.caseName == name else { return nil }
    return try data.body(T.self)
  }
}

public struct ArcTabData: Decodable, Hashable, Sendable {
  public let savedURL: String
  public let savedTitle: String?
  public let timeLastActiveAt: Date?
}

public struct ArcSplitViewData: Decodable, Hashable, Sendable {
  /// `"horizontal"` or `"vertical"`.
  public let layoutOrientation: String
  public let itemWidthFactors: [Double]
}

public enum ArcContainerType: Hashable, Sendable {
  /// A space's pinned or unpinned root; which one is decided by the space's container maps.
  case spaceItems(spaceID: String)
  /// The Favorites root for a profile.
  case topApps(profile: JSONValue)
  /// A case this decoder does not know.
  case unknown(String)
}

private struct ItemContainerData: Decodable {
  let containerType: ArcContainerType

  private enum CodingKeys: String, CodingKey { case containerType }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(TaggedEnum.self, forKey: .containerType)
    switch tag.caseName {
    case "spaceItems": containerType = .spaceItems(spaceID: try tag.payload(String.self))
    case "topApps": containerType = .topApps(profile: try tag.payload(JSONValue.self))
    default: containerType = .unknown(tag.caseName)
    }
  }
}
