import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// The leave-site prompt as a reported dialog (#584): a held close raises a `.beforeUnload` dialog, and the shell's
/// answer through `respond(to:)` is the user's Leave (the close goes on) or Stay (the close is cancelled). Each request
/// ends with one `.dialogEnded`, before the `.tabClosed` or `.closeCancelled` the answer brings.
@MainActor
struct LeaveSiteDialogTests {
  private let page = URL(string: "arkt-test://page/Draft")!

  private func make() -> (InMemoryEngine, EngineWindowID, TabID, EventRecorder) {
    let engine = InMemoryEngine()
    engine.reportsLeaveSiteDialogs = true
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: window)
    engine.activateTab(tab)
    engine.holdClose(tab)
    return (engine, window, tab, EventRecorder(engine))
  }

  private func requested(_ recorder: EventRecorder, _ tab: TabID) -> [JavaScriptDialog] {
    recorder.events(for: tab).compactMap { if case .dialogRequested(let dialog) = $0 { dialog } else { nil } }
  }

  @Test func aHeldCloseRaisesALeaveSiteDialogWithTheEnginesStrings() throws {
    let (engine, _, tab, recorder) = make()
    engine.closeTab(tab)
    let dialog = try #require(requested(recorder, tab).first)
    #expect(dialog.kind == .beforeUnload)
    #expect(dialog.tab == tab)
    #expect(dialog.title == "Leave site?")
    #expect(dialog.message == "Changes you made may not be saved.")
    #expect(dialog.acceptTitle == "Leave")
    #expect(dialog.cancelTitle == "Stay")
    #expect(dialog.defaultPromptText == nil)
    #expect(engine.snapshot(of: tab)?.isClosing == true)
  }

  @Test func stayCancelsTheCloseAfterEndingTheDialog() throws {
    let (engine, _, tab, recorder) = make()
    engine.closeTab(tab)
    let dialog = try #require(requested(recorder, tab).first)
    engine.respond(to: dialog.id, accepted: false, userInput: nil)

    #expect(Array(recorder.events(for: tab).suffix(2)) == [.dialogEnded(tab, dialog.id), .closeCancelled(tab)])
    #expect(engine.snapshot(of: tab)?.isClosing == false)
    #expect(engine.tabIDs.contains(tab))
    #expect(engine.dialogAnswers.map(\.accepted) == [false])
  }

  @Test func leaveClosesTheTabAndTabClosedIsLast() throws {
    let (engine, _, tab, recorder) = make()
    engine.closeTab(tab)
    let dialog = try #require(requested(recorder, tab).first)
    engine.respond(to: dialog.id, accepted: true, userInput: nil)
    engine.respond(to: dialog.id, accepted: false, userInput: nil)   // a late second answer does nothing

    #expect(Array(recorder.events(for: tab).suffix(2)) == [.dialogEnded(tab, dialog.id),
                                                           .tabClosed(tab, reason: .client)])
    #expect(engine.snapshot(of: tab) == nil)
    #expect(engine.dialogAnswers.map(\.accepted) == [true])
  }

  @Test func theTestDriversAnswerEndsTheReportedDialogToo() throws {
    let (engine, _, tab, recorder) = make()
    engine.closeTab(tab)
    let dialog = try #require(requested(recorder, tab).first)
    #expect(engine.answerDialog(tab, accept: false))
    #expect(Array(recorder.events(for: tab).suffix(2)) == [.dialogEnded(tab, dialog.id), .closeCancelled(tab)])
    engine.respond(to: dialog.id, accepted: true, userInput: nil)    // already ended
    #expect(engine.tabIDs.contains(tab))
  }

  @Test func aHeldWindowClosePromptsOneTabAtATimeShownTabFirst() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    engine.holdClose(other)
    engine.closeWindow(window)

    let first = try #require(requested(recorder, tab).first, "the shown tab is prompted first")
    #expect(requested(recorder, other).isEmpty, "one prompt at a time")
    #expect(engine.snapshot(of: other)?.isClosing == true)
    #expect(engine.activeTab(in: window) == tab)

    engine.respond(to: first.id, accepted: true, userInput: nil)        // Leave on the first

    let second = try #require(requested(recorder, other).first, "the next held tab is prompted after Leave")
    #expect(engine.activeTab(in: window) == other, "on the tab it activated first")
    let events = recorder.events(for: other)
    let activated = try #require(events.firstIndex(of: .activeTabChanged(other)))
    let raised = try #require(events.firstIndex(of: .dialogRequested(second)))
    #expect(activated < raised, "activated before its prompt")
    #expect(engine.windowIDs.contains(window), "the window waits on the second prompt")

    engine.respond(to: second.id, accepted: true, userInput: nil)
    #expect(!engine.windowIDs.contains(window))
    #expect(recorder.windowEvents.last == .windowClosed(window, reason: .userClose))
  }

  @Test func stayOnTheSecondPromptKeepsTheWindowAndEveryTab() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    engine.holdClose(other)
    engine.closeWindow(window)
    engine.respond(to: try #require(requested(recorder, tab).first).id, accepted: true, userInput: nil)
    let second = try #require(requested(recorder, other).first)

    engine.respond(to: second.id, accepted: false, userInput: nil)     // Stay

    #expect(Array(recorder.events(for: other).suffix(2)) == [.dialogEnded(other, second.id), .closeCancelled(other)])
    #expect(recorder.events(for: tab).last == .closeCancelled(tab))
    #expect(engine.windowIDs.contains(window))
    #expect(engine.tabIDs.contains(tab) && engine.tabIDs.contains(other))
    #expect(!recorder.windowEvents.contains { if case .windowClosed = $0 { true } else { false } })
  }

  @Test func aHeldBackgroundTabIsActivatedBeforeItsWindowClosePrompt() throws {
    let (engine, window, tab, recorder) = make()
    let shown = engine.createTab(url: URL(string: "arkt-test://page/Shown")!, in: window)
    engine.activateTab(shown)                                          // the held tab is in the background
    engine.closeWindow(window)
    #expect(engine.activeTab(in: window) == tab)
    #expect(requested(recorder, tab).count == 1)
  }

  @Test func stayDuringAQuitCancelsTheQuitsWindowClose() throws {
    let (engine, window, tab, recorder) = make()
    engine.engineCloseWindow(window, reason: .appQuit)
    let dialog = try #require(requested(recorder, tab).first)
    engine.respond(to: dialog.id, accepted: false, userInput: nil)

    #expect(recorder.events(for: tab).last == .closeCancelled(tab))
    #expect(engine.windowIDs.contains(window))

    engine.engineCloseWindow(window, reason: .appQuit)              // quit again, and leave this time
    let again = try #require(requested(recorder, tab).last)
    #expect(again.id != dialog.id)
    engine.respond(to: again.id, accepted: true, userInput: nil)
    #expect(!engine.windowIDs.contains(window))
    #expect(recorder.windowEvents.last == .windowClosed(window, reason: .appQuit))
  }

  @Test func aLeaveSitePromptOfAHiddenTabStaysPending() throws {
    let (engine, window, tab, recorder) = make()
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    engine.closeTab(tab)
    engine.activateTab(other)                                        // the tab with the prompt goes to the back
    #expect(!recorder.events(for: tab).contains { if case .dialogEnded = $0 { true } else { false } })
    #expect(engine.snapshot(of: tab)?.isClosing == true)
  }

  @Test func withoutReportingTheHeldCloseRaisesNoDialog() {
    let (engine, _, tab, recorder) = make()
    engine.reportsLeaveSiteDialogs = false
    engine.closeTab(tab)
    #expect(requested(recorder, tab).isEmpty)
    #expect(engine.answerDialog(tab, accept: false))
    #expect(recorder.events(for: tab).last == .closeCancelled(tab))
  }
}
