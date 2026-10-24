import AppKit
internal import ArktEngineABI
import EngineAPI

/// `EngineClient` and `EngineExtensions` over the engine facade (`arkt_engine.h`; week-3 plan, Task W3-6).
///
/// Main thread only: every facade protocol is `NS_SWIFT_UI_ACTOR`, and on macOS Chromium's UI thread is the main
/// thread (Decision 3). The facade delivers its events in batches from a posted task, one task after the call that
/// caused them, so:
/// - The synchronous parts of the contract stay here (Decision 4): `createTab`, `duplicateTab` and `createWindow`
///   announce `.tabCreated` / `.windowOpened` themselves, and a `closeTab` the facade answers `closed` emits
///   `.tabClosed(reason: .client)` at once. The facade's later events for those calls are dropped.
/// - `snapshot(of:)`, `tabIDs`, `activeTab(in:)` and `windowIDs` read tables kept current from facade events, so a
///   snapshot agrees with the last event a handler saw. Three values have no facade event and are read from the tab
///   handle when asked: `isClosing`, `wouldHoldClose` and the back and forward entries of `history(of:)`.
///
/// Instance scoping: an instance lists only the windows it created (`createWindow(host:)`) or was handed through its
/// `windowHostProvider`, and only their tabs. Several instances over one facade (the in-app contract runner) never
/// see each other's tabs. A tab moved into another instance's window ends here with `.tabClosed(reason:
/// .extension)` (only extensions move tabs between windows this week).
///
/// Nested run loops: the facade defers mutators called inside a nested loop (`close` answers `held`, `createTab`
/// returns a handle that is inserted later). Nothing here runs a modal or a nested loop, and batch handling makes no
/// assumption that the shell is idle (Decision 3).
@MainActor
public final class ChromiumEngine: EngineClient, EngineExtensions {
  struct TabRecord {
    let handle: any ArktTabHandle
    /// Fields from events. `isClosing` and `wouldHoldClose` are overlaid from the handle in `snapshot(of:)`.
    var snapshot: TabSnapshot
    /// This client's close answered `held`; a second `closeTab` does nothing until it is answered.
    var clientCloseHeld = false
  }

  struct WindowRecord {
    let browser: any ArktBrowserHandle
    let adapter: WindowHostAdapter
    var activeTab: TabID?
  }

  let facade: any ArktEngine
  let hub = EngineEventHub()
  private var sinkToken: (any NSObjectProtocol)?

  public internal(set) var tabIDs: [TabID] = []
  var tabs: [TabID: TabRecord] = [:]
  var tabByHandle: [ObjectIdentifier: TabID] = [:]
  /// Handles whose terminal `.tabClosed` this instance already emitted (a client close answered `closed`). Every
  /// later facade event for them is dropped; the entry goes when the facade's own `TabClosed` arrives.
  var retired: [ObjectIdentifier: any ArktTabHandle] = [:]

  public internal(set) var windowIDs: [EngineWindowID] = []
  var windows: [EngineWindowID: WindowRecord] = [:]
  var windowByBrowser: [ObjectIdentifier: EngineWindowID] = [:]
  /// Hosts handed out by `host(for:)`, waiting for the facade's `WindowOpened` with that host.
  var pendingHosts: [ObjectIdentifier: (id: EngineWindowID, adapter: WindowHostAdapter)] = [:]
  /// The window that last got `createWindow`, `createTab(url:in:)` or an activation (contract rule 15).
  var recentWindow: EngineWindowID?

  /// Builds the shell window for a window the engine creates on its own (Decision 2). Must not call the engine; the
  /// window is usable after its `.windowOpened`.
  public var windowHostProvider: EngineWindowHostProvider?

  init(facade: any ArktEngine) {
    self.facade = facade
    sinkToken = facade.addEventSink { [weak self] batch in
      self?.receive(batch)
    }
  }

  isolated deinit {
    if let sinkToken { facade.removeEventSink(sinkToken) }
  }

