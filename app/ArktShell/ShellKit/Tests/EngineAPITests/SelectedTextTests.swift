import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// The page selection (#404, BH-193): reported until the page changes or the tab closes.
@MainActor
struct SelectedTextTests {
  private let page = URL(string: "arkt-test://page/Words")!
  private let other = URL(string: "arkt-test://page/Other")!

  @Test func aSelectionIsReportedAndCleared() {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page)
    #expect(engine.selectedText(of: tab) == nil)
    engine.setSelectedText(tab, "quick brown fox")
    #expect(engine.selectedText(of: tab) == "quick brown fox")
    engine.setSelectedText(tab, "")
    #expect(engine.selectedText(of: tab) == nil)
  }

  @Test func aNavigationDropsTheSelection() {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page)
    engine.setSelectedText(tab, "quick brown fox")
    engine.navigate(tab, to: other)
    #expect(engine.selectedText(of: tab) == nil)
  }

  @Test func aClosedTabHasNoSelection() {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page)
    engine.setSelectedText(tab, "quick brown fox")
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    #expect(engine.selectedText(of: tab) == nil)
  }
}
