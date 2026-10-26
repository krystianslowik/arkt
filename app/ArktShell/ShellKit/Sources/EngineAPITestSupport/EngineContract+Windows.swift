import AppKit
import EngineAPI

// MARK: - Rules 11-16: windows, activation, engine-side tabs, held closes

extension EngineContract {
  static let eventTimeout: Duration = .seconds(10)

  static func driver<T>(_ value: T?, _ name: String) throws -> T {
    guard let value else { throw ContractNotApplicable(driver: name) }
    return value
  }

  static func tabs(of engine: any EngineClient, in window: EngineWindowID) -> [TabID] {
    engine.tabIDs.filter { engine.snapshot(of: $0)?.window == window }
  }

  static func activeCount(_ engine: any EngineClient, in window: EngineWindowID) -> Int {
    tabs(of: engine, in: window).filter { engine.snapshot(of: $0)?.isActive == true }.count
  }

  static func closes(_ recorder: EventRecorder, _ id: TabID) -> [CloseReason] {
    recorder.events(for: id).compactMap { if case .tabClosed(_, let reason) = $0 { reason } else { nil } }
  }

  /// The reasons of every `.windowClosed` reported for `window`, in order.
  static func windowCloses(_ recorder: EventRecorder, _ window: EngineWindowID) -> [WindowCloseReason] {
    recorder.windowEvents.compactMap {
      if case .windowClosed(window, let reason) = $0 { reason } else { nil }
    }
  }

  static func wait(_ what: @autoclosure () -> String, _ condition: @MainActor () -> Bool) async throws {
    do {
      try await waitUntil(timeout: eventTimeout, condition)
    } catch {
      throw ContractViolation(description: "timed out waiting for \(what())")
    }
  }

  // MARK: Rule 11

  public static func windowIsListedAndAnnounced(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let host = h.makeWindowHost()
    let window = engine.createWindow(host: host)
    try require(engine.windowIDs.contains(window), "createWindow must list the window: \(engine.windowIDs)")
    try await wait("windowOpened") { recorder.windowEvents.contains(.windowOpened(window)) }
    try require(host.onCloseRequested != nil, "the engine must set the host's onCloseRequested")
    let blank = engine.createTab(url: nil, in: window)
    let page = engine.createTab(url: try h.pageURL("WindowPage"), in: window)
    try await h.settle(engine, page)
    for id in [blank, page] {
      let snap = try requireValue(engine.snapshot(of: id), "snapshot of a tab in the window")
      try require(snap.window == window, "the snapshot must name its window: \(snap)")
    }
    try require(recorder.events(for: page).first == .tabCreated(page), "first event must be tabCreated")
  }

