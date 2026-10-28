import ArcImport
@testable import CoreBridge
import CoreTestSupport
import EngineAPI
import Foundation
import ShellUI
import Testing

/// A scripted `ProfileImporting`: the test sends the events the coordinator would stream and asks the consent closure
/// the way the coordinator's counting step does.
@MainActor
final class FakeProfileImporter: ProfileImporting {
  private(set) var runs = 0
  private(set) var retries: [ProfileImportSummary] = []
  private(set) var cancels = 0
  var throwOnRun: ProfileImportError?
  private var consent: (@MainActor (ProfileDataCounts) async -> ImportSelection?)?
  private var continuation: AsyncStream<ProfileImportEvent>.Continuation?

  func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
    -> AsyncStream<ProfileImportEvent> {
    if let throwOnRun { throw throwOnRun }
    runs += 1
    self.consent = consent
    return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
  }

  func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
    if let throwOnRun { throw throwOnRun }
    retries.append(summary)
    return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
  }

  func cancel() { cancels += 1 }

  /// The counting step finished: returns what the user answered.
  func askConsent(_ counts: ProfileDataCounts) async -> ImportSelection? { await consent?(counts) ?? nil }
  func send(_ event: ProfileImportEvent) { continuation?.yield(event) }
  func finish(_ summary: ProfileImportSummary) {
    continuation?.yield(.finished(summary))
    continuation?.finish()
  }
}

/// Counts and a step for the Spaces and tabs row, with a log shared with the importer's events.
@MainActor
final class FakeSpacesStep {
  var count: SpacesAndTabsCount? = SpacesAndTabsCount(items: 213, spaces: 4)
  var result = SpacesAndTabsResult(items: 213, skipped: 0, failed: false, addedSpaces: [UUID()])
  private(set) var runs = 0
  var onRun: (@MainActor () -> Void)?

  var step: SpacesAndTabsStep {
    SpacesAndTabsStep(count: { [self] in count }, run: { [self] in
      runs += 1
      onRun?()
      return result
    })
  }
}

/// Lets the main actor run other tasks until `condition` holds; bounded by turns, not time.
@MainActor
func settle(_ condition: @MainActor () -> Bool) async -> Bool {
  var turns = 0
  while !condition(), turns < 20_000 {
    await Task.yield()
    turns += 1
  }
  return condition()
}

/// The browser data import's state machine against scripted coordinator events (#514).
@MainActor
struct BrowserDataImportModelTests {
  static let root = URL(fileURLWithPath: "/nonexistent/arc-user-data")
  static let counts = ProfileDataCounts(
    historyURLs: 9_000, historyVisits: 48_210, bookmarks: 0, cookies: 3_904, logins: 312, extensions: 14)

  @MainActor struct Rig {
    let model: BrowserDataImportModel
    let importer = FakeProfileImporter()
    let spaces = FakeSpacesStep()
    var outcomes: OutcomeBox

    @MainActor final class OutcomeBox { var finished: [BrowserDataImportOutcome] = [] }

    init(withSpaces: Bool = true) {
      let box = OutcomeBox()
      outcomes = box
      let importer = importer
      let spaces = spaces
      model = BrowserDataImportModel(
        coordinator: importer, root: BrowserDataImportModelTests.root, spaces: withSpaces ? spaces.step : nil,
        locale: Locale(identifier: "en_US"))
      model.onFinish = { box.finished.append($0) }
    }

    var state: BrowserDataImportState { model.state }

    /// Starts, runs the counting step and waits for the consent state. Returns the consent answer's task.
    func reachConsent(_ counts: ProfileDataCounts = BrowserDataImportModelTests.counts)
      async -> Task<ImportSelection?, Never> {
      model.start()
      _ = await settle { importer.runs == 1 }
      let answer = Task { @MainActor in await importer.askConsent(counts) }
      _ = await settle { model.state.phase == .consent }
      return answer
    }

    /// Consent, Import, and waits until the coordinator's closure returned.
    func reachProgress(_ selection: Set<BrowserDataKind>? = nil) async -> ImportSelection? {
      let answer = await reachConsent()
      if let selection {
        for kind in BrowserDataKind.allCases { model.setSelected(kind, selection.contains(kind)) }
      }
      model.beginImport()
      return await answer.value
    }
  }

  static func summary(_ outcomes: [ImportDataType: ImportTypeOutcome], cancelled: Bool = false) -> ProfileImportSummary {
    var summary = ProfileImportSummary()
    summary.outcomes = outcomes
    summary.cancelled = cancelled
    return summary
  }

