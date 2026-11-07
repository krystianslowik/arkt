import Foundation
import Testing
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

@MainActor
struct RestorePagesModelTests {
  @Test func offerRequestsEveryPageBeforeAcknowledgingOnce() {
    let recovery = InMemorySessionRecovery()
    let pages = (0..<5).map { ShellRecoveryPage(title: "Page \($0)",
      url: URL(string: "https://example.invalid/\($0)")!, kind: $0 == 0 ? .littleArkt : .peek) }
    recovery.simulateCrashedExit()
    var requested: [ShellRecoveryPage] = []
    let model = RestorePagesModel(recovery: recovery, pages: pages) { pages in
      #expect(recovery.dismissals == 0)
      requested = pages
      return true
    }
    #expect(model.presentation == .offer(pages))
    model.restore()
    model.restore()
    model.dismiss()
    #expect(requested == pages)
    #expect(recovery.dismissals == 1)
  }

  @Test func unavailableShellActionRetainsOffer() {
    let recovery = InMemorySessionRecovery()
    let page = ShellRecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)
    recovery.simulateCrashedExit()
    let model = RestorePagesModel(recovery: recovery, pages: [page]) { _ in false }
    model.restore()
    #expect(model.presentation == .offer([page]))
    #expect(recovery.dismissals == 0)
  }

  @Test func cleanAndEmptySessions() {
    let recovery = InMemorySessionRecovery()
    let clean = RestorePagesModel(recovery: recovery) { _ in true }
    #expect(clean.presentation == .none)
    recovery.simulateCrashedExit()
    let empty = RestorePagesModel(recovery: recovery) { _ in true }
    #expect(empty.presentation == .notice)
    #expect(recovery.dismissals == 1)
  }
}

@MainActor
private final class LegacyRecovery: EngineSessionRecovery {
  var lastSessionCrashed = true
  var dismissals = 0
  func dismissLastSession() { lastSessionCrashed = false; dismissals += 1 }
}

@MainActor
struct LegacyRecoveryTests {
  @Test func crashOnlyProviderDoesNotOfferPages() {
    let recovery = LegacyRecovery()
    let model = RestorePagesModel(recovery: recovery) { _ in true }
    #expect(model.presentation == .notice)
    #expect(recovery.dismissals == 1)
  }
}
