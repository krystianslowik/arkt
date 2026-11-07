import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Infobars (#400): the engine reports a tab's whole list with the values to show, an action runs the engine's
/// delegate, and the list follows what the engine decides.
@MainActor
struct InfobarTests {
  private let page = URL(string: "arkt-test://page/Infobar")!

  private func make() -> (InMemoryEngine, EngineWindowID, TabID, EventRecorder) {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    engine.activateTab(tab)
    return (engine, window, tab, EventRecorder(engine))
  }

  private func lists(_ recorder: EventRecorder, _ tab: TabID) -> [[Infobar]] {
    recorder.events(for: tab).compactMap { if case .infobarsChanged(_, let list) = $0 { list } else { nil } }
  }

  @Test func raisedInfobarIsReportedWithItsValues() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.raiseInfobar(in: tab, message: "\"Page Inspector\" started debugging this browser",
                                              kind: .debugger))
    let expected = Infobar(id: id, tab: tab, kind: .debugger,
                           message: "\"Page Inspector\" started debugging this browser",
                           ok: InfobarButton(title: "OK"), cancel: InfobarButton(title: "Cancel"), closeLabel: "Close")
    #expect(recorder.events(for: tab) == [.infobarsChanged(tab, [expected])])
    #expect(expected.isCloseable)
  }

  @Test func theListHoldsEveryInfobarInOrder() throws {
    let (engine, _, tab, recorder) = make()
    let first = try #require(engine.raiseInfobar(in: tab, message: "First"))
    let second = try #require(engine.raiseInfobar(in: tab, message: "Second"))
    #expect(lists(recorder, tab).map { $0.map(\.id) } == [[first], [first, second]])
  }

  @Test(arguments: [InfobarAction.ok, .cancel, .close])
  func anActionThatTheDelegateAcceptsRemovesTheInfobarOnce(action: InfobarAction) throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.raiseInfobar(in: tab, message: "Hello"))
    engine.act(on: id, action: action)
    engine.act(on: id, action: .ok)

    #expect(engine.infobarActions.map(\.action) == [action])
    #expect(lists(recorder, tab).map(\.count) == [1, 0])
  }

  @Test func aLinkKeepsTheInfobarLikeADelegateThatReturnsFalse() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.raiseInfobar(in: tab, message: "Hello"))
    engine.act(on: id, action: .link)
    engine.act(on: id, action: .messageLink(1))

    #expect(engine.infobarActions.map(\.action) == [.link, .messageLink(1)])
    #expect(lists(recorder, tab).map(\.count) == [1])
  }

  @Test func theEngineRemovingOneLeavesTheOthersWithTheirIDs() throws {
    let (engine, _, tab, recorder) = make()
    let first = try #require(engine.raiseInfobar(in: tab, message: "First"))
    let second = try #require(engine.raiseInfobar(in: tab, message: "Second"))
    engine.removeInfobar(first)
    #expect(lists(recorder, tab).last?.map(\.id) == [second])
    engine.removeInfobar(first)                              // gone: nothing is reported again
    #expect(lists(recorder, tab).count == 3)
  }

  @Test func switchingTabsKeepsTheInfobarsOfEachTab() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: page, in: window)
    let id = try #require(engine.raiseInfobar(in: tab, message: "Mine"))
    engine.activateTab(other)
    engine.activateTab(tab)

    #expect(lists(recorder, tab).count == 1 && lists(recorder, other).isEmpty)
    engine.act(on: id, action: .ok)
    #expect(lists(recorder, tab).last == [])
  }

  @Test func closingTheTabEmptiesItsListBeforeTabClosed() throws {
    let (engine, _, tab, recorder) = make()
    _ = try #require(engine.raiseInfobar(in: tab, message: "Hello"))
    engine.closeTab(tab, mode: .skipUnloadHandlers)

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.infobarsChanged(tab, []), .tabClosed(tab, reason: .client)])
  }

  @Test func anUnknownOrClosedTabRaisesNothing() {
    let (engine, _, tab, _) = make()
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    #expect(engine.raiseInfobar(in: tab, message: "Late") == nil)
  }
}
