import ArcImport
@testable import CoreBridge
import CoreTestSupport
import EngineAPI
import Foundation
import Testing

/// The profile import against a fake Arc `User Data` folder (invented values), a recording engine and fake key providers.
/// Never real Arc data, never the Keychain, never an engine.
@MainActor
struct ProfileImportCoordinatorTests {
  /// Just after the fixture's base date: its cookies are unexpired and its visits are inside the retention window.
  static let clock = Date(timeIntervalSince1970: 1_704_067_200 + 10)
  static let good = FakeSafeStorageKeyProvider(password: FakeChromiumProfile.safeStoragePassword)

  @MainActor
  struct Harness {
    let folder: ArcUserDataFolder
    let engine: RecordingImportEngine
    let records: FakeArcImportRecordStore
    let provider: CountingKeyProvider
    let coordinator: ProfileImportCoordinator

    init(
      folder: ArcUserDataFolder? = nil, provider: FakeSafeStorageKeyProvider = ProfileImportCoordinatorTests.good,
      batchSize: Int = 500, historyVisitsPerBatch: Int = 2_000, record: ArcImportRecord = ArcImportRecord(),
      engine: RecordingImportEngine? = nil
    ) throws {
      let folder = try folder ?? ArcUserDataFolder()
      self.folder = folder
      let engine = engine ?? RecordingImportEngine()
      self.engine = engine
      records = FakeArcImportRecordStore(record)
      self.provider = CountingKeyProvider(provider)
      coordinator = ProfileImportCoordinator(
        engine: engine, importRecord: records, keyProvider: self.provider,
        configuration: ProfileImportConfiguration(
          batchSize: batchSize, historyVisitsPerBatch: historyVisitsPerBatch, scratchParent: folder.scratch),
        now: { ProfileImportCoordinatorTests.clock })
    }

    func run(_ selection: ImportSelection? = .default) async throws -> [ProfileImportEvent] {
      var events: [ProfileImportEvent] = []
      for await event in try coordinator.run(root: folder.root, consent: { _ in selection }) { events.append(event) }
      return events
    }

    func summary(_ selection: ImportSelection? = .default) async throws -> ProfileImportSummary {
      try Self.summary(of: try await run(selection))
    }

    static func summary(of events: [ProfileImportEvent]) throws -> ProfileImportSummary {
      guard case .finished(let summary)? = events.last else { throw Missing() }
      return summary
    }
  }

  struct Missing: Error {}

  static func counts(_ written: Int, skipped: Int = 0, failed: Int = 0) -> ImportTypeOutcome {
    .done(ImportItemCounts(written: written, skipped: skipped, failed: failed))
  }

  // MARK: First import

  @Test func importsEveryTypeInOrderAndRecordsWhatItWrote() async throws {
    let harness = try Harness()
    let manifest = harness.folder.manifest
    let summary = try await harness.summary()

    #expect(harness.engine.calls == ["history", "bookmarks", "cookies", "passwords", "extensions"])
    #expect(harness.engine.visitCount == manifest.visitCount)
    #expect(harness.engine.bookmarkCount == manifest.bookmarkCount)
    #expect(harness.engine.cookieCount == 2)                 // the third fixture cookie is a session cookie
    #expect(harness.engine.loginCount == manifest.logins.count)
    #expect(harness.engine.installCalls == [[manifest.extensions[0].id]])

    #expect(summary.outcomes[.history] == Self.counts(manifest.visitCount))
    #expect(summary.outcomes[.bookmarks] == Self.counts(manifest.bookmarkCount))
    #expect(summary.outcomes[.cookies] == Self.counts(2))
    #expect(summary.outcomes[.passwords] == Self.counts(manifest.logins.count))
    #expect(summary.outcomes[.extensions] == .skipped(reason: "not yet available"))
    #expect(!summary.cancelled && summary.abortReason == nil && !summary.recordFailed && !summary.canRetry)

    let record = await harness.records.stored
    let newest = try #require(manifest.history.flatMap(\.visits).map(\.date).max())
    #expect(record.historyWatermark == newest)
    #expect(record.bookmarkKeys.count == manifest.bookmarkCount)
    #expect(record.cookieKeys.count == 2 && record.loginKeys.count == manifest.logins.count)
    #expect(record.extensionIDs.isEmpty)                    // nothing was installed
    #expect(harness.provider.timesAsked == 1)
    #expect(harness.folder.leftoverSnapshots.isEmpty)
  }

