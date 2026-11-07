import CoreTestSupport
import Foundation
import SQLite3
import Testing

@testable import ArcImport

struct HistoryReaderTests {
  // MARK: - Helpers

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func fixture(
    _ drift: FakeChromiumProfile.SchemaDrift = .none, in directory: URL
  ) throws -> FixtureManifest {
    try FakeChromiumProfile.make(at: directory, options: .init(drift: drift))
  }

  private func readAll(_ url: URL, limits: HistoryReader.Limits = .init()) throws -> (
    entries: [HistoryEntry], summary: HistoryReader.Summary, batches: [Int]
  ) {
    var entries: [HistoryEntry] = []
    var batches: [Int] = []
    let summary = try HistoryReader.read(from: url, limits: limits) { batch in
      batches.append(batch.count)
      entries += batch
    }
    return (entries, summary, batches)
  }

  /// Runs write statements against a copy of a fixture database.
  private func execute(_ url: URL, _ statements: [String]) throws {
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    for sql in statements {
      #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
    }
  }

  private func assertMatches(_ entries: [HistoryEntry], _ manifest: FixtureManifest) {
    #expect(entries.count == manifest.history.count)
    #expect(entries.reduce(0) { $0 + $1.visits.count } == manifest.visitCount)
    for expected in manifest.history {
      guard let entry = entries.first(where: { $0.url == expected.url }) else {
        Issue.record("missing entry for fixture URL")
        continue
      }
      #expect(entry.title == expected.title)
      #expect(entry.visitCount == expected.visitCount)
      #expect(entry.lastVisit == ChromiumTime.date(fromWebKit: expected.lastVisitWebKitTime))
      let sorted = expected.visits.sorted { $0.webkitTime < $1.webkitTime }
      #expect(entry.visits.map(\.time) == sorted.map(\.date))
      #expect(entry.visits.map(\.transition) == sorted.map { HistoryTransition(webKitValue: $0.transition) })
    }
  }

  // MARK: - Time and transition

  @Test func webKitTimeConvertsToDate() {
    #expect(WebKitTime.date(fromMicroseconds: 11_644_473_600_000_000) == Date(timeIntervalSince1970: 0))
    #expect(WebKitTime.date(fromMicroseconds: 11_644_473_600_000_000 + 1_500_000) == Date(timeIntervalSince1970: 1.5))
    // 2024-01-01 00:00:00 UTC
    #expect(WebKitTime.date(fromMicroseconds: 13_348_540_800_000_000) == Date(timeIntervalSince1970: 1_704_067_200))
    #expect(WebKitTime.date(fromMicroseconds: 0) == nil)
    #expect(WebKitTime.date(fromMicroseconds: -5) == nil)
  }

  @Test(arguments: [
    (Int64(0), HistoryTransition.link),
    (1, .typed),
    (2, .autoBookmark),
    (3, .autoSubframe),
    (4, .manualSubframe),
    (5, .generated),
    (6, .autoToplevel),
    (7, .formSubmit),
    (8, .reload),
    (9, .keyword),
    (10, .keywordGenerated),
    (0x1000_0000 | 0x2000_0000 | 0x0200_0000 | 1, .typed),
    (0x8000_0000 | 8, .reload),
    (0xFF, .unknown),
    (11, .unknown),
  ])
  func transitionDecodesCoreTypeFromBitmask(value: Int64, expected: HistoryTransition) {
    #expect(HistoryTransition(webKitValue: Int32(truncatingIfNeeded: value)) == expected)
  }

  // MARK: - Reading the fixture

