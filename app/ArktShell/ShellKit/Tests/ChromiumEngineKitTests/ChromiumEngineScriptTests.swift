import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Scripts beyond the shared contract: batch reordering, Decision 4's deduplication, deferred (nested-loop) calls,
/// contents replacement, moves, engine-initiated windows, instance scoping, hosting, extensions, quit, the test API.
@MainActor
struct ChromiumEngineScriptTests {
  let facade = ScriptedFacade()

  func makeEngine() -> (ChromiumEngine, EngineWindowID, StubWindowHost) {
    let engine = ChromiumEngine(facade: facade)
    let host = StubWindowHost()
    return (engine, engine.createWindow(host: host), host)
  }

  func delivered() async throws {
    try await ScriptedWait.until("the facade to deliver its batch") { facade.isIdle }
  }

  func scriptedTab(_ engine: ChromiumEngine, _ id: TabID) throws -> ScriptedTab {
    try #require(engine.handle(of: id) as? ScriptedTab)
  }

  func scriptedBrowser(_ engine: ChromiumEngine, _ id: EngineWindowID) throws -> ScriptedBrowser {
    try #require(engine.windows[id]?.browser as? ScriptedBrowser)
  }

  // MARK: Parked duplicates (#380)

  /// A duplicate is a parked copy: it carries the page and its history, never takes the window's active tab, and
  /// loads only when it is shown (activated). The facade keeps it outside the tab strip, so extensions never see it.
  @Test func duplicateIsParkedUntilItIsShown() async throws {
    let (engine, window, _) = makeEngine()
    let first = URL(string: "arkt-test://alpha.test/First")!
    let second = URL(string: "arkt-test://alpha.test/Second")!
    let id = engine.createTab(url: first, in: window)
    try scriptedTab(engine, id).finishLoad()
    engine.navigate(id, to: second)
    try scriptedTab(engine, id).finishLoad()
    try await delivered()

    let copy = try #require(engine.duplicateTab(id))
    try await delivered()
    let parked = try #require(engine.snapshot(of: copy))
    #expect(parked.url == second && parked.canGoBack && !parked.isLoading, "the copy holds the page without loading")
    #expect(!parked.isActive && engine.snapshot(of: id)?.isActive == true, "the copy never displaces the active tab")
    #expect(engine.activeTab(in: window) == id)
    #expect(engine.history(of: copy)?.back.map(\.url) == [first], "the copy keeps the back and forward history")

    engine.activateTab(copy)
    try await delivered()
    #expect(engine.snapshot(of: copy)?.isActive == true && engine.activeTab(in: window) == copy)
    #expect(engine.snapshot(of: copy)?.isLoading == true, "shown, the copy loads")
  }

