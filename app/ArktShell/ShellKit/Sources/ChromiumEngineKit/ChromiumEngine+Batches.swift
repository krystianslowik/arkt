import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Facade batches

extension ChromiumEngine {
  /// One facade batch, in order. Tables are updated before each event is emitted, so a handler's `snapshot(of:)`
  /// agrees with the event it receives. A handler may call back into the engine (close a tab, navigate): the hub
  /// queues what that emits behind the current event, and the rest of the batch re-reads the tables, so events for a
  /// tab closed meanwhile are dropped.
  func receive(_ batch: [any ArktEngineEvent]) {
    for event in Self.reordered(batch) {
      apply(event)
    }
  }

  /// Contract rules 2 and 6 within one batch: a title, or a favicon clear, that the facade recorded after the load
  /// end of the same navigation is delivered before that load end. Events are never moved across batches (Risk 2).
  static func reordered(_ batch: [any ArktEngineEvent]) -> [any ArktEngineEvent] {
    var events = batch
    var index = 0
    while index < events.count {
      let event = events[index]
      guard event.kind == .loadingChanged, !event.isLoading, let tab = event.tab else {
        index += 1
        continue
      }
      var moved: [any ArktEngineEvent] = []
      var scan = index + 1
      while scan < events.count {
        let later = events[scan]
        guard later.tab === tab else {
          scan += 1
          continue
        }
        if later.kind == .titleChanged || (later.kind == .faviconChanged && later.faviconPNG == nil) {
          moved.append(events.remove(at: scan))
          continue
        }
        // A new load, or the end of the tab: what follows belongs to it.
        if [.loadingChanged, .urlChanged, .tabClosed, .tabReplaced].contains(later.kind) { break }
        scan += 1
      }
      events.insert(contentsOf: moved, at: index)
      index += moved.count + 1
    }
    return events
  }

  private func apply(_ event: any ArktEngineEvent) {
    switch event.kind {
    case .windowOpened: windowOpened(event)
    case .windowClosed: windowClosed(event)
    case .extensionActionsChanged:
      if let id = window(of: event) { hub.emit(.extensionActionsChanged(id)) }
    case .tabCreated: tabCreated(event)
    case .tabMoved: tabMoved(event)
    case .tabClosed: tabClosed(event)
    case .dialogRequested: dialogRequested(event)
    case .dialogEnded: dialogEnded(event)
    case .permissionRequested: permissionRequested(event)
    case .permissionEnded: permissionEnded(event)
    case .infobarsChanged: infobarsChanged(event)
    default: tabChanged(event)
    }
  }

  func window(of event: any ArktEngineEvent) -> EngineWindowID? {
    event.browser.flatMap { windowByBrowser[ObjectIdentifier($0)] }
  }

  // MARK: Windows

  private func windowOpened(_ event: any ArktEngineEvent) {
    guard let browser = event.browser, windowByBrowser[ObjectIdentifier(browser)] == nil else {
      return  // createWindow(host:) announced it already, or no browser
    }
    let host = ObjectIdentifier(browser.host)
    guard let pending = pendingHosts.removeValue(forKey: host) else { return }  // another instance's window
    register(browser, adapter: pending.adapter, as: pending.id)
    windows[pending.id]?.keepsNewTabPage = [.reopen, .startupURL].contains(pending.kind)
    hub.emit(.windowOpened(pending.id))
  }

  private func windowClosed(_ event: any ArktEngineEvent) {
    guard let browser = event.browser, let id = windowByBrowser[ObjectIdentifier(browser)] else { return }
    // The facade reports every tab's TabClosed first; a tab still listed here ends with its window.
    for tab in tabIDs where tabs[tab]?.snapshot.window == id {
      removeTab(tab)
      hub.emit(.tabClosed(tab, reason: .windowClosing))
    }
    windows[id]?.adapter.detach()
    windows[id] = nil
    windowByBrowser[ObjectIdentifier(browser)] = nil
    windowIDs.removeAll { $0 == id }
    if recentWindow == id { recentWindow = windowIDs.last }
    hub.emit(.windowClosed(id, reason: WindowCloseReason(facade: event.windowCloseReason)))
  }

  // MARK: Tab lifetime

  private func tabCreated(_ event: any ArktEngineEvent) {
    guard let handle = event.tab else { return }
    let key = ObjectIdentifier(handle)
    // A tab this client created or duplicated was announced when the call returned (Decision 4); one deferred
    // inside a nested loop is in the window only now.
    guard tabByHandle[key] == nil, retired[key] == nil, let window = window(of: event) else {
      if let window = window(of: event) { closeNewTabPage(in: window) }
      return
    }
    if keepsBack(handle, url: event.url, in: window) { return }
    adopt(handle, in: window, origin: TabOrigin(facade: event.origin), url: event.url, title: event.title)
    closeNewTabPage(in: window)
  }

  /// Lists and announces a tab the engine created on its own (contract rule 13), or one moved in from a window this
  /// instance does not list. Activation follows as its own `ActiveTabChanged`.
  func adopt(_ handle: any ArktTabHandle, in window: EngineWindowID, origin: TabOrigin, url: URL?,
                     title: String?) {
    var snapshot = initialSnapshot(of: handle, id: TabID(), window: window, origin: origin)
    if let url { snapshot.url = url }
    if let title { snapshot.title = title }
    insert(handle, snapshot: snapshot)
    hub.emit(.tabCreated(snapshot.id))
  }

