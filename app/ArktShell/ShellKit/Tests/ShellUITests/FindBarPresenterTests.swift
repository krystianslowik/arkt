import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ShellUI

/// The find bar's state and its engine calls (#134), against `InMemoryEngine`'s find results. Time is injected: the
/// debounce sleeps on a sleeper the test resumes, so no test waits on a real clock.
@MainActor
struct FindBarPresenterTests {
  private static let link = URL(string: "https://example.com/link")!

  @MainActor
  private final class Rig {
    let engine = InMemoryEngine()
    let sleeper = ParkingSleeper()
    let presenter: FindBarPresenter
    let recorder: EventRecorder
    let tab: TabID
    private var observation: EngineObservation?
    var changes = 0
    var focusRequests = 0
    var closes = 0
    var noMatchCues = 0
    var announcements: [String] = []

    init(occurrences: Int = 12) {
      let sleeper = sleeper
      presenter = FindBarPresenter(engine: engine, sleep: { try await sleeper.sleep($0) })
      recorder = EventRecorder(engine)
      tab = engine.createTab(url: InMemoryEngine.findPageURL(occurrences: occurrences, link: FindBarPresenterTests.link))
      observation = engine.observe { [presenter] in presenter.handle($0) }
      presenter.onChange = { [unowned self] in changes += 1 }
      presenter.onFocusRequested = { [unowned self] in focusRequests += 1 }
      presenter.onClosed = { [unowned self] in closes += 1 }
      presenter.onNoMatches = { [unowned self] in noMatchCues += 1 }
      presenter.onAnnouncement = { [unowned self] in announcements.append($0) }
      presenter.shownTabChanged(tab)
    }

    /// The final find replies the engine sent, in order.
    var replies: [EngineEvent] {
      recorder.events.filter { if case .findResult = $0 { true } else { false } }
    }

    var countText: String? { presenter.display?.countText }
  }