  static let denial = ImportTypeOutcome.failed(reason: "Keychain access denied")

  // MARK: Consent

  @Test func theCountingStepFillsTheConsentWithEveryTypeTickedThatHasSomething() async {
    let rig = Rig()
    #expect(rig.state.phase == .counting)
    let answer = await rig.reachConsent()
    #expect(rig.state.counts[.history] == 48_210)
    #expect(rig.state.counts[.cookies] == 3_904)
    #expect(rig.state.counts[.passwords] == 312)
    #expect(rig.state.counts[.extensions] == 14)
    #expect(rig.state.counts[.spacesAndTabs] == 213)
    #expect(rig.state.counts.spaces == 4)
    #expect(rig.state.selection == [.spacesAndTabs, .history, .extensions, .cookies, .passwords],
            "everything with something in it is ticked: cookies and passwords included")
    #expect(rig.state.counts[.bookmarks] == 0)
    #expect(rig.state.showsKeychainLine)
    rig.model.cancel()
    _ = await answer.value
  }

  @Test func ticksChangeOnlyForTypesWithSomethingAndOnlyInConsent() async {
    let rig = Rig()
    let answer = await rig.reachConsent()
    rig.model.setSelected(.cookies, false)
    #expect(!rig.state.selection.contains(.cookies))
    rig.model.setSelected(.bookmarks, true)
    #expect(!rig.state.selection.contains(.bookmarks), "a type with nothing in it cannot be ticked")
    rig.model.setSelected(.cookies, true)
    #expect(rig.state.selection.contains(.cookies))
    rig.model.cancel()
    _ = await answer.value
    rig.model.setSelected(.history, false)
    #expect(rig.state.phase == .dismissed)
  }

  @Test func importWithNothingTickedDoesNothing() async {
    let rig = Rig()
    let answer = await rig.reachConsent()
    for kind in BrowserDataKind.allCases { rig.model.setSelected(kind, false) }
    rig.model.beginImport()
    #expect(rig.state.phase == .consent)
    rig.model.cancel()
    #expect(await answer.value == nil)
  }

  @Test func everyTypeAtZeroOffersOnlyCancel() async {
    let rig = Rig()
    rig.spaces.count = SpacesAndTabsCount(items: 0, spaces: 0)
    let answer = await rig.reachConsent(ProfileDataCounts())
    #expect(rig.state.isNothingToImport)
    #expect(rig.state.canImport == false)
    rig.model.beginImport()
    #expect(rig.state.phase == .consent)
    rig.model.cancel()
    #expect(await answer.value == nil)
    #expect(rig.state.phase == .dismissed)
  }

  @Test func cancelInConsentDeclinesAndWritesNothing() async {
    let rig = Rig()
    let answer = await rig.reachConsent()
    rig.model.cancel()
    #expect(rig.state.phase == .dismissed, "the sheet closes at once")
    #expect(await answer.value == nil, "the consent answer is nil: the coordinator reports a cancelled run")
    rig.importer.finish(Self.summary([:], cancelled: true))
    for _ in 0..<100 { await Task.yield() }
    #expect(rig.state.phase == .dismissed, "the coordinator's last event does not reopen a result")
    #expect(rig.outcomes.finished.count == 1)
    #expect(rig.outcomes.finished == [BrowserDataImportOutcome(importedAnything: false)])
    #expect(rig.spaces.runs == 0)
  }

  @Test func cancelWhileCountingAnswersNilAtOnce() async {
    let rig = Rig()
    rig.model.start()
    _ = await settle { rig.importer.runs == 1 }
    rig.model.cancel()
    #expect(rig.importer.cancels == 1)
    #expect(await rig.importer.askConsent(Self.counts) == nil)
    #expect(rig.state.phase == .dismissed)
    rig.importer.finish(Self.summary([:], cancelled: true))
    for _ in 0..<100 { await Task.yield() }
    #expect(rig.state.phase == .dismissed)
  }

  @Test func startingTwiceStartsOneRun() async {
    let rig = Rig()
    rig.model.start()
    rig.model.start()
    #expect(await settle { rig.importer.runs == 1 })
    #expect(rig.importer.runs == 1)
  }

  // MARK: Import

  @Test func importRunsTheSidebarStepFirstThenHandsTheTickedTypesToTheCoordinator() async {
    let rig = Rig()
    var order: [String] = []
    rig.spaces.onRun = { order.append("spaces: \(rig.state.rows[.spacesAndTabs].map { "\($0)" } ?? "none")") }
    rig.model.setSelected(.history, true)   // before consent: ignored
    let answer = await rig.reachConsent()
    rig.model.setSelected(.passwords, false)
    rig.model.beginImport()
    let selection = await answer.value
    #expect(selection == ImportSelection([.history, .cookies, .extensions]), "no bookmarks (zero), no passwords (unticked)")
    #expect(rig.spaces.runs == 1)
    #expect(order == ["spaces: working(done: 0, total: 213)"])
    #expect(rig.state.phase == .progress)
    #expect(rig.state.rows[.spacesAndTabs] == .imported(count: 213, failed: 0))
    #expect(rig.state.rows[.history] == .waiting)
    #expect(rig.state.rows[.passwords] == .skipped)
    #expect(rig.state.rows[.bookmarks] == .skipped)
    #expect(rig.state.rows[.cookies] == .waitingForMac, "the Keychain prompt comes next")
    #expect(rig.state.showsKeychainLine == false, "the line is the consent's; the row says it from here")
  }

  @Test func theSidebarStepAloneAsksTheCoordinatorForNothing() async {
    let rig = Rig()
    let answer = await rig.reachConsent()
    for kind in BrowserDataKind.allCases { rig.model.setSelected(kind, kind == .spacesAndTabs) }
    rig.model.beginImport()
    #expect(await answer.value == ImportSelection([]))
    #expect(rig.state.rows[.cookies] == .skipped, "no Keychain wait when no password type is ticked")
  }

  @Test func withoutAPasswordTypeNoRowWaitsForMacOS() async {
    let rig = Rig()
    _ = await rig.reachProgress([.history, .extensions])
    #expect(!rig.state.rows.values.contains(.waitingForMac))
  }

  @Test func eventsMoveTheRowsAndTheFirstOneEndsTheKeychainWait() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.send(.progress(.history, .counting))
    rig.importer.send(.counted(Self.counts))
    for _ in 0..<100 { await Task.yield() }   // the consumer has handled both events
    #expect(rig.state.rows[.cookies] == .waitingForMac, "counting events are not the key being read")
    rig.importer.send(.progress(.history, .writing(done: 0, total: 48_210)))
    #expect(await settle { rig.state.rows[.history] == .working(done: 0, total: 48_210) })
    #expect(rig.state.rows[.cookies] == .waiting, "the key was settled: the prompt is gone")
    rig.importer.send(.progress(.history, .writing(done: 30_854, total: 48_210)))
    #expect(await settle { rig.state.rows[.history] == .working(done: 30_854, total: 48_210) })
    rig.importer.send(.progress(.history, .done(ImportItemCounts(written: 48_000, skipped: 210, failed: 0))))
    #expect(await settle { rig.state.rows[.history] == .imported(count: 48_210, failed: 0) })
    rig.importer.send(.progress(.extensions, .skipped(reason: "not yet available")))
    #expect(await settle { rig.state.rows[.extensions] == .stopped })
    #expect(rig.state.overall.trailing == "3 of 5 done", "sidebar, history and the extensions that cannot be installed yet")
  }

  @Test func aCleanRunEndsInTheResultAndDoneClosesIt() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    for (type, counts) in [(ImportDataType.history, 48_210), (.extensions, 14), (.cookies, 3_904), (.passwords, 312)] {
      rig.importer.send(.progress(type, .done(ImportItemCounts(written: counts))))
    }
    rig.importer.finish(Self.summary([
      .history: .done(ImportItemCounts(written: 48_210)), .extensions: .done(ImportItemCounts(written: 14)),
      .cookies: .done(ImportItemCounts(written: 3_904)), .passwords: .done(ImportItemCounts(written: 312)),
    ]))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result == BrowserDataImportResult())
    #expect(rig.state.title == "Import finished")
    #expect(rig.state.subtitle == "Everything you chose came over.")
    #expect(rig.outcomes.finished.isEmpty, "the result stays up until Done")
    rig.model.finish()
    #expect(rig.state.phase == .dismissed)
    #expect(rig.outcomes.finished.count == 1)
    #expect(rig.outcomes.finished.first?.importedAnything == true)
    #expect(rig.outcomes.finished.first?.addedSpaces == rig.spaces.result.addedSpaces)
  }

  @Test func theCoordinatorRefusingToStartIsAResultNotACrash() async {
    let rig = Rig()
    rig.importer.throwOnRun = .alreadyRunning
    rig.model.start()
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result.couldNotRead)
    #expect(rig.state.primaryButton?.action == .done)
  }

  @Test func aRunThatCouldNotReadAnythingShowsNoRowsAndOnlyDone() async {
    let rig = Rig()
    rig.model.start()
    _ = await settle { rig.importer.runs == 1 }
    var summary = ProfileImportSummary()
    summary.abortReason = "no Arc profile found"
    rig.importer.finish(summary)
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result.couldNotRead)
    #expect(rig.state.groups.isEmpty)
    #expect(rig.state.subtitle == "Arkt couldn't read your other browser's data.", "the abort reason (it names Arc) never reaches the sheet")
  }

  // MARK: Denied Keychain and Retry

  @Test func aDeniedKeychainSplitsTheResultAndRetryRunsOnlyTheDeniedTypes() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.send(.progress(.history, .done(ImportItemCounts(written: 48_210))))
    rig.importer.send(.progress(.cookies, .failed(reason: "Keychain access denied")))
    rig.importer.send(.progress(.passwords, .failed(reason: "Keychain access denied")))
    let denied = Self.summary([
      .history: .done(ImportItemCounts(written: 48_210)), .extensions: .done(ImportItemCounts(written: 14)),
      .cookies: Self.denial, .passwords: Self.denial,
    ])
    rig.importer.finish(denied)
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.rows[.cookies] == .notImported(.keychainDenied))
    #expect(rig.state.deniedKinds == [.cookies, .passwords])
    #expect(rig.state.result.canRetry)
    #expect(rig.state.groups.map(\.heading) == ["Imported", "Not imported"])
    #expect(rig.state.primaryButton?.action == .retry)

    rig.model.retry()
    #expect(await settle { rig.importer.retries.count == 1 })
    #expect(rig.importer.retries == [denied], "Retry hands the coordinator the first summary: only the failed types run")
    #expect(rig.state.phase == .progress)
    #expect(rig.state.isRetry)
    #expect(rig.state.rows[.cookies] == .waitingForMac)
    #expect(rig.state.rows[.history] == .imported(count: 48_210, failed: 0), "what came over stays on screen")
    #expect(rig.state.showsKeychainLine, "the pre-prompt line shows again")
    #expect(rig.spaces.runs == 1, "the sidebar part came over once and is not run again")

    rig.importer.send(.progress(.cookies, .writing(done: 10, total: 3_904)))
    rig.importer.send(.progress(.cookies, .done(ImportItemCounts(written: 3_904))))
    rig.importer.send(.progress(.passwords, .done(ImportItemCounts(written: 312))))
    rig.importer.finish(Self.summary([.cookies: .done(ImportItemCounts(written: 3_904)),
                                      .passwords: .done(ImportItemCounts(written: 312))]))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result == BrowserDataImportResult())
    #expect(rig.state.rows[.cookies] == .imported(count: 3_904, failed: 0))
    #expect(rig.state.groups.map(\.heading) == ["Imported"])
  }

  @Test func aRetryThatIsDeniedAgainIsTheSameStateWithNoCounter() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    let denied = Self.summary([.history: .done(ImportItemCounts(written: 1)), .cookies: Self.denial, .passwords: Self.denial])
    rig.importer.finish(denied)
    #expect(await settle { rig.state.phase == .result })
    let first = rig.state
    rig.model.retry()
    #expect(await settle { rig.importer.retries.count == 1 })
    rig.importer.send(.progress(.cookies, .failed(reason: "Keychain prompt dismissed")))
    rig.importer.send(.progress(.passwords, .failed(reason: "Keychain prompt dismissed")))
    rig.importer.finish(Self.summary([.cookies: .failed(reason: "Keychain prompt dismissed"),
                                      .passwords: .failed(reason: "Keychain prompt dismissed")]))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.rows == first.rows)
    #expect(rig.state.result == first.result)
    #expect(rig.state.groups == first.groups)
    #expect(rig.state.primaryButton?.action == .retry)
  }

  @Test func retryOnlyWorksFromAResultThatOffersIt() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.model.retry()
    #expect(rig.importer.retries.isEmpty, "not while importing")
    rig.importer.finish(Self.summary([.history: .done(ImportItemCounts(written: 1))]))
    #expect(await settle { rig.state.phase == .result })
    rig.model.retry()
    #expect(rig.importer.retries.isEmpty, "nothing failed")
  }

  @Test func aFailedSidebarStepIsRetriedWithTheRest() async {
    let rig = Rig()
    rig.spaces.result = SpacesAndTabsResult(items: 0, skipped: 0, failed: true, addedSpaces: [])
    _ = await rig.reachProgress()
    #expect(rig.state.rows[.spacesAndTabs] == .notImported(.unreadable))
    rig.importer.finish(Self.summary([.history: .done(ImportItemCounts(written: 1))]))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result.canRetry)
    rig.spaces.result = SpacesAndTabsResult(items: 213, skipped: 2, failed: false, addedSpaces: [UUID()])
    rig.model.retry()
    #expect(await settle { rig.importer.retries.count == 1 })
    #expect(rig.spaces.runs == 2)
    #expect(rig.state.rows[.spacesAndTabs] == .imported(count: 213, failed: 2))
    rig.importer.finish(Self.summary([:]))
    #expect(await settle { rig.state.phase == .result })
    rig.model.finish()
    #expect(rig.outcomes.finished.first?.skippedSidebarItems == 2)
  }

  @Test func theRetryFailingToStartEndsInAResult() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.finish(Self.summary([.cookies: Self.denial]))
    #expect(await settle { rig.state.phase == .result })
    rig.importer.throwOnRun = .alreadyRunning
    rig.model.retry()
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.rows[.cookies] == .notImported(.keychainDenied), "the denied rows are as they were")
    #expect(rig.state.result.canRetry)
    #expect(rig.state.isRetry == false)
  }

  @Test func onlyAKeychainReasonCountsAsDenied() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.send(.progress(.cookies, .failed(reason: "Arc Safe Storage item not found")))
    rig.importer.send(.progress(.passwords, .failed(reason: "Keychain prompt not available")))
    rig.importer.send(.progress(.history, .failed(reason: "could not read History")))
    #expect(await settle { rig.state.rows[.history] == .notImported(.unreadable) })
    #expect(rig.state.rows[.cookies] == .notImported(.unreadable))
    #expect(rig.state.rows[.passwords] == .notImported(.keychainDenied))
  }

  // MARK: Cancel

  @Test func cancelWhileImportingStopsAfterTheBatchAndKeepsWhatCameOver() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.send(.progress(.history, .writing(done: 100, total: 48_210)))
    #expect(await settle { rig.state.rows[.history] == .working(done: 100, total: 48_210) })
    rig.model.cancel()
    #expect(rig.importer.cancels == 1)
    #expect(rig.state.isStopping)
    #expect(rig.state.secondaryButton()?.isEnabled == false)
    rig.model.cancel()
    #expect(rig.importer.cancels == 1, "a second Cancel asks nothing more")
    rig.importer.send(.progress(.history, .done(ImportItemCounts(written: 200))))
    rig.importer.send(.progress(.extensions, .skipped(reason: "cancelled")))
    rig.importer.finish(Self.summary([.history: .done(ImportItemCounts(written: 200)),
                                      .extensions: .skipped(reason: "cancelled"), .cookies: .skipped(reason: "cancelled"),
                                      .passwords: .skipped(reason: "cancelled")], cancelled: true))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result.cancelled)
    #expect(rig.state.rows[.history] == .imported(count: 200, failed: 0))
    #expect(rig.state.rows[.cookies] == .stopped)
    #expect(rig.state.rows[.passwords] == .stopped)
    #expect(rig.state.rows[.bookmarks] == .skipped)
    #expect(rig.state.title == "Import stopped")
    #expect(rig.state.groups.map(\.heading) == ["Imported", "Not imported"])
    #expect(!rig.state.isStopping)
  }

  @Test func cancelDuringTheSidebarStepDeclinesTheRestAfterItReturns() async {
    let rig = Rig()
    rig.spaces.onRun = { rig.model.cancel() }
    let answer = await rig.reachConsent()
    rig.model.beginImport()
    #expect(await answer.value == nil)
    #expect(rig.state.rows[.spacesAndTabs] == .imported(count: 213, failed: 0), "the sidebar part already came over")
    rig.importer.finish(Self.summary([:], cancelled: true))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.result.cancelled)
    #expect(rig.state.rows[.history] == .stopped)
  }

  @Test func theStreamEndingWithoutAnEventStillEndsInAResult() async {
    let rig = Rig()
    _ = await rig.reachProgress()
    rig.importer.finish(Self.summary([:], cancelled: true))
    #expect(await settle { rig.state.phase == .result })
    #expect(rig.state.rows.values.allSatisfy { $0 != .waiting && $0 != .waitingForMac })
  }

  // MARK: Notifications

  @Test func onChangeFiresOnlyWhenTheStateChanges() async {
    let rig = Rig()
    var changes = 0
    rig.model.onChange = { changes += 1 }
    let answer = await rig.reachConsent()
    let afterConsent = changes
    rig.model.setSelected(.cookies, true)   // already ticked
    #expect(changes == afterConsent)
    rig.model.setSelected(.cookies, false)
    #expect(changes == afterConsent + 1)
    rig.model.cancel()
    _ = await answer.value
  }

  // MARK: The real coordinator

  @Test func aFullImportThroughTheRealCoordinatorShowsEveryTypeAndEndsInAResult() async throws {
    let folder = try ArcUserDataFolder()
    let engine = RecordingImportEngine()
    engine.installResult = ImportWriteResult(written: 3)
    let coordinator = ProfileImportCoordinator(
      engine: engine, importRecord: FakeArcImportRecordStore(ArcImportRecord()),
      keyProvider: FakeSafeStorageKeyProvider(password: FakeChromiumProfile.safeStoragePassword),
      configuration: ProfileImportConfiguration(batchSize: 2, historyVisitsPerBatch: 3, scratchParent: folder.scratch),
      now: { ProfileImportCoordinatorTests.clock })
    let model = BrowserDataImportModel(coordinator: coordinator, root: folder.root, spaces: nil,
                                       locale: Locale(identifier: "en_US"))
    model.start()
    #expect(await settle { model.state.phase == .consent })
    #expect(model.state.counts[.cookies] > 0)
    #expect(model.state.counts[.spacesAndTabs] == 0, "no sidebar step: nothing to import there")
    model.beginImport()
    #expect(await settle { model.state.phase == .result })
    #expect(model.state.result == BrowserDataImportResult())
    let imported = BrowserDataKind.allCases.filter { if case .imported? = model.state.rows[$0] { true } else { false } }
    #expect(imported.contains(.history) && imported.contains(.cookies) && imported.contains(.passwords))
    #expect(engine.cookieCount > 0)
    #expect(folder.leftoverSnapshots.isEmpty)
    model.finish()
    #expect(model.state.phase == .dismissed)
  }

  @Test func aDeniedKeychainThroughTheRealCoordinatorOffersRetryAndRetrySucceeds() async throws {
    let folder = try ArcUserDataFolder()
    let engine = RecordingImportEngine()
    let records = FakeArcImportRecordStore(ArcImportRecord())
    func coordinator(_ provider: FakeSafeStorageKeyProvider) -> ProfileImportCoordinator {
      ProfileImportCoordinator(
        engine: engine, importRecord: records, keyProvider: provider,
        configuration: ProfileImportConfiguration(scratchParent: folder.scratch),
        now: { ProfileImportCoordinatorTests.clock })
    }
    let model = BrowserDataImportModel(
      coordinator: SwitchingImporter(first: coordinator(FakeSafeStorageKeyProvider(failure: .accessDenied)),
                                     then: coordinator(FakeSafeStorageKeyProvider(
                                       password: FakeChromiumProfile.safeStoragePassword))),
      root: folder.root, spaces: nil, locale: Locale(identifier: "en_US"))
    model.start()
    #expect(await settle { model.state.phase == .consent })
    model.beginImport()
    #expect(await settle { model.state.phase == .result })
    #expect(model.state.deniedKinds == [.cookies, .passwords])
    #expect(model.state.result.canRetry)
    #expect(model.state.groups.map(\.heading) == ["Imported", "Not imported"])
    #expect(engine.cookieCount == 0)
    model.retry()
    #expect(await settle { model.state.phase == .result })
    #expect(model.state.result == BrowserDataImportResult())
    #expect(engine.cookieCount > 0)
  }
}

/// Runs the first request on one coordinator and the Retry on another, the way a user who allows the Keychain the
/// second time sees it.
@MainActor
final class SwitchingImporter: ProfileImporting {
  private let first: ProfileImportCoordinator
  private let second: ProfileImportCoordinator
  private var retried = false

  init(first: ProfileImportCoordinator, then second: ProfileImportCoordinator) {
    self.first = first
    self.second = second
  }

  func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
    -> AsyncStream<ProfileImportEvent> { try first.run(root: root, consent: consent) }

  func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
    retried = true
    return try second.retry(root: root, after: summary)
  }

  func cancel() { (retried ? second : first).cancel() }
}
