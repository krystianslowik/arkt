import AppKit
import EngineAPI

public struct ContractViolation: Error, CustomStringConvertible {
  public let description: String
}

/// A contract rule that needs a harness driver the engine's harness does not provide. Reported as not applicable,
/// never as passed: the XCTest runner turns it into a skip, the in-app runner lists it.
public struct ContractNotApplicable: Error, CustomStringConvertible {
  public let driver: String
  public var description: String { "not applicable: the harness has no \(driver) driver" }
}

/// Everything an engine-specific test needs to drive the shared contract.
@MainActor
public struct EngineHarness {
  /// Makes the engine open a tab on its own in `window` (a link with `target=_blank`, `window.open`,
  /// `chrome.tabs.create`), opened by `opener` when given, and returns it once it is listed.
  public typealias EngineCreateTab = @MainActor (_ engine: any EngineClient, _ window: EngineWindowID,
                                                 _ opener: TabID?, _ active: Bool) async throws -> TabID
  /// Makes the engine (the page or an extension) close `id` on its own.
  public typealias EngineTabAction = @MainActor (_ engine: any EngineClient, _ id: TabID) async throws -> Void
  /// Makes an extension close `window` on its own (`chrome.windows.remove`).
  public typealias EngineWindowAction = @MainActor (_ engine: any EngineClient, _ window: EngineWindowID) async throws
    -> Void
  /// Answers the pending leave-site dialog of `id`: stay (`false`) or leave (`true`).
  public typealias AnswerDialog = @MainActor (_ engine: any EngineClient, _ id: TabID, _ accept: Bool) async throws
    -> Void

  public let makeEngine: @MainActor () -> any EngineClient
  /// A URL whose page has `<title>title</title>` and needs no network.
  public let pageURL: @MainActor (_ title: String) throws -> URL
  /// Drives (in-memory) or waits for (real engines) the end of the current load of `id`.
  public let settle: @MainActor (_ engine: any EngineClient, _ id: TabID) async throws -> Void
  /// Changes the loaded document's title the way page script would (`document.title = title`).
  public let retitle: @MainActor (_ engine: any EngineClient, _ id: TabID, _ title: String) async throws -> Void
  /// Two pages on different hosts, each declaring a favicon the engine will pick up.
  public let pagesOnTwoHosts: @MainActor () throws -> (URL, URL)
  /// A host for `createWindow(host:)` (rules 11, 12, 13, 15, 16).
  public let makeWindowHost: @MainActor () -> any EngineWindowHosting

  // Drivers for engine-side behaviour (rules 13, 14, 16). A rule whose driver is nil is not applicable.
  public let engineCreateTab: EngineCreateTab?
  public let engineCloseTab: EngineTabAction?
  /// Makes the engine activate `id` on its own (an extension's `chrome.tabs.update({active: true})`).
  public let engineActivate: EngineTabAction?
  /// Makes the page register a `beforeunload` handler with sticky user activation, so an honouring close holds.
  public let holdClose: EngineTabAction?
  public let answerDialog: AnswerDialog?
  /// Makes the page of `id` play sound (rule 17), for example `EngineContract.toneScript` run with a user gesture.
  public let makeAudible: EngineTabAction?
  /// Makes an extension close the window (rule 11, #401).
  public let engineCloseWindow: EngineWindowAction?

  public init(makeEngine: @escaping @MainActor () -> any EngineClient,
              pageURL: @escaping @MainActor (String) throws -> URL,
              settle: @escaping @MainActor (any EngineClient, TabID) async throws -> Void,
              retitle: @escaping @MainActor (any EngineClient, TabID, String) async throws -> Void,
              pagesOnTwoHosts: @escaping @MainActor () throws -> (URL, URL),
              makeWindowHost: @escaping @MainActor () -> any EngineWindowHosting = { StubWindowHost() },
              engineCreateTab: EngineCreateTab? = nil,
              engineCloseTab: EngineTabAction? = nil,
              engineActivate: EngineTabAction? = nil,
              holdClose: EngineTabAction? = nil,
              answerDialog: AnswerDialog? = nil,
              makeAudible: EngineTabAction? = nil,
              engineCloseWindow: EngineWindowAction? = nil) {
    self.makeEngine = makeEngine; self.pageURL = pageURL; self.settle = settle
    self.retitle = retitle; self.pagesOnTwoHosts = pagesOnTwoHosts; self.makeWindowHost = makeWindowHost
    self.engineCreateTab = engineCreateTab; self.engineCloseTab = engineCloseTab
    self.engineActivate = engineActivate; self.holdClose = holdClose; self.answerDialog = answerDialog
    self.makeAudible = makeAudible; self.engineCloseWindow = engineCloseWindow
  }

