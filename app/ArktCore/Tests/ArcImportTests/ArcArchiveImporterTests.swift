import Archive
import Foundation
import Testing
@testable import ArcImport
import SidebarModel

struct ArcArchiveImporterTests {
  static let alpha = SpaceID()
  static let beta = SpaceID()
  static let spaceMap = [ArcSidebarImporterTests.alphaID: alpha, ArcSidebarImporterTests.betaID: beta]

  static func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(
      forResource: "StorableArchiveItems-synthetic", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  static func importFixture() throws -> ArcArchiveImportResult {
    ArcArchiveImporter.makeItems(from: try ArcArchiveFile.decode(fixtureData()), spaceIDsByArcID: spaceMap)
  }

  static func item(_ result: ArcArchiveImportResult, _ suffix: String) throws -> ArchivedItem {
    let id = try #require(UUID(uuidString: "C0000000-0000-4000-8000-000000000\(suffix)"))
    return try #require(result.items.first { $0.id == id })
  }

  /// Imports a file built from the fixture with `items` replaced.
  static func importItems(_ items: [Any]) throws -> ArcArchiveImportResult {
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    json["items"] = items
    let file = try ArcArchiveFile.decode(JSONSerialization.data(withJSONObject: json))
    return ArcArchiveImporter.makeItems(from: file, spaceIDsByArcID: spaceMap)
  }

  static func tabEntry(id: String, url: String) -> [String: Any] {
    [
      "reason": "manual", "archivedAt": 783_000_000, "source": ["unknown": [String: Any]()],
      "sidebarItem": [
        "id": id, "parentID": NSNull(), "childrenIds": [String](),
        "data": ["tab": ["savedURL": url]],
      ] as [String: Any],
    ]
  }

  @Test func sidebarImportMapsArcSpaceIDs() throws {
    let result = try ArcSidebarImporterTests.importFixtureResult()
    #expect(result.spaceIDsByArcID.count == 2)
    #expect(result.spaceIDsByArcID[ArcSidebarImporterTests.alphaID] == result.sidebar.spaceOrder[0])
    #expect(Set(result.spaceIDsByArcID.values) == Set(result.sidebar.spaceOrder))
  }

  @Test func reportCountsEveryEntry() throws {
    let result = try Self.importFixture()
    #expect(result.items.count == 7)
    #expect(result.report == ArchiveImportReport(
      entries: 10, imported: 7, manual: 5, auto: 2, fromSpace: 4, fromLittleArc: 1, fromUnknown: 2,
      skipped: result.report.skipped, decodeFailures: [.init(errorCase: .keyNotFound, key: "archivedAt")],
      warnings: result.report.warnings))
    #expect(result.report.skipped.count == 3)
    #expect(result.report.warnings.count == 2)
  }

  @Test func keepsFileOrder() throws {
    let suffixes = ["001", "002", "003", "004", "005", "006", "00A"]
    let expected = suffixes.map { UUID(uuidString: "C0000000-0000-4000-8000-000000000\($0)")! }
    #expect(try Self.importFixture().items.map(\.id) == expected)
  }

  @Test func manualTabFromASpaceKeepsItsFields() throws {
    let item = try Self.item(try Self.importFixture(), "001")
    #expect(item.reason == .manual)
    #expect(item.archivedAt == Date(timeIntervalSinceReferenceDate: 783_000_000))
    #expect(item.source == .space(Self.alpha))
    #expect(item.section == nil)
    #expect(item.snapshot.createdAt == Date(timeIntervalSinceReferenceDate: 782_990_000))
    #expect(item.snapshot.kind == .tab(TabItem(
      url: URL(string: "https://example.com/manual")!, title: "Manual tab",
      lastActiveAt: Date(timeIntervalSinceReferenceDate: 782_999_000))))
    let renamed = try Self.item(try Self.importFixture(), "002")
    #expect(renamed.title == "Renamed")
    #expect(renamed.reason == .auto)
    #expect(renamed.source == .space(Self.beta))
  }

  @Test func littleArcAndUnknownSources() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "003").source == .littleArc)
    #expect(try Self.item(result, "004").source == .unknown)
    // No createdAt in the file: archivedAt stands in.
    #expect(try Self.item(result, "003").snapshot.createdAt == Date(timeIntervalSinceReferenceDate: 783_000_200))
  }

  @Test func spaceThatWasNotImportedBecomesUnknownWithAWarning() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "005").source == .unknown)
    #expect(result.report.warnings.contains(.archiveSpaceNotImported(itemID: "C0000000-0000-4000-8000-000000000005")))
  }

  @Test func listBecomesAnEmptyFolder() throws {
    let item = try Self.item(try Self.importFixture(), "006")
    #expect(item.snapshot.kind == .folder(FolderItem(title: "Old folder")))
    #expect(item.snapshot.children.isEmpty)
  }

  @Test func skipsUnsupportedInvalidAndUndecodableEntries() throws {
    let skipped = try Self.importFixture().report.skipped
    #expect(skipped.contains(SkippedItem(itemID: "C0000000-0000-4000-8000-000000000007", reason: .unsupportedKind("easel"))))
    #expect(skipped.contains(SkippedItem(itemID: "C0000000-0000-4000-8000-000000000008", reason: .invalidURL)))
    #expect(skipped.contains { item in
      guard item.itemID == "C0000000-0000-4000-8000-000000000009", case .decodeFailed = item.reason else { return false }
      return true
    })
  }

  @Test func unknownReasonDefaultsToManualWithAWarning() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "00A").reason == .manual)
    #expect(result.report.warnings.contains(
      .unsupportedValue(itemID: "C0000000-0000-4000-8000-00000000000A", field: "reason")))
  }

  @Test func unknownSourceCaseBecomesUnknownWithAWarning() throws {
    var entry = Self.tabEntry(id: "C0000000-0000-4000-8000-000000000001", url: "https://example.com/a")
    entry["source"] = ["airTraffic": [String: Any]()]
    let result = try Self.importItems(["C0000000-0000-4000-8000-000000000001", entry])
    #expect(result.items.first?.source == .unknown)
    #expect(result.report.warnings == [
      .unsupportedValue(itemID: "C0000000-0000-4000-8000-000000000001", field: "source"),
    ])
  }

  @Test func malformedEntriesAreReportedAndTheRestImports() throws {
    let malformedTab: [String: Any] = [
      "reason": "manual", "archivedAt": 783_000_000, "source": ["unknown": [String: Any]()],
      "sidebarItem": [
        "id": "C0000000-0000-4000-8000-000000000002", "childrenIds": [String](),
        "data": ["tab": ["savedTitle": "no url"]],
      ] as [String: Any],
    ]
    let result = try Self.importItems([
      "C0000000-0000-4000-8000-000000000001", "not an object",
      "C0000000-0000-4000-8000-000000000002", malformedTab,
      "C0000000-0000-4000-8000-000000000003",
      Self.tabEntry(id: "C0000000-0000-4000-8000-000000000003", url: "https://example.com/ok"),
    ])
    #expect(result.report.entries == 3)
    #expect(result.report.imported == 1)
    #expect(result.items.map(\.url) == [URL(string: "https://example.com/ok")])
    #expect(result.report.skipped.map(\.itemID) == [
      "C0000000-0000-4000-8000-000000000001", "C0000000-0000-4000-8000-000000000002",
    ])
    #expect(result.report.skipped.allSatisfy { item in
      if case .decodeFailed = item.reason { return true }
      return false
    })
  }

  @Test func nonUUIDKeysGetStableIDs() throws {
    let items: [Any] = [
      "legacy-item", Self.tabEntry(id: "legacy-item", url: "https://example.com/legacy"),
      "other-item", Self.tabEntry(id: "other-item", url: "https://example.com/other"),
    ]
    let first = try Self.importItems(items).items.map(\.id)
    #expect(first.count == 2)
    #expect(Set(first).count == 2)
    #expect(try Self.importItems(items).items.map(\.id) == first)
  }

  @Test func rejectsAnUnknownFileVersion() throws {
    var json = try #require(try JSONSerialization.jsonObject(with: Self.fixtureData()) as? [String: Any])
    json["version"] = 2
    let file = try ArcArchiveFile.decode(JSONSerialization.data(withJSONObject: json))
    #expect(throws: ArcImportError.unsupportedVersion(2)) {
      try ArcArchiveImporter.checkVersion(file)
    }
    #expect(throws: Never.self) { try ArcArchiveImporter.checkVersion(ArcArchiveFile.decode(Self.fixtureData())) }
  }

  @Test func importingTwiceGivesTheSameIDs() throws {
    #expect(try Self.importFixture().items.map(\.id) == Self.importFixture().items.map(\.id))
  }

  @Test func listWithChildrenWarnsThatTheyWereDropped() throws {
    var entry = Self.tabEntry(id: "C0000000-0000-4000-8000-000000000001", url: "https://example.com/a")
    entry["sidebarItem"] = [
      "id": "C0000000-0000-4000-8000-000000000001", "parentID": NSNull(),
      "childrenIds": ["C0000000-0000-4000-8000-0000000000F1", "C0000000-0000-4000-8000-0000000000F2"],
      "title": "Folder", "data": ["list": [String: Any]()],
    ] as [String: Any]
    let result = try Self.importItems(["C0000000-0000-4000-8000-000000000001", entry])
    #expect(result.items.first?.snapshot.kind == .folder(FolderItem(title: "Folder")))
    #expect(result.items.first?.snapshot.children.isEmpty == true)
    #expect(result.report.warnings == [
      .archivedFolderChildrenDropped(itemID: "C0000000-0000-4000-8000-000000000001", count: 2),
    ])
  }

  @Test func malformedSpaceSourcePayloadIsAnUnsupportedValue() throws {
    for payload: [String: Any] in [[:], ["_0": 42]] {
      var entry = Self.tabEntry(id: "C0000000-0000-4000-8000-000000000001", url: "https://example.com/a")
      entry["source"] = ["space": payload]
      let result = try Self.importItems(["C0000000-0000-4000-8000-000000000001", entry])
      #expect(result.items.first?.source == .unknown)
      #expect(result.report.warnings == [
        .unsupportedValue(itemID: "C0000000-0000-4000-8000-000000000001", field: "source"),
      ])
    }
  }

  @Test func nodeIDForAUUIDKeyIsThatUUID() throws {
    let key = "C0000000-0000-4000-8000-000000000001"
    #expect(StableID.uuid(forArcID: key) == UUID(uuidString: key))
    #expect(StableID.uuid(forArcID: key.lowercased()) == UUID(uuidString: key))
  }

  @Test func nodeIDForANonUUIDKeyIsStableVersion8AndDistinct() throws {
    let keys = ["legacy-item", "other-item", "", "legacy-item "]
    let ids = keys.map(StableID.uuid(forArcID:))
    #expect(keys.map(StableID.uuid(forArcID:)) == ids)
    #expect(Set(ids).count == keys.count)
    for id in ids {
      let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
      #expect(bytes[6] >> 4 == 8)  // version 8
      #expect(bytes[8] >> 6 == 0b10)  // RFC 4122 variant
      #expect(Array(id.uuidString)[14] == "8")
    }
  }

  @Test func nonUUIDItemKeyUsesStableID() throws {
    let result = try Self.importItems(["legacy-item", Self.tabEntry(id: "legacy-item", url: "https://example.com/a")])
    #expect(result.items.map(\.id) == [StableID.uuid(forArcID: "legacy-item")])
  }
}
