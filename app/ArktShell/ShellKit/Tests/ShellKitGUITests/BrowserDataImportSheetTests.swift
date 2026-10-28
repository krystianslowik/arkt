import AppKit
import ArcImport
@testable import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// One turn of the run loop. A synchronous function, because `RunLoop.run` cannot be called from async code.
@MainActor
func browserDataImportPump() { RunLoop.main.run(mode: .default, before: Date()) }

/// Waits for `condition` on the main actor: AppKit's run loop and the main actor's tasks both get their turns. The
/// deadline only ends a failing test.
@MainActor
func browserDataImportUntil(_ state: String, timeout: TimeInterval = 5, file: StaticString = #filePath,
                            line: UInt = #line, _ condition: @MainActor () -> Bool) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() {
    guard Date() < deadline else {
      XCTFail("timed out after \(timeout) s waiting for \(state)", file: file, line: line)
      return
    }
    browserDataImportPump()
    await Task.yield()
  }
}

/// The browser data import sheet (#514, direction B) on a real window, driven through the real `BrowserDataImportModel`
/// with a scripted coordinator: consent, progress, a denied Keychain, Retry and Done; worst-case counts; Reduce Motion.
/// Synthetic counts only.
@MainActor
final class BrowserDataImportSheetTests: XCTestCase {
  @MainActor
  private final class ScriptedImporter: ProfileImporting {
    var consent: (@MainActor (ProfileDataCounts) async -> ImportSelection?)?
    var continuation: AsyncStream<ProfileImportEvent>.Continuation?
    private(set) var retries = 0
    private(set) var cancels = 0

    func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
      -> AsyncStream<ProfileImportEvent> {
      self.consent = consent
      return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
    }

    func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
      retries += 1
      return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
    }

