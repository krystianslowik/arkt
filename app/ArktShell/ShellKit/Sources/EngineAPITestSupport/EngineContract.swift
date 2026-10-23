import AppKit
import EngineAPI

public struct ContractViolation: Error, CustomStringConvertible {
  public let description: String
}

/// Everything an engine-specific test needs to drive the shared contract.
@MainActor
public struct EngineHarness {
  public let makeEngine: @MainActor () -> any EngineClient
  /// A URL whose page has `<title>title</title>` and needs no network.
  public let pageURL: @MainActor (_ title: String) throws -> URL
  /// Drives (in-memory) or waits for (real engines) the end of the current load of `id`.
  public let settle: @MainActor (_ engine: any EngineClient, _ id: TabID) async throws -> Void
  /// Changes the loaded document's title the way page script would (`document.title = title`).
  public let retitle: @MainActor (_ engine: any EngineClient, _ id: TabID, _ title: String) async throws -> Void
  /// Two pages on different hosts, each declaring a favicon the engine will pick up.
  public let pagesOnTwoHosts: @MainActor () throws -> (URL, URL)

  public init(makeEngine: @escaping @MainActor () -> any EngineClient,
              pageURL: @escaping @MainActor (String) throws -> URL,
              settle: @escaping @MainActor (any EngineClient, TabID) async throws -> Void,
              retitle: @escaping @MainActor (any EngineClient, TabID, String) async throws -> Void,
              pagesOnTwoHosts: @escaping @MainActor () throws -> (URL, URL)) {
    self.makeEngine = makeEngine; self.pageURL = pageURL; self.settle = settle
    self.retitle = retitle; self.pagesOnTwoHosts = pagesOnTwoHosts
  }

  /// In-memory pages: the title is the last path component; every finished load carries a favicon.
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
      }
    )
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
    let closes = recorder.events(for: id).filter { $0 == .tabClosed(id) }.count
    try require(closes == 1 && recorder.events(for: id).last == .tabClosed(id), "tabClosed must be last and once")
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
    try require(seen.last == .tabClosed(id) && seen.filter { $0 == .tabClosed(id) }.count == 1,
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

  static func requireValue<T>(_ value: T?, _ what: String = "value") throws -> T {
    guard let value else { throw ContractViolation(description: "missing \(what)") }
    return value
  }
}
