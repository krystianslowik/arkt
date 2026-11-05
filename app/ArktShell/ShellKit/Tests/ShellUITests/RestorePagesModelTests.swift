import Foundation
import Testing
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

@MainActor
struct RestorePagesModelTests {
  private func page(_ title: String, _ kind: RestorePagesModel.Page.Kind) -> RestorePagesModel.Page {
    RestorePagesModel.Page(title: title, url: URL(string: "https://example.invalid/\(title)")!, kind: kind)
  }

  @Test func cleanExitNeverOffersPagesOrAcknowledgesACrash() {
    let engine = InMemoryEngine()
    let model = RestorePagesModel(recovery: engine.crashedSession, pages: [page("One", .peek)])

    #expect(model.presentation == .none)
    #expect(engine.crashedSession.dismissals == 0)
  }

  @Test func crashOffersOnlyLittleArktAndPeekPages() {
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let little = page("Little", .littleArkt)
    let peek = page("Peek", .peek)
    let model = RestorePagesModel(recovery: engine.crashedSession, pages: [
      little, page("Private", .incognito), peek, page("Blank", .blank), page("Sidebar", .sidebar),
    ])

    #expect(model.presentation == .offer([little, peek]))
    #expect(engine.crashedSession.dismissals == 0)
  }

  @Test func crashWithOnlyPrivateOrSidebarPagesShowsNoticeAndAcknowledgesOnce() {
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let pages = [page("Private", .incognito), page("Blank", .blank), page("Sidebar", .sidebar)]
    let model = RestorePagesModel(recovery: engine.crashedSession, pages: pages)

    #expect(model.presentation == .notice)
    #expect(engine.crashedSession.dismissals == 1)
    #expect(RestorePagesModel(recovery: engine.crashedSession, pages: pages).presentation == .none)
    #expect(engine.crashedSession.dismissals == 1)
  }

  @Test func dismissAcknowledgesWithoutRestoringAndCannotPromptAgain() {
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let offered = [page("One", .peek)]
    var restored: [RestorePagesModel.Page] = []
    let model = RestorePagesModel(recovery: engine.crashedSession, pages: offered) { restored = $0 }

    model.dismiss()
    model.dismiss()
    model.restore()

    #expect(restored.isEmpty)
    #expect(model.presentation == .none)
    #expect(engine.crashedSession.dismissals == 1)
    #expect(RestorePagesModel(recovery: engine.crashedSession, pages: offered).presentation == .none)
  }

  @Test func restoreReopensEveryOfferedPageAndAcknowledgesOnce() {
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let offered = (0..<5).map { page("Page\($0)", .peek) }
    var restored: [RestorePagesModel.Page] = []
    let model = RestorePagesModel(recovery: engine.crashedSession, pages: offered + [page("Private", .incognito)]) {
      restored = $0
    }

    model.restore()
    model.restore()
    model.dismiss()

    #expect(restored == offered)
    #expect(model.presentation == .none)
    #expect(engine.crashedSession.dismissals == 1)
    #expect(RestorePagesModel(recovery: engine.crashedSession, pages: offered).presentation == .none)
  }
}

@MainActor
struct RestorePagesProviderTests {
  @Test func providerReceivesEveryPageExactlyOnce() {
    let engine = InMemoryEngine()
    let pages = (0..<5).map { index in
      RecoveryPage(title: "Page \(index)", url: URL(string: "https://example.invalid/\(index)")!, kind: .peek)
    }
    engine.crashedSession.recoveryPages = pages
    engine.crashedSession.simulateCrashedExit()
    let model = RestorePagesModel(recovery: engine.crashedSession)
    model.restore()
    model.restore()
    model.dismiss()
    #expect(engine.crashedSession.restoredPages == [pages])
    #expect(engine.crashedSession.dismissals == 1)
  }
}