  private func tabMoved(_ event: any ArktEngineEvent) {
    guard let handle = event.tab else { return }
    let key = ObjectIdentifier(handle)
    let target = window(of: event)
    forgetNewTabPage(handle)
    guard let id = tabByHandle[key] else {
      if retired[key] == nil, let target {
        adopt(handle, in: target, origin: TabOrigin(facade: handle.origin), url: nil, title: nil)
        closeNewTabPage(in: target)
      }
      return
    }
    guard let target else {
      removeTab(id)
      hub.emit(.tabClosed(id, reason: .extension))
      return
    }
    guard let previous = tabs[id]?.snapshot.window, previous != target else { return }
    if windows[previous]?.activeTab == id { windows[previous]?.activeTab = nil }
    tabs[id]?.snapshot.window = target
    tabs[id]?.snapshot.isActive = false
    hub.assign(id, to: target)
    closeNewTabPage(in: target)
  }

  private func tabClosed(_ event: any ArktEngineEvent) {
    guard let handle = event.tab else { return }
    let key = ObjectIdentifier(handle)
    if retired.removeValue(forKey: key) != nil { return }  // closeTab answered closed and announced it
    forgetNewTabPage(handle)
    guard let id = tabByHandle[key] else { return }
    removeTab(id)
    hub.emit(.tabClosed(id, reason: CloseReason(facade: event.closeReason)))
  }

  // MARK: Tab state

  private func tabChanged(_ event: any ArktEngineEvent) {
    guard let handle = event.tab else { return }
    guard let id = tabByHandle[ObjectIdentifier(handle)], tabs[id] != nil else {
      if event.kind == .urlChanged { newTabPageNavigated(handle, to: event.url) }
      return
    }
    switch event.kind {
    case .activeTabChanged: activeTabChanged(id)
    case .closeCancelled:
      tabs[id]?.clientCloseHeld = false
      hub.emit(.closeCancelled(id))
    case .urlChanged:
      if let phase = tabs[id]?.initialBlank {
        if Self.isBlank(event.url) { break }
        if phase == .blank {
          // The first page: its URL, then its load start (rule 2), whatever Chromium's loading flag did so far.
          tabs[id]?.initialBlank = .navigating
          tabs[id]?.snapshot.url = event.url
          hub.emit(.urlChanged(id, event.url))
          guard tabs[id] != nil else { break }
          tabs[id]?.snapshot.isLoading = true
          hub.emit(.loadingChanged(id, isLoading: true))
          break
        }
      }
      tabs[id]?.snapshot.url = event.url
      hub.emit(.urlChanged(id, event.url))
    case .titleChanged:
      let title = event.title ?? ""
      tabs[id]?.snapshot.title = title
      hub.emit(.titleChanged(id, title))
    case .faviconChanged:
      tabs[id]?.snapshot.faviconData = event.faviconPNG
      hub.emit(.faviconChanged(id, event.faviconPNG))
    case .loadingChanged:
      if let phase = tabs[id]?.initialBlank {
        if phase == .blank { break }
        if !event.isLoading { tabs[id]?.initialBlank = nil }
        if tabs[id]?.snapshot.isLoading == event.isLoading { break }
      }
      tabs[id]?.snapshot.isLoading = event.isLoading
      hub.emit(.loadingChanged(id, isLoading: event.isLoading))
    case .historyChanged:
      tabs[id]?.snapshot.canGoBack = event.canGoBack
      tabs[id]?.snapshot.canGoForward = event.canGoForward
      hub.emit(.historyChanged(id, canGoBack: event.canGoBack, canGoForward: event.canGoForward))
    case .audibleChanged:
      // The listed snapshot read the handle's live state, so a report of the value it already has is dropped.
      guard tabs[id]?.snapshot.isAudible != event.isAudible else { break }
      tabs[id]?.snapshot.isAudible = event.isAudible
      hub.emit(.audibleChanged(id, isAudible: event.isAudible))
    case .mutedChanged:
      guard tabs[id]?.snapshot.isMuted != event.isMuted else { break }
      tabs[id]?.snapshot.isMuted = event.isMuted
      hub.emit(.mutedChanged(id, isMuted: event.isMuted))
    default:
      // TabReplaced: the handle and its container stay (Decision 5, 6); nothing changes for the shell.
      break
    }
  }

  static func isBlank(_ url: URL?) -> Bool { url == nil || url?.absoluteString == "about:blank" }

  func activeTabChanged(_ id: TabID) {
    guard let window = tabs[id]?.snapshot.window, windows[window] != nil, windows[window]?.activeTab != id else {
      return
    }
    if let previous = windows[window]?.activeTab { tabs[previous]?.snapshot.isActive = false }
    windows[window]?.activeTab = id
    tabs[id]?.snapshot.isActive = true
    recentWindow = window
    hub.emit(.activeTabChanged(id))
  }
}