  @Test func theEngineReceivesThePlainValuesTheFixtureHolds() async throws {
    let harness = try Harness()
    _ = try await harness.summary()
    let passwords = Set(harness.engine.loginBatches.flatMap { $0 }.map(\.password))
    #expect(passwords == Set(harness.folder.manifest.logins.map(\.password)))
    let values = Set(harness.engine.cookieBatches.flatMap { $0 }.map(\.value))
    #expect(values == ["fixture-session-value", "dark"])
  }

  @Test func countsReachTheConsentStepAndTheStreamStartsWithCounting() async throws {
    let harness = try Harness()
    var seen: ProfileDataCounts?
    var events: [ProfileImportEvent] = []
    for await event in try harness.coordinator.run(root: harness.folder.root, consent: { counts in
      seen = counts
      return nil
    }) { events.append(event) }
    let manifest = harness.folder.manifest
    let expected = ProfileDataCounts(
      historyURLs: manifest.history.count, historyVisits: manifest.visitCount, bookmarks: manifest.bookmarkCount,
      cookies: 2, logins: manifest.logins.count, extensions: 1)
    #expect(seen == expected)
    #expect(events.prefix(5) == ImportDataType.allCases.map { .progress($0, .counting) }[...])
    #expect(events[5] == .counted(expected))
    // Declined: nothing written, no key asked for, the scratch folder gone.
    #expect(harness.engine.calls.isEmpty && harness.provider.timesAsked == 0)
    #expect(harness.folder.leftoverSnapshots.isEmpty)
    let summary = try Harness.summary(of: events)
    #expect(summary.cancelled && summary.outcomes.isEmpty)
  }

