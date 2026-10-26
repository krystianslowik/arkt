import Foundation
import Testing
@testable import CrashReporting

/// Retention (#129): at most 20 reports, kept 30 days, measured with an injected clock.
struct StoreRetentionTests {
  private let epoch = Date(timeIntervalSince1970: 2_000_000_000)

  private func report(_ index: Int, at date: Date) -> CrashReport {
    CrashFixtures.stripper.report(from: CrashFixtures.raw(at: date), id: String(format: "%08d-0000-0000-0000-000000000000", index))
  }

  private func makeStore(_ clock: CrashFixtures.Clock, directory: URL = CrashFixtures.makeDirectory()) -> CrashReportStore {
    CrashReportStore(directory: directory, now: { clock.now })
  }

  @Test func savesAndReadsBackNewestFirst() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(report(1, at: epoch))
    clock.advance(days: 1)
    try store.save(report(2, at: clock.now))
    #expect(try store.reports().map(\.id) == [report(2, at: epoch).id, report(1, at: epoch).id])
  }

  @Test func keepsTheNewestTwentyAndDropsTheRest() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    for index in 1...25 {
      clock.advance(days: 0.01)
      try store.save(report(index, at: clock.now))
    }
    let kept = try store.reports()
    #expect(kept.count == 20)
    #expect(kept.first?.id == report(25, at: epoch).id)
    #expect(kept.last?.id == report(6, at: epoch).id)
    #expect(try fileCount(store.directory) == 20, "the dropped reports are deleted from disk, not hidden")
  }

  @Test func dropsReportsOlderThanThirtyDaysButKeepsThirtyExactly() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(report(1, at: epoch))
    clock.advance(days: 30)
    #expect(try store.reports().count == 1, "exactly 30 days old is kept")
    clock.advance(days: 0.001)
    #expect(try store.reports().isEmpty, "older than 30 days is gone")
    #expect(try fileCount(store.directory) == 0)
  }

  @Test func savingPrunesExpiredReports() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(report(1, at: epoch))
    clock.advance(days: 31)
    try store.save(report(2, at: clock.now))
    #expect(try store.reports().map(\.id) == [report(2, at: epoch).id])
  }

  @Test func removeAndRemoveAll() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(report(1, at: epoch))
    try store.save(report(2, at: epoch))
    store.remove(id: report(1, at: epoch).id)
    #expect(try store.reports().count == 1)
    store.removeAll()
    #expect(try store.reports().isEmpty)
  }

  @Test func aCorruptFileIsDeletedNotFatal() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    try store.save(report(1, at: epoch))
    try Data("not json".utf8).write(to: store.directory.appendingPathComponent("junk.json"))
    #expect(try store.reports().count == 1)
    #expect(try fileCount(store.directory) == 1)
  }

  @Test func anUnsafeIdNeverEscapesTheFolder() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    defer { try? FileManager.default.removeItem(at: store.directory) }
    var bad = report(1, at: epoch)
    bad.id = "../../escape"
    #expect(throws: CrashReportStore.StoreError.self) { try store.save(bad) }
  }

  @Test func theReportsFolderIsMissingUntilTheFirstSave() throws {
    let clock = CrashFixtures.Clock(epoch)
    let store = makeStore(clock)
    #expect(try store.reports().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.directory.path))
  }

  private func fileCount(_ directory: URL) throws -> Int {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).count
  }
}
