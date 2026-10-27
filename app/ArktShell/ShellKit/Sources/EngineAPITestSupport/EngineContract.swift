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
  /// Makes the page of `id` raise an `alert()`, `confirm()` or `prompt()` with `message` (and a prompt's default text).
  public typealias RaiseDialog = @MainActor (_ engine: any EngineClient, _ id: TabID, _ kind: JavaScriptDialog.Kind,
                                             _ message: String, _ defaultText: String?) async throws -> Void

  /// Makes the page of `id` ask for `kinds`.
  public typealias RaisePermission = @MainActor (_ engine: any EngineClient, _ id: TabID, _ kinds: [PermissionKind])
    async throws -> Void

  /// Makes the engine add an infobar with `message` to `id` (OK and Cancel buttons, closeable).
  public typealias RaiseInfobar = @MainActor (_ engine: any EngineClient, _ id: TabID, _ message: String) async throws
    -> Void

  /// A page with `occurrences` copies of `EngineContract.findWord` in its text and one link, with the text
  /// `EngineContract.findLinkText`, to `link` (rules 22, 23).
  public typealias FindPage = @MainActor (_ occurrences: Int, _ link: URL) throws -> URL
  /// The text selected in the page of `id` (`window.getSelection().toString()`).
  public typealias SelectedText = @MainActor (_ engine: any EngineClient, _ id: TabID) async throws -> String

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
  /// Shows the page of `id` on screen at a real size, as the shell mounts a window's active tab (rule 18). An engine
  /// that draws without being shown passes a closure that does nothing.
  public let showPage: EngineTabAction?
  /// Makes the page raise a JavaScript dialog (rule 19). An engine that cannot (a real engine needs its tab
  /// foremost) leaves it nil.
  public let raiseDialog: RaiseDialog?
  /// Makes the page ask for a permission (rule 20). Nil for an engine that cannot (a real engine needs its tab
  /// foremost and a user gesture).
  public let raisePermission: RaisePermission?
  /// Makes the engine show an infobar on a tab (rule 21). Nil for an engine that cannot (a real engine shows them for
  /// its own reasons: a debugging extension, a flag, a changed setting).
  public let raiseInfobar: RaiseInfobar?
  /// A page to search and to hover a link on (rules 22, 23). Nil: not applicable.
  public let findPage: FindPage?
  /// Reads the page's selection (rule 22). Nil: not applicable.
  public let selectedText: SelectedText?
  /// Puts the pointer over the link of a `findPage` page, and takes it away again (rule 23). A real engine that cannot take
  /// pointer input may focus and blur the link, which reaches the same renderer report. Nil: not applicable.
  public let hoverLink: EngineTabAction?
  public let leaveLink: EngineTabAction?
  /// Makes the engine's downloads happen (rule 24). Nil: not applicable (an engine with no downloads, or one that is
  /// not wired yet).
  public let downloads: DownloadDrivers?

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
              engineCloseWindow: EngineWindowAction? = nil,
              showPage: EngineTabAction? = nil,
              raiseDialog: RaiseDialog? = nil,
              raisePermission: RaisePermission? = nil,
              raiseInfobar: RaiseInfobar? = nil,
              findPage: FindPage? = nil,
              selectedText: SelectedText? = nil,
              hoverLink: EngineTabAction? = nil,
              leaveLink: EngineTabAction? = nil,
              downloads: DownloadDrivers? = nil) {
    self.makeEngine = makeEngine; self.pageURL = pageURL; self.settle = settle
    self.retitle = retitle; self.pagesOnTwoHosts = pagesOnTwoHosts; self.makeWindowHost = makeWindowHost
    self.engineCreateTab = engineCreateTab; self.engineCloseTab = engineCloseTab
    self.engineActivate = engineActivate; self.holdClose = holdClose; self.answerDialog = answerDialog
    self.makeAudible = makeAudible; self.engineCloseWindow = engineCloseWindow
    self.showPage = showPage
    self.raiseDialog = raiseDialog
    self.raisePermission = raisePermission
    self.raiseInfobar = raiseInfobar
    self.findPage = findPage; self.selectedText = selectedText
    self.hoverLink = hoverLink; self.leaveLink = leaveLink
    self.downloads = downloads
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
      engineCloseWindow: { engine, window in try inMemory(engine).engineCloseWindow(window, reason: .extension) },
      // In-memory pages draw without a window.
      showPage: { _, _ in },
      raiseDialog: { engine, id, kind, message, defaultText in
        guard try inMemory(engine).raiseDialog(in: id, kind: kind, message: message, defaultPromptText: defaultText)
          != nil else { throw ContractViolation(description: "no dialog raised in \(id)") }
      },
      raisePermission: { engine, id, kinds in
        guard try inMemory(engine).askPermission(in: id, kinds: kinds) != nil else {
          throw ContractViolation(description: "no permission asked in \(id)")
        }
      },
      raiseInfobar: { engine, id, message in
        guard try inMemory(engine).raiseInfobar(in: id, message: message) != nil else {
          throw ContractViolation(description: "no infobar raised in \(id)")
        }
      },
      findPage: { occurrences, link in InMemoryEngine.findPageURL(occurrences: occurrences, link: link) },
      selectedText: { engine, id in try inMemory(engine).selectedText(id) },
      hoverLink: { engine, id in try inMemory(engine).hoverLink(id) },
      leaveLink: { engine, id in try inMemory(engine).leaveLink(id) },
      downloads: .inMemory()
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
///     GS-026); nil for an unknown or closed tab. The copy is parked until it is shown (#380): it is not active, it
///     loads only once activated (or navigated, or moved), and an extension never sees it in the meantime.
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
/// 18. `pageImage(of:_:)` gives a loaded, shown tab's image within the request's pixel and byte caps, decodable at the
///     size it reports; `.fullFrame` is at least as large as `.thumbnail`. An unknown or closed tab gives nil (#370,
///     #352). Needs `showPage`.
/// 19. A page's `alert()`, `confirm()` or `prompt()` is reported with `.dialogRequested` carrying the engine's strings
///     (an alert has no cancel title, a prompt its default text); `respond(to:accepted:userInput:)` ends it with one
///     `.dialogEnded` and a second answer does nothing; a dialog still pending when its tab closes ends before the
///     tab's `.tabClosed` (#400); a `confirm()` or `prompt()` still pending when its tab stops being the window's
///     active tab ends with `.dialogEnded`, as Chromium answers it false or null when the tab is hidden (an `alert()`
///     stays). Needs `raiseDialog`.
/// 20. A site's permission request is reported with `.permissionRequested` carrying the engine's strings and the kinds
///     asked for; `respond(toPermission:choice:)` ends it with one `.permissionEnded` and a second answer does nothing;
///     a request still pending when its tab closes ends before the tab's `.tabClosed`; a navigation ends it; a tab
///     that stops being its window's active tab ends it unanswered, and asks again with a new request when it is
///     active again (#400). Needs `raisePermission`.
/// 21. An infobar is reported with `.infobarsChanged` carrying the tab's whole list and the engine's strings;
///     `act(on:action:)` runs the engine's delegate, which removes the infobar with a new, shorter list, and an action
///     on an infobar that is gone does nothing; infobars stay with their tab while it is hidden and the list is
///     independent of the other tabs'; a tab's infobars are reported empty before its `.tabClosed` (#400). Needs
///     `raiseInfobar`.
///
/// 22. `findInPage(_:text:forward:matchCase:)` reports `.findResult` with the match count and the active match's
///     ordinal: a new search starts at match 1, the same search forward and backward moves the ordinal and wraps at the
///     ends, a changed text or case starts over, `stopFinding` ends the session so the next search starts at match 1,
///     empty text clears and is reported once as 0 of 0, request ids never go back. `stopFinding(.keep)` leaves the
///     active match selected, `.clear` leaves nothing selected, `.activate` follows a matched link (#134). Needs
///     `findPage`; the second check also `selectedText`.
/// 23. A link under the pointer is reported with `.targetURLChanged(url)` once, and leaving it with
///     `.targetURLChanged(nil)` once; nothing is reported while it does not change, and the engine delays and
///     merges nothing (#114). Needs `findPage`, `hoverLink` and `leaveLink`.
///
/// 24. A download is reported with `.downloadCreated` carrying the engine's values, then `.downloadUpdated` as bytes
///     arrive (the received count never goes backwards) and once more when it is complete, with its end time and
///     target. `cancel` ends an active download as `.cancelled` once; `pause` holds the bytes until `resume`; an
///     interrupted download carries its reason and `retry` starts it again (in place when it can resume, else as a
///     new download that replaces it); `remove` reports `.downloadRemoved` once and keeps the file; a dangerous
///     download is held until `keepDangerous` (its type becomes user validated) or `discardDangerous` (the file is
///     deleted and the item removed), and a blocked one cannot be kept; the save preference decides the folder (or
///     the chooser's answer in `.ask` mode, and the default folder when the chosen one is missing). A command on an
///     unknown id or a state it does not apply to does nothing. Needs `downloads`.
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
    // #380: a duplicate is a parked copy. It never takes the window's active tab and loads only once shown, so
    // the contract shows it (activates it) before it waits for the load.
    try require(engine.snapshot(of: copy)?.isActive != true, "a duplicate must not take the active tab")
    engine.activateTab(copy)
    if engine.snapshot(of: copy)?.window != nil {
      try await waitUntil(timeout: .seconds(10)) { engine.snapshot(of: copy)?.isActive == true }
    }
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

  // MARK: Rule 19 (#400)

  static func requestedDialogs(_ recorder: EventRecorder, _ id: TabID) -> [JavaScriptDialog] {
    recorder.events(for: id).compactMap { if case .dialogRequested(let dialog) = $0 { dialog } else { nil } }
  }

  static func endedDialogs(_ recorder: EventRecorder, _ id: TabID) -> [DialogID] {
    recorder.events(for: id).compactMap { if case .dialogEnded(_, let dialog) = $0 { dialog } else { nil } }
  }

  public static func dialogIsReportedAnsweredAndEndedOnce(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseDialog, "raiseDialog")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Dialog"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, .prompt, "Your name?", "Ada")
    try await waitUntil(timeout: .seconds(10)) { !requestedDialogs(recorder, id).isEmpty }
    let dialog = try requireValue(requestedDialogs(recorder, id).first, "dialog")
    try require(dialog.tab == id && dialog.kind == .prompt && dialog.message == "Your name?"
                  && dialog.defaultPromptText == "Ada" && !dialog.title.isEmpty && !dialog.acceptTitle.isEmpty
                  && dialog.cancelTitle?.isEmpty == false, "the dialog must carry the engine's values: \(dialog)")
    engine.respond(to: dialog.id, accepted: true, userInput: "Grace")
    engine.respond(to: dialog.id, accepted: false, userInput: nil)
    try await waitUntil(timeout: .seconds(10)) { !endedDialogs(recorder, id).isEmpty }

    // Events arrive in order: if the second answer had ended it again, that end would come before this request.
    try await raise(engine, id, .alert, "Saved", nil)
    try await waitUntil(timeout: .seconds(10)) { requestedDialogs(recorder, id).count == 2 }
    try require(endedDialogs(recorder, id) == [dialog.id], "an answered dialog must end once: \(recorder.events(for: id))")
    let alert = try requireValue(requestedDialogs(recorder, id).last, "alert")
    try require(alert.kind == .alert && alert.cancelTitle == nil && alert.defaultPromptText == nil,
                "an alert has OK only: \(alert)")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  public static func pendingDialogEndsBeforeItsTabCloses(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseDialog, "raiseDialog")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Dialog"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, .confirm, "Leave?", nil)
    try await waitUntil(timeout: .seconds(10)) { !requestedDialogs(recorder, id).isEmpty }
    let dialog = try requireValue(requestedDialogs(recorder, id).first, "dialog")
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try await waitUntil(timeout: .seconds(10)) { recorder.events(for: id).contains { if case .tabClosed = $0 { true } else { false } } }
    let tail = Array(recorder.events(for: id).suffix(2))
    try require(tail == [.dialogEnded(id, dialog.id), .tabClosed(id, reason: .client)],
                "the dialog must end before the tab closes: \(tail)")
    engine.respond(to: dialog.id, accepted: true, userInput: nil)    // ended: nothing happens
  }

  public static func hiddenTabEndsItsConfirmAndPrompt(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseDialog, "raiseDialog")
    let engine = h.makeEngine()
    let window = engine.createWindow(host: h.makeWindowHost())
    let shown = engine.createTab(url: try h.pageURL("Dialog"), in: window)
    let other = engine.createTab(url: try h.pageURL("Other"), in: window)
    try await h.settle(engine, shown)
    try await h.settle(engine, other)
    try await wait("the first tab to be active") { engine.activeTab(in: window) == shown }
    let recorder = EventRecorder(engine)
    for (kind, message) in [(JavaScriptDialog.Kind.confirm, "Leave?"), (.prompt, "Name?")] {
      try await raise(engine, shown, kind, message, kind == .prompt ? "Ada" : nil)
      try await waitUntil(timeout: .seconds(10)) { requestedDialogs(recorder, shown).count == (kind == .confirm ? 1 : 2) }
      let dialog = try requireValue(requestedDialogs(recorder, shown).last, "dialog")
      engine.activateTab(other)
      try await waitUntil(timeout: .seconds(10)) { endedDialogs(recorder, shown).contains(dialog.id) }
      try require(endedDialogs(recorder, shown).filter { $0 == dialog.id }.count == 1,
                  "a hidden tab's \(kind) must end once: \(recorder.events(for: shown))")
      engine.respond(to: dialog.id, accepted: true, userInput: nil)           // ended: nothing happens
      engine.activateTab(shown)
      try await wait("the tab to be active again") { engine.activeTab(in: window) == shown }
    }
  }

  // MARK: Rule 20 (#400)

  static func requestedPermissions(_ recorder: EventRecorder, _ id: TabID) -> [PermissionRequest] {
    recorder.events(for: id).compactMap { if case .permissionRequested(let request) = $0 { request } else { nil } }
  }

  static func endedPermissions(_ recorder: EventRecorder, _ id: TabID) -> [PermissionRequestID] {
    recorder.events(for: id).compactMap { if case .permissionEnded(_, let request) = $0 { request } else { nil } }
  }

  public static func permissionIsReportedAnsweredAndEndedOnce(_ h: EngineHarness) async throws {
    let raise = try driver(h.raisePermission, "raisePermission")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Permission"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, [.geolocation, .microphone])
    try await waitUntil(timeout: .seconds(10)) { !requestedPermissions(recorder, id).isEmpty }
    let request = try requireValue(requestedPermissions(recorder, id).first, "permission request")
    try require(request.tab == id && request.kinds == [.geolocation, .microphone] && request.items.count == 2
                  && !request.title.isEmpty && !request.origin.isEmpty && !request.allowTitle.isEmpty
                  && !request.blockTitle.isEmpty, "the request must carry the engine's values: \(request)")
    engine.respond(toPermission: request.id, choice: .allow)
    engine.respond(toPermission: request.id, choice: .block)
    try await waitUntil(timeout: .seconds(10)) { !endedPermissions(recorder, id).isEmpty }

    // Events arrive in order: if the second answer had ended it again, that end would come before this request.
    try await raise(engine, id, [.notifications])
    try await waitUntil(timeout: .seconds(10)) { requestedPermissions(recorder, id).count == 2 }
    try require(endedPermissions(recorder, id) == [request.id],
                "an answered request must end once: \(recorder.events(for: id))")
    let second = try requireValue(requestedPermissions(recorder, id).last, "second request")
    try require(second.kinds == [.notifications], "the second ask is notifications: \(second)")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  public static func pendingPermissionEndsBeforeItsTabCloses(_ h: EngineHarness) async throws {
    let raise = try driver(h.raisePermission, "raisePermission")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Permission"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, [.camera])
    try await waitUntil(timeout: .seconds(10)) { !requestedPermissions(recorder, id).isEmpty }
    let request = try requireValue(requestedPermissions(recorder, id).first, "permission request")
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try await waitUntil(timeout: .seconds(10)) { recorder.events(for: id).contains { if case .tabClosed = $0 { true } else { false } } }
    let tail = Array(recorder.events(for: id).suffix(2))
    try require(tail == [.permissionEnded(id, request.id), .tabClosed(id, reason: .client)],
                "the request must end before the tab closes: \(tail)")
    engine.respond(toPermission: request.id, choice: .allow)        // ended: nothing happens
  }

  public static func navigationEndsItsPermission(_ h: EngineHarness) async throws {
    let raise = try driver(h.raisePermission, "raisePermission")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Permission"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, [.geolocation])
    try await waitUntil(timeout: .seconds(10)) { !requestedPermissions(recorder, id).isEmpty }
    let request = try requireValue(requestedPermissions(recorder, id).first, "permission request")
    engine.navigate(id, to: try h.pageURL("Elsewhere"))
    try await waitUntil(timeout: .seconds(10)) { endedPermissions(recorder, id).contains(request.id) }
    engine.respond(toPermission: request.id, choice: .allow)        // ended: nothing happens
    try require(endedPermissions(recorder, id) == [request.id], "a navigation ends it once: \(recorder.events(for: id))")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  public static func hiddenTabEndsItsPermissionAndAsksAgain(_ h: EngineHarness) async throws {
    let raise = try driver(h.raisePermission, "raisePermission")
    let engine = h.makeEngine()
    let window = engine.createWindow(host: h.makeWindowHost())
    let shown = engine.createTab(url: try h.pageURL("Permission"), in: window)
    let other = engine.createTab(url: try h.pageURL("Other"), in: window)
    try await h.settle(engine, shown)
    try await h.settle(engine, other)
    try await wait("the first tab to be active") { engine.activeTab(in: window) == shown }
    let recorder = EventRecorder(engine)
    try await raise(engine, shown, [.geolocation])
    try await waitUntil(timeout: .seconds(10)) { requestedPermissions(recorder, shown).count == 1 }
    let first = try requireValue(requestedPermissions(recorder, shown).first, "permission request")
    engine.activateTab(other)
    try await waitUntil(timeout: .seconds(10)) { endedPermissions(recorder, shown).contains(first.id) }
    engine.respond(toPermission: first.id, choice: .allow)                  // ended: nothing happens
    engine.activateTab(shown)
    try await waitUntil(timeout: .seconds(10)) { requestedPermissions(recorder, shown).count == 2 }
    let again = try requireValue(requestedPermissions(recorder, shown).last, "second request")
    try require(again.id != first.id && again.items == first.items && again.kinds == first.kinds,
                "a shown tab asks again with a new request: \(recorder.events(for: shown))")
    try require(endedPermissions(recorder, shown) == [first.id], "the first request ended once: \(recorder.events(for: shown))")
    engine.respond(toPermission: again.id, choice: .block)
  }

  // MARK: Rule 21 (#400)

  static func infobarLists(_ recorder: EventRecorder, _ id: TabID) -> [[Infobar]] {
    recorder.events(for: id).compactMap { if case .infobarsChanged(_, let list) = $0 { list } else { nil } }
  }

  public static func infobarIsReportedActedOnAndRemoved(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseInfobar, "raiseInfobar")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Infobar"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, "Hello")
    try await waitUntil(timeout: .seconds(10)) { !infobarLists(recorder, id).isEmpty }
    let infobar = try requireValue(infobarLists(recorder, id).last?.first, "infobar")
    try require(infobar.tab == id && infobar.message.contains("Hello") && infobar.ok != nil && infobar.isCloseable,
                "the infobar must carry the engine's values: \(infobar)")
    engine.act(on: infobar.id, action: .ok)
    try await waitUntil(timeout: .seconds(10)) { infobarLists(recorder, id).last?.isEmpty == true }
    engine.act(on: infobar.id, action: .close)                 // gone: nothing happens

    // Events arrive in order: had the second action reported again, it would come before this second infobar.
    try await raise(engine, id, "Again")
    try await waitUntil(timeout: .seconds(10)) { infobarLists(recorder, id).count == 3 }
    try require(infobarLists(recorder, id).map(\.count) == [1, 0, 1],
                "an acted-on infobar must leave once: \(recorder.events(for: id))")
    let second = try requireValue(infobarLists(recorder, id).last?.first, "second infobar")
    try require(second.id != infobar.id, "a new infobar has a new id")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  public static func infobarsStayWithTheirTabWhileHidden(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseInfobar, "raiseInfobar")
    let engine = h.makeEngine()
    let window = engine.createWindow(host: h.makeWindowHost())
    let first = engine.createTab(url: try h.pageURL("First"), in: window)
    let second = engine.createTab(url: try h.pageURL("Second"), in: window)
    try await h.settle(engine, first)
    try await h.settle(engine, second)
    try await wait("the first tab to be active") { engine.activeTab(in: window) == first }
    let recorder = EventRecorder(engine)
    try await raise(engine, first, "Mine")
    try await waitUntil(timeout: .seconds(10)) { !infobarLists(recorder, first).isEmpty }
    let infobar = try requireValue(infobarLists(recorder, first).last?.first, "infobar")
    engine.activateTab(second)
    try await wait("the second tab to be active") { engine.activeTab(in: window) == second }
    engine.activateTab(first)
    try await wait("the first tab to be active again") { engine.activeTab(in: window) == first }
    try require(infobarLists(recorder, first).count == 1 && infobarLists(recorder, second).isEmpty,
                "switching tabs must not change either list: \(recorder.events)")
    engine.act(on: infobar.id, action: .ok)
    try await waitUntil(timeout: .seconds(10)) { infobarLists(recorder, first).last?.isEmpty == true }
    engine.closeTab(first, mode: .skipUnloadHandlers)
    engine.closeTab(second, mode: .skipUnloadHandlers)
  }

  public static func pendingInfobarsEndBeforeTheirTabCloses(_ h: EngineHarness) async throws {
    let raise = try driver(h.raiseInfobar, "raiseInfobar")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Infobar"))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await raise(engine, id, "Hello")
    try await waitUntil(timeout: .seconds(10)) { !infobarLists(recorder, id).isEmpty }
    let infobar = try requireValue(infobarLists(recorder, id).last?.first, "infobar")
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try await waitUntil(timeout: .seconds(10)) { recorder.events(for: id).contains { if case .tabClosed = $0 { true } else { false } } }
    let tail = Array(recorder.events(for: id).suffix(2))
    try require(tail == [.infobarsChanged(id, []), .tabClosed(id, reason: .client)],
                "the list must empty before the tab closes: \(tail)")
    engine.act(on: infobar.id, action: .ok)                    // gone: nothing happens
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
