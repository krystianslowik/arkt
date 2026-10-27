import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Permission requests (#400): the engine reports a request with the values to show, one answer from the shell (or the
/// engine's own end) closes it, and every request is followed by exactly one `.permissionEnded`.
@MainActor
struct PermissionRequestTests {
  private let page = URL(string: "arkt-test://page/Permission")!

  private func make() -> (InMemoryEngine, EngineWindowID, TabID, EventRecorder) {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    engine.activateTab(tab)
    return (engine, window, tab, EventRecorder(engine))
  }

  private func requests(_ recorder: EventRecorder, _ tab: TabID) -> [PermissionRequest] {
    recorder.events(for: tab).compactMap { if case .permissionRequested(let request) = $0 { request } else { nil } }
  }

  private func ended(_ recorder: EventRecorder, _ tab: TabID) -> [PermissionRequestID] {
    recorder.events(for: tab).compactMap { if case .permissionEnded(_, let id) = $0 { id } else { nil } }
  }

  @Test func askedPermissionIsReportedWithItsValues() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.askPermission(in: tab, kinds: [.camera, .microphone]))
    let expected = PermissionRequest(
      id: id, tab: tab, origin: "page", kinds: [.camera, .microphone], title: "page wants to",
      items: ["Use your camera", "Use your microphone"], allowTitle: "Allow while visiting the site",
      allowThisTimeTitle: "Allow this time", blockTitle: "Never allow")
    #expect(recorder.events(for: tab) == [.permissionRequested(expected)])
  }

  @Test func notificationsHaveNoOneVisitAnswer() throws {
    let (engine, _, tab, recorder) = make()
    _ = try #require(engine.askPermission(in: tab, kinds: [.notifications]))
    let request = try #require(requests(recorder, tab).first)
    #expect(request.allowThisTimeTitle == nil && request.allowTitle == "Allow" && request.blockTitle == "Block")
  }

  @Test(arguments: [PermissionChoice.allow, .allowThisTime, .block, .dismiss])
  func answerReachesTheSiteAndEndsTheRequestOnce(choice: PermissionChoice) throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.askPermission(in: tab, kinds: [.geolocation]))
    engine.respond(toPermission: id, choice: choice)
    engine.respond(toPermission: id, choice: .block)

    #expect(engine.permissionAnswers.map(\.choice) == [choice])
    #expect(ended(recorder, tab) == [id])
  }

  @Test func aLaterAskEndsTheEarlierOneFirst() throws {
    let (engine, _, tab, recorder) = make()
    let first = try #require(engine.askPermission(in: tab, kinds: [.geolocation]))
    let second = try #require(engine.askPermission(in: tab, kinds: [.camera]))
    let order = recorder.events(for: tab).map { event -> String in
      switch event {
      case .permissionRequested(let request): "requested \(request.items[0])"
      case .permissionEnded(_, let id): id == first ? "ended first" : "ended other"
      default: "other"
      }
    }
    #expect(order == ["requested Know your location", "ended first", "requested Use your camera"])
    engine.respond(toPermission: first, choice: .allow)         // ended: nothing happens
    #expect(engine.permissionAnswers.isEmpty)
    engine.respond(toPermission: second, choice: .block)
    #expect(engine.permissionAnswers.map(\.id) == [second])
  }

  @Test func navigationEndsTheRequestWithoutAnAnswerAndDropsTheAsk() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.askPermission(in: tab, kinds: [.geolocation]))
    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)
    engine.respond(toPermission: id, choice: .allow)
    #expect(ended(recorder, tab) == [id])
    #expect(engine.permissionAnswers.isEmpty)
  }

  @Test func closingTheTabEndsTheRequestBeforeTheTabClosed() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.askPermission(in: tab, kinds: [.notifications]))
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    #expect(Array(recorder.events(for: tab).suffix(2)) == [.permissionEnded(tab, id), .tabClosed(tab, reason: .client)])
  }

  @Test func aSiteWithdrawingItsAskEndsTheRequest() throws {
    let (engine, _, tab, recorder) = make()
    let id = try #require(engine.askPermission(in: tab, kinds: [.geolocation]))
    engine.withdrawPermission(in: tab)
    engine.withdrawPermission(in: tab)
    #expect(ended(recorder, tab) == [id])
  }

  @Test func hidingTheTabEndsTheRequestAndShowingItAsksAgain() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    let first = try #require(engine.askPermission(in: tab, kinds: [.geolocation]))

    engine.activateTab(other)
    #expect(ended(recorder, tab) == [first])
    engine.activateTab(tab)
    let asked = requests(recorder, tab)
    #expect(asked.count == 2 && asked[1].id != first && asked[1].items == asked[0].items)
    engine.respond(toPermission: first, choice: .allow)
    #expect(engine.permissionAnswers.isEmpty, "the old id is dead")
    engine.respond(toPermission: asked[1].id, choice: .allow)
    #expect(engine.permissionAnswers.map(\.id) == [asked[1].id])
  }

  @Test func anAskOfAHiddenTabShowsWhenTheTabIsShown() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    #expect(engine.askPermission(in: other, kinds: [.geolocation]) == nil, "not shown, so no prompt yet")
    #expect(requests(recorder, other).isEmpty)
    engine.activateTab(other)
    #expect(requests(recorder, other).count == 1)
    _ = tab
  }

  @Test func unknownOrClosedTabAsksNothing() {
    let (engine, _, tab, recorder) = make()
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    #expect(engine.askPermission(in: tab, kinds: [.camera]) == nil)
    #expect(engine.askPermission(in: TabID(), kinds: [.camera]) == nil)
    #expect(!recorder.events.contains { if case .permissionRequested = $0 { true } else { false } })
  }

  @Test func permissionEventsCarryTheirTabID() {
    let tab = TabID()
    let id = PermissionRequestID()
    let request = PermissionRequest(id: id, tab: tab, origin: "o", kinds: [.other], title: "t", items: ["i"],
                                    allowTitle: "a", allowThisTimeTitle: nil, blockTitle: "b")
    #expect(EngineEvent.permissionRequested(request).tabID == tab)
    #expect(EngineEvent.permissionEnded(tab, id).tabID == tab)
  }
}