  /// A parked copy ends with its window and is never shown into a closing one (#380).
  @Test func parkedCopyEndsWithItsWindowAndIsNotShownAfterwards() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "arkt-test://alpha.test/First")!, in: window)
    try scriptedTab(engine, id).finishLoad()
    let copy = try #require(engine.duplicateTab(id))
    try await delivered()
    engine.closeWindow(window)
    try await delivered()
    #expect(engine.snapshot(of: copy) == nil)
    #expect(recorder.events(for: copy).last == .tabClosed(copy, reason: .windowClosing))
    engine.activateTab(copy)
    try await delivered()
    #expect(engine.snapshot(of: copy) == nil && engine.activeTab(in: window) == nil)
  }

  // MARK: Batches

  @Test func titleRecordedAfterLoadEndIsDeliveredBeforeIt() async throws {
    facade.titleAfterLoadEnd = true
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let first = URL(string: "arkt-test://alpha.test/First")!
    let id = engine.createTab(url: first, in: window)
    try scriptedTab(engine, id).finishLoad()
    try await delivered()
    engine.navigate(id, to: URL(string: "arkt-test://beta.test/Second")!)
    try scriptedTab(engine, id).finishLoad()
    try await delivered()

    // The facade recorded the title and the favicon clear after the load end, in one batch...
    let last = try #require(facade.batches.last)
    let kinds = last.map(\.kind)
    let end = try #require(kinds.firstIndex(of: .loadingChanged).flatMap { start in
      kinds[(start + 1)...].firstIndex(of: .loadingChanged)
    })
    #expect(kinds[end...].contains(.titleChanged) && kinds[end...].contains(.faviconChanged))
    // ...and the shell got them before it.
    let events = recorder.events(for: id)
    let title = try #require(events.lastIndex(of: .titleChanged(id, "Second")))
    let cleared = try #require(events.lastIndex(of: .faviconChanged(id, nil)))
    let loadEnd = try #require(events.lastIndex(of: .loadingChanged(id, isLoading: false)))
    #expect(title < loadEnd && cleared < loadEnd)
  }

  @Test func reorderingStaysWithinOneLoad() {
    let tab = ScriptedTab(facade: facade, owner: ScriptedBrowser(facade: facade, host: AdapterProbeHost()),
                          opener: nil, origin: .client)
    func event(_ kind: ArktEngineEventKind, loading: Bool = false, title: String? = nil) -> ScriptedEvent {
      let event = ScriptedEvent(kind, tab: tab, browser: nil)
      event.isLoading = loading
      event.title = title
      return event
    }
    let batch: [any ArktEngineEvent] = [
      event(.loadingChanged, loading: false), event(.titleChanged, title: "A"),
      event(.urlChanged), event(.loadingChanged, loading: true), event(.titleChanged, title: "B"),
    ]
    let reordered = ChromiumEngine.reordered(batch).map { ($0.kind, $0.title) }
    // "A" moves before its load end; "B" belongs to the next load and stays.
    #expect(reordered.map(\.0) == [.titleChanged, .loadingChanged, .urlChanged, .loadingChanged, .titleChanged])
    #expect(reordered.map(\.1) == ["A", nil, nil, nil, "B"])
  }

  /// Decision 4: the client's calls are announced at once and the facade's own events for them are dropped.
  @Test func clientCreateAndCloseAreAnnouncedOnce() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil, in: window)
    #expect(recorder.events(for: id) == [.tabCreated(id)])
    try await delivered()
    engine.closeTab(id)
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .client))
    try await delivered()
    #expect(engine.retired.isEmpty, "the facade's own TabClosed releases the retired handle")
    let all = facade.batches.flatMap { $0 }.map(\.kind)
    #expect(all.contains(.tabCreated) && all.contains(.tabClosed), "the facade reported both")
    #expect(recorder.events(for: id).filter { if case .tabCreated = $0 { true } else { false } }.count == 1)
    #expect(recorder.events(for: id).filter { if case .tabClosed = $0 { true } else { false } }.count == 1)
  }

  @Test func secondCloseWhileHeldDoesNothing() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "arkt-test://page.test/Held")!, in: window)
    let tab = try scriptedTab(engine, id)
    tab.finishLoad()
    tab.wouldHoldClose = true
    engine.closeTab(id)
    engine.closeTab(id, mode: .skipUnloadHandlers)
    #expect(engine.snapshot(of: id)?.isClosing == true && engine.tabIDs.contains(id))
    #expect(tab.answer(accept: true))
    try await delivered()
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .client))
    #expect(engine.snapshot(of: id) == nil)
  }

  // MARK: The initial about:blank (W3-9)

  /// Records what the real facade reported for a tab created without a URL (W3-9 contract runner, run 1).
  func record(_ kind: ArktEngineEventKind, on tab: ScriptedTab, _ fill: (ScriptedEvent) -> Void = { _ in }) {
    let event = ScriptedEvent(kind, tab: tab, browser: tab.owner)
    fill(event)
    facade.record(event)
  }

  func pageEvents(_ recorder: EventRecorder, _ id: TabID) -> [EngineEvent] {
    recorder.events(for: id).filter { event in
      switch event {
      case .urlChanged, .loadingChanged, .titleChanged: true
      default: false
      }
    }
  }

  @Test func initialBlankLoadIsNotReportedAndTheFirstPageIsInOrder() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil, in: window)
    let tab = try scriptedTab(engine, id)
    try await delivered()
    let page = URL(string: "arkt-test://page.test/Page")!
    let blank = URL(string: "about:blank")!
    // Chromium: the about:blank load starts before the first navigation's URL and commits after it.
    record(.loadingChanged, on: tab) { $0.isLoading = true }
    try await delivered()
    #expect(engine.snapshot(of: id)?.isLoading == false)
    record(.urlChanged, on: tab) { $0.url = page }
    record(.urlChanged, on: tab) { $0.url = blank }
    record(.urlChanged, on: tab) { $0.url = page }
    record(.titleChanged, on: tab) { $0.title = "Page" }
    record(.loadingChanged, on: tab) { $0.isLoading = false }
    try await delivered()
    #expect(pageEvents(recorder, id) == [.urlChanged(id, page), .loadingChanged(id, isLoading: true),
                                         .urlChanged(id, page), .titleChanged(id, "Page"),
                                         .loadingChanged(id, isLoading: false)])
    // After the first page loaded, about:blank is an ordinary URL again.
    record(.urlChanged, on: tab) { $0.url = blank }
    try await delivered()
    #expect(pageEvents(recorder, id).last == .urlChanged(id, blank))
  }

  @Test func blankTabThatNeverNavigatesReportsNoLoad() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil, in: window)
    let tab = try scriptedTab(engine, id)
    record(.loadingChanged, on: tab) { $0.isLoading = true }
    record(.urlChanged, on: tab) { $0.url = URL(string: "about:blank")! }
    record(.loadingChanged, on: tab) { $0.isLoading = false }
    try await delivered()
    #expect(pageEvents(recorder, id).isEmpty)
    #expect(engine.snapshot(of: id)?.isLoading == false)
  }

  /// A window close marks all its tabs closing (the real facade, W3-9); a tab the shell drops meanwhile still closes.
  @Test func skipUnloadHandlersClosesATabThatIsClosing() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil, in: window)
    try scriptedTab(engine, id).isClosing = true
    engine.closeTab(id, mode: .skipUnloadHandlers)
    #expect(engine.snapshot(of: id) == nil)
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .client))
  }

  /// The real facade closes under `ScopedSkipUnloadHandlers` even while the window close shows the tab's leave-site
  /// dialog (#302 review).
  @Test func skipUnloadHandlersClosesATabShowingTheWindowCloseDialog() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "arkt-test://page.test/Held")!, in: window)
    let tab = try scriptedTab(engine, id)
    tab.finishLoad()
    _ = try await engine.evaluateScript("window.onbeforeunload = () => true", in: id, userGesture: true)
    try await delivered()
    engine.closeWindow(window)
    try await delivered()
    #expect(tab.dialog != nil && engine.snapshot(of: id)?.isClosing == true)
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try await delivered()
    #expect(engine.snapshot(of: id) == nil)
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .client))
  }

  // MARK: Nested run loops (Decision 3)

  @Test func deferredCallsQueueBehindTheInsert() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    try await delivered()
    facade.isNested = true
    let id = engine.createTab(url: nil, in: window)
    #expect(recorder.events(for: id) == [.tabCreated(id)], "announced at once, though not inserted yet")
    #expect(try scriptedTab(engine, id).sessionId == -1)
    engine.navigate(id, to: URL(string: "arkt-test://page.test/Queued")!)
    engine.closeTab(id)
    #expect(engine.snapshot(of: id)?.isClosing == true, "a deferred close answers held")
    facade.isNested = false
    try await delivered()
    #expect(engine.snapshot(of: id) == nil)
    let events = recorder.events(for: id)
    #expect(events.first == .tabCreated(id) && events.last == .tabClosed(id, reason: .client))
    #expect(events.filter { if case .tabClosed = $0 { true } else { false } }.count == 1)
  }

  @Test func deferredInsertIntoAClosedWindowEndsTheTab() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    facade.isNested = true
    let id = engine.createTab(url: nil, in: window)
    engine.closeWindow(window)
    facade.isNested = false
    try await delivered()
    #expect(recorder.events(for: id) == [.tabCreated(id), .tabClosed(id, reason: .windowClosing)])
    #expect(recorder.windowEvents.last == .windowClosed(window, reason: .userClose))
  }

  // MARK: Contents, moves

  @Test func replacedContentsKeepTheContainerAndTheID() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: URL(string: "arkt-test://page.test/Crashy")!, in: window)
    let tab = try scriptedTab(engine, id)
    tab.finishLoad()
    let container = try #require(engine.contentView(for: id))
    let session = tab.sessionId
    try await delivered()
    let mark = recorder.events.count
    tab.replaceContents()
    tab.reload()
    try await delivered()
    #expect(tab.sessionId != session)
    #expect(engine.contentView(for: id) === container)
    #expect(Array(recorder.events.dropFirst(mark)) == [.loadingChanged(id, isLoading: true)])
  }

  @Test func movesRouteByWindowAndLeaveForeignWindows() async throws {
    let (engine, first, _) = makeEngine()
    let second = engine.createWindow(host: StubWindowHost())
    let other = ChromiumEngine(facade: facade)
    let foreign = other.createWindow(host: StubWindowHost())
    var inSecond: [EngineEvent] = []
    let routed = engine.observe(window: second) { inSecond.append($0) }
    let recorder = EventRecorder(engine)
    let otherRecorder = EventRecorder(other)
    let id = engine.createTab(url: nil, in: first)
    try await delivered()

    try scriptedBrowser(engine, first).move(scriptedTab(engine, id), to: scriptedBrowser(engine, second))
    try await delivered()
    #expect(engine.snapshot(of: id)?.window == second)
    #expect(inSecond.contains(.activeTabChanged(id)), "events now route to the new window")

    let tab = try scriptedTab(engine, id)
    try scriptedBrowser(engine, second).move(tab, to: scriptedBrowser(other, foreign))
    try await delivered()
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .extension))
    let adopted = try #require(other.tabIDs.first)
    #expect(otherRecorder.events(for: adopted).first == .tabCreated(adopted))
    #expect(other.contentView(for: adopted) === tab.containerView)
    routed.cancel()
  }

  // MARK: Engine-initiated windows (Decision 2)

  @Test func providerWindowIsListedAfterWindowOpened() async throws {
    let engine = ChromiumEngine(facade: facade)
    let opener = engine.createWindow(host: StubWindowHost())
    var requests: [EngineWindowRequest] = []
    let host = StubWindowHost()
    engine.windowHostProvider = { request in
      requests.append(request)
      return host
    }
    facade.hostProvider = { engine.host(for: $0) }
    let recorder = EventRecorder(engine)
    let url = URL(string: "arkt-test://page.test/FromExtension")!
    let frame = NSRect(x: 300, y: 200, width: 700, height: 500)
    let browser = try #require(facade.openEngineWindow(
      ScriptedRequest(kind: .extension, opener: try scriptedBrowser(engine, opener), bounds: frame, initialURL: url)))
    #expect(requests == [EngineWindowRequest(kind: .extension, openerWindow: opener, bounds: frame,
                                             profile: EngineProfileID("Default"), initialURL: url)])
    #expect(engine.windowIDs == [opener], "not listed before the facade's WindowOpened")
    #expect(host.onCloseRequested != nil, "the engine set the host's blocks inside construction")
    try await delivered()
    let window = try #require(engine.windowIDs.last)
    #expect(engine.windowIDs.count == 2 && recorder.windowEvents == [.windowOpened(window)])
    let tab = try #require(engine.tabIDs.first)
    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(snapshot.window == window && snapshot.origin == .engine && snapshot.isActive)
    let opened = try #require(recorder.log.firstIndex(of: .window(.windowOpened(window))))
    let created = try #require(recorder.log.firstIndex(of: .tab(.tabCreated(tab))))
    #expect(opened < created)
    #expect(engine.windows[window]?.browser === browser)
  }

  // MARK: Dock reopen (#299)

  /// An engine with a host provider over the facade; the opener window comes first, as in the app.
  func makeProviderEngine() -> (ChromiumEngine, EventRecorder) {
    let engine = ChromiumEngine(facade: facade)
    engine.windowHostProvider = { _ in StubWindowHost() }
    facade.hostProvider = { engine.host(for: $0) }
    return (engine, EventRecorder(engine))
  }

  /// Chromium adds its New Tab page to the window of a Dock reopen. The window is listed and announced; the page is
  /// not, so the shell shows an empty window and adds no Today row.
  @Test func reopenWindowKeepsItsNewTabPageUnlisted() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (browser, page) = try #require(facade.dockReopen())
    try await delivered()
    let window = try #require(engine.windowIDs.first)
    #expect(recorder.windowEvents == [.windowOpened(window)])
    #expect(engine.tabIDs.isEmpty && recorder.events.isEmpty)
    #expect(engine.activeTab(in: window) == nil && engine.latestActiveTab(in: window) == nil)
    #expect(page.owner === browser && !browser.isClosed, "the page keeps the Browser open")
  }

  /// Chromium may insert the page before its navigation starts: the tab is created without a URL (the initial
  /// `about:blank`) and the New Tab page's URL follows. It is kept back all the same (real app, #299).
  @Test func newTabPageInsertedBeforeItsURLIsKeptBack() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (browser, page) = try #require(facade.dockReopen(urlAtInsert: false))
    try await delivered()
    page.finishLoad()
    try await delivered()
    #expect(page.owner === browser && page.url == ScriptedFacade.newTabPage)
    #expect(engine.tabIDs.isEmpty && recorder.events.isEmpty)
  }

  /// The first tab the shell opens in that window is the window's active tab, and the New Tab page closes then,
  /// without an event (it was never announced) and without closing the window.
  @Test func firstClientTabClosesTheReopenWindowsNewTabPage() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (browser, page) = try #require(facade.dockReopen())
    try await delivered()
    let window = try #require(engine.windowIDs.first)
    let tab = engine.createTab(url: URL(string: "arkt-test://page.test/First")!, in: window)
    try await delivered()
    #expect(page.owner == nil, "the New Tab page closed")
    #expect(!browser.isClosed && engine.windowIDs == [window])
    #expect(engine.tabIDs == [tab] && engine.activeTab(in: window) == tab)
    #expect(!recorder.events.contains { $0.tabID != tab })
    #expect(!recorder.events.contains { if case .tabClosed = $0 { true } else { false } })
    #expect(recorder.windowEvents == [.windowOpened(window)])
  }

  /// A tab an extension creates there (`chrome.tabs.create`) is listed as usual and also replaces the page.
  @Test func engineTabClosesTheReopenWindowsNewTabPage() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (browser, page) = try #require(facade.dockReopen())
    try await delivered()
    facade.engineCreateTab(in: browser, url: URL(string: "arkt-test://page.test/Created")!, opener: nil, active: true)
    try await delivered()
    #expect(page.owner == nil && !browser.isClosed)
    let tab = try #require(engine.tabIDs.first)
    #expect(engine.tabIDs.count == 1 && engine.snapshot(of: tab)?.origin == .engine)
    #expect(recorder.events.first == .tabCreated(tab))
    #expect(!recorder.events.contains { if case .tabClosed = $0 { true } else { false } })
  }

  /// A menu command with no window (Show All History) opens its page in the New Tab page's tab: the tab is listed
  /// then, with that URL, as the window's active tab.
  @Test func newTabPageThatNavigatesIsListed() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (_, page) = try #require(facade.dockReopen())
    let history = URL(string: "chrome://history/")!
    page.startLoad(history, title: "History")
    try await delivered()
    let window = try #require(engine.windowIDs.first)
    let tab = try #require(engine.tabIDs.first)
    #expect(engine.tabIDs.count == 1)
    #expect(engine.snapshot(of: tab)?.url == history && engine.activeTab(in: window) == tab)
    #expect(recorder.events.prefix(2) == [.tabCreated(tab), .activeTabChanged(tab)])
    #expect(engine.contentView(for: tab) === page.containerView)
  }

  /// A listed tab an extension moves into that window (`chrome.tabs.move`) replaces the page too.
  @Test func listedTabMovedInClosesTheReopenWindowsNewTabPage() async throws {
    let (engine, recorder) = makeProviderEngine()
    let opener = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: URL(string: "arkt-test://page.test/Moved")!, in: opener)
    let (browser, page) = try #require(facade.dockReopen())
    try await delivered()
    let window = try #require(engine.windowIDs.last)
    try scriptedBrowser(engine, opener).move(scriptedTab(engine, tab), to: browser)
    try await delivered()
    #expect(page.owner == nil && !browser.isClosed)
    #expect(engine.snapshot(of: tab)?.window == window && browser.tabs.count == 1)
    #expect(!recorder.events.contains { if case .tabClosed = $0 { true } else { false } })
  }

  /// Closing the empty window closes the page with it; the shell sees only `.windowClosed`.
  @Test func closingTheEmptyReopenWindowReportsOnlyTheWindow() async throws {
    let (engine, recorder) = makeProviderEngine()
    let (browser, _) = try #require(facade.dockReopen())
    try await delivered()
    let window = try #require(engine.windowIDs.first)
    browser.close()
    try await delivered()
    #expect(engine.windowIDs.isEmpty && recorder.events.isEmpty)
    #expect(recorder.windowEvents == [.windowOpened(window), .windowClosed(window, reason: .userClose)])
  }

  /// A startup window without a URL (the first Dock reopen of a session can take Chromium's startup path) keeps its
  /// New Tab page back too; a startup URL's own tab is listed at once.
  @Test func startupWindowKeepsItsNewTabPageButListsAURL() async throws {
    let (engine, recorder) = makeProviderEngine()
    _ = try #require(facade.dockReopen(kind: .startupURL))
    try await delivered()
    #expect(engine.tabIDs.isEmpty && recorder.events.isEmpty)
    let url = URL(string: "arkt-test://page.test/FromAnotherApp")!
    let browser = try #require(facade.openEngineWindow(ScriptedRequest(kind: .startupURL, initialURL: url)))
    try await delivered()
    let tab = try #require(engine.tabIDs.first)
    #expect(engine.tabIDs.count == 1 && engine.snapshot(of: tab)?.url == url)
    #expect(engine.activeTab(in: try #require(engine.windowIDs.last)) == tab)
    #expect(browser.tabs.count == 1)
  }

  /// Only a Dock reopen's or startup window's page is kept back: a New Tab page in a window an extension asked for
  /// is a tab like any other.
  @Test func newTabPageOfOtherRequestKindsIsListed() async throws {
    let (engine, recorder) = makeProviderEngine()
    _ = try #require(facade.dockReopen(kind: .extension))
    try await delivered()
    let tab = try #require(engine.tabIDs.first)
    #expect(engine.snapshot(of: tab)?.url == ScriptedFacade.newTabPage)
    #expect(recorder.events.first == .tabCreated(tab))
  }

  // MARK: Instance scoping

  @Test func instancesOverOneFacadeSeeOnlyTheirOwnWindowsAndTabs() async throws {
    let a = ChromiumEngine(facade: facade)
    let b = ChromiumEngine(facade: facade)
    let recordA = EventRecorder(a)
    let recordB = EventRecorder(b)
    let windowA = a.createWindow(host: StubWindowHost())
    let windowB = b.createWindow(host: StubWindowHost())
    let tabA = a.createTab(url: URL(string: "arkt-test://page.test/A")!)
    let tabB = b.createTab(url: URL(string: "arkt-test://page.test/B")!)
    try scriptedTab(a, tabA).finishLoad()
    try await delivered()
    facade.engineCreateTab(in: try scriptedBrowser(b, windowB), url: nil, opener: nil, active: false)
    try await delivered()
    #expect(a.windowIDs == [windowA] && b.windowIDs == [windowB])
    #expect(a.tabIDs == [tabA] && b.tabIDs.first == tabB && b.tabIDs.count == 2)
    #expect(recordA.events.allSatisfy { $0.tabID == tabA })
    #expect(!recordB.events.contains { $0.tabID == tabA })
    #expect(recordA.windowEvents == [.windowOpened(windowA)] && recordB.windowEvents == [.windowOpened(windowB)])
    #expect(a.snapshot(of: tabB) == nil && a.contentView(for: tabB) == nil)
  }

  @Test func createTabWithoutAWindowIsAPreconditionFailure() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        let engine = ChromiumEngine(facade: ScriptedFacade())
        engine.createTab(url: nil)
      }
    }
  }

  @Test func releasedEngineRemovesItsSink() async throws {
    var engine: ChromiumEngine? = ChromiumEngine(facade: facade)
    #expect(facade.sinkCount == 1)
    _ = engine?.createWindow(host: StubWindowHost())
    engine = nil
    #expect(facade.sinkCount == 0)
    try await delivered()
  }

  // MARK: Hosting

  @Test func hostClaimsComeFirstThenTheEngine() async throws {
    let (engine, window, host) = makeEngine()
    host.claims[.newTab] = CommandClaim(isEnabled: false)
    let forward = try #require(host.forward)
    #expect(forward.validate(.newTab) == false, "the shell's claim answers")
    #expect(forward.validate(.reload), "the engine answers an unclaimed command")
    forward.execute(.newTab, .newForegroundTab)
    forward.execute(.reload, .currentTab)
    #expect(host.performed.map(\.0) == [.newTab])
    let browser = try scriptedBrowser(engine, window)
    #expect(browser.executed.map(\.command) == [EngineCommand.reload.rawValue])
    #expect(browser.executed.map(\.disposition) == [EngineDisposition.currentTab.rawValue])

    let close = try #require(host.onCloseRequested)
    close()
    try await delivered()
    #expect(!engine.windowIDs.contains(window))
    #expect(host.forward == nil && host.onCloseRequested == nil, "a closed window leaves the host no engine closures")
  }

  // MARK: Extensions, quit, test API

  @Test func extensionActionsAndTheirChanges() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let icon = Data([1, 2, 3])
    facade.setActions([ScriptedAction(actionId: "probe", name: "Probe", iconPNG: icon, isEnabled: false)],
                      in: try scriptedBrowser(engine, window))
    try await delivered()
    #expect(recorder.windowEvents.contains(.extensionActionsChanged(window)))
    #expect(engine.extensionActions(in: window) == [ExtensionAction(id: "probe", name: "Probe", iconPNG: icon,
                                                                    isEnabled: false)])
    let anchor = NSView()
    engine.runExtensionAction("probe", in: window, anchor: anchor)
    #expect(facade.ranActions.count == 1 && facade.ranActions.first?.anchor === anchor)
    #expect((engine as Any) is any EngineExtensions)
  }

  @Test func quitClosesTabsWithAppTerminating() async throws {
    let (engine, window, _) = makeEngine()
    let recorder = EventRecorder(engine)
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    try await delivered()
    facade.terminate()
    try await delivered()
    #expect(recorder.events(for: a).last == .tabClosed(a, reason: .appTerminating))
    #expect(recorder.events(for: b).last == .tabClosed(b, reason: .appTerminating))
    #expect(recorder.windowEvents.last == .windowClosed(window, reason: .appQuit) && engine.windowIDs.isEmpty)
  }

  @Test func testAPIAnswersValuesAndErrors() async throws {
    let (engine, window, _) = makeEngine()
    let id = engine.createTab(url: nil, in: window)
    #expect(engine.testAPIEnabled)
    let value = try await engine.evaluateScript("({sum: 1 + 2, list: [1, \"two\", null], ok: true})", in: id,
                                                userGesture: false)
    #expect(value == .object(["sum": .number(3), "list": .array([.number(1), .string("two"), .null]),
                              "ok": .bool(true)]))
    #expect(!engine.answerDialog(in: id, accept: true), "no dialog pending")
    facade.testAPIEnabled = false
    await #expect(throws: EngineTestAPIError.self) {
      try await engine.evaluateScript("1", in: id, userGesture: false)
    }
    await #expect(throws: EngineTestAPIError.self) {
      try await engine.evaluateScript("1", in: TabID(), userGesture: false)
    }
  }
}

/// A bare `ArktWindowHost` for scripted browsers that need no engine.
final class AdapterProbeHost: NSObject, ArktWindowHost {
  let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
  let cardView = NSView()
  var closeRequested: (() -> Void)?
  var validateCommand: ((Int) -> Bool)?
  var executeCommand: ((Int, Int) -> Void)?
}
