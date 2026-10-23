import Archive
import Foundation
import Testing
import ArcImport

struct ArchiveCheckSummaryTests {
  @Test func summarizesTheSyntheticFixtureAsCountsOnly() throws {
    let result = try ArcArchiveImporterTests.importFixture()
    let lines = ArchiveCheckSummary.lines(report: result.report)
    #expect(lines == [
      "archive entries: 10",
      "archive imported: 7 (manual 5, auto 2)",
      "archive sources: space 4, little arc 1, unknown 2",
      "archive skipped: 3",
      "  decodeFailed: 1",
      "    keyNotFound (archivedAt): 1",
      "  invalidURL: 1",
      "  unsupportedKind: 1",
      "archive warnings: 2",
      "  archiveSpaceNotImported: 1",
      "  unsupportedValue: 1",
    ])
    ImportCheckSummaryTests.expectAllowlisted(lines)
    let text = lines.joined(separator: "\n")
    for item in result.items {
      if !item.title.isEmpty { #expect(!text.contains(item.title)) }
      if let url = item.url { #expect(!text.contains(url.absoluteString)) }
      #expect(!text.contains(item.id.uuidString))
    }
    for skipped in result.report.skipped { #expect(!text.contains(skipped.itemID)) }
  }

  @Test func groupsByCaseNameWithoutPayloads() {
    var report = ArchiveImportReport(entries: 5)
    report.skipped = [
      SkippedItem(itemID: "secret-1", reason: .unsupportedKind("secret easel")),
      SkippedItem(itemID: "secret-2", reason: .decodeFailed("secret message https://secret.example")),
    ]
    report.warnings = [
      .archiveSpaceNotImported(itemID: "secret-3"),
      .archivedFolderChildrenDropped(itemID: "secret-4", count: 987),
      .unsupportedValue(itemID: "secret-5", field: "secretField"),
    ]
    let lines = ArchiveCheckSummary.lines(report: report)
    ImportCheckSummaryTests.expectAllowlisted(lines)
    #expect(Array(lines.suffix(6)) == [
      "  decodeFailed: 1",
      "  unsupportedKind: 1",
      "archive warnings: 3",
      "  archiveSpaceNotImported: 1",
      "  archivedFolderChildrenDropped: 1",
      "  unsupportedValue: 1",
    ])
    let text = lines.joined(separator: "\n").lowercased()
    #expect(!text.contains("secret"))
    #expect(!text.contains("easel"))
    #expect(!text.contains("http"))
    #expect(!text.contains("987"))
  }

  @Test func emptyReportIsAllZeros() {
    let lines = ArchiveCheckSummary.lines(report: ArchiveImportReport())
    #expect(lines == [
      "archive entries: 0",
      "archive imported: 0 (manual 0, auto 0)",
      "archive sources: space 0, little arc 0, unknown 0",
      "archive skipped: 0",
      "archive warnings: 0",
    ])
    ImportCheckSummaryTests.expectAllowlisted(lines)
  }

  /// #100: `decodeFailed` entries are broken down by `DecodingError` case and allowlisted Arc schema key only; any
  /// non-allowlisted key name is redacted to `"other"`.
  @Test func decodeFailedBreakdownGroupsByErrorCaseAndAllowlistedKey() {
    struct FakeKey: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init(_ stringValue: String) { self.stringValue = stringValue }
      init?(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { nil }
    }

    let keyNotFoundAllowed = DecodingError.keyNotFound(
      FakeKey("archivedAt"), .init(codingPath: [], debugDescription: "secret"))
    let keyNotFoundSecret = DecodingError.keyNotFound(
      FakeKey("secretUserKey"), .init(codingPath: [], debugDescription: "secret"))
    let typeMismatchAllowed = DecodingError.typeMismatch(
      String.self, .init(codingPath: [FakeKey("sidebarItem"), FakeKey("savedURL")], debugDescription: "secret"))
    let valueNotFoundSecret = DecodingError.valueNotFound(
      String.self, .init(codingPath: [FakeKey("privateKey")], debugDescription: "secret"))
    let dataCorrupted = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "secret"))

    var report = ArchiveImportReport(entries: 5)
    let errors: [any Error] = [
      keyNotFoundAllowed, keyNotFoundSecret, typeMismatchAllowed, valueNotFoundSecret, dataCorrupted,
    ]
    for (index, error) in errors.enumerated() {
      report.skipped.append(SkippedItem(itemID: "id-\(index)", reason: .decodeFailed("secret")))
      report.decodeFailures.append(ArcDecodeFailureKind(error))
    }

    let lines = ArchiveCheckSummary.lines(report: report)
    ImportCheckSummaryTests.expectAllowlisted(lines)
    #expect(lines == [
      "archive entries: 5",
      "archive imported: 0 (manual 0, auto 0)",
      "archive sources: space 0, little arc 0, unknown 0",
      "archive skipped: 5",
      "  decodeFailed: 5",
      "    dataCorrupted: 1",
      "    keyNotFound (archivedAt): 1",
      "    keyNotFound (other): 1",
      "    typeMismatch (savedURL): 1",
      "    valueNotFound (other): 1",
      "archive warnings: 0",
    ])
    let joined = lines.joined(separator: "\n").lowercased()
    #expect(!joined.contains("secret"))
    #expect(!joined.contains("private"))
  }
}
