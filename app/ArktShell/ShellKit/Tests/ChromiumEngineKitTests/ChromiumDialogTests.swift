import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// JavaScript dialogs over the facade (#400): the facade's `DialogRequested` becomes `.dialogRequested` with the
/// engine's strings, `respond` reaches the dialog and ends it at once, and the facade's own `DialogEnded` for a dialog
/// the shell already ended is dropped.
@MainActor
struct ChromiumDialogTests {
  let facade = ScriptedFacade()
  private let page = URL(string: "arkt-test://page.test/Dialog")!

  private func makeTab() throws -> (ChromiumEngine, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    return (engine, tab, try #require(engine.handle(of: tab) as? ScriptedTab))
  }

  @Test func aRequestIsReportedWithTheEnginesValues() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)

    handle.raiseDialog(.prompt, message: "Your name?", defaultText: "Ada")
    #expect(recorder.events(for: tab).isEmpty, "delivered with the next batch, not from the call")
    facade.flush()

    guard case .dialogRequested(let dialog)? = recorder.events(for: tab).first else {
      Issue.record("no request: \(recorder.events(for: tab))")
      return
    }
    #expect(dialog.tab == tab && dialog.kind == .prompt && dialog.message == "Your name?")
    #expect(dialog.title == "page.test says" && dialog.defaultPromptText == "Ada")
    #expect(dialog.acceptTitle == "OK" && dialog.cancelTitle == "Cancel")
  }

  @Test func respondReachesTheDialogAndEndsItAtOnce() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let dialog = handle.raiseDialog(.prompt, message: "Name?", defaultText: "")
    facade.flush()
    guard case .dialogRequested(let request)? = recorder.events(for: tab).first else { return }

    engine.respond(to: request.id, accepted: true, userInput: "Grace")

    #expect(dialog.answer?.accepted == true && dialog.answer?.userInput == "Grace")
    #expect(recorder.events(for: tab).last == .dialogEnded(tab, request.id), "before the call returns")
    facade.flush()
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended.count == 1, "the facade's own DialogEnded is dropped: \(ended)")
  }

  @Test func theEnginesEndIsReportedOnceAndAnAnswerAfterItDoesNothing() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let dialog = handle.raiseDialog(.confirm, message: "Sure?")
    facade.flush()
    guard case .dialogRequested(let request)? = recorder.events(for: tab).first else { return }

    handle.navigate(to: URL(string: "arkt-test://page.test/Other")!)
    facade.flush()
    engine.respond(to: request.id, accepted: true, userInput: nil)

    #expect(dialog.answer == nil, "ended before the answer: the page was not answered")
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended == [.dialogEnded(tab, request.id)])
  }

  @Test func anAnswerThatRacesTheEnginesQueuedEndEndsItOnce() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    let dialog = handle.raiseDialog(.confirm, message: "Sure?")
    facade.flush()
    guard case .dialogRequested(let request)? = recorder.events(for: tab).first else { return }

    handle.endJSDialog()                        // the engine ended it; its event is still queued
    engine.respond(to: request.id, accepted: true, userInput: nil)
    facade.flush()

    #expect(dialog.answer == nil)
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended == [.dialogEnded(tab, request.id)])
  }

  @Test func closingTheTabEndsTheDialogBeforeTabClosedEvenWhenTheFacadeReportsItAfter() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.raiseDialog(.alert, message: "Bye")
    facade.flush()
    guard case .dialogRequested(let request)? = recorder.events(for: tab).first else { return }

    // The page closes itself: the facade reports TabClosed, then the manager's DialogEnded.
    handle.owner?.remove(handle, reason: .page)
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.dialogEnded(tab, request.id), .tabClosed(tab, reason: .page)])
  }

  @Test func aLaterDialogReplacesTheEarlierOne() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.raiseDialog(.alert, message: "One")
    handle.raiseDialog(.alert, message: "Two")
    facade.flush()
    let kinds = recorder.events(for: tab).compactMap { event -> String? in
      switch event {
      case .dialogRequested(let dialog): "requested \(dialog.message)"
      case .dialogEnded: "ended"
      default: nil
      }
    }
    #expect(kinds == ["requested One", "ended", "requested Two"])
  }
}