  @Test func progressReportsWritingNofMThenDonePerType() async throws {
    let harness = try Harness(batchSize: 2)
    let events = try await harness.run()
    let bookmarks = events.compactMap { event -> ImportProgress? in
      if case .progress(.bookmarks, let progress) = event, progress != .counting { return progress }
      return nil
    }
    #expect(bookmarks == [
      .writing(done: 0, total: 5), .writing(done: 2, total: 5), .writing(done: 4, total: 5),
      .writing(done: 5, total: 5), .done(ImportItemCounts(written: 5)),
    ])
    #expect(events.contains(.progress(.extensions, .skipped(reason: "not yet available"))))
  }

  // MARK: Selection and the key

  @Test func theKeyIsAskedForOnlyWhenCookiesOrPasswordsAreSelected() async throws {
    let harness = try Harness()
    _ = try await harness.summary(ImportSelection([.history, .bookmarks, .extensions]))
    #expect(harness.provider.timesAsked == 0)
    #expect(harness.engine.cookieCount == 0 && harness.engine.loginCount == 0)
    #expect(harness.engine.calls == ["history", "bookmarks", "extensions"])
  }

  @Test func oneKeyServesCookiesAndPasswords() async throws {
    let harness = try Harness(batchSize: 1)
    _ = try await harness.summary(ImportSelection([.cookies, .passwords]))
    #expect(harness.provider.timesAsked == 1)
    #expect(harness.engine.cookieCount == 2 && harness.engine.loginCount == 3)
  }

  @Test func cookiesAndPasswordsAreCheckedByDefault() {
    #expect(ImportSelection.default.types == Set(ImportDataType.allCases))
  }

  // MARK: Keychain denied

  @Test(arguments: [SafeStorageError.accessDenied, .userCanceled, .interactionNotAllowed])
  func aDeniedKeychainFailsOnlyCookiesAndPasswordsAndOffersRetry(failure: SafeStorageError) async throws {
    let harness = try Harness(provider: FakeSafeStorageKeyProvider(failure: failure))
    let summary = try await harness.summary()
    let manifest = harness.folder.manifest
    #expect(summary.outcomes[.history] == Self.counts(manifest.visitCount))
    #expect(summary.outcomes[.bookmarks] == Self.counts(manifest.bookmarkCount))
    guard case .failed(let reason)? = summary.outcomes[.cookies] else { throw Missing() }
    #expect(summary.outcomes[.passwords] == .failed(reason: reason))
    #expect(reason.hasPrefix("Keychain"))
    #expect(summary.retryTypes == [.cookies, .passwords] && summary.canRetry)
    #expect(harness.engine.cookieCount == 0 && harness.engine.loginCount == 0)
    #expect(harness.provider.timesAsked == 1)
    let record = await harness.records.stored
    #expect(record.cookieKeys.isEmpty && record.loginKeys.isEmpty)
    #expect(record.bookmarkKeys.count == manifest.bookmarkCount)
  }

  @Test func retryRunsOnlyTheFailedTypes() async throws {
    let folder = try ArcUserDataFolder()
    let engine = RecordingImportEngine()
    let denied = try Harness(folder: folder, provider: FakeSafeStorageKeyProvider(failure: .accessDenied), engine: engine)
    let first = try await denied.summary()
    #expect(first.retryTypes == [.cookies, .passwords])
    let callsBefore = engine.calls

    // Same engine and record, a key the user now allows.
    let allowed = ProfileImportCoordinator(
      engine: engine, importRecord: denied.records, keyProvider: Self.good,
      configuration: ProfileImportConfiguration(scratchParent: folder.scratch), now: { Self.clock })
    var events: [ProfileImportEvent] = []
    for await event in try allowed.retry(root: folder.root, after: first) { events.append(event) }
    let second = try Harness.summary(of: events)

    #expect(Array(engine.calls.dropFirst(callsBefore.count)) == ["cookies", "passwords"])
    #expect(second.outcomes.keys.sorted { $0.rawValue < $1.rawValue } == [.cookies, .passwords])
    #expect(second.outcomes[.cookies] == Self.counts(2) && second.outcomes[.passwords] == Self.counts(3))
    #expect(!second.canRetry)
    #expect(folder.leftoverSnapshots.isEmpty)
  }

  // MARK: Idempotence, cancel

  @Test func aSecondImportWritesNothingNew() async throws {
    let harness = try Harness()
    let first = try await harness.summary()
    let callsAfterFirst = harness.engine.calls
    let second = try await harness.summary()
    let manifest = harness.folder.manifest

    #expect(harness.engine.calls == callsAfterFirst + ["extensions"])    // only the skipped install step is asked again
    #expect(second.outcomes[.history] == Self.counts(0, skipped: manifest.visitCount))
    #expect(second.outcomes[.bookmarks] == Self.counts(0, skipped: manifest.bookmarkCount))
    #expect(second.outcomes[.cookies] == Self.counts(0, skipped: 2))
    #expect(second.outcomes[.passwords] == Self.counts(0, skipped: manifest.logins.count))
    #expect(first.outcomes[.cookies] == Self.counts(2))
  }

  @Test func cancelBetweenBatchesKeepsWhatWasImportedAndAReimportAddsTheRest() async throws {
    let harness = try Harness(batchSize: 2)
    let coordinator = harness.coordinator
    harness.engine.afterCall = { name, count in if name == "bookmarks", count == 1 { coordinator.cancel() } }
    let first = try await harness.summary()
    let manifest = harness.folder.manifest

    #expect(first.cancelled)
    #expect(first.outcomes[.history] == Self.counts(manifest.visitCount))
    #expect(first.outcomes[.bookmarks] == Self.counts(2))
    for type in [ImportDataType.cookies, .passwords, .extensions] {
      #expect(first.outcomes[type] == .skipped(reason: "cancelled"))
    }
    #expect(harness.engine.bookmarkBatches.count == 1 && harness.engine.cookieCount == 0)
    let kept = await harness.records.stored
    #expect(kept.bookmarkKeys.count == 2 && kept.cookieKeys.isEmpty)
    #expect(harness.folder.leftoverSnapshots.isEmpty)

    harness.engine.afterCall = nil
    let second = try await harness.summary()
    #expect(!second.cancelled)
    #expect(second.outcomes[.bookmarks] == Self.counts(3, skipped: 2))
    #expect(second.outcomes[.history] == Self.counts(0, skipped: manifest.visitCount))
    #expect(second.outcomes[.cookies] == Self.counts(2))
    // Across both runs every bookmark reached the engine exactly once.
    #expect(harness.engine.bookmarkCount == manifest.bookmarkCount)
    let urls = harness.engine.bookmarkBatches.flatMap { $0 }.map(\.url)
    #expect(Set(urls).count == urls.count)
  }

  @Test func cancelDuringHistoryResumesFromTheLastRecordedVisit() async throws {
    let harness = try Harness(historyVisitsPerBatch: 2)
    let coordinator = harness.coordinator
    harness.engine.afterCall = { name, count in if name == "history", count == 1 { coordinator.cancel() } }
    let first = try await harness.summary()
    let manifest = harness.folder.manifest

    // The fixture's visits sort by time into batches of 2, 2 and 1; the first batch holds the two oldest.
    let times = manifest.history.flatMap(\.visits).map(\.date).sorted()
    #expect(first.cancelled)
    #expect(harness.engine.historyCalls.map(\.visits) == [2])
    let afterFirst = await harness.records.stored
    #expect(afterFirst.historyWatermark == times[1])

    harness.engine.afterCall = nil
    let second = try await harness.summary()
    #expect(harness.engine.historyCalls.dropFirst().map(\.visits) == [2, 1])
    #expect(harness.engine.historyCalls.dropFirst().allSatisfy { $0.watermark == times[1] })
    #expect(second.outcomes[.history] == Self.counts(3, skipped: 2))
    #expect(harness.engine.visitCount == manifest.visitCount)
    let record = await harness.records.stored
    #expect(record.historyWatermark == times[4])
  }

  @Test func visitsAtOrBeforeTheWatermarkAreNotSent() async throws {
    let manifest = try ArcUserDataFolder().manifest
    let times = manifest.history.flatMap(\.visits).map(\.date).sorted()
    let harness = try Harness(record: ArcImportRecord(historyWatermark: times[2]))
    let summary = try await harness.summary(ImportSelection([.history]))
    #expect(harness.engine.visitCount == 2)
    #expect(summary.outcomes[.history] == Self.counts(2, skipped: 3))
    #expect(harness.engine.historyCalls.first?.watermark == times[2])
  }

  // MARK: Plaintext lifetime

  private static func isZeroed(_ secret: SecretBytes) -> Bool {
    secret.count > 0 && secret.utf8String().unicodeScalars.allSatisfy { $0.value == 0 }
  }

  @Test func theCoordinatorZeroesEveryBatchItWrote() async throws {
    let harness = try Harness(batchSize: 1)
    harness.engine.wipesSecrets = false
    _ = try await harness.summary(ImportSelection([.cookies, .passwords]))
    #expect(harness.engine.receivedCookies.count == 2 && harness.engine.receivedLogins.count == 3)
    #expect(harness.engine.receivedCookies.allSatisfy { Self.isZeroed($0.value) })
    #expect(harness.engine.receivedLogins.allSatisfy { Self.isZeroed($0.password) })
  }

  @Test func aCancelAfterDecryptingZeroesTheBatchAndDecryptsNothingMore() async throws {
    let harness = try Harness(batchSize: 1)
    harness.engine.wipesSecrets = false
    let coordinator = harness.coordinator
    var pulls: [[ArcCookie]] = []
    coordinator.afterPull = { type, items in
      guard type == .cookies, let cookies = items as? [ArcCookie] else { return }
      pulls.append(cookies)
      if pulls.count == 1 { coordinator.cancel() }
    }
    let summary = try await harness.summary(ImportSelection([.cookies, .passwords]))
    #expect(summary.cancelled)
    #expect(pulls.count == 1 && pulls[0].count == 1)           // only one batch was ever in plaintext
    #expect(pulls[0].allSatisfy { Self.isZeroed($0.value) })    // and the coordinator zeroed it, not the engine
    #expect(harness.engine.cookieCount == 0 && harness.engine.loginCount == 0)
    #expect(summary.outcomes[.passwords] == .skipped(reason: "cancelled"))
    #expect(harness.folder.leftoverSnapshots.isEmpty)
  }

  @Test func aCancelBetweenBatchesLeavesNoPlaintextBehind() async throws {
    let harness = try Harness(batchSize: 1)
    harness.engine.wipesSecrets = false
    let coordinator = harness.coordinator
    harness.engine.afterCall = { name, count in if name == "passwords", count == 1 { coordinator.cancel() } }
    var pulled: [ArcLogin] = []
    coordinator.afterPull = { type, items in if type == .passwords { pulled += (items as? [ArcLogin]) ?? [] } }
    let summary = try await harness.summary(ImportSelection([.passwords]))
    #expect(summary.cancelled && harness.engine.loginCount == 1)
    #expect(pulled.count == 1 && pulled.allSatisfy { Self.isZeroed($0.password) })
  }

  // MARK: Salt

  @Test func recordKeysAreSaltedWithAPerInstallSaltStoredInTheRecord() async throws {
    let harness = try Harness()
    _ = try await harness.summary(ImportSelection([.bookmarks]))
    let record = await harness.records.stored
    let salt = try #require(record.salt)
    #expect(salt.count == 32)
    let bookmarks = try BookmarksReader.read(from: harness.folder.manifest.bookmarksURL).bookmarks
    #expect(record.bookmarkKeys == Set(bookmarks.map { ArcImportKey.bookmark($0, salt: salt) }))
    #expect(record.bookmarkKeys.isDisjoint(with: Set(bookmarks.map { ArcImportKey.bookmark($0) })))
    // A later run reuses the salt, so it still recognizes what the first one wrote.
    let second = try await harness.summary(ImportSelection([.bookmarks]))
    #expect(second.outcomes[.bookmarks] == Self.counts(0, skipped: bookmarks.count))
    #expect(await harness.records.stored.salt == salt)
  }

  @Test func aStoredSaltIsKept() async throws {
    let harness = try Harness(record: ArcImportRecord(salt: "stored-salt"))
    _ = try await harness.summary(ImportSelection([.bookmarks]))
    #expect(await harness.records.stored.salt == "stored-salt")
  }

  // MARK: History failures

  @Test func theWatermarkStopsAtAVisitTheEngineRefused() async throws {
    let harness = try Harness(historyVisitsPerBatch: 2)
    let times = harness.folder.manifest.history.flatMap(\.visits).map(\.date).sorted()
    let engine = harness.engine
    // The first batch is stored; from the second on the engine refuses one visit per batch.
    engine.afterCall = { name, count in
      if name == "history", count == 1 {
        engine.scripted["history"] = ImportWriteResult(written: 1, failed: 1, latestVisit: times[3])
      }
    }
    let summary = try await harness.summary(ImportSelection([.history]))
    #expect(engine.historyCalls.map(\.visits) == [2, 2, 1])      // the rest still imports
    #expect(summary.outcomes[.history] == Self.counts(4, failed: 2))
    #expect(await harness.records.stored.historyWatermark == times[1])
  }

  // MARK: Failures

  @Test func aBatchTheEngineRefusedIsNotRecordedSoARetryCoversIt() async throws {
    let harness = try Harness()
    harness.engine.scripted["bookmarks"] = ImportWriteResult(written: 4, failed: 1, failureReason: "invalid url: 1\n")
    let summary = try await harness.summary(ImportSelection([.bookmarks]))
    #expect(summary.outcomes[.bookmarks] == Self.counts(4, failed: 1))
    #expect(await harness.records.stored.bookmarkKeys.isEmpty)
    #expect(summary.lines == ["Bookmarks: 4 bookmarks added, 1 failed"])
  }

  @Test func aMissingBookmarksFileIsSkippedAndTheRestImports() async throws {
    let harness = try Harness(folder: ArcUserDataFolder(withBookmarks: false))
    let summary = try await harness.summary()
    #expect(summary.outcomes[.bookmarks] == .skipped(reason: "not in the Arc profile"))
    #expect(!harness.engine.calls.contains("bookmarks"))
    #expect(summary.outcomes[.history] == Self.counts(harness.folder.manifest.visitCount))
  }

  @Test func anUnreadableHistoryFileFailsOnlyHistoryAndCleansUp() async throws {
    let folder = try ArcUserDataFolder()
    try Data("not a database".utf8).write(to: folder.profile.appendingPathComponent("History"))
    let harness = try Harness(folder: folder)
    let summary = try await harness.summary()
    #expect(summary.outcomes[.history] == .failed(reason: "could not read History"))
    #expect(summary.retryTypes == [.history])
    #expect(summary.outcomes[.bookmarks] == Self.counts(folder.manifest.bookmarkCount))
    #expect(folder.leftoverSnapshots.isEmpty)
  }

  @Test func aMissingArcFolderAbortsBeforeAnythingIsCopied() async throws {
    let harness = try Harness()
    let missing = harness.folder.root.appendingPathComponent("Nowhere", isDirectory: true)
    var events: [ProfileImportEvent] = []
    for await event in try harness.coordinator.run(root: missing, consent: { _ in .default }) { events.append(event) }
    let summary = try Harness.summary(of: events)
    #expect(events.count == 1)
    #expect(summary.abortReason == "Arc data not found" && summary.outcomes.isEmpty)
    #expect(harness.engine.calls.isEmpty && harness.provider.timesAsked == 0)
    #expect(harness.folder.leftoverSnapshots.isEmpty)
  }

  @Test func anUnreadableRecordAbortsBeforeAnythingIsWritten() async throws {
    let harness = try Harness()
    await harness.records.setFailsLoads(true)
    let summary = try await harness.summary()
    #expect(summary.abortReason == "the import record could not be read")
    #expect(harness.engine.calls.isEmpty && harness.folder.leftoverSnapshots.isEmpty)
  }

  @Test func aRecordThatCannotBeSavedIsReportedNotThrown() async throws {
    let harness = try Harness()
    await harness.records.setFailsWrites(true)
    let summary = try await harness.summary(ImportSelection([.bookmarks]))
    #expect(summary.recordFailed)
    #expect(summary.outcomes[.bookmarks] == Self.counts(harness.folder.manifest.bookmarkCount))
  }

  @Test func aSecondRunWhileOneIsActiveIsRefused() async throws {
    let harness = try Harness()
    let stream = try harness.coordinator.run(root: harness.folder.root, consent: { _ in .default })
    #expect(harness.coordinator.isRunning)
    #expect(throws: ProfileImportError.alreadyRunning) {
      _ = try harness.coordinator.run(root: harness.folder.root, consent: { _ in .default })
    }
    for await _ in stream {}
    #expect(!harness.coordinator.isRunning)
    _ = try harness.coordinator.run(root: harness.folder.root, consent: { _ in nil })
  }

  // MARK: Extensions

  @Test func anEngineWithoutTheInstallStepSkipsExtensions() async throws {
    let bare = BareImportEngine()
    let folder = try ArcUserDataFolder()
    let coordinator = ProfileImportCoordinator(
      engine: bare, importRecord: FakeArcImportRecordStore(), keyProvider: Self.good,
      configuration: ProfileImportConfiguration(scratchParent: folder.scratch), now: { Self.clock })
    var events: [ProfileImportEvent] = []
    for await event in try coordinator.run(root: folder.root, consent: { _ in ImportSelection([.extensions]) }) {
      events.append(event)
    }
    let summary = try Harness.summary(of: events)
    #expect(summary.outcomes == [.extensions: .skipped(reason: "not yet available")])
    #expect(summary.lines == ["Extensions: skipped, not yet available"])
  }

  @Test func installedExtensionsAreRecordedAndNotAskedAgain() async throws {
    let harness = try Harness()
    harness.engine.installResult = ImportWriteResult(written: 1)
    let first = try await harness.summary(ImportSelection([.extensions]))
    #expect(first.outcomes[.extensions] == Self.counts(1))
    #expect(await harness.records.stored.extensionIDs == [harness.folder.manifest.extensions[0].id])
    let second = try await harness.summary(ImportSelection([.extensions]))
    #expect(second.outcomes[.extensions] == Self.counts(0, skipped: 1))
    #expect(harness.engine.installCalls.count == 1)
  }

  // MARK: Counts only

  @Test func eventsAndSummaryHoldNoItemText() async throws {
    let harness = try Harness(provider: FakeSafeStorageKeyProvider(failure: .accessDenied))
    let events = try await harness.run()
    let text = events.map { String(describing: $0) }.joined(separator: "\n")
      + (try Harness.summary(of: events)).lines.joined(separator: "\n")
    let manifest = harness.folder.manifest
    var forbidden = ["example", "fixture", "correct-horse", "session", "Reading"]
    forbidden += manifest.logins.map(\.username).filter { !$0.isEmpty }
    forbidden += manifest.logins.map(\.password)
    for word in forbidden { #expect(!text.localizedCaseInsensitiveContains(word), "\(word) leaked") }
  }
}
