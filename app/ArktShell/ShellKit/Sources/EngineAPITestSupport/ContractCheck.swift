import EngineAPI

/// Every check of the shared engine contract (rules 1-19), so the XCTest and Swift Testing suites and the in-app
/// runner (W3-9) run the same list. `ChromiumEngineContractTests.everyContractCheckIsListed` keeps it complete.
public enum ContractCheck: String, CaseIterable, Sendable {
  // Rules 1-10
  case createdTabIsListedAndAnnounced, navigateReportsURLLoadingAndTitle, titleChangedAfterLoadIsReported
  case contentViewIsStable, closeIsTerminal, closeInsideObserverKeepsOrder, cancelledObservationStopsDelivery
  case droppedObservationStopsDelivery, tabIDsKeepCreationOrder, hostChangeClearsFavicon, historyMovesBackAndForward
  case historyAvailabilityIsReported, historyEntriesAndOffsetNavigation, duplicateTabCopiesURLTitleAndHistory
  // Rules 11-16
  case windowIsListedAndAnnounced, closeWindowClosesItsTabsThenReportsWindowClosed, hostCloseRequestClosesTheWindow
  case emptiedWindowReportsLastTabClosed, extensionWindowCloseReportsExtension
  case activationIsOneTabPerWindow, engineCreatedTabIsAnnounced, engineCloseIsTerminal
  case windowlessCreateTabLandsInMostRecentlyActiveWindow, heldCloseKeepsTheTabUntilAnswered
  case skipUnloadHandlersNeverHolds, cancelledWindowCloseKeepsTheWindow
  // Rule 17
  case muteIsReportedOnce, audibleStateIsReported
  // Rule 18
  case pageImageFitsTheCaps, pageImageOfAClosedTabIsNil
  // Rule 19
  case dialogIsReportedAnsweredAndEndedOnce, pendingDialogEndsBeforeItsTabCloses

  /// The contract rule (1-19) the check belongs to, as numbered in `EngineContract`'s documentation.
  public var rule: Int {
    switch self {
    case .createdTabIsListedAndAnnounced, .tabIDsKeepCreationOrder: 1
    case .navigateReportsURLLoadingAndTitle, .titleChangedAfterLoadIsReported: 2
    case .contentViewIsStable: 3
    case .closeIsTerminal, .closeInsideObserverKeepsOrder: 4
    case .cancelledObservationStopsDelivery, .droppedObservationStopsDelivery: 5
    case .hostChangeClearsFavicon: 6
    case .historyMovesBackAndForward: 7
    case .historyAvailabilityIsReported: 8
    case .historyEntriesAndOffsetNavigation: 9
    case .duplicateTabCopiesURLTitleAndHistory: 10
    case .windowIsListedAndAnnounced, .closeWindowClosesItsTabsThenReportsWindowClosed,
         .hostCloseRequestClosesTheWindow, .emptiedWindowReportsLastTabClosed,
         .extensionWindowCloseReportsExtension: 11
    case .activationIsOneTabPerWindow: 12
    case .engineCreatedTabIsAnnounced: 13
    case .engineCloseIsTerminal: 14
    case .windowlessCreateTabLandsInMostRecentlyActiveWindow: 15
    case .heldCloseKeepsTheTabUntilAnswered, .skipUnloadHandlersNeverHolds, .cancelledWindowCloseKeepsTheWindow: 16
    case .muteIsReportedOnce, .audibleStateIsReported: 17
    case .pageImageFitsTheCaps, .pageImageOfAClosedTabIsNil: 18
    case .dialogIsReportedAnsweredAndEndedOnce, .pendingDialogEndsBeforeItsTabCloses: 19
    }
  }

  @MainActor
  public func run(_ h: EngineHarness) async throws {
    switch self {
    case .createdTabIsListedAndAnnounced: try await EngineContract.createdTabIsListedAndAnnounced(h)
    case .navigateReportsURLLoadingAndTitle: try await EngineContract.navigateReportsURLLoadingAndTitle(h)
    case .titleChangedAfterLoadIsReported: try await EngineContract.titleChangedAfterLoadIsReported(h)
    case .contentViewIsStable: try await EngineContract.contentViewIsStable(h)
    case .closeIsTerminal: try await EngineContract.closeIsTerminal(h)
    case .closeInsideObserverKeepsOrder: try await EngineContract.closeInsideObserverKeepsOrder(h)
    case .cancelledObservationStopsDelivery: try await EngineContract.cancelledObservationStopsDelivery(h)
    case .droppedObservationStopsDelivery: try await EngineContract.droppedObservationStopsDelivery(h)
    case .tabIDsKeepCreationOrder: try await EngineContract.tabIDsKeepCreationOrder(h)
    case .hostChangeClearsFavicon: try await EngineContract.hostChangeClearsFavicon(h)
    case .historyMovesBackAndForward: try await EngineContract.historyMovesBackAndForward(h)
    case .historyAvailabilityIsReported: try await EngineContract.historyAvailabilityIsReported(h)
    case .historyEntriesAndOffsetNavigation: try await EngineContract.historyEntriesAndOffsetNavigation(h)
    case .duplicateTabCopiesURLTitleAndHistory: try await EngineContract.duplicateTabCopiesURLTitleAndHistory(h)
    case .windowIsListedAndAnnounced: try await EngineContract.windowIsListedAndAnnounced(h)
    case .closeWindowClosesItsTabsThenReportsWindowClosed:
      try await EngineContract.closeWindowClosesItsTabsThenReportsWindowClosed(h)
    case .hostCloseRequestClosesTheWindow: try await EngineContract.hostCloseRequestClosesTheWindow(h)
    case .emptiedWindowReportsLastTabClosed: try await EngineContract.emptiedWindowReportsLastTabClosed(h)
    case .extensionWindowCloseReportsExtension: try await EngineContract.extensionWindowCloseReportsExtension(h)
    case .activationIsOneTabPerWindow: try await EngineContract.activationIsOneTabPerWindow(h)
    case .engineCreatedTabIsAnnounced: try await EngineContract.engineCreatedTabIsAnnounced(h)
    case .engineCloseIsTerminal: try await EngineContract.engineCloseIsTerminal(h)
    case .windowlessCreateTabLandsInMostRecentlyActiveWindow:
      try await EngineContract.windowlessCreateTabLandsInMostRecentlyActiveWindow(h)
    case .heldCloseKeepsTheTabUntilAnswered: try await EngineContract.heldCloseKeepsTheTabUntilAnswered(h)
    case .skipUnloadHandlersNeverHolds: try await EngineContract.skipUnloadHandlersNeverHolds(h)
    case .cancelledWindowCloseKeepsTheWindow: try await EngineContract.cancelledWindowCloseKeepsTheWindow(h)
    case .muteIsReportedOnce: try await EngineContract.muteIsReportedOnce(h)
    case .audibleStateIsReported: try await EngineContract.audibleStateIsReported(h)
    case .pageImageFitsTheCaps: try await EngineContract.pageImageFitsTheCaps(h)
    case .pageImageOfAClosedTabIsNil: try await EngineContract.pageImageOfAClosedTabIsNil(h)
    case .dialogIsReportedAnsweredAndEndedOnce: try await EngineContract.dialogIsReportedAnsweredAndEndedOnce(h)
    case .pendingDialogEndsBeforeItsTabCloses: try await EngineContract.pendingDialogEndsBeforeItsTabCloses(h)
    }
  }
}