  @Test func readsFixtureHistoryWithCountsMatchingManifest() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(in: dir)
    let result = try readAll(manifest.historyURL)
    assertMatches(result.entries, manifest)
    #expect(result.summary.urlCount == manifest.history.count)
    #expect(result.summary.visitCount == manifest.visitCount)
    #expect(result.summary.skippedURLRows == 0)
    #expect(result.summary.skippedVisitRows == 0)
    let typed = try #require(result.entries.first { $0.url == "https://example.com/" })
    #expect(typed.typedCount == 1)
  }

  @Test(arguments: [FakeChromiumProfile.SchemaDrift.extraColumn, .missingOptionalColumn])
  func driftVariantsKeepCountsMatchingManifest(drift: FakeChromiumProfile.SchemaDrift) throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(drift, in: dir)
    let result = try readAll(manifest.historyURL)
    assertMatches(result.entries, manifest)
    #expect(result.summary.skippedURLRows == 0)
    #expect(result.summary.skippedVisitRows == 0)
  }

  @Test func missingOptionalUrlsColumnsFallBackToDefaults() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(in: dir)
    try execute(manifest.historyURL, [
      "ALTER TABLE urls DROP COLUMN typed_count",
      "ALTER TABLE urls DROP COLUMN title",
      "ALTER TABLE urls DROP COLUMN visit_count",
      "ALTER TABLE urls DROP COLUMN last_visit_time",
      "ALTER TABLE visits DROP COLUMN transition",
    ])
    let result = try readAll(manifest.historyURL)
    #expect(result.entries.count == manifest.history.count)
    for expected in manifest.history {
      let entry = try #require(result.entries.first { $0.url == expected.url })
      #expect(entry.title == "")
      #expect(entry.typedCount == 0)
      #expect(entry.visitCount == expected.visitCount)
      #expect(entry.lastVisit == expected.visits.map(\.date).max())
      #expect(entry.visits.allSatisfy { $0.transition == .link })
    }
  }

  @Test func readsThroughAProfileSnapshot() async throws {
    let root = try makeDirectory()
    let scratch = try makeDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: scratch)
    }
    let manifest = try fixture(in: root.appendingPathComponent("Default", isDirectory: true))
    let entries = try await ArcProfileSnapshot.withSnapshot(root: root, scratchParent: scratch) { snapshot in
      let profile = try #require(snapshot.profiles.first)
      return try HistoryReader.readAll(profile: profile).entries
    }
    assertMatches(entries, manifest)
  }

  // MARK: - Batching and budget

  private func bigHistory(urls: Int, visitsPerURL: Int, in dir: URL) throws -> URL {
    let manifest = try fixture(in: dir)
    var statements = ["DELETE FROM visits", "DELETE FROM urls", "BEGIN"]
    var visitID = 0
    for id in 1...urls {
      statements.append("INSERT INTO urls (id, url, title, visit_count, typed_count, last_visit_time) VALUES (\(id), 'https://example.com/\(id)', 't\(id)', \(visitsPerURL), 0, \(13_348_540_800_000_000 + id))")
      for step in 0..<visitsPerURL {
        visitID += 1
        statements.append("INSERT INTO visits (id, url, visit_time, transition) VALUES (\(visitID), \(id), \(13_348_540_800_000_000 + id + step), 0)")
      }
    }
    statements.append("COMMIT")
    try execute(manifest.historyURL, statements)
    return manifest.historyURL
  }

  @Test func largeHistoryArrivesInBatchesOf500() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try bigHistory(urls: 1_200, visitsPerURL: 2, in: dir)
    let result = try readAll(url)
    #expect(result.batches == [500, 500, 200])
    #expect(result.summary.urlCount == 1_200)
    #expect(result.summary.visitCount == 2_400)
    #expect(Set(result.entries.map(\.url)).count == 1_200)
  }

  @Test func visitBudgetClosesABatchEarly() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try bigHistory(urls: 10, visitsPerURL: 5, in: dir)
    let result = try readAll(url, limits: .init(batchSize: 500, maxVisitsPerBatch: 12))
    // Each batch closes as soon as it holds at least 12 visits: 3 entries (15 visits) per batch.
    #expect(result.batches == [3, 3, 3, 1])
    #expect(result.summary.visitCount == 50)
  }

  @Test func defaultLimitsAreBatch500() {
    #expect(HistoryReader.Limits().batchSize == 500)
    #expect(HistoryReader.Limits().maxVisitsPerBatch > 0)
  }

  // MARK: - Bad rows and bad files

  @Test func badRowsAreSkippedAndCounted() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(in: dir)
    try execute(manifest.historyURL, [
      "INSERT INTO urls (id, url, title, last_visit_time) VALUES (100, NULL, 'no url', 1)",
      "INSERT INTO urls (id, url, title, last_visit_time) VALUES (101, '', 'empty url', 1)",
      "INSERT INTO visits (id, url, visit_time, transition) VALUES (200, 1, 0, 0)",
      "INSERT INTO visits (id, url, visit_time, transition) VALUES (201, 1, -7, 0)",
      "INSERT INTO visits (id, url, visit_time, transition) VALUES (202, 9999, 13348540800000000, 0)",
      "INSERT INTO visits (id, url, visit_time, transition) VALUES (203, 101, 13348540800000000, 0)",
    ])
    let result = try readAll(manifest.historyURL)
    assertMatches(result.entries, manifest)
    #expect(result.summary.skippedURLRows == 2)
    #expect(result.summary.skippedVisitRows == 4)
    #expect(result.summary.urlCount == manifest.history.count)
    #expect(result.summary.visitCount == manifest.visitCount)
  }

  @Test func missingFileThrows() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
    #expect(throws: HistoryReader.ReadError.self) { try HistoryReader.read(from: url) { _ in } }
  }

  @Test func missingTableOrRequiredColumnThrows() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(in: dir)
    try execute(manifest.historyURL, ["ALTER TABLE visits DROP COLUMN visit_time"])
    #expect(throws: HistoryReader.ReadError.missingColumn(table: "visits", column: "visit_time")) {
      try HistoryReader.read(from: manifest.historyURL) { _ in }
    }
    try execute(manifest.historyURL, ["DROP TABLE visits"])
    #expect(throws: HistoryReader.ReadError.missingTable("visits")) {
      try HistoryReader.read(from: manifest.historyURL) { _ in }
    }
  }

  @Test func notADatabaseThrows() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("History")
    try Data("not a database, just invented text".utf8).write(to: url)
    #expect(throws: HistoryReader.ReadError.self) { try HistoryReader.read(from: url) { _ in } }
  }

  @Test func handlerErrorStopsReading() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try fixture(in: dir)
    struct Stop: Error {}
    var calls = 0
    #expect(throws: Stop.self) {
      try HistoryReader.read(from: manifest.historyURL, limits: .init(batchSize: 1)) { _ in
        calls += 1
        throw Stop()
      }
    }
    #expect(calls == 1)
  }
}
