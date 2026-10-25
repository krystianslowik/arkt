import Testing
import EngineAPI
import EngineAPITestSupport

@MainActor
struct LatestActiveTabTests {
  @Test func latestActiveTabDefaultsToTheImmediateEnginesActiveTab() {
    let engine = InMemoryEngine()
    let client: any EngineClient = engine
    let window = engine.createWindow(host: StubWindowHost())
    #expect(client.latestActiveTab(in: window) == nil)
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    #expect(client.latestActiveTab(in: window) == a)
    engine.activateTab(b)
    #expect(client.latestActiveTab(in: window) == b)
    engine.closeWindow(window)
    #expect(client.latestActiveTab(in: window) == nil)
  }
}
