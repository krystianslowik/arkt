import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// `EngineClient.moveTab(_:to:)` (#314, Little Arkt's Open in): the tab keeps its id, page, history and view, its
/// events go to the new window, it becomes that window's active tab, and a window left without tabs closes.
@MainActor
struct MoveTabTests {
  private let page = URL(string: "arkt-test://page/Moved")!
  private let earlier = URL(string: "arkt-test://page/Earlier")!

  @Test func moveEndsARunningFind() async throws {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let little = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 3, link: page), in: little)
    let recorder = EventRecorder(engine)
    engine.findInPage(tab, text: "needle", forward: true, matchCase: false)
    engine.findInPage(tab, text: "needle", forward: true, matchCase: false)
    let replies = EngineContract.findReplies(recorder, tab)
    #expect(replies.last?.ordinal == 2)

    engine.moveTab(tab, to: main)
    #expect(EngineContract.findReplies(recorder, tab) == replies)
    engine.findInPage(tab, text: "needle", forward: true, matchCase: false)
    #expect(EngineContract.findReplies(recorder, tab).last?.ordinal == 1)
  }

  @Test func emptyFindTextUsesNoRequestID() {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 1, link: page))
    let recorder = EventRecorder(engine)
    engine.findInPage(tab, text: "", forward: true, matchCase: false)
    engine.findInPage(tab, text: "needle", forward: true, matchCase: false)
    #expect(EngineContract.findReplies(recorder, tab).map(\.requestID) == [0, 1])
  }

  @Test func movedTabKeepsItsIdentityHistoryAndView() throws {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let little = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: earlier, in: little)
    engine.navigate(tab, to: page)
    let view = try #require(engine.contentView(for: tab))

    engine.moveTab(tab, to: main)

    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(snapshot.window == main)
    #expect(snapshot.url == page)
    #expect(engine.history(of: tab)?.back.map(\.url) == [earlier])
    #expect(engine.contentView(for: tab) === view)
    #expect(engine.activeTab(in: main) == tab)
    #expect(snapshot.isActive)
  }

  @Test func emptiedSourceWindowCloses() {
    let engine = InMemoryEngine()
    let recorder = EventRecorder(engine)
    let main = engine.createWindow(host: StubWindowHost())
    let little = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: little)

    engine.moveTab(tab, to: main)

    #expect(!engine.windowIDs.contains(little))
    #expect(recorder.windowEvents.last == .windowClosed(little, reason: .lastTabClosed))
    #expect(engine.tabIDs == [tab])
    #expect(!recorder.events.contains(.tabClosed(tab, reason: .windowClosing)))
  }

  @Test func laterEventsReachTheNewWindowOnly() {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let little = engine.createWindow(host: StubWindowHost())
    let keep = engine.createTab(url: earlier, in: little)
    let tab = engine.createTab(url: page, in: little)
    var inMain: [EngineEvent] = []
    var inLittle: [EngineEvent] = []
    let mainToken = engine.observe(window: main) { inMain.append($0) }
    let littleToken = engine.observe(window: little) { inLittle.append($0) }

    engine.moveTab(tab, to: main)
    engine.setDocumentTitle(tab, "After")

    #expect(inMain.contains(.activeTabChanged(tab)))
    #expect(inMain.contains(.titleChanged(tab, "After")))
    #expect(!inLittle.contains(.titleChanged(tab, "After")))
    #expect(engine.windowIDs.contains(little))
    #expect(engine.snapshot(of: keep)?.window == little)
    _ = (mainToken, littleToken)
  }

  @Test func unknownTargetsAndTheOwnWindowAreNoOps() {
    let engine = InMemoryEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    let before = recorder.log.count

    engine.moveTab(tab, to: window)
    engine.moveTab(tab, to: EngineWindowID())
    engine.moveTab(TabID(), to: window)

    #expect(recorder.log.count == before)
    #expect(engine.snapshot(of: tab)?.window == window)
  }
}
