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
