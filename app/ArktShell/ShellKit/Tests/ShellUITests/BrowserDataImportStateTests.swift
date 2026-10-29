import Foundation
import Testing
@testable import ShellUI

/// The browser data import's values (#514, direction B): number text, groups, copy and buttons per state, with
/// synthetic counts only.
struct BrowserDataImportStateTests {
  private static let us = Locale(identifier: "en_US")

  private static let counts = BrowserDataCounts(
    items: [.spacesAndTabs: 213, .history: 48_210, .bookmarks: 0, .extensions: 14, .cookies: 3_904, .passwords: 312],
    spaces: 4)

  private static func consent(
    _ counts: BrowserDataCounts = counts, selection: Set<BrowserDataKind>? = nil
  ) -> BrowserDataImportState {
    var state = BrowserDataImportState(phase: .consent, counts: counts, locale: us)
    state.selection = selection ?? Set(BrowserDataKind.allCases.filter { counts[$0] > 0 })
    return state
  }

  private static let chosen: Set<BrowserDataKind> = [.spacesAndTabs, .history, .extensions, .cookies, .passwords]

  private static func progress(_ rows: [BrowserDataKind: BrowserDataRowStatus], retry: Bool = false)
    -> BrowserDataImportState {
    BrowserDataImportState(phase: .progress, counts: counts, selection: chosen, rows: rows, isRetry: retry, locale: us)
  }

  private static func result(_ rows: [BrowserDataKind: BrowserDataRowStatus],
                             _ result: BrowserDataImportResult = .init()) -> BrowserDataImportState {
    BrowserDataImportState(phase: .result, counts: counts, selection: chosen, rows: rows, result: result, locale: us)
  }

  private static let denied: [BrowserDataKind: BrowserDataRowStatus] = [
    .spacesAndTabs: .imported(count: 213, failed: 0), .history: .imported(count: 48_210, failed: 0),
    .extensions: .imported(count: 14, failed: 0), .cookies: .notImported(.keychainDenied),
    .passwords: .notImported(.keychainDenied),
  ]

  // MARK: Numbers

