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

  /// A dialog of a tab the engine no longer lists has nobody to show it; answering it false keeps the page's call from
  /// hanging (#471).
  @Test func aDialogOfATabTheEngineDoesNotListIsAnsweredFalseAndNotReported() throws {
    let (engine, tab, handle) = try makeTab()
    let recorder = EventRecorder(engine)
    handle.owner?.remove(handle, reason: .page)
    facade.flush()
    let before = recorder.events(for: tab)

    let dialog = handle.raiseDialog(.prompt, message: "Late", defaultText: "x")
    facade.flush()

    #expect(dialog.answer?.accepted == false && dialog.answer?.userInput == nil, "the page's call returned")
    #expect(dialog.isEnded)
    #expect(recorder.events(for: tab) == before, "nothing reported")
    #expect(engine.pendingDialogs.isEmpty)
  }
  // MARK: Several instances over one facade (#882)

  /// Every instance sees every batch. A dialog of a tab another live instance lists is that instance's: an instance
  /// made earlier (the main one, before the contract runner's or the import checker's) neither answers nor reports it.
  @Test func aDialogOfAnotherInstancesTabIsLeftToThatInstance() throws {
    facade.holdsBatches = true
    let first = ChromiumEngine(facade: facade)
    _ = first.createWindow(host: StubWindowHost())
    let second = ChromiumEngine(facade: facade)
    let tab = second.createTab(url: page, in: second.createWindow(host: StubWindowHost()))
    facade.flush()
    let handle = try #require(second.handle(of: tab) as? ScriptedTab)
    let firstRecorder = EventRecorder(first)
    let recorder = EventRecorder(second)

    let dialog = handle.raiseDialog(.confirm, message: "Sure?")
    facade.flush()

    #expect(dialog.answer == nil && !dialog.isEnded, "the first instance did not answer it")
    #expect(first.pendingDialogs.isEmpty && firstRecorder.events.isEmpty)
    guard case .dialogRequested(let request)? = recorder.events(for: tab).first else {
      Issue.record("the owner was not told: \(recorder.events(for: tab))")
      return
    }
    second.respond(to: request.id, accepted: true, userInput: nil)
    #expect(dialog.answer?.accepted == true, "the owner's answer reached the page")
  }

  /// A tab this instance closed (its handle retired) has nobody to show a dialog raised just before the close; the
  /// dialog is not reported, here or by another instance.
  @Test func aDialogOfARetiredTabIsNotReported() throws {
    let (engine, tab, handle) = try makeTab()
    let other = ChromiumEngine(facade: facade)
    _ = other.createWindow(host: StubWindowHost())
    facade.flush()
    let recorder = EventRecorder(engine)
    let otherRecorder = EventRecorder(other)

    let dialog = handle.raiseDialog(.confirm, message: "Leaving?")
    engine.closeTab(tab)                      // answered closed: the handle is retired until the facade's TabClosed
    facade.flush()

    #expect(dialog.isEnded && dialog.answer?.accepted != true)
    #expect(recorder.events(for: tab) == [.tabClosed(tab, reason: .client)])
    #expect(engine.pendingDialogs.isEmpty && other.pendingDialogs.isEmpty && otherRecorder.events.isEmpty)
  }

  /// The New Tab page a Dock reopen's window keeps unlisted (#299) is this instance's own tab: a dialog there has
  /// nobody to show it and is answered false at once, even with another instance live.
  @Test func aDialogOfTheKeptNewTabPageIsAnsweredFalse() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    engine.windowHostProvider = { _ in StubWindowHost() }
    facade.hostProvider = { engine.host(for: $0) }
    let other = ChromiumEngine(facade: facade)
    _ = other.createWindow(host: StubWindowHost())
    let (_, newTabPage) = try #require(facade.dockReopen())
    facade.flush()
    #expect(engine.tabIDs.isEmpty, "kept back")

    let dialog = newTabPage.raiseDialog(.prompt, message: "Name?", defaultText: "x")
    facade.flush()

    #expect(dialog.answer?.accepted == false && dialog.answer?.userInput == nil, "the page's call returned")
    #expect(engine.pendingDialogs.isEmpty && other.pendingDialogs.isEmpty)
  }

  /// A window whose instance is gone (a runner dropped it before its window closed) has nobody to show a dialog: a live
  /// instance answers it false so the page's call returns.
  @Test func aDialogInAWindowWhoseInstanceIsGoneIsAnsweredFalse() throws {
    facade.holdsBatches = true
    let survivor = ChromiumEngine(facade: facade)
    _ = survivor.createWindow(host: StubWindowHost())
    var gone: ChromiumEngine? = ChromiumEngine(facade: facade)
    weak var released = gone
    let handle = try #require(gone.flatMap { engine in
      engine.handle(of: engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost())))
    } as? ScriptedTab)
    facade.flush()
    gone = nil
    #expect(released == nil, "the instance is gone; its window is still open")
    #expect(handle.browser != nil)

    let dialog = handle.raiseDialog(.alert, message: "Hello")
    facade.flush()

    #expect(dialog.answer?.accepted == false, "the page's call returned")
    #expect(survivor.pendingDialogs.isEmpty)
  }

  // MARK: Leave-site dialogs (#585)

  private func makeHeldTab() throws -> (ChromiumEngine, TabID, ScriptedTab, EventRecorder) {
    facade.reportsLeaveSiteDialogs = true
    let (engine, tab, handle) = try makeTab()
    handle.finishLoad()
    handle.wouldHoldClose = true
    facade.flush()
    return (engine, tab, handle, EventRecorder(engine))
  }

  private func leaveSiteRequest(_ recorder: EventRecorder, _ tab: TabID) -> JavaScriptDialog? {
    for case .dialogRequested(let dialog) in recorder.events(for: tab) where dialog.kind == .beforeUnload {
      return dialog
    }
    return nil
  }

  /// A held close's leave-site dialog reaches the shell as `.beforeUnload` with Chromium's strings, never as an
  /// alert (whose OK and Escape would both answer Leave).
  @Test func aLeaveSiteDialogIsReportedAsBeforeUnloadWithTheEnginesStrings() throws {
    let (engine, tab, _, recorder) = try makeHeldTab()
    engine.closeTab(tab)
    facade.flush()

    let dialog = try #require(leaveSiteRequest(recorder, tab), "\(recorder.events(for: tab))")
    #expect(dialog.title == "Leave site?" && dialog.message == "Changes you made may not be saved.")
    #expect(dialog.acceptTitle == "Leave" && dialog.cancelTitle == nil, "the shell draws its own Stay (#584)")
    #expect(dialog.defaultPromptText == nil)
    #expect(engine.snapshot(of: tab)?.isClosing == true)
  }

  /// Leave lets the held close go on: `.dialogEnded`, then `.tabClosed(reason: .client)` (contract rules 16, 19).
  @Test func leaveEndsTheDialogBeforeTheTabCloses() throws {
    let (engine, tab, _, recorder) = try makeHeldTab()
    engine.closeTab(tab)
    facade.flush()
    let dialog = try #require(leaveSiteRequest(recorder, tab))

    engine.respond(to: dialog.id, accepted: true, userInput: nil)
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.dialogEnded(tab, dialog.id), .tabClosed(tab, reason: .client)])
    #expect(engine.snapshot(of: tab) == nil && engine.pendingDialogs.isEmpty)
  }

  /// Stay cancels the held close: `.dialogEnded`, then `.closeCancelled`, and the tab stays open.
  @Test func stayEndsTheDialogBeforeTheCloseIsCancelled() throws {
    let (engine, tab, _, recorder) = try makeHeldTab()
    engine.closeTab(tab)
    facade.flush()
    let dialog = try #require(leaveSiteRequest(recorder, tab))

    engine.respond(to: dialog.id, accepted: false, userInput: nil)
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.dialogEnded(tab, dialog.id), .closeCancelled(tab)])
    #expect(engine.snapshot(of: tab)?.isClosing == false && engine.tabIDs.contains(tab))
  }

  /// The engine can cancel the close before it reports the dialog's end (a cancelled dialog runs the page's callback
  /// before the queue closes it). The shell still sees the end first, and once.
  @Test func aCancelledCloseEndsItsLeaveSiteDialogFirst() throws {
    let (engine, tab, handle, recorder) = try makeHeldTab()
    engine.closeTab(tab)
    facade.flush()
    let dialog = try #require(leaveSiteRequest(recorder, tab))

    handle.isClosing = false
    facade.record(ScriptedEvent(.closeCancelled, tab: handle, browser: handle.owner))
    handle.endLeaveSiteDialog()
    facade.flush()

    let tail = Array(recorder.events(for: tab).suffix(2))
    #expect(tail == [.dialogEnded(tab, dialog.id), .closeCancelled(tab)])
    let ended = recorder.events(for: tab).filter { if case .dialogEnded = $0 { true } else { false } }
    #expect(ended.count == 1)
  }

  /// A window close held by two tabs prompts one at a time on the shown tab: the next tab is activated and prompted
  /// only after Leave.
  @Test func aHeldWindowClosePromptsOneTabAtATimeOnTheShownTab() throws {
    facade.reportsLeaveSiteDialogs = true
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let window = engine.createWindow(host: StubWindowHost())
    let first = engine.createTab(url: page, in: window)
    let second = engine.createTab(url: page, in: window)
    facade.flush()
    for id in [first, second] {
      let handle = try #require(engine.handle(of: id) as? ScriptedTab)
      handle.finishLoad()
      handle.wouldHoldClose = true
    }
    engine.activateTab(first)
    facade.flush()
    let recorder = EventRecorder(engine)

    engine.closeWindow(window)
    facade.flush()
    let firstDialog = try #require(leaveSiteRequest(recorder, first))
    #expect(leaveSiteRequest(recorder, second) == nil, "one prompt at a time")

    engine.respond(to: firstDialog.id, accepted: true, userInput: nil)
    facade.flush()
    let secondDialog = try #require(leaveSiteRequest(recorder, second), "the next one after Leave")
    let events = recorder.events
    let activated = try #require(events.firstIndex(of: .activeTabChanged(second)))
    let requested = try #require(events.firstIndex(of: .dialogRequested(secondDialog)))
    #expect(activated < requested, "the tab is shown before its prompt")

    engine.respond(to: secondDialog.id, accepted: false, userInput: nil)
    facade.flush()
    #expect(recorder.events(for: second).suffix(2) == [.dialogEnded(second, secondDialog.id), .closeCancelled(second)])
    #expect(engine.windowIDs.contains(window) && engine.tabIDs == [first, second])
  }

  /// #897 review: when nobody can show a leave-site dialog, declining it would be Stay, and the window could never
  /// close. It is answered Leave.
  @Test func aLeaveSiteDialogNobodyShowsIsAnsweredLeave() throws {
    facade.holdsBatches = true
    let survivor = ChromiumEngine(facade: facade)
    _ = survivor.createWindow(host: StubWindowHost())
    var gone: ChromiumEngine? = ChromiumEngine(facade: facade)
    let handle = try #require(gone.flatMap { engine in
      engine.handle(of: engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost())))
    } as? ScriptedTab)
    facade.flush()
    gone = nil

    let dialog = handle.raiseLeaveSiteDialog()
    facade.flush()

    #expect(dialog.answer?.accepted == true, "Leave, so the close goes on")
    #expect(survivor.pendingDialogs.isEmpty)
  }

  /// #897 review: a tab that moved from instance A's window to instance B's is B's. B reports its dialog; A neither
  /// reports nor answers it.
  @Test func aDialogOfATabMovedToAnotherInstancesWindowIsThatInstances() throws {
    facade.holdsBatches = true
    let first = ChromiumEngine(facade: facade)
    let tab = first.createTab(url: page, in: first.createWindow(host: StubWindowHost()))
    let second = ChromiumEngine(facade: facade)
    let target = second.createWindow(host: StubWindowHost())
    facade.flush()
    let handle = try #require(first.handle(of: tab) as? ScriptedTab)
    let browser = try #require(facade.browserList.last)
    handle.move(to: browser)
    facade.flush()
    #expect(!first.tabIDs.contains(tab), "gone from the first instance")
    let moved = try #require(second.tabIDs.first)
    #expect(second.snapshot(of: moved)?.window == target)
    let firstRecorder = EventRecorder(first)
    let recorder = EventRecorder(second)

    let dialog = handle.raiseDialog(.confirm, message: "Sure?")
    facade.flush()

    #expect(dialog.answer == nil && !dialog.isEnded, "the first instance did not answer it")
    #expect(first.pendingDialogs.isEmpty && firstRecorder.events.isEmpty)
    guard case .dialogRequested(let request)? = recorder.events(for: moved).first else {
      Issue.record("the new owner was not told: \(recorder.events(for: moved))")
      return
    }
    second.respond(to: request.id, accepted: true, userInput: nil)
    #expect(dialog.answer?.accepted == true)
  }
}
