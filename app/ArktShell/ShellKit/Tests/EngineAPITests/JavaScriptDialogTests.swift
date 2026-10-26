import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// JavaScript alert, confirm and prompt (#400): the engine reports a request with the values to show, one answer from
/// the shell (or the engine's own end) closes it, and every request is followed by exactly one `.dialogEnded`.
@MainActor
struct JavaScriptDialogTests {
  private let page = URL(string: "arkt-test://page/Dialog")!

  private func make() -> (InMemoryEngine, TabID, EventRecorder) {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    return (engine, tab, EventRecorder(engine))
  }

  @Test func raisedDialogIsReportedWithItsValues() throws {
    let (engine, tab, recorder) = make()
    let id = try #require(engine.raiseDialog(in: tab, kind: .prompt, message: "Your name?", defaultPromptText: "Ada"))
    let expected = JavaScriptDialog(id: id, tab: tab, kind: .prompt, title: "page says", message: "Your name?",
                                    defaultPromptText: "Ada", acceptTitle: "OK", cancelTitle: "Cancel")
    #expect(recorder.events(for: tab) == [.dialogRequested(expected)])
  }

  @Test func alertHasNoCancelButtonAndNoDefaultText() throws {
    let (engine, tab, recorder) = make()
    _ = try #require(engine.raiseDialog(in: tab, kind: .alert, message: "Saved"))
    guard case .dialogRequested(let dialog)? = recorder.events(for: tab).first else {
      Issue.record("no request")
      return
    }
    #expect(dialog.cancelTitle == nil)
    #expect(dialog.defaultPromptText == nil)
  }

  @Test func answerReachesThePageAndEndsTheDialogOnce() throws {
    let (engine, tab, recorder) = make()
    let id = try #require(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: ""))
    engine.respond(to: id, accepted: true, userInput: "Grace")
    engine.respond(to: id, accepted: false, userInput: nil)

    #expect(engine.dialogAnswers.count == 1)
    #expect(engine.dialogAnswers.first?.accepted == true)
    #expect(engine.dialogAnswers.first?.userInput == "Grace")
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended == [.dialogEnded(tab, id)])
  }

  @Test func aLaterDialogEndsTheEarlierOneFirst() throws {
    let (engine, tab, recorder) = make()
    let first = try #require(engine.raiseDialog(in: tab, kind: .confirm, message: "One?"))
    let second = try #require(engine.raiseDialog(in: tab, kind: .confirm, message: "Two?"))
    let kinds = recorder.events(for: tab).map { event -> String in
      switch event {
      case .dialogRequested(let dialog): "requested \(dialog.message)"
      case .dialogEnded(_, let id): id == first ? "ended first" : "ended other"
      default: "other"
      }
    }
    #expect(kinds == ["requested One?", "ended first", "requested Two?"])
    engine.respond(to: first, accepted: true, userInput: nil)   // already ended: nothing happens
    #expect(engine.dialogAnswers.isEmpty)
    engine.respond(to: second, accepted: false, userInput: nil)
    #expect(engine.dialogAnswers.map(\.id) == [second])
  }

  @Test func navigationEndsThePendingDialogWithoutAnAnswer() throws {
    let (engine, tab, recorder) = make()
    let id = try #require(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended == [.dialogEnded(tab, id)])
    engine.respond(to: id, accepted: true, userInput: nil)
    #expect(engine.dialogAnswers.isEmpty)
  }

  @Test func closingTheTabEndsTheDialogBeforeTheTabClosed() throws {
    let (engine, tab, recorder) = make()
    let id = try #require(engine.raiseDialog(in: tab, kind: .alert, message: "Bye"))
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    let tail = recorder.events(for: tab).suffix(2)
    #expect(Array(tail) == [.dialogEnded(tab, id), .tabClosed(tab, reason: .client)])
  }

  @Test func unknownOrClosedTabRaisesNothing() {
    let (engine, tab, recorder) = make()
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    #expect(engine.raiseDialog(in: tab, kind: .alert, message: "x") == nil)
    #expect(engine.raiseDialog(in: TabID(), kind: .alert, message: "x") == nil)
    #expect(!recorder.events.contains { if case .dialogRequested = $0 { true } else { false } })
  }

  @Test func dialogEventsReachTheTabsWindowOnly() throws {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let other = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: main)
    var inMain: [EngineEvent] = []
    var inOther: [EngineEvent] = []
    let first = engine.observe(window: main) { inMain.append($0) }
    let second = engine.observe(window: other) { inOther.append($0) }
    defer { first.cancel(); second.cancel() }

    let id = try #require(engine.raiseDialog(in: tab, kind: .alert, message: "Hi"))
    engine.respond(to: id, accepted: true, userInput: nil)

    #expect(inMain.count == 2)
    #expect(inOther.isEmpty)
  }

  @Test func dialogEventsCarryTheirTabID() {
    let tab = TabID()
    let id = DialogID()
    let dialog = JavaScriptDialog(id: id, tab: tab, kind: .alert, title: "t", message: "m", defaultPromptText: nil,
                                  acceptTitle: "OK", cancelTitle: nil)
    #expect(EngineEvent.dialogRequested(dialog).tabID == tab)
    #expect(EngineEvent.dialogEnded(tab, id).tabID == tab)
  }
}