  @Test func countsAreGroupedUpToNineMillionThenCompact() {
    let cases: [(Int, String)] = [
      (0, "0"), (1, "1"), (999, "999"), (48_210, "48,210"), (9_999_999, "9,999,999"), (10_000_000, "10M"),
      (12_500_000, "12.5M"), (999_999_999, "999.9M"), (2_100_000_000, "2.1B"), (4_000_000_000_000, "4T"),
      (Int.max, "999T+"), (-5, "0"),
    ]
    for (value, text) in cases { #expect(BrowserDataNumberFormat.text(value, locale: Self.us) == text) }
  }

  @Test func progressTextStaysShortForHugeCounts() {
    #expect(BrowserDataNumberFormat.progress(done: 30_854, total: 48_210, locale: Self.us) == "30,854 of 48,210")
    let huge = BrowserDataNumberFormat.progress(done: 1_400_000_000, total: 2_100_000_000, locale: Self.us)
    #expect(huge == "1.4B of 2.1B")
    #expect(BrowserDataNumberFormat.progress(done: Int.max, total: Int.max, locale: Self.us).count <= 14)
  }

  @Test func oneSpaceIsSingular() {
    #expect(BrowserDataNumberFormat.spaces(1, locale: Self.us) == "1 Space")
    #expect(BrowserDataNumberFormat.spaces(4, locale: Self.us) == "4 Spaces")
  }

  // MARK: Consent

  @Test func consentGroupsTheTypesByWhatTheyNeed() {
    let groups = Self.consent().groups
    #expect(groups.map(\.heading) == ["Ready to import", "Needs your Mac password"])
    #expect(groups[0].rows.map(\.kind) == [.spacesAndTabs, .history, .bookmarks, .extensions])
    #expect(groups[1].rows.map(\.kind) == [.cookies, .passwords])
    #expect(groups[0].rows.map(\.value) == ["213", "48,210", "0", "14"])
    #expect(groups[0].rows[0].detail == "in 4 Spaces")
    #expect(groups[1].rows.allSatisfy { $0.accessibilityDescription == "Needs your Mac password" })
    #expect(groups[0].rows[0].accessibilityLabel == "Spaces and tabs, 213")
  }

  @Test func aTypeWithNothingInItIsDimmedUncheckedAndDisabled() throws {
    let bookmarks = try #require(Self.consent().groups[0].rows.first { $0.kind == .bookmarks })
    #expect(bookmarks.leading == .checkbox(isOn: false, isEnabled: false))
    #expect(bookmarks.isDimmed)
    #expect(bookmarks.value == "0")
    var state = Self.consent()
    state.selection.insert(.bookmarks)
    #expect(state.effectiveSelection.contains(.bookmarks) == false, "a zero type is never run")
  }

  @Test func theKeychainLineSitsInTheSecondGroupWhileCookiesOrPasswordsAreTicked() throws {
    let both = Self.consent()
    #expect(both.showsKeychainLine)
    let notice = try #require(both.groups[1].notice)
    #expect(notice.symbol == .lock)
    #expect(notice.emphasis == "Choose Allow, not Always Allow")
    #expect(notice.text.contains("Choose Allow, not Always Allow"))
    #expect(notice.text.contains("one-time permission"))
    #expect(both.groups[0].notice == nil)

    var cookiesOnly = Self.consent(selection: [.history, .cookies])
    #expect(cookiesOnly.showsKeychainLine)
    cookiesOnly.selection = [.history]
    #expect(cookiesOnly.showsKeychainLine == false)
    #expect(cookiesOnly.groups[1].notice == nil)
  }

  @Test func importNeedsAtLeastOneTickedType() {
    #expect(Self.consent().primaryButton == BrowserDataImportButton(action: .importData, title: "Import", isEnabled: true))
    #expect(Self.consent(selection: []).primaryButton?.isEnabled == false)
    #expect(Self.consent(selection: [.bookmarks]).canImport == false, "only a type that is empty")
  }

  @Test func everyTypeAtZeroSaysNothingToImportAndOnlyCancelWorks() {
    let state = Self.consent(BrowserDataCounts())
    #expect(state.isNothingToImport)
    #expect(state.title == "Nothing to import")
    #expect(state.heroTitle == "Nothing to import.")
    #expect(state.primaryButton?.isEnabled == false)
    #expect(state.secondaryButton()?.isEnabled == true)
    #expect(state.secondaryButton()?.title == "Cancel")
    #expect(state.secondaryButton(hero: true)?.title == "Not now")
    #expect(state.groups.flatMap(\.rows).allSatisfy { $0.isDimmed })
    #expect(state.showsKeychainLine == false)
  }

  @Test func countingShowsTheRowsWithoutNumbersAndNoImport() {
    let state = BrowserDataImportState(phase: .counting, locale: Self.us)
    #expect(state.title == "Import browser data")
    #expect(state.primaryButton?.isEnabled == false)
    #expect(state.groups.flatMap(\.rows).allSatisfy { $0.value.isEmpty })
  }

  // MARK: Progress

  @Test func progressNamesTheWorkingTypeAndCountsFinishedRows() throws {
    let state = Self.progress([
      .spacesAndTabs: .imported(count: 213, failed: 0), .history: .working(done: 30_854, total: 48_210),
      .extensions: .skipped, .cookies: .waiting, .passwords: .waiting,
    ])
    #expect(state.title == "Importing your browser data")
    #expect(state.groups.map(\.heading) == ["No password needed", "Needs your Mac password"])
    #expect(state.overall.label == "Importing history")
    #expect(state.overall.trailing == "1 of 5 done")
    let history = try #require(state.groups[0].rows.first { $0.kind == .history })
    #expect(history.value == "30,854 of 48,210")
    #expect(history.leading == .working)
    #expect(try #require(history.barFraction) - 0.64 < 0.01)
    #expect(history.accessibilityLabel == "History, 30,854 of 48,210")
    #expect(state.groups[1].rows.map(\.value) == ["Waiting", "Waiting"])
    #expect(state.groups[1].rows[0].accessibilityLabel == "Cookies, waiting")
    #expect(state.primaryButton == nil)
    #expect(state.secondaryButton() == BrowserDataImportButton(action: .cancel, title: "Cancel", isEnabled: true))
    #expect(state.footnote == "Cancel keeps what has already come over.")
    #expect(state.showsKeychainLine == false)
  }

  @Test func theOverallBarIsTheMeanOfTheRows() {
    let state = Self.progress([
      .spacesAndTabs: .imported(count: 1, failed: 0), .history: .working(done: 1, total: 2),
      .extensions: .skipped, .cookies: .waiting, .passwords: .waiting,
    ])
    #expect(abs(state.overall.fraction - (1.5 / 5)) < 0.0001)
  }

  @Test func theRowSaysWaitingForMacWhileTheKeychainPromptIsUp() {
    let state = Self.progress([
      .spacesAndTabs: .waiting, .history: .waiting, .extensions: .waiting,
      .cookies: .waitingForMac, .passwords: .waitingForMac,
    ])
    #expect(state.overall.label == "Waiting for macOS")
    #expect(state.groups[1].rows.map(\.value) == ["Waiting for macOS", "Waiting for macOS"])
  }

  @Test func aRetryShowsThePrePromptLineAgain() {
    let rows: [BrowserDataKind: BrowserDataRowStatus] = Self.denied.merging([
      .cookies: .waitingForMac, .passwords: .waitingForMac,
    ]) { _, new in new }
    #expect(Self.progress(rows, retry: true).showsKeychainLine)
    #expect(Self.progress(rows, retry: true).groups[1].notice?.symbol == .lock)
    #expect(Self.progress(rows, retry: false).showsKeychainLine == false)
  }

  @Test func stoppingDisablesCancelAndSaysSo() {
    var state = Self.progress([.history: .working(done: 1, total: 9)])
    state.isStopping = true
    #expect(state.secondaryButton()?.isEnabled == false)
    #expect(state.footnote == "Stopping after the batch being written.")
  }

  @Test func anUnknownTotalShowsNoBarAndNoDivision() throws {
    let state = Self.progress([.history: .working(done: 0, total: 0)])
    let history = try #require(state.groups[0].rows.first { $0.kind == .history })
    #expect(history.value == "Starting")
    #expect(history.barFraction == 0)
  }

  @Test func hugeCountsKeepTheRowTextShort() throws {
    let huge = BrowserDataCounts(items: [.history: 2_100_000_000], spaces: 1)
    var state = BrowserDataImportState(phase: .progress, counts: huge, selection: [.history], locale: Self.us)
    state.rows[.history] = .working(done: 1_400_000_000, total: 2_100_000_000)
    let row = try #require(state.groups[0].rows.first { $0.kind == .history })
    #expect(row.value == "1.4B of 2.1B")
    #expect(row.value.count <= 14)
  }

  // MARK: Result

  @Test func aCleanResultListsOnlyImportedRows() {
    let state = Self.result([
      .spacesAndTabs: .imported(count: 213, failed: 0), .history: .imported(count: 48_210, failed: 0),
      .extensions: .imported(count: 14, failed: 0), .cookies: .imported(count: 3_904, failed: 0),
      .passwords: .imported(count: 312, failed: 0),
    ])
    #expect(state.groups.map(\.heading) == ["Imported"])
    #expect(state.title == "Import finished")
    #expect(state.subtitle == "Everything you chose came over.")
    #expect(state.heroTitle == "Your setup is here.")
    #expect(state.primaryButton == BrowserDataImportButton(action: .done, title: "Done", isEnabled: true))
    #expect(state.secondaryButton() == nil)
    #expect(state.heroPrimaryButton()?.title == "Continue")
  }

  @Test func aDeniedKeychainSplitsTheResultAndOffersRetry() throws {
    let state = Self.result(Self.denied, BrowserDataImportResult(canRetry: true))
    #expect(state.groups.map(\.heading) == ["Imported", "Not imported"])
    #expect(state.groups[1].rows.map(\.value) == ["Not imported", "Not imported"])
    #expect(state.groups[1].rows.map(\.leading) == [.notImported, .notImported])
    let notice = try #require(state.groups[1].notice)
    #expect(notice.text == "Passwords and cookies weren't imported. macOS didn't let Arkt read your other browser's "
      + "saved logins. Retry asks again.")
    #expect(notice.symbol == .exclamation)
    #expect(state.subtitle == "Most of it came over.")
    #expect(state.heroTitle == "Most of it came over.")
    #expect(state.primaryButton == BrowserDataImportButton(action: .retry, title: "Retry", isEnabled: true))
    #expect(state.secondaryButton() == BrowserDataImportButton(action: .done, title: "Done", isEnabled: true))
    #expect(state.secondaryButton(hero: true)?.title == "Continue")
  }