  // MARK: - Tabs

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    guard let window = recentWindow, windows[window] != nil else {
      preconditionFailure("ChromiumEngine.createTab(url:) needs a window: call createWindow(host:) first")
    }
    return createTab(url: url, in: window)
  }

  @discardableResult
  public func createTab(url: URL?, in window: EngineWindowID) -> TabID {
    guard let record = windows[window] else {
      preconditionFailure("createTab(url:in:) needs a window of this engine, got \(window)")
    }
    recentWindow = window
    let first = !tabIDs.contains { tabs[$0]?.snapshot.window == window }
    let handle = record.browser.createTab(url: url, active: first)
    return announceClientTab(handle, in: window)
  }

  public func closeTab(_ id: TabID) { closeTab(id, mode: .honourUnloadHandlers) }

  public func closeTab(_ id: TabID, mode: CloseMode) {
    guard let record = tabs[id], !record.clientCloseHeld, !record.handle.isClosing else { return }
    switch record.handle.close(mode: mode.facade) {
    case .closed:
      retired[ObjectIdentifier(record.handle)] = record.handle
      removeTab(id)
      hub.emit(.tabClosed(id, reason: .client))
    case .held:
      tabs[id]?.clientCloseHeld = true
    @unknown default:
      tabs[id]?.clientCloseHeld = true
    }
  }

  public func navigate(_ id: TabID, to url: URL) { tabs[id]?.handle.navigate(to: url) }
  public func reload(_ id: TabID) { tabs[id]?.handle.reload() }
  public func goBack(_ id: TabID) { tabs[id]?.handle.goBack() }
  public func goForward(_ id: TabID) { tabs[id]?.handle.goForward() }

  public func goToHistory(_ id: TabID, offset: Int) {
    guard offset != 0 else { return }
    tabs[id]?.handle.goToHistory(offset: offset)
  }

  /// Read from the handle: the facade has no event for entry changes.
  public func history(of id: TabID) -> TabHistory? {
    guard let handle = tabs[id]?.handle else { return nil }
    return TabHistory(back: handle.backEntries.map(HistoryEntry.init(facade:)),
                      forward: handle.forwardEntries.map(HistoryEntry.init(facade:)))
  }

  @discardableResult
  public func duplicateTab(_ id: TabID) -> TabID? {
    guard let record = tabs[id], let window = record.snapshot.window, let copy = record.handle.duplicate() else {
      return nil
    }
    return announceClientTab(copy, in: window)
  }

  public func snapshot(of id: TabID) -> TabSnapshot? {
    guard let record = tabs[id] else { return nil }
    var snapshot = record.snapshot
    snapshot.isClosing = record.clientCloseHeld || record.handle.isClosing
    snapshot.wouldHoldClose = record.handle.wouldHoldClose
    return snapshot
  }

  /// The handle's stable container (Decision 6): the same view across contents replacement and moves.
  public func contentView(for id: TabID) -> NSView? { tabs[id]?.handle.containerView }

  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(handler)
  }

  // MARK: - Windows

  @discardableResult
  public func createWindow(host: any EngineWindowHosting) -> EngineWindowID {
    let adapter = WindowHostAdapter(host: host)
    let browser = facade.createBrowser(host: adapter)
    let id = EngineWindowID()
    register(browser, adapter: adapter, as: id)
    recentWindow = id
    hub.emit(.windowOpened(id))
    return id
  }

  public func closeWindow(_ id: EngineWindowID) { windows[id]?.browser.close() }

  public func activateTab(_ id: TabID) {
    guard let record = tabs[id] else { return }
    recentWindow = record.snapshot.window ?? recentWindow
    record.handle.activate()
  }

  public func activeTab(in window: EngineWindowID) -> TabID? { windows[window]?.activeTab }

  /// The host of a listed window.
  public func host(of window: EngineWindowID) -> (any EngineWindowHosting)? { windows[window]?.adapter.host }

  public func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    hub.addWindowObserver(handler)
  }

  public func observe(window: EngineWindowID,
                      _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(window: window, handler)
  }

  // MARK: - Extensions

  public func extensionActions(in window: EngineWindowID) -> [ExtensionAction] {
    guard let browser = windows[window]?.browser else { return [] }
    return facade.extensionActions(in: browser).map(ExtensionAction.init(facade:))
  }

  public func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView) {
    guard let browser = windows[window]?.browser else { return }
    facade.runExtensionAction(id, in: browser, anchor: anchor)
  }

  // MARK: - Engine-initiated windows

  /// The facade asks for a host inside `Browser` construction (`-hostForEngineWindowRequest:`). Builds the shell's
  /// window through `windowHostProvider` and keeps its adapter until the facade's `WindowOpened` names the browser.
  func host(for request: any ArktWindowRequest) -> any ArktWindowHost {
    guard let provider = windowHostProvider else {
      preconditionFailure("ChromiumEngine has no windowHostProvider for an engine window request")
    }
    let adapter = WindowHostAdapter(host: provider(engineRequest(from: request)))
    pendingHosts[ObjectIdentifier(adapter)] = (EngineWindowID(), adapter)
    return adapter
  }

  func engineRequest(from request: any ArktWindowRequest) -> EngineWindowRequest {
    EngineWindowRequest(
      kind: EngineWindowRequestKind(facade: request.kind),
      openerWindow: request.opener.flatMap { windowByBrowser[ObjectIdentifier($0)] },
      bounds: request.hasBounds ? request.bounds : nil,
      profile: EngineProfileID(request.profileId),
      initialURL: request.initialURL)
  }

  // MARK: - Tables

  /// The tab handle of a listed tab (the test API and tests).
  func handle(of id: TabID) -> (any ArktTabHandle)? { tabs[id]?.handle }

  func register(_ browser: any ArktBrowserHandle, adapter: WindowHostAdapter, as id: EngineWindowID) {
    windowIDs.append(id)
    windows[id] = WindowRecord(browser: browser, adapter: adapter)
    windowByBrowser[ObjectIdentifier(browser)] = id
  }

  /// A tab this client created: listed and announced now (contract rule 1), with the window the caller named (a
  /// handle deferred inside a nested loop has no browser yet).
  private func announceClientTab(_ handle: any ArktTabHandle, in window: EngineWindowID) -> TabID {
    let snapshot = initialSnapshot(of: handle, id: TabID(), window: window, origin: .client)
    insert(handle, snapshot: snapshot)
    hub.emit(.tabCreated(snapshot.id))
    return snapshot.id
  }

  func initialSnapshot(of handle: any ArktTabHandle, id: TabID, window: EngineWindowID,
                       origin: TabOrigin) -> TabSnapshot {
    TabSnapshot(id: id, url: handle.url, title: handle.title, faviconData: handle.faviconPNG,
                isLoading: handle.isLoading, canGoBack: handle.canGoBack, canGoForward: handle.canGoForward,
                window: window, opener: handle.opener.flatMap { tabByHandle[ObjectIdentifier($0)] },
                origin: origin)
  }

  func insert(_ handle: any ArktTabHandle, snapshot: TabSnapshot) {
    tabIDs.append(snapshot.id)
    tabs[snapshot.id] = TabRecord(handle: handle, snapshot: snapshot)
    tabByHandle[ObjectIdentifier(handle)] = snapshot.id
    hub.assign(snapshot.id, to: snapshot.window)
  }

  func removeTab(_ id: TabID) {
    guard let record = tabs.removeValue(forKey: id) else { return }
    tabIDs.removeAll { $0 == id }
    tabByHandle[ObjectIdentifier(record.handle)] = nil
    if let window = record.snapshot.window, windows[window]?.activeTab == id { windows[window]?.activeTab = nil }
  }
}
