import AppKit
import EngineAPI

/// Pure in-memory engine for tests and previews. Loads complete only when `finishLoad` is called,
/// which makes event order fully deterministic. Every event is emitted synchronously.
///
/// Windows, activation and held closes follow contract rules 11-16; the engine-side test drivers
/// (`engineCreateTab`, `engineCloseTab`, `engineCloseWindow`, `engineActivate`, `holdClose`, `answerDialog`,
/// `openEngineWindow`, `setExtensionActions`) stand in for what a page, an extension or the user does in a real engine.
@MainActor
public final class InMemoryEngine: EngineClient, EngineExtensions {
  /// A close waiting on a leave-site dialog.
  private enum HeldClose {
    /// One tab, closed by the client or the engine, with the reason it will report.
    case tab(CloseReason)
    /// The tab's window is closing.
    case window(EngineWindowID, WindowCloseReason)
  }

  private var snapshots: [TabID: TabSnapshot] = [:]
  private var views: [TabID: NSView] = [:]
  /// Per-tab history: entries behind and ahead of the current one (nearest last on each stack).
  private var history: [TabID: (back: [HistoryEntry], forward: [HistoryEntry])] = [:]
  private let hub = EngineEventHub()
  public private(set) var tabIDs: [TabID] = []

  public private(set) var windowIDs: [EngineWindowID] = []
  private var hosts: [EngineWindowID: any EngineWindowHosting] = [:]
  private var activeTabs: [EngineWindowID: TabID] = [:]
  private var lastActiveWindow: EngineWindowID?
  private var heldCloses: [TabID: HeldClose] = [:]
  private var actions: [EngineWindowID: [ExtensionAction]] = [:]

  /// Builds hosts for `openEngineWindow(_:)`, as the app's provider does for a real engine.
  public var windowHostProvider: EngineWindowHostProvider?
  /// Commands that reached the engine through a host's `forward.execute`, in order.
  public private(set) var executedCommands: [(command: EngineCommand, disposition: EngineDisposition,
                                              window: EngineWindowID)] = []
  /// Actions run through `runExtensionAction`, in order.
  public private(set) var ranExtensionActions: [(id: String, window: EngineWindowID, anchor: NSView)] = []

  public init() {}