  @Test func theDeniedMessageNamesOnlyWhatWasTicked() throws {
    var rows = Self.denied
    rows[.cookies] = .skipped
    let state = Self.result(rows, BrowserDataImportResult(canRetry: true))
    #expect(state.deniedKinds == [.passwords])
    #expect(try #require(state.groups[1].notice).text.hasPrefix("Passwords weren't imported."))
    rows[.cookies] = .notImported(.keychainDenied)
    rows[.passwords] = .skipped
    #expect(try #require(Self.result(rows).groups[1].notice).text.hasPrefix("Cookies weren't imported."))
  }

  @Test func aCancelledRunListsTheRestAsSkippedAndKeepsWhatCameOver() {
    let state = Self.result([
      .spacesAndTabs: .imported(count: 213, failed: 0), .history: .imported(count: 100, failed: 0),
      .extensions: .stopped, .cookies: .stopped, .passwords: .stopped,
    ], BrowserDataImportResult(cancelled: true))
    #expect(state.title == "Import stopped")
    #expect(state.subtitle == "What already came over stays.")
    #expect(state.groups.map(\.heading) == ["Imported", "Not imported"])
    #expect(state.groups[1].rows.map(\.value) == ["Skipped", "Skipped", "Skipped"])
    #expect(state.groups[1].notice == nil)
    #expect(state.primaryButton?.action == .done)
  }

