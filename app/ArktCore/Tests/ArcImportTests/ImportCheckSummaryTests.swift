import Foundation
import Testing
import ArcImport
import SidebarModel

struct ImportCheckSummaryTests {
  @Test func summarizesSyntheticFixtureAsCountsOnly() throws {
    let (sidebar, report) = try ArcSidebarImporterTests.importFixture()
    let lines = ImportCheckSummary.lines(
      sidebar: sidebar, report: report, favicons: .init(found: 3, missing: 6))
    #expect(lines == [
      "spaces: 2 (report: 2)",
      "favorites: tabs 2, folders 0, splits 0",
      "pinned: tabs 5, folders 1, splits 1",
      "today: tabs 2, folders 0, splits 0",
      "imported totals (report): tabs 9, folders 1, splits 1",
      "skipped: 1",
      "  unsupportedKind: 1",
      "warnings: 0",
      "favicons (imported tabs): found 3, missing 6",
    ])

    // Nothing stored in the sidebar may leak into the output.
    let text = lines.joined(separator: "\n")
    for space in sidebar.spaces.values { #expect(!text.contains(space.title)) }
    for node in sidebar.nodes.values {
      if case .tab(let tab) = node.kind {
        #expect(!text.contains(tab.url.absoluteString))
        if !tab.title.isEmpty { #expect(!text.contains(tab.title)) }
      }
    }
    for skipped in report.skipped { #expect(!text.contains(skipped.itemID)) }
  }

  /// Every output line must be a label and counts. The value part also allows ":" for "spaces: 5 (report: 5)".
  static func expectAllowlisted(_ lines: [String]) {
    let allowed = /^ *[A-Za-z ()]+: [0-9a-z ,():]+$/
    for line in lines { #expect(line.wholeMatch(of: allowed) != nil, "line not allowlisted: \(line)") }
  }

  @Test func groupsReasonsAndWarningsByCaseNameWithoutPayloads() {
    var report = ImportReport()
    report.skipped = [
      SkippedItem(itemID: "secret-1", reason: .unsupportedKind("secret easel")),
      SkippedItem(itemID: "secret-2", reason: .unsupportedKind("secret arcDocument")),
      SkippedItem(itemID: "secret-3", reason: .parentSkipped(parentID: "secret-1")),
      SkippedItem(itemID: "secret-4", reason: .invalidURL),
      SkippedItem(itemID: "secret-5", reason: .decodeFailed("secret decoder message https://secret.example")),
      SkippedItem(itemID: "secret-6", reason: .duplicateReference),
      SkippedItem(itemID: "secret-7", reason: .unreachable),
      SkippedItem(itemID: "secret-8", reason: .missingItem),
      SkippedItem(itemID: "secret-9", reason: .notAllowedHere),
    ]
    report.warnings = [
      .unrecognizedProfile("secret-profile"),
      .unsupportedTheme(spaceID: "secret-space"),
      .unsupportedValue(itemID: "secret-x", field: "secretField"),
      .archiveSpaceNotImported(itemID: "secret-a"),
      .archivedFolderChildrenDropped(itemID: "secret-f", count: 7),
    ]
    let lines = ImportCheckSummary.lines(
      sidebar: Sidebar(), report: report, favicons: .init(found: 1, missing: 2))
    #expect(Array(lines.suffix(16)) == [
      "skipped: 9",
      "  decodeFailed: 1",
      "  duplicateReference: 1",
      "  invalidURL: 1",
      "  missingItem: 1",
      "  notAllowedHere: 1",
      "  parentSkipped: 1",
      "  unreachable: 1",
      "  unsupportedKind: 2",
      "warnings: 5",
      "  archiveSpaceNotImported: 1",
      "  archivedFolderChildrenDropped: 1",
      "  unrecognizedProfile: 1",
      "  unsupportedTheme: 1",
      "  unsupportedValue: 1",
      "favicons (imported tabs): found 1, missing 2",
    ])
    let text = lines.joined(separator: "\n").lowercased()
    #expect(!text.contains("secret"))
    #expect(!text.contains("easel"))
    #expect(!text.contains("http"))
    #expect(!text.contains("7"))
    Self.expectAllowlisted(lines)
  }

  @Test func fixtureOutputIsAllowlisted() throws {
    let (sidebar, report) = try ArcSidebarImporterTests.importFixture()
    Self.expectAllowlisted(ImportCheckSummary.lines(
      sidebar: sidebar, report: report, favicons: .init(found: 3, missing: 6)))
  }

  // Exhaustive switches: a new SkipReason or ImportWarning case fails to compile here until it is covered.
  static func expectedName(_ reason: SkipReason) -> String {
    switch reason {
    case .unsupportedKind: "unsupportedKind"
    case .decodeFailed: "decodeFailed"
    case .invalidURL: "invalidURL"
    case .parentSkipped: "parentSkipped"
    case .missingItem: "missingItem"
    case .notAllowedHere: "notAllowedHere"
    case .duplicateReference: "duplicateReference"
    case .unreachable: "unreachable"
    }
  }

  static func expectedName(_ warning: ImportWarning) -> String {
    switch warning {
    case .unrecognizedProfile: "unrecognizedProfile"
    case .unsupportedTheme: "unsupportedTheme"
    case .unsupportedValue: "unsupportedValue"
    case .archiveSpaceNotImported: "archiveSpaceNotImported"
    case .archivedFolderChildrenDropped: "archivedFolderChildrenDropped"
    }
  }

  @Test func caseNameDropsPayloadForEveryCase() {
    let reasons: [SkipReason] = [
      .unsupportedKind("secret"), .decodeFailed("secret (nested)"), .invalidURL,
      .parentSkipped(parentID: "secret"), .missingItem, .notAllowedHere, .duplicateReference, .unreachable,
    ]
    for reason in reasons { #expect(ImportCheckSummary.caseName(reason) == Self.expectedName(reason)) }
    let warnings: [ImportWarning] = [
      .unrecognizedProfile("secret"), .unsupportedTheme(spaceID: "secret"),
      .unsupportedValue(itemID: "secret", field: "secret"), .archiveSpaceNotImported(itemID: "secret"),
      .archivedFolderChildrenDropped(itemID: "secret", count: 3),
    ]
    for warning in warnings { #expect(ImportCheckSummary.caseName(warning) == Self.expectedName(warning)) }
  }
}
