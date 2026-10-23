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