  @Test func rowsThatWereNeverTickedDoNotAppearInTheResult() {
    let state = Self.result([
      .spacesAndTabs: .imported(count: 213, failed: 0), .history: .skipped, .extensions: .skipped,
      .cookies: .skipped, .passwords: .skipped,
    ])
    #expect(state.groups.flatMap(\.rows).map(\.kind) == [.spacesAndTabs])
  }

  @Test func everythingFailingSaysNoneOfItCameOver() {
    let state = Self.result([.history: .notImported(.unreadable), .cookies: .notImported(.unreadable)],
                            BrowserDataImportResult(canRetry: true))
    #expect(state.subtitle == "None of it came over.")
    #expect(state.heroTitle == "None of it came over.")
    #expect(state.groups.map(\.heading) == ["Not imported"])
    #expect(state.groups[0].notice?.text == "Some of it couldn't be read. Retry tries again.")
  }

  @Test func refusedItemsAreCountedUnderTheRow() throws {
    let state = Self.result([.history: .imported(count: 100, failed: 7)])
    let row = try #require(state.groups[0].rows.first)
    #expect(row.detail == "7 couldn't be imported")
    #expect(row.accessibilityLabel.contains("7 couldn't be imported"))
  }

  @Test func aRunThatCouldNotReadAnythingHasNoRowsAndOnlyDone() {
    let state = Self.result([:], BrowserDataImportResult(couldNotRead: true))
    #expect(state.title == "Nothing came over")
    #expect(state.groups.isEmpty)
    #expect(state.primaryButton?.action == .done)
  }

