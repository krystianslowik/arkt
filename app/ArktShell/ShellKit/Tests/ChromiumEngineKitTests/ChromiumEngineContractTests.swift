import Foundation
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Every check of the shared engine contract (rules 1-16), each in its own test.
enum ContractCheck: String, CaseIterable, Sendable {
  // Rules 1-10
  case createdTabIsListedAndAnnounced, navigateReportsURLLoadingAndTitle, titleChangedAfterLoadIsReported
  case contentViewIsStable, closeIsTerminal, closeInsideObserverKeepsOrder, cancelledObservationStopsDelivery
  case droppedObservationStopsDelivery, tabIDsKeepCreationOrder, hostChangeClearsFavicon, historyMovesBackAndForward
  case historyAvailabilityIsReported, historyEntriesAndOffsetNavigation, duplicateTabCopiesURLTitleAndHistory
  // Rules 11-16
  case windowIsListedAndAnnounced, closeWindowClosesItsTabsThenReportsWindowClosed, hostCloseRequestClosesTheWindow
  case activationIsOneTabPerWindow, engineCreatedTabIsAnnounced, engineCloseIsTerminal
  case windowlessCreateTabLandsInMostRecentlyActiveWindow, heldCloseKeepsTheTabUntilAnswered
  case skipUnloadHandlersNeverHolds, cancelledWindowCloseKeepsTheWindow

  @MainActor
  func run(_ h: EngineHarness) async throws {
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
    case .activationIsOneTabPerWindow: try await EngineContract.activationIsOneTabPerWindow(h)
    case .engineCreatedTabIsAnnounced: try await EngineContract.engineCreatedTabIsAnnounced(h)
    case .engineCloseIsTerminal: try await EngineContract.engineCloseIsTerminal(h)
    case .windowlessCreateTabLandsInMostRecentlyActiveWindow:
      try await EngineContract.windowlessCreateTabLandsInMostRecentlyActiveWindow(h)
    case .heldCloseKeepsTheTabUntilAnswered: try await EngineContract.heldCloseKeepsTheTabUntilAnswered(h)
    case .skipUnloadHandlersNeverHolds: try await EngineContract.skipUnloadHandlersNeverHolds(h)
    case .cancelledWindowCloseKeepsTheWindow: try await EngineContract.cancelledWindowCloseKeepsTheWindow(h)
    }
  }
}

/// How the scripted facade orders a load's events.
enum FacadeScript: String, CaseIterable, Sendable {
  /// Chromium's usual order: title, favicon clear, load end.
  case chromiumOrder
  /// The title and the favicon clear recorded after the load end, in the same batch (Risk 2).
  case titleAfterLoadEnd
}

/// The shared contract against `ChromiumEngine` over the scripted facade, in plain `swift test` (no Chromium). Every
/// harness driver is present, so no rule is reported as not applicable.
@MainActor
struct ChromiumEngineContractTests {
  @Test(arguments: ContractCheck.allCases, FacadeScript.allCases)
  func contract(_ check: ContractCheck, _ script: FacadeScript) async throws {
    let harness = ScriptedHarness.make { facade in facade.titleAfterLoadEnd = script == .titleAfterLoadEnd }
    try await check.run(harness)
  }

  /// The drivers are all present: a rule that needs one never throws `ContractNotApplicable`.
  @Test func everyDriverIsPresent() {
    let harness = ScriptedHarness.make()
    #expect(harness.engineCreateTab != nil && harness.engineCloseTab != nil && harness.engineActivate != nil)
    #expect(harness.holdClose != nil && harness.answerDialog != nil)
  }

  /// The list names every public check of `EngineContract` (read from its sources), so a new rule cannot be left out.
  @Test func everyContractCheckIsListed() throws {
    let support = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../Sources/EngineAPITestSupport").standardizedFileURL
    let files = try FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("EngineContract") }
    var names: Set<String> = []
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      for match in source.matches(of: #/public static func (\w+)\(_ h: EngineHarness\)/#) {
        names.insert(String(match.output.1))
      }
    }
    #expect(names.count == 24)
    #expect(names == Set(ContractCheck.allCases.map(\.rawValue)))
  }
}