  /// A sleeper whose sleeps end only when the test resumes them, oldest first, or throw when their task is
  /// cancelled.
  actor ParkingSleeper {
    private struct Parked {
      let id: Int
      let duration: Duration
      let continuation: CheckedContinuation<Void, any Error>
    }

    private var parked: [Parked] = []
    private var nextID = 0

    func sleep(_ duration: Duration) async throws {
      let id = nextID
      nextID += 1
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          parked.append(Parked(id: id, duration: duration, continuation: continuation))
        }
      } onCancel: {
        Task { await self.cancel(id) }
      }
    }

    private func cancel(_ id: Int) {
      guard let index = parked.firstIndex(where: { $0.id == id }) else { return }
      parked.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    var parkedCount: Int { parked.count }
    var durations: [Duration] { parked.map(\.duration) }

    func resumeNext() {
      guard !parked.isEmpty else { return }
      parked.removeFirst().continuation.resume()
    }
  }

  /// Takes main-actor turns until `condition` holds; a bounded turn driver, never a clock.
  private static func until(_ what: String, turns: Int = 5000, _ condition: () async -> Bool) async {
    for _ in 0..<turns {
      if await condition() { return }
      await Task.yield()
    }
    Issue.record("never reached: \(what)")
  }

  // MARK: Typing

  @Test func `typing searches once, after the debounce`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("n")
    rig.presenter.setText("ne")
    rig.presenter.setText("nee")
    await Self.until("only the last keystroke's timer is parked") { await rig.sleeper.parkedCount == 1 }
    #expect(await rig.sleeper.durations == [FindBarPresenter.debounce])
    #expect(FindBarPresenter.debounce == .milliseconds(250))
    #expect(rig.replies.isEmpty, "nothing is searched before the debounce ends")

    await rig.sleeper.resumeNext()
    await Self.until("the search ran") { rig.replies.count == 1 }
    #expect(rig.countText == "1 of 12")
    #expect(rig.presenter.pendingSearches == 0)
  }

  @Test func `the search is for the text as typed`() async throws {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("fill")
    await Self.until("a timer is parked") { await rig.sleeper.parkedCount == 1 }
    await rig.sleeper.resumeNext()
    await Self.until("the search ran") { rig.replies.count == 1 }
    #expect(rig.presenter.display?.text == "fill")
    let count = try #require(rig.replies.first.flatMap { event -> Int? in
      if case .findResult(_, _, _, let count, _) = event { count } else { nil }
    })
    #expect(count == 12, "twelve separators between the page's thirteen words")
  }

  @Test func `an empty field clears at once and shows no count`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    await Self.until("a timer is parked") { await rig.sleeper.parkedCount == 1 }
    await rig.sleeper.resumeNext()
    await Self.until("the search ran") { rig.countText == "1 of 12" }

    rig.presenter.setText("")
    #expect(rig.countText == "", "no count for an empty field")
    #expect(rig.presenter.display?.hasNoMatches == false, "an empty field is not an empty result")
    #expect(await rig.sleeper.parkedCount == 0, "an empty field needs no debounce")
    #expect(rig.presenter.pendingSearches == 0)
  }

  @Test func `clearing the field cancels a timer that is still running`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    await Self.until("a timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.presenter.setText("")
    await Self.until("the timer was cancelled") { await rig.sleeper.parkedCount == 0 }
    #expect(rig.replies == [.findResult(rig.tab, requestID: 0, ordinal: 0, count: 0, isFinal: true)],
            "only the engine's answer to the empty text, no search for \"nee\"")
  }

  // MARK: Stepping

  @Test func `Return runs the pending search at once and does not wait for the timer`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    await Self.until("a timer is parked") { await rig.sleeper.parkedCount == 1 }

    rig.presenter.step(forward: true)

    #expect(rig.countText == "1 of 12", "the first Return finds the first match, it does not skip it")
    await Self.until("the timer was cancelled") { await rig.sleeper.parkedCount == 0 }
    #expect(rig.replies.count == 1, "one search, not two")
  }

  @Test func `next and previous move the ordinal and wrap`() async {
    let rig = Rig(occurrences: 3)
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    #expect(rig.countText == "1 of 3")
    rig.presenter.step(forward: true)
    #expect(rig.countText == "2 of 3")
    rig.presenter.step(forward: true)
    rig.presenter.step(forward: true)
    #expect(rig.countText == "1 of 3", "next wraps past the last match")
    rig.presenter.step(forward: false)
    #expect(rig.countText == "3 of 3", "previous wraps past the first match")
    rig.presenter.step(forward: false)
    #expect(rig.countText == "2 of 3")
  }

  @Test func `stepping with no text does nothing`() {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.step(forward: true)
    #expect(rig.replies.isEmpty)
    #expect(rig.presenter.display?.countText == "")
  }

  // MARK: The count

  @Test func `no matches reads in plain text and cues the field once per change into it`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("zzz")
    rig.presenter.step(forward: true)
    #expect(rig.countText == "No matches")
    #expect(rig.presenter.display?.hasNoMatches == true)
    #expect(rig.noMatchCues == 1)

    rig.presenter.setText("zzzz")
    rig.presenter.step(forward: true)
    #expect(rig.noMatchCues == 1, "still no matches: no second nudge")

    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    #expect(rig.presenter.display?.hasNoMatches == false)
    rig.presenter.setText("qqq")
    rig.presenter.step(forward: true)
    #expect(rig.noMatchCues == 2, "a new change into the empty result nudges again")
  }

  @Test func `counts above 999 read 999 plus`() {
    let rig = Rig(occurrences: 1200)
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    #expect(rig.countText == "1 of 999+")
  }

  @Test func `the count text`() {
    #expect(FindBarPresenter.countText(ordinal: 3, count: 12) == "3 of 12")
    #expect(FindBarPresenter.countText(ordinal: 1, count: 999) == "1 of 999")
    #expect(FindBarPresenter.countText(ordinal: 1, count: 1000) == "1 of 999+")
    #expect(FindBarPresenter.countText(ordinal: 0, count: 0) == "No matches")
  }

  @Test func `replies of an older search are ignored and unfinished ones do not announce`() {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    let announced = rig.announcements
    rig.presenter.handle(.findResult(rig.tab, requestID: 500, ordinal: 2, count: 7, isFinal: false))
    #expect(rig.countText == "2 of 7", "an unfinished reply updates the live count")
    #expect(rig.announcements == announced, "but it is not announced")
    rig.presenter.handle(.findResult(rig.tab, requestID: 499, ordinal: 9, count: 9, isFinal: true))
    #expect(rig.countText == "2 of 7", "a reply older than the one shown is dropped")
    rig.presenter.handle(.findResult(rig.tab, requestID: 501, ordinal: 3, count: 7, isFinal: true))
    #expect(rig.countText == "3 of 7")
    #expect(rig.announcements == announced + ["3 of 7"])
  }

  @Test func `the count is announced after each final reply`() async {
    let rig = Rig(occurrences: 3)
    rig.presenter.open()
    rig.presenter.setText("nee")
    #expect(rig.announcements.isEmpty, "not while the field is still settling")
    rig.presenter.step(forward: true)
    rig.presenter.step(forward: true)
    rig.presenter.setText("zzz")
    rig.presenter.step(forward: true)
    #expect(rig.announcements == ["1 of 3", "2 of 3", "No matches"])
  }

  // MARK: Opening and closing

  @Test func `opening shows the bar and asks for focus, again on a second open`() {
    let rig = Rig()
    #expect(rig.presenter.display == nil, "closed: nothing shows")
    rig.presenter.open()
    #expect(rig.presenter.display != nil)
    #expect(rig.focusRequests == 1)
    rig.presenter.open()
    #expect(rig.focusRequests == 2, "Cmd-F with the bar open focuses and selects again")
  }

  @Test func `close ends the find with activate, hides the bar and gives the page its focus back`() async throws {
    let rig = Rig(occurrences: 3)
    let selectedText: (TabID) throws -> String = { try rig.engine.selectedText($0) }
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)

    rig.presenter.close()

    #expect(rig.presenter.display == nil)
    #expect(rig.closes == 1)
    #expect(try selectedText(rig.tab) == "nee", "activate: the current match becomes the page's selection")
    #expect(rig.presenter.pendingSearches == 0)
  }

  @Test func `request ids never go back for a tab, through a clear and a close`() {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.handle(.findResult(rig.tab, requestID: 10, ordinal: 2, count: 7, isFinal: true))
    #expect(rig.countText == "2 of 7")

    rig.presenter.setText("")
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    #expect(rig.countText == "", "the engine's reply (id 2) is older than id 10 and is dropped, as after a close")
    rig.presenter.close()
    rig.presenter.open()
    rig.presenter.handle(.findResult(rig.tab, requestID: 9, ordinal: 5, count: 5, isFinal: true))
    #expect(rig.countText != "5 of 5", "an older reply after a close and a reopen is dropped")
    rig.presenter.handle(.findResult(rig.tab, requestID: 11, ordinal: 3, count: 7, isFinal: true))
    #expect(rig.countText == "3 of 7", "a newer one is taken")
  }

  @Test func `closing cancels a search that is still waiting for its timer`() async {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    await Self.until("a timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.presenter.close()
    await Self.until("the timer was cancelled") { await rig.sleeper.parkedCount == 0 }
    #expect(rig.replies.isEmpty)
  }

  @Test func `closing a bar that is not open does nothing`() {
    let rig = Rig()
    rig.presenter.close()
    #expect(rig.closes == 0)
  }

  @Test func `a reply after the bar closed does not bring a count back`() {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.close()
    rig.presenter.handle(.findResult(rig.tab, requestID: 900, ordinal: 4, count: 9, isFinal: true))
    rig.presenter.open()
    #expect(rig.countText != "4 of 9")
  }

  @Test func `reopening keeps the text and searches it again`() {
    let rig = Rig()
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.close()

    rig.presenter.open()

    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 12", "the highlight and the count come back with the bar")
  }

  @Test func `Find Next with the bar closed opens it on the last text`() {
    let rig = Rig()
    #expect(!rig.presenter.canFindAgain, "no text yet: nothing to find again")
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.close()
    #expect(rig.presenter.canFindAgain)

    rig.presenter.step(forward: true)

    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 12")
    #expect(rig.focusRequests == 2, "it opened the bar, as Cmd-F does")
  }

  // MARK: One bar per tab

  @Test func `switching tabs hides the bar and keeps its text, switching back shows it again`() {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.step(forward: true)

    rig.presenter.shownTabChanged(other)
    #expect(rig.presenter.display == nil, "the other tab has no bar")
    #expect(!rig.presenter.isOpen(other))

    rig.presenter.shownTabChanged(rig.tab)
    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "2 of 3", "its count is where it was")
  }

  @Test func `each tab has its own bar, text and count`() {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)

    rig.presenter.shownTabChanged(other)
    rig.presenter.open()
    rig.presenter.setText("fill")
    rig.presenter.step(forward: true)
    rig.presenter.step(forward: true)
    #expect(rig.presenter.display?.text == "fill")
    #expect(rig.countText == "2 of 5")

    rig.presenter.shownTabChanged(rig.tab)
    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 3")
  }

  @Test func `a reply for a hidden tab updates it without touching the shown bar`() {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.shownTabChanged(other)
    let announced = rig.announcements

    rig.presenter.handle(.findResult(rig.tab, requestID: 700, ordinal: 3, count: 3, isFinal: true))

    #expect(rig.presenter.display == nil)
    #expect(rig.announcements == announced, "a page nobody sees announces nothing")
    rig.presenter.shownTabChanged(rig.tab)
    #expect(rig.countText == "3 of 3")
  }

  @Test func `a tab that left the window takes its bar with it`() {
    let rig = Rig(occurrences: 3)
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)

    rig.presenter.forget(rig.tab)

    #expect(rig.presenter.display == nil)
    #expect(!rig.presenter.isOpen(rig.tab))
    #expect(rig.closes == 0, "nothing in this window to give focus back to")
    rig.presenter.handle(.findResult(rig.tab, requestID: 800, ordinal: 1, count: 3, isFinal: true))
    #expect(rig.presenter.display == nil, "a late reply does not bring the bar back")
    rig.presenter.open()
    #expect(rig.presenter.display?.text == "", "a tab that comes back starts with an empty field")
  }

  @Test func `an open query stays and the search moves to the newly focused tab`() throws {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.step(forward: true)
    #expect(rig.countText == "2 of 3")
    let focus = rig.focusRequests
    let closes = rig.closes

    rig.presenter.moveOpenSearch(to: other)

    #expect(rig.presenter.visibleTab == other)
    #expect(rig.presenter.display?.text == "nee", "the query stays")
    #expect(rig.countText == "1 of 5", "the search starts on the focused tab")
    #expect(rig.presenter.isOpen(other))
    #expect(!rig.presenter.isOpen(rig.tab), "the pane the search left is not still finding")
    #expect(try rig.engine.selectedText(rig.tab) == "", "its highlights are cleared")
    #expect(rig.focusRequests == focus, "focus does not jump back to the field")
    #expect(rig.closes == closes, "moving is not closing")
    rig.presenter.step(forward: false)
    #expect(rig.countText == "5 of 5", "Find Previous steps the focused tab")

    rig.presenter.moveOpenSearch(to: rig.tab)
    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 3", "coming back searches that pane again, from the first match")
  }

  @Test func `a search still waiting on the debounce moves with the query`() async {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    await Self.until("the debounce timer is parked") { await rig.sleeper.parkedCount == 1 }

    rig.presenter.moveOpenSearch(to: other)

    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 5", "the focused tab is searched at once, not the one that was waiting")
    await Self.until("the parked timer was cancelled") { await rig.sleeper.parkedCount == 0 }
    #expect(rig.presenter.pendingSearches == 0)
  }

  @Test func `a closed find stays on its tab when the focused pane changes`() {
    let rig = Rig(occurrences: 3)
    let other = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 5, link: Self.link))
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    rig.presenter.close()

    rig.presenter.moveOpenSearch(to: other)

    #expect(rig.presenter.display == nil, "a closed bar does not open on the pane that gained focus")
    #expect(!rig.presenter.isOpen(other))
    #expect(rig.presenter.visibleTab == other)
    rig.presenter.moveOpenSearch(to: rig.tab)
    rig.presenter.open()
    #expect(rig.presenter.display?.text == "nee", "the query stayed on the tab that had it")
  }

  @Test func `no focused pane hides the bar and searches nothing new`() throws {
    let rig = Rig(occurrences: 3)
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    let replies = rig.replies.count

    rig.presenter.moveOpenSearch(to: nil)

    #expect(rig.presenter.display == nil)
    #expect(rig.presenter.visibleTab == nil)
    #expect(rig.replies.count == replies, "nothing is searched while no pane is focused")
    #expect(rig.closes == 0, "hiding is not closing")
    #expect(rig.presenter.isOpen(rig.tab), "the query stays")
    rig.presenter.moveOpenSearch(to: rig.tab)
    #expect(rig.presenter.display?.text == "nee")
    #expect(rig.countText == "1 of 3")
  }

  @Test func `the engine ends a moved tab's find itself, so the shell makes no stop call`() throws {
    let rig = Rig(occurrences: 3)
    let window = rig.engine.createWindow(host: StubWindowHost())
    let target = rig.engine.createWindow(host: StubWindowHost())
    let tab = rig.engine.createTab(url: InMemoryEngine.findPageURL(occurrences: 3, link: Self.link), in: window)
    rig.presenter.shownTabChanged(tab)
    rig.presenter.open()
    rig.presenter.setText("nee")
    rig.presenter.step(forward: true)
    let before = rig.replies.count

    rig.engine.moveTab(tab, to: target)
    rig.presenter.forget(tab)

    #expect(rig.replies.count == before, "the move reports nothing")
    #expect(try rig.engine.selectedText(tab) == "", "the engine cleared the find")
    #expect(rig.presenter.display == nil)
  }
}