  /// In-memory pages: the title is the last path component; every finished load carries a favicon. Every driver is
  /// present.
  public static func inMemory() -> EngineHarness {
    EngineHarness(
      makeEngine: { InMemoryEngine() },
      pageURL: { title in URL(string: "arkt-test://page/\(title)")! },
      settle: { engine, id in
        guard let engine = engine as? InMemoryEngine, let url = engine.snapshot(of: id)?.url else { return }
        engine.finishLoad(id, title: url.lastPathComponent, favicon: Data("icon:\(url.absoluteString)".utf8))
      },
      retitle: { engine, id, title in (engine as? InMemoryEngine)?.setDocumentTitle(id, title) },
      pagesOnTwoHosts: {
        (URL(string: "arkt-test://alpha.test/Alpha")!, URL(string: "arkt-test://beta.test/Beta")!)
      },
      engineCreateTab: { engine, window, opener, active in
        try inMemory(engine).engineCreateTab(url: nil, in: window, opener: opener, active: active)
      },
      engineCloseTab: { engine, id in try inMemory(engine).engineCloseTab(id, reason: .page) },
      engineActivate: { engine, id in try inMemory(engine).engineActivate(id) },
      holdClose: { engine, id in try inMemory(engine).holdClose(id) },
      answerDialog: { engine, id, accept in
        guard try inMemory(engine).answerDialog(id, accept: accept) else {
          throw ContractViolation(description: "no pending dialog in \(id)")
        }
      },
      makeAudible: { engine, id in try inMemory(engine).setAudible(id, true) },
      engineCloseWindow: { engine, window in try inMemory(engine).engineCloseWindow(window, reason: .extension) }
    )
  }

  private static func inMemory(_ engine: any EngineClient) throws -> InMemoryEngine {
    guard let engine = engine as? InMemoryEngine else {
      throw ContractViolation(description: "the in-memory harness needs an InMemoryEngine, got \(type(of: engine))")
    }
    return engine
  }
}

