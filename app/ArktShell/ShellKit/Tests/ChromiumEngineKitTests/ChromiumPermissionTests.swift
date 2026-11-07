import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Permission requests over the facade (#400): the facade's `PermissionRequested` becomes `.permissionRequested` with
/// the engine's strings, `respond` reaches the request and ends it at once, the facade's own `PermissionEnded` for a
/// request the shell already ended is dropped, and every path ends a request exactly once.
@MainActor
struct ChromiumPermissionTests {
  let facade = ScriptedFacade()
  private let page = URL(string: "arkt-test://page.test/Permission")!

  private func makeTab() throws -> (ChromiumEngine, EngineWindowID, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    facade.flush()
    return (engine, window, tab, try #require(engine.handle(of: tab) as? ScriptedTab))
  }

  private func requests(_ recorder: EventRecorder, _ tab: TabID) -> [PermissionRequest] {
    recorder.events(for: tab).compactMap { if case .permissionRequested(let request) = $0 { request } else { nil } }
  }

  private func ended(_ recorder: EventRecorder, _ tab: TabID) -> [PermissionRequestID] {
    recorder.events(for: tab).compactMap { if case .permissionEnded(_, let id) = $0 { id } else { nil } }
  }

  @Test func aRequestIsReportedWithTheEnginesValues() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)

    handle.askPermission([.geolocation, .camera], items: ["Know your location", "Use your camera"], oneTime: true)
    #expect(recorder.events(for: tab).isEmpty, "delivered with the next batch, not from the call")
    facade.flush()

    let request = try #require(requests(recorder, tab).first)
    #expect(request.tab == tab && request.origin == "page.test" && request.title == "page.test wants to")
    #expect(request.kinds == [.geolocation, .camera])
    #expect(request.items == ["Know your location", "Use your camera"])
    #expect(request.allowTitle == "Allow while visiting the site" && request.allowThisTimeTitle == "Allow this time")
    #expect(request.blockTitle == "Never allow")
  }

  @Test func aRequestWithoutAOneVisitGrantHasTwoAnswers() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.askPermission([.notifications], items: ["Show notifications"], oneTime: false)
    facade.flush()
    let request = try #require(requests(recorder, tab).first)
    #expect(request.kinds == [.notifications] && request.allowThisTimeTitle == nil)
    #expect(request.allowTitle == "Allow" && request.blockTitle == "Block")
  }

  @Test(arguments: [(PermissionChoice.allow, ArktPermissionChoice.allow), (.allowThisTime, .allowThisTime),
                    (.block, .block), (.dismiss, .dismiss)])
  func respondReachesTheRequestAndEndsItAtOnce(choice: PermissionChoice, facadeChoice: ArktPermissionChoice) throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let ask = try #require(handle.askPermission([.microphone], items: ["Use your microphone"], oneTime: true))
    facade.flush()
    let request = try #require(requests(recorder, tab).first)

    engine.respond(toPermission: request.id, choice: choice)
    engine.respond(toPermission: request.id, choice: .block)          // answered: nothing happens

    #expect(ask.choice == facadeChoice)
    #expect(recorder.events(for: tab).last == .permissionEnded(tab, request.id), "before the call returns")
    facade.flush()
    #expect(ended(recorder, tab) == [request.id], "the facade's own PermissionEnded is dropped")
  }

  @Test func theEnginesEndIsReportedOnceAndAnAnswerAfterItDoesNothing() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let ask = try #require(handle.askPermission([.geolocation], items: ["Know your location"], oneTime: true))
    facade.flush()
    let request = try #require(requests(recorder, tab).first)

    handle.navigate(to: URL(string: "arkt-test://page.test/Other")!)         // the site's ask is dropped
    facade.flush()
    engine.respond(toPermission: request.id, choice: .allow)

    #expect(ask.choice == nil, "ended before the answer: the site was not answered")
    #expect(ended(recorder, tab) == [request.id])
  }

  @Test func anAnswerThatRacesTheEnginesQueuedEndEndsItOnce() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let ask = try #require(handle.askPermission([.geolocation], items: ["Know your location"], oneTime: true))
    facade.flush()
    let request = try #require(requests(recorder, tab).first)

    handle.endPermission()                      // the engine ended it; its event is still queued
    engine.respond(toPermission: request.id, choice: .allow)
    facade.flush()

    #expect(ask.choice == nil)
    #expect(ended(recorder, tab) == [request.id])
  }

  @Test func closingTheTabEndsTheRequestBeforeTabClosedEvenWhenTheFacadeReportsItAfter() throws {
    let (engine, _, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.askPermission([.notifications], items: ["Show notifications"], oneTime: false)
    facade.flush()
    let request = try #require(requests(recorder, tab).first)

    handle.owner?.remove(handle, reason: .page)
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.permissionEnded(tab, request.id), .tabClosed(tab, reason: .page)])
  }

  @Test func aHiddenTabEndsTheRequestAndAsksAgainWhenShown() throws {
    let (engine, window, tab, handle) = try makeTab()
    let other = engine.createTab(url: URL(string: "arkt-test://page.test/Other")!, in: window)
    facade.flush()
    engine.activateTab(tab)
    facade.flush()
    let recorder = EventRecorder(engine)
    let ask = try #require(handle.askPermission([.geolocation], items: ["Know your location"], oneTime: true))
    facade.flush()
    let first = try #require(requests(recorder, tab).first)

    engine.activateTab(other)
    facade.flush()
    #expect(ended(recorder, tab) == [first.id])
    #expect(ask.choice == nil, "hiding is not an answer")

    engine.activateTab(tab)
    facade.flush()
    let again = requests(recorder, tab)
    #expect(again.count == 2 && again[1].id != first.id && again[1].items == first.items,
            "a new request for the same ask: \(recorder.events(for: tab))")
    engine.respond(toPermission: first.id, choice: .allow)                // the old id is dead
    #expect(ended(recorder, tab) == [first.id])
  }
}