  // MARK: Hero type

  /// The Hero entry's roles (design spec): headline 56 DemiBold, rows 18 medium, counts 26 DemiBold tabular, the
  /// compact sizes for windows below 700 pt.
  @MainActor @Test func theHeroTypeFollowsTheSpec() {
    typealias R = BrandType.Role
    let title = R.dataTitle.style(compact: false)
    #expect(title.weight == .demiBold && title.size == 56 && title.leading == 0.92 && title.trackingEm == -0.055)
    #expect(R.dataTitle.style(compact: true).size == 46)
    #expect(R.dataRow.style(compact: false).size == 18 && R.dataRow.style(compact: false).weight == .medium)
    let count = R.dataCount.style(compact: false)
    #expect(count.size == 26 && count.weight == .demiBold && count.tabular)
    #expect(R.dataCount.style(compact: true).size == 22)
    #expect(R.dataStatus.style(compact: false).tabular)
    #expect(R.dataNote.style(compact: false).leading == 1.45)
  }

  // MARK: Words

  @Test func noStateNamesTheOtherBrowser() {
    let states = [
      Self.consent(), Self.consent(BrowserDataCounts()), BrowserDataImportState(phase: .counting, locale: Self.us),
      Self.progress([.history: .working(done: 1, total: 2), .cookies: .waitingForMac]),
      Self.progress(Self.denied, retry: true),
      Self.result(Self.denied, BrowserDataImportResult(canRetry: true)),
      Self.result([:], BrowserDataImportResult(couldNotRead: true)),
      Self.result([.history: .notImported(.unreadable)], BrowserDataImportResult(cancelled: true)),
    ]
    for state in states {
      var words = [state.title, state.subtitle, state.heroTitle, state.heroLede, state.heroEyebrow, state.footnote ?? ""]
      for group in state.groups {
        words += [group.heading, group.notice?.text ?? ""]
        for row in group.rows { words += [row.title, row.detail ?? "", row.value, row.accessibilityLabel, row.accessibilityDescription ?? ""] }
      }
      for text in words {
        #expect(text.range(of: #"\barc\b"#, options: [.regularExpression, .caseInsensitive]) == nil, "names the other browser: \(text)")
      }
    }
  }

  // MARK: VoiceOver

  @Test func announcementsFollowPhasesAndFinishedTypesNotCounts() {
    let before = Self.progress([.history: .working(done: 1, total: 100), .extensions: .waiting])
    var counting = before
    counting.rows[.history] = .working(done: 50, total: 100)
    #expect(counting.announcement(after: before) == nil, "no announcement per count")

    var finished = counting
    finished.rows[.history] = .imported(count: 100, failed: 0)
    #expect(finished.announcement(after: counting) == "History imported")
    #expect(finished.announcement(after: finished) == nil)

    #expect(Self.progress([:]).announcement(after: Self.consent()) == "Importing your browser data")
    #expect(Self.consent().announcement(after: BrowserDataImportState(phase: .counting)) == "Choose what to import")
    #expect(Self.consent(BrowserDataCounts()).announcement(after: nil) == "Nothing to import")

    let result = Self.result(Self.denied, BrowserDataImportResult(canRetry: true))
    let spoken = result.announcement(after: finished)
    #expect(spoken?.hasPrefix("Import finished. Most of it came over. Passwords and cookies weren't imported.") == true)
  }

  @Test func theKeychainWaitIsAnnouncedOnce() {
    let waiting = Self.progress([.cookies: .waitingForMac, .passwords: .waitingForMac])
    let before = Self.progress([.cookies: .waiting, .passwords: .waiting])
    #expect(waiting.announcement(after: before) == "Waiting for macOS")
    #expect(waiting.announcement(after: waiting) == nil)
  }
}
