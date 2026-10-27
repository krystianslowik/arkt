import Foundation
import Testing
import EngineAPI
@testable import EngineAPITestSupport

@MainActor
struct InMemoryEngineContractTests {
  let harness = EngineHarness.inMemory()

  @Test func createdTabIsListedAndAnnounced() async throws { try await EngineContract.createdTabIsListedAndAnnounced(harness) }
  @Test func navigateReportsURLLoadingAndTitle() async throws { try await EngineContract.navigateReportsURLLoadingAndTitle(harness) }
  @Test func titleChangedAfterLoadIsReported() async throws { try await EngineContract.titleChangedAfterLoadIsReported(harness) }
  @Test func contentViewIsStable() async throws { try await EngineContract.contentViewIsStable(harness) }
  @Test func closeIsTerminal() async throws { try await EngineContract.closeIsTerminal(harness) }
  @Test func closeInsideObserverKeepsOrder() async throws { try await EngineContract.closeInsideObserverKeepsOrder(harness) }
  @Test func cancelledObservationStopsDelivery() async throws { try await EngineContract.cancelledObservationStopsDelivery(harness) }
  @Test func droppedObservationStopsDelivery() async throws { try await EngineContract.droppedObservationStopsDelivery(harness) }
  @Test func tabIDsKeepCreationOrder() async throws { try await EngineContract.tabIDsKeepCreationOrder(harness) }
  @Test func hostChangeClearsFavicon() async throws { try await EngineContract.hostChangeClearsFavicon(harness) }
  @Test func historyMovesBackAndForward() async throws { try await EngineContract.historyMovesBackAndForward(harness) }
  @Test func historyAvailabilityIsReported() async throws { try await EngineContract.historyAvailabilityIsReported(harness) }
  @Test func historyEntriesAndOffsetNavigation() async throws { try await EngineContract.historyEntriesAndOffsetNavigation(harness) }
  @Test func duplicateTabCopiesURLTitleAndHistory() async throws { try await EngineContract.duplicateTabCopiesURLTitleAndHistory(harness) }
  // Rules 11-16
  @Test func windowIsListedAndAnnounced() async throws { try await EngineContract.windowIsListedAndAnnounced(harness) }
  @Test func closeWindowClosesItsTabsThenReportsWindowClosed() async throws {
    try await EngineContract.closeWindowClosesItsTabsThenReportsWindowClosed(harness)
  }
  @Test func hostCloseRequestClosesTheWindow() async throws { try await EngineContract.hostCloseRequestClosesTheWindow(harness) }
  @Test func emptiedWindowReportsLastTabClosed() async throws {
    try await EngineContract.emptiedWindowReportsLastTabClosed(harness)
  }
  @Test func extensionWindowCloseReportsExtension() async throws {
    try await EngineContract.extensionWindowCloseReportsExtension(harness)
  }
  @Test func activationIsOneTabPerWindow() async throws { try await EngineContract.activationIsOneTabPerWindow(harness) }
  @Test func engineCreatedTabIsAnnounced() async throws { try await EngineContract.engineCreatedTabIsAnnounced(harness) }
  @Test func engineCloseIsTerminal() async throws { try await EngineContract.engineCloseIsTerminal(harness) }
  @Test func windowlessCreateTabLandsInMostRecentlyActiveWindow() async throws {
    try await EngineContract.windowlessCreateTabLandsInMostRecentlyActiveWindow(harness)
  }
  @Test func heldCloseKeepsTheTabUntilAnswered() async throws { try await EngineContract.heldCloseKeepsTheTabUntilAnswered(harness) }
  @Test func skipUnloadHandlersNeverHolds() async throws { try await EngineContract.skipUnloadHandlersNeverHolds(harness) }
  @Test func cancelledWindowCloseKeepsTheWindow() async throws { try await EngineContract.cancelledWindowCloseKeepsTheWindow(harness) }
  // Rule 17
  @Test func muteIsReportedOnce() async throws { try await EngineContract.muteIsReportedOnce(harness) }
  @Test func audibleStateIsReported() async throws { try await EngineContract.audibleStateIsReported(harness) }
  // Rule 18
  @Test func pageImageFitsTheCaps() async throws { try await EngineContract.pageImageFitsTheCaps(harness) }
  @Test func pageImageOfAClosedTabIsNil() async throws { try await EngineContract.pageImageOfAClosedTabIsNil(harness) }
  // Rule 19
  @Test func dialogIsReportedAnsweredAndEndedOnce() async throws {
    try await EngineContract.dialogIsReportedAnsweredAndEndedOnce(harness)
  }
  @Test func pendingDialogEndsBeforeItsTabCloses() async throws {
    try await EngineContract.pendingDialogEndsBeforeItsTabCloses(harness)
  }
  @Test func hiddenTabEndsItsConfirmAndPrompt() async throws {
    try await EngineContract.hiddenTabEndsItsConfirmAndPrompt(harness)
  }
  // Rule 20
  @Test func permissionIsReportedAnsweredAndEndedOnce() async throws {
    try await EngineContract.permissionIsReportedAnsweredAndEndedOnce(harness)
  }
  @Test func pendingPermissionEndsBeforeItsTabCloses() async throws {
    try await EngineContract.pendingPermissionEndsBeforeItsTabCloses(harness)
  }
  @Test func navigationEndsItsPermission() async throws { try await EngineContract.navigationEndsItsPermission(harness) }
  @Test func hiddenTabEndsItsPermissionAndAsksAgain() async throws {
    try await EngineContract.hiddenTabEndsItsPermissionAndAsksAgain(harness)
  }

