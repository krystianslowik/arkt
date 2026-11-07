import ArcImport
import CoreTestSupport
import Foundation
import Testing

struct ExtensionListReaderTests {
  // MARK: - Helpers

  private static let webStoreURL = "https://clients2.google.com/service/update2/crx"

  private func json(_ settings: String) -> Data {
    Data(#"{"extensions":{"settings":{\#(settings)}}}"#.utf8)
  }

  private func item(
    location: Int, state: Int? = 1, name: String? = "Name", updateURL: String? = nil, extra: String = ""
  ) -> String {
    var manifest: [String] = []
    if let name { manifest.append(#""name":"\#(name)""#) }
    if let updateURL { manifest.append(#""update_url":"\#(updateURL)""#) }
    var fields = [#""location":\#(location)"#, #""manifest":{\#(manifest.joined(separator: ","))}"#]
    if let state { fields.append(#""state":\#(state)"#) }
    if !extra.isEmpty { fields.append(extra) }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private func ids(_ entries: [ExtensionListReader.Entry]) -> [String] { entries.map(\.id) }

  // MARK: - Fixtures

  @Test func fixtureProfileYieldsOnlyTheWebStoreExtension() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("ext-reader-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let manifest = try FakeChromiumProfile.make(at: base.appendingPathComponent("User Data/Default"))
    let snapshot = try ArcProfileSnapshot.make(root: base.appendingPathComponent("User Data"), scratchParent: base)
    defer { snapshot.remove() }

    let entries = try ExtensionListReader.read(profile: try #require(snapshot.profiles.first))

    let expected = manifest.extensions.filter { $0.kind == .webStore }
    #expect(expected.count == 1)
    #expect(entries == [.init(id: expected[0].id, name: expected[0].name, isEnabled: true, location: .internal)])
  }

  @Test func maintainerProbeShapeKeepsTenOfFifteen() throws {
    var settings: [String] = []
    for index in 0..<10 { settings.append(#""web\#(index)":\#(item(location: 1))"#) }
    for index in 0..<5 { settings.append(#""comp\#(index)":\#(item(location: 5))"#) }
    let entries = try ExtensionListReader.read(preferences: json(settings.joined(separator: ",")), securePreferences: nil)
    #expect(entries.count == 10)
    #expect(entries.allSatisfy { $0.id.hasPrefix("web") })
  }

  // MARK: - Filtering

  @Test(arguments: [
    (1, nil as String?, true),
    (1, Self.webStoreURL, true),
    (10, Self.webStoreURL, true),
    (10, nil, false),
    (1, "https://example.com/update.xml", false),
    (10, "https://example.com/update.xml", false),
    (1, "https://clients2.google.com.evil.example/service/update2/crx", false),
    (4, nil, false),
    (4, Self.webStoreURL, false),
    (5, nil, false),
    (5, Self.webStoreURL, false),
    (2, Self.webStoreURL, false),
    (6, Self.webStoreURL, false),
    (7, Self.webStoreURL, false),
    (8, nil, false),
    (9, Self.webStoreURL, false),
    (0, nil, false),
  ])
  func locationAndUpdateURLRules(location: Int, updateURL: String?, kept: Bool) throws {
    let entries = try ExtensionListReader.read(
      preferences: json(#""a":\#(item(location: location, updateURL: updateURL))"#), securePreferences: nil)
    #expect(entries.count == (kept ? 1 : 0))
  }

  @Test func entryWithoutLocationIsExcluded() throws {
    let data = json(#""a":{"manifest":{"name":"x"},"state":1}"#)
    #expect(try ExtensionListReader.read(preferences: data, securePreferences: nil).isEmpty)
  }

  // MARK: - Fields

  @Test func reportsEnabledAndDisabledAndLocation() throws {
    let data = json(
      #""a":\#(item(location: 1, state: 1)),"b":\#(item(location: 10, state: 0, updateURL: Self.webStoreURL)),"#
        + #""c":\#(item(location: 1, state: 1, extra: #""disable_reasons":1"#)),"d":\#(item(location: 1, state: nil))"#)
    let entries = try ExtensionListReader.read(preferences: data, securePreferences: nil)
    #expect(ids(entries) == ["a", "b", "c", "d"])
    #expect(entries.map(\.isEnabled) == [true, false, false, false])
    #expect(entries.map(\.location) == [.internal, .externalComponent, .internal, .internal])
  }

  @Test func nameIsNilWhenTheManifestHasNoUsableName() throws {
    let data = json(
      #""a":\#(item(location: 1, name: nil)),"b":\#(item(location: 1, name: "__MSG_appName__")),"#
        + #""c":{"location":1,"state":1}"#)
    let entries = try ExtensionListReader.read(preferences: data, securePreferences: nil)
    #expect(entries.map(\.name) == [nil, nil, nil])
  }

  // MARK: - Merging

  @Test func mergesBothFilesByIDWithSecurePreferencesWinning() throws {
    let preferences = json(
      #""a":\#(item(location: 1, state: 1, name: "From Preferences")),"b":\#(item(location: 1, name: "Only Preferences"))"#)
    let secure = json(
      #""a":{"state":0},"c":{"location":1,"state":1}"#)
    let entries = try ExtensionListReader.read(preferences: preferences, securePreferences: secure)
    #expect(ids(entries) == ["a", "b", "c"])
    #expect(entries[0].name == "From Preferences")
    #expect(entries[0].isEnabled == false)
    #expect(entries[1].name == "Only Preferences")
  }

  @Test func idPresentInBothFilesCountsOnce() throws {
    let data = json(#""a":\#(item(location: 1))"#)
    #expect(try ExtensionListReader.read(preferences: data, securePreferences: data).count == 1)
  }

  // MARK: - Errors and empty results

  @Test func malformedJSONIsATypedError() {
    let good = json(#""a":\#(item(location: 1))"#)
    #expect(throws: ExtensionListReader.ReadError.malformedJSON(file: "Preferences")) {
      try ExtensionListReader.read(preferences: Data("{not json".utf8), securePreferences: good)
    }
    #expect(throws: ExtensionListReader.ReadError.malformedJSON(file: "Secure Preferences")) {
      try ExtensionListReader.read(preferences: good, securePreferences: Data("[1,2]".utf8))
    }
    #expect(throws: ExtensionListReader.ReadError.malformedJSON(file: "Preferences")) {
      try ExtensionListReader.read(preferences: Data(), securePreferences: nil)
    }
  }

  @Test(arguments: [
    #"{}"#, #"{"extensions":{}}"#, #"{"extensions":{"settings":{}}}"#, #"{"extensions":[]}"#,
    #"{"extensions":{"settings":[]}}"#, #"{"extensions":{"settings":{"a":"text"}}}"#,
  ])
  func missingOrEmptyKeysGiveAnEmptyResult(text: String) throws {
    #expect(try ExtensionListReader.read(preferences: Data(text.utf8), securePreferences: nil).isEmpty)
  }

  @Test func absentFilesGiveAnEmptyResult() throws {
    #expect(try ExtensionListReader.read(preferences: nil, securePreferences: nil).isEmpty)
  }

  @Test func profileWithoutPreferencesFilesGivesAnEmptyResult() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("ext-reader-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(
      at: base.appendingPathComponent("User Data/Default"), withIntermediateDirectories: true)
    try Data().write(to: base.appendingPathComponent("User Data/Default/History"))
    let snapshot = try ArcProfileSnapshot.make(root: base.appendingPathComponent("User Data"), scratchParent: base)
    defer { snapshot.remove() }
    #expect(try ExtensionListReader.read(profile: try #require(snapshot.profiles.first)).isEmpty)
  }
}
