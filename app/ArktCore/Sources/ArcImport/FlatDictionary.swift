/// A keyed collection stored as a flat `[k0, v0, k1, v1, ...]` array. This is the
/// Codable format of swift-collections' `OrderedDictionary`, and also what
/// JSONEncoder writes for a `Dictionary` whose key type is not String or Int.
/// The on-disk order is meaningful (Arc uses it for space order) and is preserved.
/// Duplicate keys are rejected as corrupt data.
public struct FlatDictionary<Key: Decodable & Hashable, Value: Decodable>: Decodable {
  public struct Pair {
    public let key: Key
    public let value: Value
  }

  public let pairs: [Pair]
  private let index: [Key: Int]

  /// An empty dictionary, used when an optional field is missing.
  init() {
    pairs = []
    index = [:]
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var pairs: [Pair] = []
    var index: [Key: Int] = [:]
    while !container.isAtEnd {
      let key = try container.decode(Key.self)
      guard !container.isAtEnd else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Flat dictionary has a key without a value")
      }
      guard index[key] == nil else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Flat dictionary has a duplicate key \(key)")
      }
      index[key] = pairs.count
      pairs.append(Pair(key: key, value: try container.decode(Value.self)))
    }
    self.pairs = pairs
    self.index = index
  }

  public subscript(key: Key) -> Value? {
    index[key].map { pairs[$0].value }
  }

  public var values: [Value] { pairs.map(\.value) }
}

extension FlatDictionary: Sendable where Key: Sendable, Value: Sendable {}
extension FlatDictionary.Pair: Sendable where Key: Sendable, Value: Sendable {}