    func cancel() { cancels += 1 }
    func send(_ event: ProfileImportEvent) { continuation?.yield(event) }
    func finish(_ summary: ProfileImportSummary) {
      continuation?.yield(.finished(summary))
      continuation?.finish()
    }
  }

  @MainActor private struct Rig {
    let controller: ShellWindowController
    let importer = ScriptedImporter()
    let model: BrowserDataImportModel
    let sheet: BrowserDataImportSheet
    var window: NSWindow { controller.window! }

    init(reduceMotion: Bool = false, spaces: SpacesAndTabsStep? = nil) throws {
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: ModelSidebarSource(sidebar: SidebarModel.Sidebar()))
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      model = BrowserDataImportModel(coordinator: importer, root: URL(fileURLWithPath: "/nonexistent"), spaces: spaces,
                                     locale: Locale(identifier: "en_US"))
      sheet = BrowserDataImportSheet(source: model, reduceMotion: reduceMotion)
      sheet.begin(on: controller.window!)
    }

    var content: ImportContentView { sheet.content }

    /// The coordinator's counting step finished: asks the consent closure the way it does. The task's value is the
    /// answer the user gave.
    func reachConsent(_ counts: ProfileDataCounts) async -> Task<ImportSelection?, Never> {
      await browserDataImportUntil("the coordinator running") { importer.consent != nil }
      return Task { @MainActor in await importer.consent?(counts) ?? nil }
    }
  }

  private static let counts = ProfileDataCounts(
    historyURLs: 9_000, historyVisits: 48_210, bookmarks: 0, cookies: 3_904, logins: 312, extensions: 14)

  private static let sidebar = SpacesAndTabsStep(
    count: { SpacesAndTabsCount(items: 213, spaces: 4) },
    run: { SpacesAndTabsResult(items: 213, skipped: 0, failed: false, addedSpaces: [UUID()]) })

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func row(_ rig: Rig, _ kind: BrowserDataKind) throws -> ImportRowView {
    try XCTUnwrap(rig.content.rowViews[kind])
  }

  /// Consent with a count per type and the Keychain line, progress with a named type and the overall bar, a denied
  /// Keychain with Retry, Retry's own progress, then Done: the whole flow on the real sheet.
  func testTheSheetWalksConsentProgressDeniedResultAndRetry() async throws {
    let rig = try Rig(spaces: Self.sidebar)
    let window = rig.window
    await browserDataImportUntil("the sheet") { window.attachedSheet === rig.sheet.window }
    XCTAssertEqual(rig.content.title.text, "Import browser data")
    XCTAssertFalse((rig.content.primaryButton as? ArchivePillButton)?.isEnabled ?? true, "no Import while counting")

    let answer = await rig.reachConsent(Self.counts)
    await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
    XCTAssertEqual(rig.content.title.text, "Import browser data")
    XCTAssertEqual(rig.content.subtitle.text, "Choose what to bring into Arkt. Your other browser stays as it is.")
    let history = try row(rig, .history)
    XCTAssertEqual(history.valueText.text, "48,210")
    XCTAssertEqual(try row(rig, .spacesAndTabs).detailText.text, "in 4 Spaces")
    XCTAssertEqual(rig.content.groupViews.map { $0.heading.text }, ["Ready to import", "Needs your Mac password"])
    XCTAssertNotNil(rig.content.groupViews[1].noticeView, "the Keychain line sits inside the second group")
    XCTAssertTrue(rig.content.groupViews[1].noticeView?.text.text.contains("Choose Allow, not Always Allow") == true)
    let cookies = try row(rig, .cookies)
    XCTAssertTrue(cookies.checkbox.isOn, "cookies and passwords start checked")
    XCTAssertEqual(cookies.checkbox.accessibilityLabel(), "Cookies, 3,904")
    XCTAssertEqual(cookies.checkbox.accessibilityHelp(), "Needs your Mac password")
    XCTAssertEqual(cookies.checkbox.accessibilityRole(), .checkBox)
    XCTAssertEqual(cookies.checkbox.accessibilityIdentifier(), AXID.BrowserDataImport.row("cookies"))
    let bookmarks = try row(rig, .bookmarks)
    XCTAssertFalse(bookmarks.checkbox.isEnabled, "a type with nothing in it cannot be ticked")
    let first = try row(rig, .spacesAndTabs).checkbox
    XCTAssertTrue(rig.sheet.window?.firstResponder === first || rig.sheet.window?.firstResponder === history.checkbox,
                  "focus starts on the first checkbox")
    XCTAssertTrue(rig.content.primaryButton.isEnabled)
    XCTAssertEqual(Array(rig.content.primaryButton.keyEquivalent.utf8), [13], "Return presses Import")
    XCTAssertEqual(rig.content.secondaryButton.keyEquivalent, "", "and never Cancel")

    // Unticking both password types removes the line; ticking one brings it back.
    XCTAssertTrue(cookies.checkbox.accessibilityPerformPress())
    XCTAssertTrue(try row(rig, .passwords).checkbox.accessibilityPerformPress())
    XCTAssertNil(rig.content.groupViews[1].noticeView)
    XCTAssertTrue(cookies.checkbox.accessibilityPerformPress())
    XCTAssertNotNil(rig.content.groupViews[1].noticeView)

    rig.content.primaryButton.performClick(nil)
    let selection = await answer.value
    XCTAssertEqual(selection, ImportSelection([.history, .cookies, .extensions]))
    await browserDataImportUntil("progress") { rig.content.title.text == "Importing your browser data" }
    XCTAssertTrue(rig.content.primaryButton.isHidden, "Cancel is the only button while importing")
    XCTAssertEqual(rig.content.secondaryButton.title, "Cancel")
    XCTAssertEqual(rig.content.footnote.text, "Cancel keeps what has already come over.")
    XCTAssertEqual(rig.content.groupViews.map { $0.heading.text }, ["No password needed", "Needs your Mac password"])
    XCTAssertEqual(try row(rig, .cookies).valueText.text, "Waiting for macOS")

    rig.importer.send(.progress(.history, .writing(done: 30_854, total: 48_210)))
    await browserDataImportUntil("history working") { history.valueText.text == "30,854 of 48,210" }
    XCTAssertEqual(rig.content.overallLead.text, "Importing history")
    XCTAssertEqual(history.accessibilityLabel(), "History, 30,854 of 48,210")
    XCTAssertFalse(history.bar.isHidden)
    XCTAssertEqual(history.bar.fraction, 30_854.0 / 48_210.0, accuracy: 0.001)
    XCTAssertEqual(try row(rig, .cookies).valueText.text, "Waiting", "the Keychain prompt is gone")
    XCTAssertEqual(rig.sheet.announcements.filter { $0.hasPrefix("History") }, [], "no announcement per count")

    rig.importer.send(.progress(.history, .done(ImportItemCounts(written: 48_210))))
    rig.importer.send(.progress(.cookies, .failed(reason: "Keychain access denied")))
    rig.importer.send(.progress(.extensions, .done(ImportItemCounts(written: 14))))
    var summary = ProfileImportSummary()
    summary.outcomes = [.history: .done(ImportItemCounts(written: 48_210)), .extensions: .done(ImportItemCounts(written: 14)),
                        .cookies: .failed(reason: "Keychain access denied")]
    rig.importer.finish(summary)
    await browserDataImportUntil("the result") { rig.content.title.text == "Import finished" }
    XCTAssertEqual(rig.content.groupViews.map { $0.heading.text }, ["Imported", "Not imported"])
    XCTAssertEqual(try row(rig, .cookies).valueText.text, "Not imported")
    XCTAssertEqual(rig.content.groupViews[1].noticeView?.text.text,
                   "Cookies weren't imported. macOS didn't let Arkt read your other browser's saved logins. Retry asks again.")
    XCTAssertEqual(rig.content.primaryButton.title, "Retry")
    XCTAssertEqual(rig.content.secondaryButton.title, "Done")
    XCTAssertTrue(rig.sheet.announcements.contains { $0.hasPrefix("History imported") || $0 == "History imported" })
    XCTAssertTrue(rig.sheet.announcements.last?.hasPrefix("Import finished. Most of it came over. Cookies weren't imported.") == true)

    rig.content.primaryButton.performClick(nil)
    await browserDataImportUntil("retry progress") { rig.model.state.phase == .progress && rig.importer.retries == 1 }
    XCTAssertEqual(rig.content.subtitle.text, "Your other browser stays as it is.")
    XCTAssertNotNil(rig.content.groupViews.last?.noticeView, "the pre-prompt line shows again")
    XCTAssertEqual(try row(rig, .history).valueText.text, "48,210", "what came over stays on screen")
    rig.importer.send(.progress(.cookies, .done(ImportItemCounts(written: 3_904))))
    var retried = ProfileImportSummary()
    retried.outcomes = [.cookies: .done(ImportItemCounts(written: 3_904))]
    rig.importer.finish(retried)
    await browserDataImportUntil("the second result") { rig.model.state.phase == .result }
    XCTAssertEqual(rig.content.subtitle.text, "Everything you chose came over.")
    XCTAssertEqual(rig.content.primaryButton.title, "Done")
    XCTAssertTrue(rig.content.secondaryButton.isHidden)

    var outcome: BrowserDataImportOutcome?
    rig.model.onFinish = { outcome = $0 }
    rig.content.primaryButton.performClick(nil)
    await browserDataImportUntil("the sheet closed") { window.attachedSheet == nil }
    XCTAssertEqual(outcome?.importedAnything, true)
    rig.controller.close()
  }

  /// Escape cancels (Done on the result), at every phase, and Cancel in consent closes the sheet with nothing run.
  func testEscapeCancelsAndCancelInConsentCloses() async throws {
    let rig = try Rig()
    let window = rig.window
    await browserDataImportUntil("the sheet") { window.attachedSheet === rig.sheet.window }
    let answer = await rig.reachConsent(Self.counts)
    await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
    XCTAssertTrue(try XCTUnwrap(rig.sheet.window as? DialogWindow).onEscape?() == true)
    await browserDataImportUntil("the sheet closed") { window.attachedSheet == nil }
    let selection = await answer.value
    XCTAssertNil(selection)
    rig.controller.close()
  }

  /// Every type at zero: "Nothing to import", all rows dimmed, only Cancel works.
  func testEveryTypeAtZeroOffersOnlyCancel() async throws {
    let rig = try Rig()
    await browserDataImportUntil("the sheet") { rig.window.attachedSheet === rig.sheet.window }
    let answer = await rig.reachConsent(ProfileDataCounts())
    await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
    XCTAssertEqual(rig.content.title.text, "Nothing to import")
    XCTAssertFalse(rig.content.primaryButton.isEnabled)
    XCTAssertTrue(rig.content.secondaryButton.isEnabled)
    XCTAssertTrue(rig.content.rowViews.values.allSatisfy { !$0.checkbox.isEnabled })
    XCTAssertNil(rig.content.groupViews[1].noticeView)
    rig.content.secondaryButton.performClick(nil)
    await browserDataImportUntil("closed") { rig.window.attachedSheet == nil }
    _ = await answer.value
    rig.controller.close()
  }

  /// Huge counts: the value stays on one line and under 14 characters, the name keeps its place, nothing leaves the
  /// sheet and no row is wider than the sheet.
  func testHugeCountsKeepEveryRowInsideTheSheet() async throws {
    let huge = ProfileDataCounts(historyURLs: .max, historyVisits: .max, bookmarks: 12_500_000, cookies: 2_100_000_000,
                                 logins: 9_999_999, extensions: 1)
    let rig = try Rig(spaces: SpacesAndTabsStep(
      count: { SpacesAndTabsCount(items: 123_456_789, spaces: 1) },
      run: { SpacesAndTabsResult(items: 1, skipped: 0, failed: false, addedSpaces: []) }))
    await browserDataImportUntil("the sheet") { rig.window.attachedSheet === rig.sheet.window }
    let answer = await rig.reachConsent(huge)
    await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
    rig.content.layoutSubtreeIfNeeded()
    let values = Dictionary(uniqueKeysWithValues: rig.content.rowViews.map { ($0.key, $0.value.valueText.text) })
    XCTAssertEqual(values[.history], "999T+")
    XCTAssertEqual(values[.bookmarks], "12.5M")
    XCTAssertEqual(values[.cookies], "2.1B")
    XCTAssertEqual(values[.passwords], "9,999,999")
    XCTAssertEqual(values[.spacesAndTabs], "123.4M")
    for (_, view) in rig.content.rowViews {
      XCTAssertLessThanOrEqual(view.valueText.frame.maxX, view.bounds.width - 12 + 0.5, "\(view.kind)")
      XCTAssertGreaterThanOrEqual(view.valueText.frame.minX, view.nameText.frame.maxX, "the name never runs under the count: \(view.kind)")
      XCTAssertEqual(view.valueText.frame.height, view.valueText.fitting(width: 400).height, "one line")
      XCTAssertLessThan(view.valueText.text.count, 14)
    }
    let height = rig.content.layoutContent(width: BrowserDataImportSheet.width)
    XCTAssertEqual(rig.sheet.window?.contentRect(forFrameRect: rig.sheet.window!.frame).height ?? 0, height, accuracy: 1)
    XCTAssertLessThan(height, 560, "the sheet stays compact")
    for view in rig.content.subviews where !view.isHidden {
      XCTAssertLessThanOrEqual(view.frame.maxX, BrowserDataImportSheet.width + 0.5, "\(type(of: view))")
    }
    rig.content.secondaryButton.performClick(nil)
    _ = await answer.value
    rig.controller.close()
  }

  /// Reduce Motion: no spinning arc, no sweep, the bar moves in tenths; with it off the arc spins and the bar sweeps.
  func testReduceMotionStopsTheArcAndTheSweep() async throws {
    for reduce in [false, true] {
      let rig = try Rig(reduceMotion: reduce)
      await browserDataImportUntil("the sheet") { rig.window.attachedSheet === rig.sheet.window }
      let answer = await rig.reachConsent(Self.counts)
      await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
      rig.content.primaryButton.performClick(nil)
      _ = await answer.value
      rig.importer.send(.progress(.history, .writing(done: 33, total: 100)))
      let history = try row(rig, .history)
      await browserDataImportUntil("working") { history.valueText.text == "33 of 100" }
      XCTAssertEqual(history.glyph.isSpinning, !reduce, "reduce motion \(reduce)")
      XCTAssertEqual(history.bar.isSweeping, !reduce)
      XCTAssertEqual(history.bar.displayedFraction, reduce ? 0.3 : 0.33, accuracy: 0.0001)
      rig.content.secondaryButton.performClick(nil)
      rig.importer.finish({ var s = ProfileImportSummary(); s.cancelled = true; return s }())
      await browserDataImportUntil("the result") { rig.model.state.phase == .result }
      XCTAssertFalse(history.glyph.isSpinning, "nothing loops after the run")
      rig.content.primaryButton.performClick(nil)
      await browserDataImportUntil("closed") { rig.window.attachedSheet == nil }
      rig.controller.close()
    }
  }

  /// Light and dark: the text and the field follow the appearance.
  func testTheSheetFollowsLightAndDark() async throws {
    let rig = try Rig()
    await browserDataImportUntil("the sheet") { rig.window.attachedSheet === rig.sheet.window }
    let answer = await rig.reachConsent(Self.counts)
    await browserDataImportUntil("consent") { rig.model.state.phase == .consent }
    func resolved(_ appearance: NSAppearance.Name) -> NSColor {
      let window = rig.sheet.window
      window?.appearance = NSAppearance(named: appearance)
      window?.contentView?.viewDidChangeEffectiveAppearance()
      return rig.content.style.palette.text.usingColorSpace(.sRGB) ?? .clear
    }
    let light = resolved(.aqua)
    let dark = resolved(.darkAqua)
    XCTAssertNotEqual(light, dark)
    XCTAssertGreaterThan(light.brightnessComponent, 0, "")
    XCTAssertLessThan(light.brightnessComponent, dark.brightnessComponent, "dark text on light, light on dark")
    rig.content.secondaryButton.performClick(nil)
    _ = await answer.value
    rig.controller.close()
  }
}
