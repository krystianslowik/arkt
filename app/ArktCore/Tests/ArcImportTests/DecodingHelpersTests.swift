import Foundation
import Testing
import ArcImport

struct DecodingHelpersTests {
  @Test func flatDictionaryKeepsPairsInOrder() throws {
    let json = #"["b", 2, "a", 1, "c", 3]"#.data(using: .utf8)!
    let dict = try JSONDecoder().decode(FlatDictionary<String, Int>.self, from: json)
    #expect(dict.pairs.map(\.key) == ["b", "a", "c"])
    #expect(dict["a"] == 1)
    #expect(dict["missing"] == nil)
  }

  @Test func flatDictionaryRejectsOddLength() {
    let json = #"["a", 1, "b"]"#.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FlatDictionary<String, Int>.self, from: json)
    }
  }

  @Test func flatDictionaryAcceptsObjectKeys() throws {
    let json = #"[{"global": {}}, 7]"#.data(using: .utf8)!
    let dict = try JSONDecoder().decode(FlatDictionary<TaggedEnum, Int>.self, from: json)
    #expect(dict.pairs.first?.key.caseName == "global")
    #expect(dict.pairs.first?.value == 7)
  }

  @Test func taggedEnumExposesCaseAndPayload() throws {
    let json = #"{"spaceItems": {"_0": "SPACE-1"}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(tag.caseName == "spaceItems")
    #expect(try tag.payload(String.self) == "SPACE-1")
  }

  @Test func taggedEnumWithoutPayload() throws {
    let json = #"{"pinned": {}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(tag.caseName == "pinned")
    #expect(tag.hasPayload == false)
  }

  @Test func flatDictionaryRejectsDuplicateKeys() {
    let json = #"["a", 1, "a", 2]"#.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FlatDictionary<String, Int>.self, from: json)
    }
  }

  @Test func taggedEnumRejectsNonObjectBody() {
    let json = #"{"spaceItems": "SPACE-1"}"#.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(TaggedEnum.self, from: json)
    }
  }

  @Test func taggedEnumAcceptsNullBody() throws {
    let json = #"{"pinned": null}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(tag.caseName == "pinned")
    #expect(tag.hasPayload == false)
  }

  @Test func taggedEnumPayloadAtSecondPosition() throws {
    let json = #"{"split": {"_0": "A", "_1": 42}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(try tag.payload(String.self) == "A")
    #expect(try tag.payload(Int.self, at: 1) == 42)
  }

  @Test func taggedEnumMissingPayloadThrows() throws {
    let json = #"{"pinned": {}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(throws: DecodingError.self) {
      try tag.payload(String.self)
    }
  }

  @Test func taggedEnumLargeIntegerPayloadIsExact() throws {
    let json = #"{"id": {"_0": 9007199254740993}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(try tag.payload(Int.self) == 9_007_199_254_740_993)
  }

  @Test func taggedEnumDecodesWholeBody() throws {
    struct Body: Decodable { let savedURL: String }
    let json = #"{"tab": {"savedURL": "https://example.com/a", "extra": 1}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(try tag.body(Body.self).savedURL == "https://example.com/a")
  }
}
