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
}