  /// A harness without engine drivers reports rules 13, 14, 16 and 17's audible check as not applicable, never as passed.
  @Test func missingDriversAreNotApplicable() async throws {
    let bare = EngineHarness(makeEngine: harness.makeEngine, pageURL: harness.pageURL, settle: harness.settle,
                             retitle: harness.retitle, pagesOnTwoHosts: harness.pagesOnTwoHosts)
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.engineCreatedTabIsAnnounced(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.engineCloseIsTerminal(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.heldCloseKeepsTheTabUntilAnswered(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.skipUnloadHandlersNeverHolds(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.cancelledWindowCloseKeepsTheWindow(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.audibleStateIsReported(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.pageImageFitsTheCaps(bare) }
    await #expect(throws: ContractNotApplicable.self) { try await EngineContract.dialogIsReportedAnsweredAndEndedOnce(bare) }
    await #expect(throws: ContractNotApplicable.self) {
      try await EngineContract.permissionIsReportedAnsweredAndEndedOnce(bare)
    }
    await #expect(throws: ContractNotApplicable.self) {
      try await EngineContract.extensionWindowCloseReportsExtension(bare)
    }
  }
}

@MainActor
struct InMemoryEngineTests {
  @Test func reloadEmitsOnlyWhenLoadingStarts() {
    let engine = InMemoryEngine()
    let id = engine.createTab(url: URL(string: "arkt-test://page/A")!)
    let recorder = EventRecorder(engine)
    engine.reload(id)
    #expect(recorder.events.isEmpty, "reload while loading must not emit")
    engine.finishLoad(id, title: "A")
    let mark = recorder.events.count
    engine.reload(id)
    #expect(Array(recorder.events.dropFirst(mark)) == [.loadingChanged(id, isLoading: true)])
  }

  @Test func newNavigationDropsForwardHistory() {
    let engine = InMemoryEngine()
    let (a, b, c) = (URL(string: "arkt-test://page/A")!, URL(string: "arkt-test://page/B")!,
                     URL(string: "arkt-test://page/C")!)
    let id = engine.createTab(url: a)
    engine.navigate(id, to: b)
    engine.goBack(id)
    #expect(engine.snapshot(of: id)?.url == a)
    engine.navigate(id, to: c)
    let recorder = EventRecorder(engine)
    engine.goForward(id)
    #expect(recorder.events.isEmpty, "forward after a new navigation must be a no-op")
    engine.goBack(id)
    #expect(engine.snapshot(of: id)?.url == a)
  }

  /// Like a reload: the history is left as it was, so Back finds no duplicate and Forward still works.
  @Test func navigatingToTheCurrentURLLeavesTheHistoryAlone() {
    let engine = InMemoryEngine()
    let (a, b) = (URL(string: "arkt-test://page/A")!, URL(string: "arkt-test://page/B")!)
    let id = engine.createTab(url: a)
    engine.navigate(id, to: b)
    engine.goBack(id)
    engine.navigate(id, to: a)
    #expect(engine.snapshot(of: id)?.url == a)
    let recorder = EventRecorder(engine)
    engine.goBack(id)
    #expect(recorder.events.isEmpty, "no back entry for the URL the tab already shows")
    engine.goForward(id)
    #expect(engine.snapshot(of: id)?.url == b, "the forward entry survives")
    engine.goBack(id)
    #expect(engine.snapshot(of: id)?.url == a)
  }

  /// `.historyChanged` only when availability changes: a third page or a same-URL navigation emits none.
  @Test func historyChangedOnlyWhenAvailabilityChanges() {
    let engine = InMemoryEngine()
    let (a, b, c) = (URL(string: "arkt-test://page/A")!, URL(string: "arkt-test://page/B")!,
                     URL(string: "arkt-test://page/C")!)
    let id = engine.createTab(url: a)
    let recorder = EventRecorder(engine)
    let history = { recorder.events(for: id).filter { if case .historyChanged = $0 { return true }; return false } }
    engine.navigate(id, to: b)
    #expect(history() == [.historyChanged(id, canGoBack: true, canGoForward: false)])
    engine.navigate(id, to: c)
    engine.navigate(id, to: c)
    #expect(history().count == 1, "Back was already available")
    engine.goBack(id)
    engine.goBack(id)
    #expect(history().last == .historyChanged(id, canGoBack: false, canGoForward: true))
    #expect(engine.snapshot(of: id)?.canGoBack == false && engine.snapshot(of: id)?.canGoForward == true)
  }

  @Test func sameHostNavigationKeepsFavicon() {
    let engine = InMemoryEngine()
    let id = engine.createTab(url: URL(string: "arkt-test://alpha.test/A")!)
    engine.finishLoad(id, title: "A", favicon: Data([1]))
    let recorder = EventRecorder(engine)
    engine.navigate(id, to: URL(string: "arkt-test://alpha.test/B")!)
    #expect(!recorder.events.contains(.faviconChanged(id, nil)))
    #expect(engine.snapshot(of: id)?.faviconData == Data([1]))
  }
}