  // MARK: - Tabs

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    let window = lastActiveWindow.flatMap { windowIDs.contains($0) ? $0 : nil }
    return insertTab(url: url, window: window, opener: nil, origin: .client, activate: false)
  }

  @discardableResult
  public func createTab(url: URL?, in window: EngineWindowID) -> TabID {
    precondition(windowIDs.contains(window), "createTab(url:in:) needs a listed window, got \(window)")
    lastActiveWindow = window
    return insertTab(url: url, window: window, opener: nil, origin: .client, activate: false)
  }

  public func closeTab(_ id: TabID) { closeTab(id, mode: .honourUnloadHandlers) }

  public func closeTab(_ id: TabID, mode: CloseMode) {
    guard let current = snapshots[id], !current.isClosing else { return }
    if mode == .honourUnloadHandlers, current.wouldHoldClose {
      hold(id, .tab(.client))
    } else {
      removeTab(id, reason: .client)
    }
  }

  /// Starts a load and commits it at once: url, loading, then (on a host change) the favicon reset. A new
  /// navigation drops the forward history; navigating to the URL the tab already shows leaves the history alone,
  /// like a reload.
  public func navigate(_ id: TabID, to url: URL) {
    guard let previous = snapshots[id] else { return }
    if let current = previous.url, current != url {
      history[id, default: ([], [])].back.append(HistoryEntry(url: current, title: previous.title))
      history[id, default: ([], [])].forward.removeAll()
    }
    load(id, url, title: nil, previous: previous)
  }

  public func goBack(_ id: TabID) { goToHistory(id, offset: -1) }

  public func goForward(_ id: TabID) { goToHistory(id, offset: 1) }

  public func goToHistory(_ id: TabID, offset: Int) {
    guard offset != 0, let previous = snapshots[id] else { return }
    var stack = history[id] ?? ([], [])
    var current: HistoryEntry? = previous.url.map { HistoryEntry(url: $0, title: previous.title) }
    let target: HistoryEntry
    if offset < 0 {
      let steps = -offset
      guard stack.back.count >= steps else { return }
      var popped: HistoryEntry!
      for _ in 0..<steps {
        if let current { stack.forward.append(current) }
        popped = stack.back.popLast()
        current = popped
      }
      target = popped
    } else {
      let steps = offset
      guard stack.forward.count >= steps else { return }
      var popped: HistoryEntry!
      for _ in 0..<steps {
        if let current { stack.back.append(current) }
        popped = stack.forward.popLast()
        current = popped
      }
      target = popped
    }
    history[id] = stack
    load(id, target.url, title: target.title, previous: previous)
  }

  public func history(of id: TabID) -> TabHistory? {
    guard snapshots[id] != nil else { return nil }
    let stack = history[id] ?? ([], [])
    return TabHistory(back: Array(stack.back.reversed()), forward: Array(stack.forward.reversed()))
  }

  /// The copy lands in the source's window, after the source in `tabIDs`, and does not take activation.
  @discardableResult
  public func duplicateTab(_ id: TabID) -> TabID? {
    guard let source = snapshots[id] else { return nil }
    let copy = insertTab(url: nil, window: source.window, opener: nil, origin: .client, activate: false,
                         history: history[id] ?? ([], []))
    if let url = source.url, let initial = snapshots[copy] {
      load(copy, url, title: source.title, previous: initial)
    } else {
      reportHistory(copy)
    }
    return copy
  }

  public func moveTab(_ id: TabID, to window: EngineWindowID) {
    guard let moved = snapshots[id], !moved.isClosing, let source = moved.window, source != window,
          windowIDs.contains(window) else { return }
    if activeTabs[source] == id { activeTabs[source] = nil }
    snapshots[id]?.window = window
    snapshots[id]?.isActive = false
    tabIDs.removeAll { $0 == id }
    tabIDs.append(id)
    hub.assign(id, to: window)
    setActive(id)
    let left = tabs(in: source)
    if left.isEmpty {
      finishWindowClose(source, reason: .lastTabClosed)
    } else if activeTabs[source] == nil, let successor = left.last {
      setActive(successor)
      lastActiveWindow = window
    }
  }

  /// Mute is engine state only: the in-memory page plays nothing.
  public func setMuted(_ id: TabID, muted: Bool) {
    guard let current = snapshots[id], current.isMuted != muted else { return }
    snapshots[id]?.isMuted = muted
    hub.emit(.mutedChanged(id, isMuted: muted))
  }

  public func reload(_ id: TabID) {
    guard let current = snapshots[id], current.url != nil, !current.isLoading else { return }
    snapshots[id]?.isLoading = true
    hub.emit(.loadingChanged(id, isLoading: true))
  }

  public func snapshot(of id: TabID) -> TabSnapshot? { snapshots[id] }

  public func contentView(for id: TabID) -> NSView? {
    guard snapshots[id] != nil else { return nil }
    if let view = views[id] { return view }
    let view = InMemoryPageView()
    view.identifier = NSUserInterfaceItemIdentifier("in-memory-tab-\(id)")
    views[id] = view
    return view
  }

  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(handler)
  }

  // MARK: - Windows

  @discardableResult
  public func createWindow(host: any EngineWindowHosting) -> EngineWindowID {
    let id = EngineWindowID()
    windowIDs.append(id)
    hosts[id] = host
    lastActiveWindow = id
    host.onCloseRequested = { [weak self] in self?.closeWindow(id) }
    host.forward = EngineCommandForwarding(
      validate: { _ in true },
      execute: { [weak self] command, disposition in self?.executedCommands.append((command, disposition, id)) }
    )
    hub.emit(.windowOpened(id))
    return id
  }

  /// A window close already waiting on a dialog is not started again.
  public func closeWindow(_ id: EngineWindowID) { closeWindow(id, reason: .userClose) }

  private func closeWindow(_ id: EngineWindowID, reason: WindowCloseReason) {
    guard windowIDs.contains(id) else { return }
    let tabs = tabs(in: id)
    guard !tabs.contains(where: { snapshots[$0]?.isClosing == true }) else { return }
    let holding = tabs.filter { snapshots[$0]?.wouldHoldClose == true }
    guard holding.isEmpty else {
      for tab in holding { hold(tab, .window(id, reason)) }
      return
    }
    finishWindowClose(id, reason: reason)
  }

  public func activateTab(_ id: TabID) { setActive(id) }

  public func activeTab(in window: EngineWindowID) -> TabID? { activeTabs[window] }

  public func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    hub.addWindowObserver(handler)
  }

  public func observe(window: EngineWindowID,
                      _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(window: window, handler)
  }

  /// The host of a listed window.
  public func host(of window: EngineWindowID) -> (any EngineWindowHosting)? { hosts[window] }

  // MARK: - Extensions

  public func extensionActions(in window: EngineWindowID) -> [ExtensionAction] { actions[window] ?? [] }

  public func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView) {
    guard actions[window]?.contains(where: { $0.id == id }) == true else { return }
    ranExtensionActions.append((id, window, anchor))
  }

  // MARK: - Test drivers

  /// Test hook: the page started or stopped playing sound (rule 17). A muted page stays audible, as in Chromium.
  public func setAudible(_ id: TabID, _ audible: Bool) {
    guard let current = snapshots[id], current.isAudible != audible else { return }
    snapshots[id]?.isAudible = audible
    hub.emit(.audibleChanged(id, isAudible: audible))
  }

  /// Test hook: the page changed `document.title` after loading.
  public func setDocumentTitle(_ id: TabID, _ title: String) {
    guard let current = snapshots[id], current.title != title else { return }
    snapshots[id]?.title = title
    hub.emit(.titleChanged(id, title))
  }

  /// Test hook: completes the pending load the way a real engine would.
  public func finishLoad(_ id: TabID, title: String, favicon: Data? = nil) {
    guard let current = snapshots[id] else { return }
    if current.title != title {
      snapshots[id]?.title = title
      hub.emit(.titleChanged(id, title))
    }
    if let favicon {
      snapshots[id]?.faviconData = favicon
      hub.emit(.faviconChanged(id, favicon))
    }
    if current.isLoading {
      snapshots[id]?.isLoading = false
      hub.emit(.loadingChanged(id, isLoading: false))
    }
  }

  /// Test driver: the engine opens a tab on its own (`window.open`, `chrome.tabs.create`), origin `.engine`.
  @discardableResult
  public func engineCreateTab(url: URL? = nil, in window: EngineWindowID, opener: TabID? = nil,
                              active: Bool = true) -> TabID {
    precondition(windowIDs.contains(window), "engineCreateTab needs a listed window, got \(window)")
    return insertTab(url: url, window: window, opener: opener, origin: .engine, activate: active)
  }

  /// Test driver: the page (`window.close()`, reason `.page`) or an extension (`.extension`) closes the tab. A page
  /// with a `beforeunload` handler holds the close until `answerDialog`.
  public func engineCloseTab(_ id: TabID, reason: CloseReason = .page) {
    guard let current = snapshots[id], !current.isClosing else { return }
    if current.wouldHoldClose { hold(id, .tab(reason)) } else { removeTab(id, reason: reason) }
  }

  /// Test driver: the engine closes the window on its own, with `reason` (#401): an extension (`.extension`,
  /// `chrome.windows.remove`), quitting (`.appQuit`), the engine's own Close Window (`.userClose`), or the window
  /// emptied by its last tab (`.lastTabClosed`, as Chromium closes a `Browser` with its last tab). Unload processing
  /// first, as `closeWindow`; its tabs close with `.extension`, `.appTerminating` or `.windowClosing`.
  public func engineCloseWindow(_ id: EngineWindowID, reason: WindowCloseReason) {
    closeWindow(id, reason: reason)
  }

  /// Test driver: the engine activates the tab (an extension's `chrome.tabs.update`).
  public func engineActivate(_ id: TabID) { setActive(id) }

  /// Test driver: the user activates a link to `url` in the page of `tab` (#313). The tab's window host decides, as a
  /// real engine asks before it navigates; `.navigate` navigates the tab (a `.currentTab` disposition only), `.cancel`
  /// leaves it as it was. A tab without a window host navigates.
  @discardableResult
  public func simulateLinkActivation(in tab: TabID, url: URL, modifiers: EngineLinkModifiers = [],
                                     disposition: EngineDisposition = .currentTab) -> EngineLinkDecision {
    guard let snapshot = snapshots[tab] else { return .navigate }
    let activation = EngineLinkActivation(url: url, sourceTab: tab, sourceURL: snapshot.url, modifiers: modifiers,
                                          disposition: disposition)
    let decision = snapshot.window.flatMap { hosts[$0] }?.decideLinkActivation(activation) ?? .navigate
    if decision == .navigate, disposition == .currentTab { navigate(tab, to: url) }
    return decision
  }

  /// Test driver: the page of `tab` did not handle the key down `event` (an Esc it does not use), which goes to the
  /// tab's window host. True when the host took it.
  @discardableResult
  public func simulateUnhandledKeyDown(_ event: NSEvent, in tab: TabID) -> Bool {
    guard let window = snapshots[tab]?.window, let host = hosts[window] else { return false }
    return host.handleUnhandledKeyDown(event, in: tab)
  }

  /// Test driver: the page registers a `beforeunload` handler with sticky user activation. `wouldHoldClose` stays
  /// true after a cancelled close, as the handler stays registered.
  public func holdClose(_ id: TabID) {
    guard snapshots[id] != nil else { return }
    snapshots[id]?.wouldHoldClose = true
  }

  /// Test driver: answers the tab's leave-site dialog. False when no close is held there. Accepting the last held
  /// tab of a closing window closes the window; cancelling any of them cancels the window close and reports
  /// `.closeCancelled` for every tab of the window that was closing.
  @discardableResult
  public func answerDialog(_ id: TabID, accept: Bool) -> Bool {
    guard let held = heldCloses.removeValue(forKey: id) else { return false }
    switch (held, accept) {
    case (.tab(let reason), true):
      removeTab(id, reason: reason)
    case (.tab, false):
      snapshots[id]?.isClosing = false
      hub.emit(.closeCancelled(id))
    case (.window(let window, let reason), true):
      let waiting = heldCloses.values.contains { if case .window(window, _) = $0 { true } else { false } }
      if !waiting { finishWindowClose(window, reason: reason) }
    case (.window(let window, _), false):
      for tab in tabs(in: window) where snapshots[tab]?.isClosing == true {
        heldCloses[tab] = nil
        snapshots[tab]?.isClosing = false
        hub.emit(.closeCancelled(tab))
      }
    }
    return true
  }

  /// Test driver: the engine asks for a window of its own (Dock reopen, `chrome.windows.create`). Builds the host
  /// through `windowHostProvider` and opens `initialURL` in an engine tab; nil without a provider.
  @discardableResult
  public func openEngineWindow(_ request: EngineWindowRequest) -> EngineWindowID? {
    guard let provider = windowHostProvider else { return nil }
    let window = createWindow(host: provider(request))
    if let url = request.initialURL {
      insertTab(url: url, window: window, opener: nil, origin: .engine, activate: true)
    }
    return window
  }

  /// Test driver: the window's extension actions changed.
  public func setExtensionActions(_ list: [ExtensionAction], in window: EngineWindowID) {
    guard windowIDs.contains(window) else { return }
    actions[window] = list
    hub.emit(.extensionActionsChanged(window))
  }

  // MARK: - Internals

  private func tabs(in window: EngineWindowID) -> [TabID] { tabIDs.filter { snapshots[$0]?.window == window } }

  @discardableResult
  private func insertTab(url: URL?, window: EngineWindowID?, opener: TabID?, origin: TabOrigin, activate: Bool,
                         history copied: (back: [HistoryEntry], forward: [HistoryEntry])? = nil) -> TabID {
    let id = TabID()
    snapshots[id] = TabSnapshot(id: id, window: window, opener: opener, origin: origin)
    tabIDs.append(id)
    if let copied { history[id] = copied }
    hub.assign(id, to: window)
    hub.emit(.tabCreated(id))
    if let window, activate || activeTabs[window] == nil { setActive(id) }
    if let url { navigate(id, to: url) }
    return id
  }

  private func load(_ id: TabID, _ url: URL, title: String?, previous: TabSnapshot) {
    snapshots[id]?.url = url
    if let title, !title.isEmpty { snapshots[id]?.title = title }
    snapshots[id]?.isLoading = true
    hub.emit(.urlChanged(id, url))
    if !previous.isLoading { hub.emit(.loadingChanged(id, isLoading: true)) }
    if previous.url?.host() != url.host(), previous.faviconData != nil {
      snapshots[id]?.faviconData = nil
      hub.emit(.faviconChanged(id, nil))
    }
    reportHistory(id)
  }

  /// Syncs `canGoBack` / `canGoForward` with the history and emits `.historyChanged` only on a change (rule 8).
  private func reportHistory(_ id: TabID) {
    guard let current = snapshots[id] else { return }
    let back = !(history[id]?.back.isEmpty ?? true)
    let forward = !(history[id]?.forward.isEmpty ?? true)
    guard back != current.canGoBack || forward != current.canGoForward else { return }
    snapshots[id]?.canGoBack = back
    snapshots[id]?.canGoForward = forward
    hub.emit(.historyChanged(id, canGoBack: back, canGoForward: forward))
  }

  private func setActive(_ id: TabID) {
    guard let window = snapshots[id]?.window else { return }
    lastActiveWindow = window
    let previous = activeTabs[window]
    guard previous != id else { return }
    if let previous { snapshots[previous]?.isActive = false }
    snapshots[id]?.isActive = true
    activeTabs[window] = id
    hub.emit(.activeTabChanged(id))
  }

  private func hold(_ id: TabID, _ close: HeldClose) {
    heldCloses[id] = close
    snapshots[id]?.isClosing = true
  }

  /// Removes the tab and reports it. A window's active tab is replaced by its right neighbour, else its left one,
  /// unless the whole window is closing.
  private func removeTab(_ id: TabID, reason: CloseReason, reactivate: Bool = true) {
    guard let removed = snapshots[id] else { return }
    var successor: TabID?
    if let window = removed.window, activeTabs[window] == id {
      activeTabs[window] = nil
      let siblings = tabs(in: window)
      if reactivate, let index = siblings.firstIndex(of: id) {
        if siblings.indices.contains(index + 1) {
          successor = siblings[index + 1]
        } else if index > 0 {
          successor = siblings[index - 1]
        }
      }
    }
    snapshots[id] = nil
    tabIDs.removeAll { $0 == id }
    views[id]?.removeFromSuperview()
    views[id] = nil
    history[id] = nil
    heldCloses[id] = nil
    hub.emit(.tabClosed(id, reason: reason))
    if let successor { setActive(successor) }
  }

  private func finishWindowClose(_ id: EngineWindowID, reason: WindowCloseReason) {
    let tabReason: CloseReason = switch reason {
    case .extension: .extension
    case .appQuit: .appTerminating
    case .userClose, .lastTabClosed: .windowClosing
    }
    for tab in tabs(in: id) { removeTab(tab, reason: tabReason, reactivate: false) }
    windowIDs.removeAll { $0 == id }
    activeTabs[id] = nil
    actions[id] = nil
    if let host = hosts.removeValue(forKey: id) {
      host.onCloseRequested = nil
      host.forward = nil
    }
    if lastActiveWindow == id { lastActiveWindow = windowIDs.last }
    hub.emit(.windowClosed(id, reason: reason))
  }
}

/// The page view of an in-memory tab. It accepts first responder like a real engine's page, so focus tests can
/// check where the window put it.
@MainActor
final class InMemoryPageView: NSView {
  override var acceptsFirstResponder: Bool { true }
}