/// The engine contract (design section 1). Every engine runs these checks:
/// 1. `createTab` lists the tab (creation order) and emits `.tabCreated` before any other event for it.
/// 2. `navigate` emits `.urlChanged` then `.loadingChanged(true)`. A title present in the document when
///    loading ends is reported before `.loadingChanged(false)`; `.titleChanged` may also arrive later
///    (for example a title set by script). `snapshot(of:)` agrees with the last events.
/// 3. `contentView(for:)` keeps its identity for the life of the tab.
/// 4. `closeTab` is terminal: `.tabClosed` once, then nothing for that tab, even when the tab is closed
///    from inside an observer; every observer sees the same order.
/// 5. Cancelling or dropping an `EngineObservation` stops delivery to that handler only.
/// 6. When a navigation commits on a different host, the old favicon is cleared
///    (`.faviconChanged(nil)`) before that load's `.loadingChanged(false)`.
/// 7. `goBack` / `goForward` move through the tab's history and report the URL they land on with `.urlChanged`,
///    like a navigation; at either end of the history they do nothing.
/// 8. `snapshot(of:)` carries `canGoBack` / `canGoForward`: false for a new tab, Back available once a second page
///    is shown, Forward available after `goBack`. Every change is announced with `.historyChanged`, and the snapshot
///    agrees with the last one. Its position relative to `.urlChanged` and `.loadingChanged` is not fixed.
/// 9. `history(of:)` lists `back` and `forward` entries nearest-first (nil once closed), and `goToHistory(_:offset:)`
///    jumps across multiple entries (`-2` = two steps back, `+2` = two steps forward); `0` or out-of-range offsets do
///    nothing (#81, GS-024).
/// 10. `duplicateTab(_:)` creates a new tab with the source tab's URL, title and back/forward history (#81, BH-027,
///     GS-026); nil for an unknown or closed tab.
/// 11. A window from `createWindow(host:)` is listed in `windowIDs` and announced with `.windowOpened`; every tab's
///     snapshot names its window; `closeWindow` (or the host's `onCloseRequested`) closes its tabs
///     (`.tabClosed(reason: .windowClosing)` each) and then reports `.windowClosed` with reason `.userClose`. A window
///     whose last tab moved to another window closes with `.lastTabClosed`; one an extension closes reports its tabs
///     and itself with `.extension` (needs `engineCloseWindow`). Quitting reports `.appQuit` (#401).
/// 12. `activateTab` makes the tab its window's active tab: `.activeTabChanged(id)` and `isActive` in the snapshot,
///     with exactly one active tab per window that has tabs (the first tab of a window is active; closing the
///     active tab activates another).
/// 13. A tab the engine creates on its own is announced with `.tabCreated` and its snapshot has `origin == .engine`,
///     its window, its opener (when there is one) and `isActive`; an engine-side activation is announced with
///     `.activeTabChanged`. Needs `engineCreateTab` and `engineActivate`.
/// 14. A tab the engine closes on its own ends with one `.tabClosed` with reason `.page` or `.extension`, and nothing
///     after it, as rule 4. Needs `engineCloseTab`.
/// 15. `createTab(url:)` without a window lands in the most recently active window.
/// 16. A held close keeps the tab listed with `isClosing` until `.tabClosed(reason: .client)`; a cancelled close
///     reports `.closeCancelled` and leaves the tab open with no `.tabClosed`; `.skipUnloadHandlers` never holds on a
///     `beforeunload` page. A window close with a held tab that is cancelled keeps the window and its tabs open (no
///     `.windowClosed`). Needs `holdClose` and `answerDialog`.
/// 17. `setMuted(_:muted:)` sets `isMuted` in the snapshot and reports each change with one `.mutedChanged`; setting
///     the state the tab already has reports nothing (#364). A page that plays sound reports `.audibleChanged(true)`
///     and `isAudible` (needs `makeAudible`).
///
/// Engines may deliver events one main-actor turn after the call that caused them (the Chromium engine does, except
/// for the synchronous parts of rules 1 and 4), so rules 11-16 wait for events and snapshot values.
@MainActor
public enum EngineContract {
  static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw ContractViolation(description: message()) }
  }

  /// Polls while yielding the main actor, so run-loop driven engines (WKWebView) make progress.
  public static func waitUntil(timeout: Duration, _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      if ContinuousClock.now > deadline { throw ContractViolation(description: "timed out after \(timeout)") }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  public static func createdTabIsListedAndAnnounced(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    try require(engine.tabIDs == [id], "tabIDs should be [id], got \(engine.tabIDs)")
    try require(recorder.events(for: id).first == .tabCreated(id), "first event must be tabCreated")
    try require(engine.snapshot(of: id) != nil, "snapshot of a live tab must exist")
  }

  public static func navigateReportsURLLoadingAndTitle(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    let url = try h.pageURL("ContractPage")
    engine.navigate(id, to: url)
    try await h.settle(engine, id)
    let events = recorder.events(for: id)
    let urlIndex = events.firstIndex { if case .urlChanged(_, let u) = $0 { return u == url }; return false }
    let startIndex = events.firstIndex(of: .loadingChanged(id, isLoading: true))
    let endIndex = events.lastIndex(of: .loadingChanged(id, isLoading: false))
    let titleIndex = events.firstIndex(of: .titleChanged(id, "ContractPage"))
    try require(urlIndex != nil && startIndex != nil && endIndex != nil && titleIndex != nil,
                "missing url/loading/title events: \(events)")
    try require(urlIndex! < startIndex!, "urlChanged must precede loadingChanged(true): \(events)")
    try require(startIndex! < endIndex!, "load must finish after it starts: \(events)")
    try require(titleIndex! < endIndex!, "title must be reported before loading ends: \(events)")
    let snap = try requireValue(engine.snapshot(of: id))
    try require(snap.url == url && snap.title == "ContractPage" && !snap.isLoading, "snapshot disagrees: \(snap)")
  }

  public static func titleChangedAfterLoadIsReported(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: try h.pageURL("Before"))
    try await h.settle(engine, id)
    let loadedAt = recorder.events(for: id).count
    try await h.retitle(engine, id, "After")
    try await waitUntil(timeout: .seconds(5)) { engine.snapshot(of: id)?.title == "After" }
    let later = recorder.events(for: id).dropFirst(loadedAt)
    try require(later.contains(.titleChanged(id, "After")), "late title not reported: \(Array(later))")
  }

  public static func contentViewIsStable(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let id = engine.createTab(url: nil)
    let first = try requireValue(engine.contentView(for: id))
    let host = NSView()
    host.addSubview(first)
    try require(engine.contentView(for: id) === first, "contentView must keep its identity")
  }

  public static func closeIsTerminal(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    engine.closeTab(id)
    let late = try h.pageURL("AfterClose")
    engine.navigate(id, to: late)
    engine.closeTab(id)
    try await Task.sleep(for: .milliseconds(50))
    try require(!engine.tabIDs.contains(id), "closed tab still listed")
    try require(engine.snapshot(of: id) == nil && engine.contentView(for: id) == nil, "closed tab still resolvable")
    let closes = recorder.events(for: id).filter { $0 == .tabClosed(id, reason: .client) }.count
    try require(closes == 1 && recorder.events(for: id).last == .tabClosed(id, reason: .client),
                "tabClosed(reason: .client) must be last and once")
  }

  /// An observer closes the tab while the title is being delivered; a second observer must still see
  /// the same sequence, ending with exactly one tabClosed.
  public static func closeInsideObserverKeepsOrder(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let id = engine.createTab(url: nil)
    var closer: [EngineEvent] = []
    let closing = engine.observe { event in
      guard event.tabID == id else { return }
      closer.append(event)
      if case .titleChanged = event { engine.closeTab(id) }
    }
    let watcher = EventRecorder(engine)
    engine.navigate(id, to: try h.pageURL("ClosedWhileLoading"))
    try await h.settle(engine, id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id) == nil }
    try await Task.sleep(for: .milliseconds(50))
    let seen = watcher.events(for: id)
    try require(seen == closer, "observers disagree:\n closer \(closer)\n watcher \(seen)")
    try require(seen.last == .tabClosed(id, reason: .client)
                  && seen.filter { $0 == .tabClosed(id, reason: .client) }.count == 1,
                "tabClosed must be last and once: \(seen)")
    closing.cancel()
  }

  public static func cancelledObservationStopsDelivery(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    var count = 0
    var other = 0
    let token = engine.observe { _ in count += 1 }
    let otherToken = engine.observe { _ in other += 1 }
    engine.createTab(url: nil)
    token.cancel()
    engine.createTab(url: nil)
    try require(count == 1, "expected 1 event before cancel, got \(count)")
    try require(other == 2, "cancel must not affect other observers, got \(other)")
    otherToken.cancel()
  }

  public static func droppedObservationStopsDelivery(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    var count = 0
    var token: EngineObservation? = engine.observe { _ in count += 1 }
    engine.createTab(url: nil)
    try require(token != nil, "token must be alive before the drop")
    token = nil
    engine.createTab(url: nil)
    try require(count == 1, "expected 1 event before the token was dropped, got \(count)")
  }

  public static func tabIDsKeepCreationOrder(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let a = engine.createTab(url: nil), b = engine.createTab(url: nil), c = engine.createTab(url: nil)
    engine.closeTab(b)
    try require(engine.tabIDs == [a, c], "order broken: \(engine.tabIDs)")
  }

  public static func hostChangeClearsFavicon(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let (first, second) = try h.pagesOnTwoHosts()
    let id = engine.createTab(url: first)
    try await h.settle(engine, id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.faviconData != nil }
    let mark = recorder.events(for: id).count
    engine.navigate(id, to: second)
    try await h.settle(engine, id)
    let later = Array(recorder.events(for: id).dropFirst(mark))
    let cleared = later.firstIndex(of: .faviconChanged(id, nil))
    let finished = later.firstIndex(of: .loadingChanged(id, isLoading: false))
    try require(cleared != nil && finished != nil, "missing faviconChanged(nil) or load end: \(later)")
    try require(cleared! < finished!, "favicon must be cleared before the new load ends: \(later)")
  }

  public static func historyMovesBackAndForward(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let (first, second) = (try h.pageURL("HistoryFirst"), try h.pageURL("HistorySecond"))
    let id = engine.createTab(url: first)
    try await h.settle(engine, id)
    engine.goBack(id)                                   // nothing behind the first page
    try await Task.sleep(for: .milliseconds(50))
    try require(engine.snapshot(of: id)?.url == first, "goBack at the start must do nothing")
    engine.navigate(id, to: second)
    try await h.settle(engine, id)
    let mark = recorder.events(for: id).count
    engine.goBack(id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == first }
    try await h.settle(engine, id)
    let back = Array(recorder.events(for: id).dropFirst(mark))
    try require(back.contains(.urlChanged(id, first)), "goBack must report the URL it lands on: \(back)")
    engine.goForward(id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == second }
    try await h.settle(engine, id)
    engine.goForward(id)                                // nothing ahead of the last page
    try await Task.sleep(for: .milliseconds(50))
    try require(engine.snapshot(of: id)?.url == second, "goForward at the end must do nothing")
  }

  public static func historyAvailabilityIsReported(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let (first, second) = (try h.pageURL("AvailabilityFirst"), try h.pageURL("AvailabilitySecond"))
    let id = engine.createTab(url: nil)
    let fresh = try requireValue(engine.snapshot(of: id))
    try require(!fresh.canGoBack && !fresh.canGoForward, "a new tab has no history: \(fresh)")
    engine.navigate(id, to: first)
    try await h.settle(engine, id)
    try await expectHistory(engine, recorder, id, back: false, forward: false, "after the first page")
    engine.navigate(id, to: second)
    try await h.settle(engine, id)
    try await expectHistory(engine, recorder, id, back: true, forward: false, "after the second page")
    engine.goBack(id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == first }
    try await h.settle(engine, id)
    try await expectHistory(engine, recorder, id, back: false, forward: true, "after goBack")
    engine.goForward(id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == second }
    try await h.settle(engine, id)
    try await expectHistory(engine, recorder, id, back: true, forward: false, "after goForward")
    let announced = recorder.events(for: id).compactMap { event -> (Bool, Bool)? in
      if case .historyChanged(_, let back, let forward) = event { return (back, forward) }
      return nil
    }
    try require(announced.contains { $0 == (false, true) }, "Forward becoming available was not announced")
  }

  public static func historyEntriesAndOffsetNavigation(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let (first, second, third) = (
      try h.pageURL("HistoryOne"), try h.pageURL("HistoryTwo"), try h.pageURL("HistoryThree"))
    let id = engine.createTab(url: nil)
    try require(engine.history(of: id) == TabHistory(), "a new tab starts with empty history")
    engine.navigate(id, to: first)
    try await h.settle(engine, id)
    engine.navigate(id, to: second)
    try await h.settle(engine, id)
    engine.navigate(id, to: third)
    try await h.settle(engine, id)
    let atThird = try requireValue(engine.history(of: id), "history at third")
    try require(atThird.back.map(\.url) == [second, first], "back must be nearest-first: \(atThird.back)")
    try require(atThird.back.map(\.title) == ["HistoryTwo", "HistoryOne"],
                "back entries must carry titles: \(atThird.back)")
    try require(atThird.forward.isEmpty, "forward must be empty at third: \(atThird.forward)")

    // Jump two steps back in one move (`offset = -2`).
    engine.goToHistory(id, offset: -2)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == first }
    try await h.settle(engine, id)
    let atFirst = try requireValue(engine.history(of: id), "history at first")
    try require(atFirst.back.isEmpty, "back must be empty at first: \(atFirst.back)")
    try require(atFirst.forward.map(\.url) == [second, third], "forward must be nearest-first: \(atFirst.forward)")

    // Jump two steps forward (`offset = 2`), and check 0 / out-of-range offsets are no-ops.
    engine.goToHistory(id, offset: 2)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == third }
    try await h.settle(engine, id)
    engine.goToHistory(id, offset: 0)
    engine.goToHistory(id, offset: 5)
    engine.goToHistory(id, offset: -5)
    try await Task.sleep(for: .milliseconds(50))
    try require(engine.snapshot(of: id)?.url == third, "out-of-range offsets must do nothing")

    engine.closeTab(id)
    try require(engine.history(of: id) == nil, "closed tab history must be nil")
  }

  public static func duplicateTabCopiesURLTitleAndHistory(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    try require(engine.duplicateTab(TabID()) == nil, "duplicating an unknown tab must return nil")

    let (first, second, third) = (
      try h.pageURL("DupOne"), try h.pageURL("DupTwo"), try h.pageURL("DupThree"))
    let id = engine.createTab(url: first)
    try await h.settle(engine, id)
    engine.navigate(id, to: second)
    try await h.settle(engine, id)
    engine.navigate(id, to: third)
    try await h.settle(engine, id)
    engine.goBack(id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.url == second }
    try await h.settle(engine, id)

    let copy = try requireValue(engine.duplicateTab(id), "duplicateTab of a live tab")
    try require(copy != id && engine.tabIDs == [id, copy], "duplicate must be listed after original: \(engine.tabIDs)")
    try require(recorder.events(for: copy).first == .tabCreated(copy), "first event for duplicate must be tabCreated")
    try await h.settle(engine, copy)
    let copySnap = try requireValue(engine.snapshot(of: copy), "duplicate snapshot")
    try require(copySnap.url == second && copySnap.canGoBack && copySnap.canGoForward,
                "duplicate snapshot must carry URL and history flags: \(copySnap)")
    let copyHistory = try requireValue(engine.history(of: copy), "duplicate history")
    try require(copyHistory.back.map(\.url) == [first] && copyHistory.forward.map(\.url) == [third],
                "duplicate must copy back and forward stacks: \(copyHistory)")

    // Moving in the duplicate leaves the original tab untouched.
    engine.goBack(copy)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: copy)?.url == first }
    try require(engine.snapshot(of: id)?.url == second, "original tab must stay on second")
  }

  // MARK: Rule 17 (#364)

  /// A page that plays a tone through Web Audio, for the `makeAudible` driver of a real engine. It needs a user
  /// gesture (the autoplay policy), so run it as one. It answers the context's state at once (`running` with the
  /// gesture); the test API does not wait for promises.
  public static let toneScript = """
    (() => { const c = new AudioContext(); const o = c.createOscillator(); const g = c.createGain(); \
    g.gain.value = 0.05; o.connect(g).connect(c.destination); o.start(); c.resume(); window.arktTone = c; \
    return c.state; })()
    """

  public static func muteIsReportedOnce(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Muted"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try require(engine.snapshot(of: id)?.isMuted == false, "a new tab must not be muted")
    engine.setMuted(id, muted: true)
    try await waitUntil(timeout: .seconds(5)) { engine.snapshot(of: id)?.isMuted == true }
    engine.setMuted(id, muted: true)
    engine.setMuted(id, muted: false)
    try await waitUntil(timeout: .seconds(5)) { engine.snapshot(of: id)?.isMuted == false }
    // A redundant call that an engine reported anyway would arrive by now (one batch after the calls).
    try await Task.sleep(for: .milliseconds(100))
    let mutes = recorder.events(for: id).filter { if case .mutedChanged = $0 { true } else { false } }
    try require(mutes == [.mutedChanged(id, isMuted: true), .mutedChanged(id, isMuted: false)],
                "each mute change must be reported once: \(mutes)")
  }

  public static func audibleStateIsReported(_ h: EngineHarness) async throws {
    let makeAudible = try driver(h.makeAudible, "makeAudible")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Tone"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try require(engine.snapshot(of: id)?.isAudible == false, "a silent page must not be audible")
    try await makeAudible(engine, id)
    try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: id)?.isAudible == true }
    try require(recorder.events(for: id).contains(.audibleChanged(id, isAudible: true)),
                "the audible start must be reported: \(recorder.events(for: id))")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  /// Waits for the snapshot to show the expected availability, then checks the last event agrees with it.
  static func expectHistory(_ engine: any EngineClient, _ recorder: EventRecorder, _ id: TabID,
                            back: Bool, forward: Bool, _ when: String) async throws {
    do {
      try await waitUntil(timeout: .seconds(10)) {
        engine.snapshot(of: id).map { $0.canGoBack == back && $0.canGoForward == forward } ?? false
      }
    } catch {
      throw ContractViolation(description: "\(when): snapshot \(String(describing: engine.snapshot(of: id))), "
                                + "want back \(back) forward \(forward)")
    }
    let last = recorder.events(for: id).last { if case .historyChanged = $0 { return true }; return false }
    if back || forward || last != nil {
      try require(last == .historyChanged(id, canGoBack: back, canGoForward: forward),
                  "\(when): last historyChanged \(String(describing: last)) disagrees with the snapshot")
    }
  }

  static func requireValue<T>(_ value: T?, _ what: String = "value") throws -> T {
    guard let value else { throw ContractViolation(description: "missing \(what)") }
    return value
  }
}
