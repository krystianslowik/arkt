import Foundation

/// An enum case as Swift's synthesized Codable writes it: a single-key object
/// `{caseName: {...}}`, where associated values sit under `_0`, `_1`, ...
public struct TaggedEnum: Decodable, Hashable, Sendable {
  public let caseName: String
  private let body: [String: JSONValue]

  public var hasPayload: Bool { !body.isEmpty }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    guard container.allKeys.count == 1, let key = container.allKeys.first else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: decoder.codingPath, debugDescription: "Expected a single-key enum object"))
    }
    caseName = key.stringValue
    switch try container.decode(JSONValue.self, forKey: key) {
    case .object(let fields):
      body = fields
    case .null:
      body = [:]
    default:
      throw DecodingError.typeMismatch([String: JSONValue].self, .init(
        codingPath: decoder.codingPath + [key],
        debugDescription: "Enum case \(caseName) body must be an object or null"))
    }
  }

  /// Decodes the whole case body object as `T`. Arc writes sidebar item
  /// bodies this way, as `{"tab": {"savedURL": ...}}` with no `_0` level.
  public func body<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(body))
  }

  /// Decodes associated value `_<position>` as `T`.
  public func payload<T: Decodable>(_ type: T.Type, at position: Int = 0) throws -> T {
    guard let value = body["_\(position)"] else {
      throw DecodingError.valueNotFound(T.self, .init(
        codingPath: [], debugDescription: "\(caseName) has no _\(position)"))
    }
    return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
  }
}

struct AnyKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}
