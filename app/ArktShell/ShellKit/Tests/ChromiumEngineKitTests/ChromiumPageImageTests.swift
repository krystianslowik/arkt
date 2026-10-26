import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Page images over the facade (#370, #352): the request's pixel cap goes to the tab handle's `copyFrame` (the
/// facade's `CopyFromSurface` scales on the GPU), the PNG it answers comes back within both caps, and a tab without a
/// drawn frame gives nil without being asked to load.
@MainActor
struct ChromiumPageImageTests {
  let facade = ScriptedFacade()
  private let page = URL(string: "arkt-test://page.test/Frame")!

  private func loadedTab() throws -> (ChromiumEngine, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    let handle = try #require(engine.handle(of: tab) as? ScriptedTab)
    handle.finishLoad()
    facade.flush()
    return (engine, tab, handle)
  }

  @Test func thumbnailAsksTheFacadeForTheCapAndFitsIt() async throws {
    let (engine, tab, handle) = try loadedTab()
    let image = try #require(await engine.pageImage(of: tab, .thumbnail))
    #expect(handle.copyRequests == [NSSize(width: 600, height: 360)])
    // 2560 x 1600 px scaled to fit 600 x 360.
    #expect(image.pixelWidth == 576 && image.pixelHeight == 360)
    #expect(image.data.count <= 80_000)
    #expect(abs(image.scale - 0.45) < 0.001)
  }

  @Test func fullFrameAsksForNoCapAndKeepsTheBackingSize() async throws {
    let (engine, tab, handle) = try loadedTab()
    let image = try #require(await engine.pageImage(of: tab, .fullFrame))
    #expect(handle.copyRequests == [.zero])
    #expect(image.pixelWidth == 2560 && image.pixelHeight == 1600)
    #expect(image.scale == 2)
    #expect(image.format == .png)
  }

  /// A hidden-and-evicted or discarded tab: nil, and nothing is loaded for it.
  @Test func tabWithoutACopyableFrameGivesNil() async throws {
    let (engine, tab, handle) = try loadedTab()
    handle.frameAvailable = false
    let recorder = EventRecorder(engine)
    #expect(await engine.pageImage(of: tab, .thumbnail) == nil)
    facade.flush()
    #expect(recorder.events(for: tab).isEmpty)
  }

  @Test func tabBeforeItsFirstLoadGivesNil() async throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    #expect(await engine.pageImage(of: tab, .thumbnail) == nil)
  }

  @Test func unknownTabNeverReachesTheFacade() async throws {
    let (engine, _, handle) = try loadedTab()
    #expect(await engine.pageImage(of: TabID(), .thumbnail) == nil)
    #expect(handle.copyRequests.isEmpty)
  }
}
