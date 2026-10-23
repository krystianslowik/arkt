import Foundation
import Testing
import ArcImport

struct JSONValueTests {
  @Test func decodesEveryKind() throws {
    let json = #"{"s": "x", "n": 1.5, "i": 7, "t": true, "f": false, "z": null, "a": [1, "y"], "o": {"k": null}}"#
      .data(using: .utf8)!
    let value = try JSONDecoder().decode(JSONValue.self, from: json)
    #expect(value == .object([
      "s": .string("x"),
      "n": .number(1.5),
      "i": .int(7),
      "t": .bool(true),
      "f": .bool(false),
      "z": .null,
      "a": .array([.int(1), .string("y")]),
      "o": .object(["k": .null]),
    ]))
  }

  @Test func roundTripsThroughEncoder() throws {
    let original: JSONValue = .array([.null, .bool(true), .number(-2.25), .int(-3), .string("a"), .object(["b": .array([])])])
    let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
  }

  @Test func largeIntegerRoundTripsExactly() throws {
    let json = "9007199254740993".data(using: .utf8)!
    let value = try JSONDecoder().decode(JSONValue.self, from: json)
    #expect(value == .int(9_007_199_254_740_993))
    let reencoded = try JSONEncoder().encode(value)
    #expect(String(decoding: reencoded, as: UTF8.self) == "9007199254740993")
  }
}