  public static func closeWindowClosesItsTabsThenReportsWindowClosed(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let other = engine.createWindow(host: h.makeWindowHost())
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: try h.pageURL("ClosingWindow"), in: window)
    try await h.settle(engine, b)
    let survivor = engine.createTab(url: nil, in: other)
    engine.closeWindow(window)
    try await wait("windowClosed") { !windowCloses(recorder, window).isEmpty }
    try require(windowCloses(recorder, window) == [.userClose],
                "closeWindow must report .windowClosed once with .userClose: \(recorder.windowEvents)")
    try require(!engine.windowIDs.contains(window), "a closed window must not be listed: \(engine.windowIDs)")
    try require(engine.windowIDs.contains(other), "closing one window must leave the other listed")
    guard let closedAt = recorder.log.firstIndex(of: .window(.windowClosed(window, reason: .userClose))) else {
      throw ContractViolation(description: "windowClosed missing from the log")
    }
    for id in [a, b] {
      try require(closes(recorder, id) == [.windowClosing],
                  "each tab must close once with .windowClosing: \(recorder.events(for: id))")
      let tabClosedAt = recorder.log.firstIndex(of: .tab(.tabClosed(id, reason: .windowClosing)))
      try require(tabClosedAt.map { $0 < closedAt } ?? false, "tabClosed must precede windowClosed: \(recorder.log)")
      try require(engine.snapshot(of: id) == nil && !engine.tabIDs.contains(id), "a closed window's tab is gone")
    }
    try require(engine.snapshot(of: survivor)?.window == other, "the other window's tab must stay")
    let after = recorder.log.dropFirst(closedAt + 1)
    try require(!after.contains { if case .window(let event) = $0 { event.windowID == window } else { false } },
                "nothing may follow windowClosed for the window: \(Array(after))")
  }

  public static func hostCloseRequestClosesTheWindow(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let host = h.makeWindowHost()
    let window = engine.createWindow(host: host)
    let id = engine.createTab(url: nil, in: window)
    let onClose = try requireValue(host.onCloseRequested, "onCloseRequested")
    onClose()
    try await wait("windowClosed after onCloseRequested") { !windowCloses(recorder, window).isEmpty }
    try require(closes(recorder, id) == [.windowClosing], "the tab must close with .windowClosing")
    try require(windowCloses(recorder, window) == [.userClose],
                "the host's close request is the user's: \(recorder.windowEvents)")
  }

  /// #401: a window whose last tab moved to another window closes with `.lastTabClosed`, not as a close somebody
  /// asked for; the moved tab does not close.
  public static func emptiedWindowReportsLastTabClosed(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let source = engine.createWindow(host: h.makeWindowHost())
    let target = engine.createWindow(host: h.makeWindowHost())
    _ = engine.createTab(url: nil, in: target)
    let moved = engine.createTab(url: try h.pageURL("MovedOut"), in: source)
    try await h.settle(engine, moved)
    engine.moveTab(moved, to: target)
    try await wait("windowClosed of the emptied window") { !windowCloses(recorder, source).isEmpty }
    try require(windowCloses(recorder, source) == [.lastTabClosed],
                "an emptied window closes with .lastTabClosed: \(recorder.windowEvents)")
    try require(closes(recorder, moved).isEmpty && engine.snapshot(of: moved)?.window == target,
                "the moved tab stays open in the target: \(recorder.events(for: moved))")
    try require(windowCloses(recorder, target).isEmpty, "the target stays open")
  }

  /// #401: a window an extension closes (`chrome.windows.remove`) reports `.windowClosed` with `.extension`, after
  /// its tabs' `.tabClosed(reason: .extension)`. Needs `engineCloseWindow`.
  public static func extensionWindowCloseReportsExtension(_ h: EngineHarness) async throws {
    let close = try driver(h.engineCloseWindow, "engineCloseWindow")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let other = engine.createWindow(host: h.makeWindowHost())
    let a = engine.createTab(url: try h.pageURL("RemovedA"), in: window)
    let b = engine.createTab(url: try h.pageURL("RemovedB"), in: window)
    try await h.settle(engine, a)
    try await h.settle(engine, b)
    let survivor = engine.createTab(url: nil, in: other)
    try await close(engine, window)
    try await wait("windowClosed after the extension's close") { !windowCloses(recorder, window).isEmpty }
    try require(windowCloses(recorder, window) == [.extension],
                "an extension's window close reports .extension: \(recorder.windowEvents)")
    guard let closedAt = recorder.log.firstIndex(of: .window(.windowClosed(window, reason: .extension))) else {
      throw ContractViolation(description: "windowClosed missing from the log")
    }
    for id in [a, b] {
      try require(closes(recorder, id) == [.extension],
                  "each tab must close once with .extension: \(recorder.events(for: id))")
      let tabClosedAt = recorder.log.firstIndex(of: .tab(.tabClosed(id, reason: .extension)))
      try require(tabClosedAt.map { $0 < closedAt } ?? false, "tabClosed must precede windowClosed: \(recorder.log)")
    }
    try require(engine.snapshot(of: survivor)?.window == other && windowCloses(recorder, other).isEmpty,
                "the other window and its tab stay")
  }

  // MARK: Rule 12

  public static func activationIsOneTabPerWindow(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let other = engine.createWindow(host: h.makeWindowHost())
    let a = engine.createTab(url: nil, in: window)
    let b = engine.createTab(url: nil, in: window)
    let c = engine.createTab(url: nil, in: other)
    try await wait("the first tab of each window to be active") {
      engine.activeTab(in: window) == a && engine.activeTab(in: other) == c
    }
    try require(engine.snapshot(of: a)?.isActive == true && engine.snapshot(of: b)?.isActive == false,
                "the first tab is active, a later one is not")
    engine.activateTab(b)
    try await wait("b active") { engine.activeTab(in: window) == b && engine.snapshot(of: b)?.isActive == true }
    try require(recorder.events(for: b).contains(.activeTabChanged(b)), "activateTab must emit activeTabChanged")
    try require(engine.snapshot(of: a)?.isActive == false, "the previous active tab must be inactive")
    try require(activeCount(engine, in: window) == 1 && activeCount(engine, in: other) == 1,
                "exactly one active tab per window")
    try require(engine.activeTab(in: other) == c, "activation in one window must leave the other alone")
    engine.closeTab(b)
    try await wait("another tab active after closing the active one") { engine.activeTab(in: window) == a }
    try require(activeCount(engine, in: window) == 1, "exactly one active tab after the close")
    try require(engine.snapshot(of: a)?.isActive == true, "the remaining tab must be active")
  }

  // MARK: Rule 13

  public static func engineCreatedTabIsAnnounced(_ h: EngineHarness) async throws {
    let createTab = try driver(h.engineCreateTab, "engineCreateTab")
    let activate = try driver(h.engineActivate, "engineActivate")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let opener = engine.createTab(url: try h.pageURL("Opener"), in: window)
    try await h.settle(engine, opener)
    let id = try await createTab(engine, window, opener, true)
    try await wait("the engine tab to be active") { engine.snapshot(of: id)?.isActive == true }
    try require(recorder.events(for: id).first == .tabCreated(id), "first event must be tabCreated: "
                  + "\(recorder.events(for: id))")
    let snap = try requireValue(engine.snapshot(of: id), "engine tab snapshot")
    try require(snap.origin == .engine && snap.window == window && snap.opener == opener,
                "engine tab snapshot must carry origin, window and opener: \(snap)")
    try require(engine.tabIDs.contains(id), "engine tab must be listed")
    try require(recorder.events(for: id).contains(.activeTabChanged(id)), "its activation must be announced")
    try require(engine.snapshot(of: opener)?.origin == .client, "a client tab has origin .client")
    let mark = recorder.events(for: opener).count
    try await activate(engine, opener)
    try await wait("engine activation of the opener") { engine.activeTab(in: window) == opener }
    try require(recorder.events(for: opener).dropFirst(mark).contains(.activeTabChanged(opener)),
                "an engine-side activation must emit activeTabChanged")
    try require(activeCount(engine, in: window) == 1, "exactly one active tab")
  }

  // MARK: Rule 14

  public static func engineCloseIsTerminal(_ h: EngineHarness) async throws {
    let closeTab = try driver(h.engineCloseTab, "engineCloseTab")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    _ = engine.createTab(url: nil, in: window)
    let id = engine.createTab(url: try h.pageURL("ClosedByEngine"), in: window)
    try await h.settle(engine, id)
    try await closeTab(engine, id)
    try await wait("the engine close") { engine.snapshot(of: id) == nil }
    try await Task.sleep(for: .milliseconds(50))
    let reasons = closes(recorder, id)
    try require(reasons.count == 1 && [.page, .extension].contains(reasons[0]),
                "one tabClosed with .page or .extension: \(reasons)")
    try require({ if case .tabClosed = recorder.events(for: id).last { true } else { false } }(),
                "tabClosed must be last: \(recorder.events(for: id))")
    try require(!engine.tabIDs.contains(id) && engine.contentView(for: id) == nil, "closed tab still resolvable")
  }

  // MARK: Rule 15

  public static func windowlessCreateTabLandsInMostRecentlyActiveWindow(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let first = engine.createWindow(host: h.makeWindowHost())
    let second = engine.createWindow(host: h.makeWindowHost())
    let a = engine.createTab(url: nil, in: first)
    let b = engine.createTab(url: nil, in: second)
    try await wait("both windows to have an active tab") {
      engine.activeTab(in: first) == a && engine.activeTab(in: second) == b
    }
    engine.activateTab(a)
    let inFirst = engine.createTab(url: nil)
    try require(engine.snapshot(of: inFirst)?.window == first,
                "createTab(url:) after activating a tab in the first window must land there: "
                  + "\(String(describing: engine.snapshot(of: inFirst)))")
    engine.activateTab(b)
    let inSecond = engine.createTab(url: nil)
    try require(engine.snapshot(of: inSecond)?.window == second,
                "createTab(url:) after activating a tab in the second window must land there")
  }

  // MARK: Rule 16

  public static func heldCloseKeepsTheTabUntilAnswered(_ h: EngineHarness) async throws {
    let hold = try driver(h.holdClose, "holdClose")
    let answer = try driver(h.answerDialog, "answerDialog")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let id = engine.createTab(url: try h.pageURL("Held"), in: window)
    try await h.settle(engine, id)
    try await hold(engine, id)
    try await wait("wouldHoldClose") { engine.snapshot(of: id)?.wouldHoldClose == true }

    engine.closeTab(id)
    try await wait("isClosing") { engine.snapshot(of: id)?.isClosing == true }
    try require(engine.tabIDs.contains(id) && closes(recorder, id).isEmpty, "a held tab stays listed")
    try await answer(engine, id, false)
    try await wait("closeCancelled") { recorder.events(for: id).contains(.closeCancelled(id)) }
    try await wait("isClosing reset") { engine.snapshot(of: id)?.isClosing == false }
    try require(engine.tabIDs.contains(id) && closes(recorder, id).isEmpty, "a cancelled close leaves the tab open")

    engine.closeTab(id, mode: .honourUnloadHandlers)
    try await wait("isClosing again") { engine.snapshot(of: id)?.isClosing == true }
    try await answer(engine, id, true)
    try await wait("the accepted close") { engine.snapshot(of: id) == nil }
    try await Task.sleep(for: .milliseconds(50))
    try require(closes(recorder, id) == [.client], "one tabClosed(.client): \(recorder.events(for: id))")
    try require(recorder.events(for: id).last == .tabClosed(id, reason: .client), "tabClosed must be last")
  }

  public static func skipUnloadHandlersNeverHolds(_ h: EngineHarness) async throws {
    let hold = try driver(h.holdClose, "holdClose")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let id = engine.createTab(url: try h.pageURL("Skipped"), in: window)
    try await h.settle(engine, id)
    try await hold(engine, id)
    try await wait("wouldHoldClose") { engine.snapshot(of: id)?.wouldHoldClose == true }
    engine.closeTab(id, mode: .skipUnloadHandlers)
    try require(engine.snapshot(of: id) == nil && !engine.tabIDs.contains(id), ".skipUnloadHandlers must close at once")
    try require(closes(recorder, id) == [.client], "one tabClosed(.client): \(recorder.events(for: id))")
  }

  public static func cancelledWindowCloseKeepsTheWindow(_ h: EngineHarness) async throws {
    let hold = try driver(h.holdClose, "holdClose")
    let answer = try driver(h.answerDialog, "answerDialog")
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: h.makeWindowHost())
    let held = engine.createTab(url: try h.pageURL("HeldInWindow"), in: window)
    let plain = engine.createTab(url: try h.pageURL("PlainInWindow"), in: window)
    try await h.settle(engine, held)
    try await h.settle(engine, plain)
    try await hold(engine, held)
    try await wait("wouldHoldClose") { engine.snapshot(of: held)?.wouldHoldClose == true }

    engine.closeWindow(window)
    try await wait("the held tab closing") { engine.snapshot(of: held)?.isClosing == true }
    try await answer(engine, held, false)
    try await wait("closeCancelled") { recorder.events(for: held).contains(.closeCancelled(held)) }
    try await Task.sleep(for: .milliseconds(50))
    try require(engine.windowIDs.contains(window) && windowCloses(recorder, window).isEmpty,
                "a cancelled window close keeps the window")
    try require(engine.tabIDs.contains(held) && engine.tabIDs.contains(plain), "and its tabs")
    try require(closes(recorder, held).isEmpty && closes(recorder, plain).isEmpty, "no tabClosed")

    engine.closeWindow(window)
    try await wait("the held tab closing again") { engine.snapshot(of: held)?.isClosing == true }
    try await answer(engine, held, true)
    try await wait("windowClosed") { !windowCloses(recorder, window).isEmpty }
    try require(windowCloses(recorder, window) == [.userClose], "a held window close is still the user's")
    try require(closes(recorder, held) == [.windowClosing] && closes(recorder, plain) == [.windowClosing],
                "both tabs close with .windowClosing once the dialog is accepted")
  }
}
