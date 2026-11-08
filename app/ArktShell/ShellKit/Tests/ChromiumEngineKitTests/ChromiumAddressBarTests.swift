import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// #784: `navigateFromAddressBar` reaches the facade's address-bar call, which Chromium counts and treats as Chrome's
/// omnibox does (`ScriptedAddressBar.swift`), while `navigate` keeps the plain typed transition.
@MainActor
struct ChromiumAddressBarTests {
  let facade = ScriptedFacade()
  let first = URL(string: "arkt-test://alpha.test/First")!
  let second = URL(string: "arkt-test://alpha.test/Second")!

  /// A tab that shows `first`, loaded, with no visits recorded yet.
  func loadedTab() throws -> (ChromiumEngine, TabID, ScriptedTab) {
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    let id = engine.createTab(url: first, in: window)
    let tab = try #require(engine.handle(of: id) as? ScriptedTab)
    tab.finishLoad()
    return (engine, id, tab)
  }

  @Test func addressBarNavigationCarriesTheAddressBarTransition() throws {
    let (engine, id, tab) = try loadedTab()
    engine.navigateFromAddressBar(id, to: second)
    #expect(facade.history.visits == [ScriptedVisit(url: second, fromAddressBar: true, ranAsReload: false)])
    #expect(tab.url == second && tab.back.map(\.url) == [first], "a new URL is a new entry, as with navigate")
  }

  @Test func plainNavigateKeepsTheTypedTransitionAlone() throws {
    let (engine, id, _) = try loadedTab()
    engine.navigate(id, to: second)
    #expect(facade.history.visits == [ScriptedVisit(url: second, fromAddressBar: false, ranAsReload: false)])
  }

  /// The same URL again: plain navigate reloads the page, the address bar loads it as a new navigation. Both visits
  /// count as typed (out/Spike: `typed_count` 3 for three visits); only the address bar's carries the qualifier.
  @Test func theSameURLFromTheAddressBarIsANewNavigationNotAReload() throws {
    let (engine, id, tab) = try loadedTab()
    engine.navigate(id, to: second)
    tab.finishLoad()
    engine.navigate(id, to: second)
    tab.finishLoad()
    #expect(facade.history.visits.last == ScriptedVisit(url: second, fromAddressBar: false, ranAsReload: true),
            "plain navigate to the same URL reloads")

    engine.navigateFromAddressBar(id, to: second)
    tab.finishLoad()
    #expect(facade.history.visits.last == ScriptedVisit(url: second, fromAddressBar: true, ranAsReload: false),
            "the address bar loads it again")
    #expect(facade.history.typedCount(of: second) == 3, "every one of the three visits counts as typed")
    #expect(facade.history.visits.filter(\.fromAddressBar).count == 1)
    #expect(tab.back.map(\.url) == [first] && tab.forward.isEmpty, "the back list does not grow")
    #expect(engine.history(of: id)?.back.map(\.url) == [first])
  }

  /// A new URL: both calls add an entry and a typed visit.
  @Test func aNewURLCountsAsTypedEitherWay() throws {
    let (engine, id, tab) = try loadedTab()
    let third = URL(string: "arkt-test://alpha.test/Third")!
    engine.navigate(id, to: second)
    tab.finishLoad()
    engine.navigateFromAddressBar(id, to: third)
    tab.finishLoad()
    #expect(facade.history.typedCount(of: second) == 1 && facade.history.typedCount(of: third) == 1)
    #expect(tab.back.map(\.url) == [second, first])
  }

  @Test func browserDebugURLsDoNothingWithoutTheTestAPI() throws {
    facade.testAPIEnabled = false
    let (engine, id, tab) = try loadedTab()
    for address in ["chrome://gpucrash", "chrome://inducebrowsercrashforrealz/", "chrome://uithreadhang",
                    "chrome://gpuhang", "chrome://crash/browser/use-after-free"] {
      engine.navigateFromAddressBar(id, to: try #require(URL(string: address)))
    }
    #expect(facade.history.ranDebugURLs.isEmpty)
    #expect(facade.history.visits.isEmpty && tab.url == first && !tab.isLoading, "nothing navigates either")
  }

  @Test func browserDebugURLsRunFromTheAddressBarOnlyWithTheTestAPI() throws {
    let (engine, id, tab) = try loadedTab()
    let gpuCrash = try #require(URL(string: "chrome://gpucrash"))
    engine.navigate(id, to: gpuCrash)
    #expect(facade.history.ranDebugURLs.isEmpty, "plain navigate never runs one")
    engine.navigateFromAddressBar(id, to: gpuCrash)
    #expect(facade.history.ranDebugURLs == [gpuCrash])
    #expect(tab.url == first && facade.history.visits.isEmpty, "a debug URL is never a navigation")
  }

  @Test func onlyBrowserDebugURLsAreGated() {
    for address in ["chrome://gpucrash", "chrome://gpucrash/", "chrome://gpuclean", "chrome://delayeduithreadhang",
                    "chrome://memory-pressure-critical", "chrome://crash/gpu/heap-overflow"] {
      #expect(ScriptedHistory.isBrowserDebugURL(URL(string: address)!), "\(address)")
    }
    for address in ["chrome://crash", "chrome://crash/", "chrome://kill", "chrome://hang", "chrome://settings",
                    "chrome://gpucrash/other", "https://gpucrash/"] {
      #expect(!ScriptedHistory.isBrowserDebugURL(URL(string: address)!), "\(address)")
    }
  }

  /// Queued like navigate while the tab's insert is deferred (a nested run loop), then run in order.
  @Test func aDeferredAddressBarNavigationRunsAfterTheInsert() async throws {
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    facade.isNested = true
    let id = engine.createTab(url: first, in: window)
    engine.navigateFromAddressBar(id, to: second)
    #expect(facade.history.visits.isEmpty)
    facade.isNested = false
    try await ScriptedWait.until("the facade to deliver its batch") { facade.isIdle }
    #expect(facade.history.visits == [ScriptedVisit(url: second, fromAddressBar: true, ranAsReload: false)])
    #expect(engine.snapshot(of: id)?.url == second)
  }
}
