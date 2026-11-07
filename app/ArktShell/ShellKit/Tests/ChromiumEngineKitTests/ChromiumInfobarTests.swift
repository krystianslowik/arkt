import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Infobars over the facade (#400): the facade's `InfobarsChanged` becomes `.infobarsChanged` with the engine's
/// strings, `act` reaches the infobar's delegate, an infobar keeps its id across lists, and a tab's infobars are
/// reported empty before it closes.
@MainActor
struct ChromiumInfobarTests {
  let facade = ScriptedFacade()
  private let page = URL(string: "arkt-test://page.test/Infobar")!

  private func makeTab() throws -> (ChromiumEngine, EngineWindowID, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    facade.flush()
    return (engine, window, tab, try #require(engine.handle(of: tab) as? ScriptedTab))
  }

  private func lists(_ recorder: EventRecorder, _ tab: TabID) -> [[Infobar]] {
    recorder.events(for: tab).compactMap { if case .infobarsChanged(_, let list) = $0 { list } else { nil } }
  }

  @Test func theListIsReportedWithTheEnginesValues() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let icon = Data("png:icon".utf8)

    handle.addInfobar("\"Page Inspector\" started debugging this browser") {
      $0.kind = .debugger
      $0.okTitle = "Cancel"
      $0.okTooltip = "Stop debugging"
      $0.cancelTitle = nil
      $0.iconPNG = icon
    }
    #expect(recorder.events(for: tab).isEmpty, "delivered with the next batch, not from the call")
    facade.flush()

    let infobar = try #require(lists(recorder, tab).last?.first)
    #expect(infobar.tab == tab && infobar.kind == .debugger)
    #expect(infobar.message == "\"Page Inspector\" started debugging this browser")
    #expect(infobar.ok == InfobarButton(title: "Cancel", tooltip: "Stop debugging", isEnabled: true))
    #expect(infobar.cancel == nil && infobar.isCloseable && infobar.closeLabel == "Close" && infobar.iconPNG == icon)
  }

  @Test func messageLinksKeepTheirSubstitutionIndex() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.addInfobar("Read the notes or the terms.") {
      // Substitution 0 is plain text, 1 and 2 are links.
      $0.messageLinkRanges = [NSValue(range: NSRange(location: NSNotFound, length: 0)),
                              NSValue(range: NSRange(location: 9, length: 9)), NSValue(range: NSRange(location: 22, length: 5))]
      $0.linkTitle = "Learn more"
      $0.linkAccessibilityLabel = "Learn more about this"
      $0.linkBeforeButtons = true
    }
    facade.flush()

    let infobar = try #require(lists(recorder, tab).last?.first)
    #expect(infobar.messageLinks == [InfobarLink(index: 1, range: 9..<18), InfobarLink(index: 2, range: 22..<27)])
    #expect(infobar.linkTitle == "Learn more" && infobar.linkAccessibilityLabel == "Learn more about this")
    #expect(infobar.linkBeforeButtons)
  }

  @Test(arguments: [(InfobarAction.ok, ArktInfobarAction.ok), (.cancel, .cancel), (.close, .close)])
  func anActionReachesTheDelegateAndTheNextListDropsTheInfobar(action: InfobarAction, facadeAction: ArktInfobarAction)
    throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let scripted = handle.addInfobar("Hello")
    facade.flush()
    let infobar = try #require(lists(recorder, tab).last?.first)

    engine.act(on: infobar.id, action: action)
    facade.flush()
    engine.act(on: infobar.id, action: .ok)                  // gone: nothing happens
    facade.flush()

    #expect(scripted.actions.map(\.action) == [facadeAction])
    #expect(lists(recorder, tab).map(\.count) == [1, 0])
  }

  @Test func aLinkReachesTheDelegateWithItsIndexAndKeepsTheInfobar() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let scripted = handle.addInfobar("Hello")
    facade.flush()
    let infobar = try #require(lists(recorder, tab).last?.first)

    engine.act(on: infobar.id, action: .link)
    engine.act(on: infobar.id, action: .messageLink(2))
    facade.flush()

    #expect(scripted.actions.map(\.action) == [.link, .messageLink])
    #expect(scripted.actions.last?.linkIndex == 2)
    #expect(lists(recorder, tab).count == 1)
  }

  @Test func anInfobarKeepsItsIDWhenAnotherOneLeaves() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let first = handle.addInfobar("First")
    handle.addInfobar("Second")
    facade.flush()
    first.remove()
    facade.flush()

    let all = lists(recorder, tab)
    #expect(all.count == 3, "one list per change")
    #expect(all[1].count == 2 && all[2].count == 1)
    #expect(all[2][0].id == all[1][1].id && all[2][0].message == "Second")
    #expect(all[1][0].id == all[0][0].id, "the first keeps its id in the next list")
  }

  @Test func aBatchWithSeveralChangesReportsEachList() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.addInfobar("One")
    handle.addInfobar("Two")
    facade.flush()
    #expect(lists(recorder, tab).map(\.count) == [1, 2])
  }

  @Test func aMovedTabsNewListReplacesTheOldAndTheOldObjectsRefuseActions() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let before = handle.addInfobar("Mine")
    facade.flush()
    let oldID = try #require(lists(recorder, tab).last?.first?.id)

    handle.moveInfobarsToNewPresenter()
    facade.flush()
    let moved = try #require(lists(recorder, tab).last)
    #expect(moved.map(\.message) == ["Mine"] && moved[0].id != oldID)

    engine.act(on: oldID, action: .ok)                      // the old one is gone
    engine.act(on: moved[0].id, action: .close)
    facade.flush()
    #expect(before.actions.isEmpty && handle.infobars.isEmpty)
    #expect(lists(recorder, tab).last == [])
  }

  @Test func hidingTheTabLeavesItsInfobars() throws {
    let (engine, window, tab, handle) = try makeTab()
    let other = engine.createTab(url: page, in: window)
    facade.flush()
    engine.activateTab(tab)
    facade.flush()
    let recorder = EventRecorder(engine)
    handle.addInfobar("Mine")
    facade.flush()
    engine.activateTab(other)
    facade.flush()
    engine.activateTab(tab)
    facade.flush()

    #expect(lists(recorder, tab).count == 1 && lists(recorder, other).isEmpty)
  }

  @Test func closingTheTabEmptiesItsListBeforeTabClosedEvenWhenTheFacadeReportsNothing() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.addInfobar("Mine")
    facade.flush()

    handle.owner?.remove(handle, reason: .page)
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.infobarsChanged(tab, []), .tabClosed(tab, reason: .page)])
  }

  @Test func aTabWithoutInfobarsReportsNoEmptyListWhenItCloses() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.owner?.remove(handle, reason: .page)
    facade.flush()
    #expect(lists(recorder, tab).isEmpty)
  }
}
