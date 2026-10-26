import AppKit
import ArktEngineABI

// A scripted Swift implementation of the facade protocols (arkt_engine.h), modelled on the real facade's recorded
// behaviour (week-3 results, W3-3 to W3-5 and #258): events are recorded as plain values and delivered in one batch
// on the next main-actor turn, never from inside the call that caused them; a close answers `closed` or `held`; a
// call made while `isNested` is set is deferred (pending handle, `held` close) and runs before the next batch; the
// test API's `evaluateScript` understands the few scripts the contract drivers send.

final class ScriptedEvent: NSObject, ArktEngineEvent {
  let kind: ArktEngineEventKind
  let tab: (any ArktTabHandle)?
  let browser: (any ArktBrowserHandle)?
  var closeReason: ArktCloseReason = .none
  var url: URL?
  var title: String?
  var faviconPNG: Data?
  var isLoading = false
  var canGoBack = false
  var canGoForward = false
  var opener: (any ArktTabHandle)?
  var origin: ArktTabOrigin = .client
  var isActive = false

  init(_ kind: ArktEngineEventKind, tab: (any ArktTabHandle)?, browser: (any ArktBrowserHandle)?) {
    self.kind = kind; self.tab = tab; self.browser = browser
  }
}

final class ScriptedHistoryEntry: NSObject, ArktHistoryEntry {
  let url: URL
  let title: String
  init(url: URL, title: String) { self.url = url; self.title = title }
}

final class ScriptedAction: NSObject, ArktExtensionAction {
  let actionId: String
  let name: String
  let iconPNG: Data?
  let isEnabled: Bool
  init(actionId: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true) {
    self.actionId = actionId; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
  }
}

final class ScriptedRequest: NSObject, ArktWindowRequest {
  let kind: ArktWindowRequestKind
  let opener: (any ArktBrowserHandle)?
  let bounds: NSRect
  let hasBounds: Bool
  let profileId = "Default"
  let initialURL: URL?
  init(kind: ArktWindowRequestKind, opener: (any ArktBrowserHandle)? = nil, bounds: NSRect? = nil,
       initialURL: URL? = nil) {
    self.kind = kind; self.opener = opener; self.bounds = bounds ?? .zero; self.hasBounds = bounds != nil
    self.initialURL = initialURL
  }
}

/// What a leave-site dialog, when answered, decides.
enum PendingDialog {
  /// A single tab close with the reason it reports when accepted.
  case tab(ArktCloseReason)
  /// The tab's window is closing.
  case window
}

final class ScriptedTab: NSObject, ArktTabHandle {
  unowned let facade: ScriptedFacade
  let containerView = NSView()
  private(set) var contentsView = NSView()
  var sessionId: Int32
  weak var owner: ScriptedBrowser?
  var browser: (any ArktBrowserHandle)? { owner }
  var url: URL?
  var title = ""
  var faviconPNG: Data?
  var isLoading = false
  /// Nearest first, as the header specifies.
  var back: [(url: URL, title: String)] = []
  var forward: [(url: URL, title: String)] = []
  var backEntries: [any ArktHistoryEntry] { back.map { ScriptedHistoryEntry(url: $0.url, title: $0.title) } }
  var forwardEntries: [any ArktHistoryEntry] { forward.map { ScriptedHistoryEntry(url: $0.url, title: $0.title) } }
  var canGoBack: Bool { !back.isEmpty }
  var canGoForward: Bool { !forward.isEmpty }
  let opener: (any ArktTabHandle)?
  let origin: ArktTabOrigin
  var isActive: Bool { owner?.active === self }
  var isClosing = false
  /// A `beforeunload` handler registered with sticky user activation.
  var wouldHoldClose = false
  var dialog: PendingDialog?
  /// Inserted later (a deferred createTab); calls queue until then.
  var isPending = false
  var queued: [() -> Void] = []
  /// Showing the initial about:blank, which is replaced by the first navigation and never kept in the history.
  var isInitialBlank = false
  /// The title the current load will report.
  private var loadingTitle: String?
  private var committedHost: String?
  private var lastHistory = (false, false)

  init(facade: ScriptedFacade, owner: ScriptedBrowser, opener: (any ArktTabHandle)?, origin: ArktTabOrigin) {
    self.facade = facade; self.owner = owner; self.opener = opener; self.origin = origin
    sessionId = facade.nextId()
    super.init()
    containerView.addSubview(contentsView)
  }

  private var current: (url: URL, title: String)? { url.map { ($0, title) } }

  private func record(_ kind: ArktEngineEventKind, _ fill: (ScriptedEvent) -> Void = { _ in }) {
    let event = ScriptedEvent(kind, tab: self, browser: owner)
    fill(event)
    facade.record(event)
  }

  /// Runs now, or after the deferred insert.
  private func whenInserted(_ call: @escaping () -> Void) {
    if isPending { queued.append(call) } else { call() }
  }

  // MARK: Loads

  func startLoad(_ target: URL, title: String?) {
    isInitialBlank = false
    url = target
    loadingTitle = title
    record(.urlChanged) { $0.url = target }
    if !isLoading {
      isLoading = true
      record(.loadingChanged) { $0.isLoading = true }
    }
    reportHistory()
  }

  /// The end of the current load: the document's title, a favicon clear on a host change, the load end, then the
  /// new favicon. With `facade.titleAfterLoadEnd` the title and the clear are recorded after the load end, in the
  /// same batch (contract rules 2 and 6 rely on ChromiumEngine's reordering).
  func finishLoad() {
    guard isLoading, let url else { return }
    let newTitle = loadingTitle ?? ScriptedFacade.title(of: url)
    let host = url.host ?? url.absoluteString
    let hostChanged = committedHost != nil && committedHost != host
    committedHost = host
    let clear = { [self] in
      if hostChanged, faviconPNG != nil {
        faviconPNG = nil
        record(.faviconChanged)
      }
    }
    let retitle = { [self] in
      if title != newTitle {
        title = newTitle
        record(.titleChanged) { $0.title = newTitle }
      }
    }
    if !facade.titleAfterLoadEnd { retitle(); clear() }
    isLoading = false
    record(.loadingChanged) { $0.isLoading = false }
    if facade.titleAfterLoadEnd { retitle(); clear() }
    if faviconPNG == nil {
      let png = Data("png:\(host)".utf8)
      faviconPNG = png
      record(.faviconChanged) { $0.faviconPNG = png }
    }
  }

  func setDocumentTitle(_ newTitle: String) {
    guard title != newTitle else { return }
    title = newTitle
    record(.titleChanged) { $0.title = newTitle }
  }

  private func reportHistory() {
    let now = (canGoBack, canGoForward)
    guard now != lastHistory else { return }
    lastHistory = now
    record(.historyChanged) { $0.canGoBack = now.0; $0.canGoForward = now.1 }
  }

  // MARK: ArktTabHandle

  func navigate(to target: URL) {
    whenInserted { [self] in
      guard owner != nil else { return }
      if let current, current.url != target, !isInitialBlank {
        back.insert(current, at: 0)
        forward = []
      }
      startLoad(target, title: nil)
    }
  }

  func reload() {
    whenInserted { [self] in
      guard owner != nil, url != nil, !isLoading else { return }
      isLoading = true
      record(.loadingChanged) { $0.isLoading = true }
    }
  }

  func goBack() { goToHistory(offset: -1) }
  func goForward() { goToHistory(offset: 1) }

  func goToHistory(offset: Int) {
    whenInserted { [self] in
      guard owner != nil, let here = current, offset != 0 else { return }
      let target: (url: URL, title: String)
      if offset < 0, -offset <= back.count {
        let steps = -offset
        target = back[steps - 1]
        forward = Array(back[..<(steps - 1)].reversed()) + [here] + forward
        back.removeFirst(steps)
      } else if offset > 0, offset <= forward.count {
        target = forward[offset - 1]
        back = Array(forward[..<(offset - 1)].reversed()) + [here] + back
        forward.removeFirst(offset)
      } else {
        return
      }
      startLoad(target.url, title: target.title)
    }
  }

  func activate() {
    whenInserted { [self] in owner?.activate(self) }
  }

  func close(mode: ArktCloseMode) -> ArktCloseResult {
    // As the real facade (`ScopedSkipUnloadHandlers`), a close that skips unload handlers runs whatever close is
    // under way, a pending leave-site dialog included; ChromiumEngine guards its own held close (`clientCloseHeld`).
    guard let owner, !isClosing || mode == .skipUnloadHandlers else {
      return isClosing ? .held : .closed
    }
    if isPending || facade.isNested {
      isClosing = true
      let deferred = { [self] in
        isClosing = false
        _ = close(mode: mode)
      }
      if isPending { queued.append(deferred) } else { facade.defer(deferred) }
      return .held
    }
    if wouldHoldClose && mode == .honourUnloadHandlers {
      isClosing = true
      dialog = .tab(.client)
      return .held
    }
    owner.remove(self, reason: .client)
    return .closed
  }

  /// How often the client asked for focus.
  private(set) var focusCount = 0
  func focus() { focusCount += 1 }

  func duplicate() -> (any ArktTabHandle)? {
    guard let owner else { return nil }
    let copy = owner.insertTab(opener: owner.active, origin: .client, active: true)
    copy.back = back
    copy.forward = forward
    if let url { copy.startLoad(url, title: title) }
    return copy
  }

  // MARK: Engine side

  /// `kReplaced` (crash recovery, prerender): new contents in the same container, a new session id.
  func replaceContents() {
    contentsView.removeFromSuperview()
    contentsView = NSView()
    containerView.addSubview(contentsView)
    sessionId = facade.nextId()
    record(.tabReplaced)
  }

  /// The dialog's answer (`answerDialogInTab:accept:`).
  func answer(accept: Bool) -> Bool {
    guard let pending = dialog, let owner else { return false }
    dialog = nil
    switch pending {
    case .tab(let reason):
      if accept {
        owner.remove(self, reason: reason)
      } else {
        isClosing = false
        record(.closeCancelled)
      }
    case .window:
      owner.windowDialogAnswered(by: self, accept: accept)
    }
    return true
  }
}

final class ScriptedBrowser: NSObject, ArktBrowserHandle {
  unowned let facade: ScriptedFacade
  let windowId: Int32
  let host: any ArktWindowHost
  private(set) var tabList: [ScriptedTab] = []
  private(set) weak var active: ScriptedTab?
  var tabs: [any ArktTabHandle] { tabList }
  var activeTab: (any ArktTabHandle)? { active }
  private(set) var isClosingWindow = false
  private(set) var isClosed = false
  /// Commands the host forwarded (`executeCommand`).
  var executed: [(command: Int, disposition: Int)] = []

  init(facade: ScriptedFacade, host: any ArktWindowHost) {
    self.facade = facade; self.host = host
    windowId = facade.nextId()
  }

  func createTab(url: URL?, active: Bool) -> any ArktTabHandle {
    if facade.isNested {
      let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .client)
      tab.isPending = true
      tab.sessionId = -1
      facade.defer { [self] in
        guard !isClosed else {
          tab.isPending = false
          tab.owner = nil
          let closed = ScriptedEvent(.tabClosed, tab: tab, browser: nil)
          closed.closeReason = .windowClosing
          facade.record(closed)
          return
        }
        tab.sessionId = facade.nextId()
        insert(tab, active: active, url: url)
        tab.isPending = false
        let calls = tab.queued
        tab.queued = []
        calls.forEach { $0() }
      }
      return tab
    }
    let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .client)
    insert(tab, active: active, url: url)
    return tab
  }

  @discardableResult
  func insertTab(opener: (any ArktTabHandle)?, origin: ArktTabOrigin, active: Bool) -> ScriptedTab {
    let tab = ScriptedTab(facade: facade, owner: self, opener: opener, origin: origin)
    insert(tab, active: active, url: nil)
    return tab
  }

  /// `chrome::NewEmptyWindow`'s tab: Chromium's New Tab page, created already showing its URL (#299).
  /// `urlAtInsert` false: the tab is inserted before its navigation starts (TabCreated without the URL).
  @discardableResult
  func insertNewTabPage(urlAtInsert: Bool = true) -> ScriptedTab {
    let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .engine)
    if urlAtInsert {
      tab.url = ScriptedFacade.newTabPage
      tab.title = "New Tab"
    }
    insert(tab, active: true, url: urlAtInsert ? nil : ScriptedFacade.newTabPage)
    return tab
  }

  /// A tab without a URL shows the initial about:blank, with no load events.
  private func insert(_ tab: ScriptedTab, active: Bool, url: URL?) {
    if tab.url == nil {
      tab.url = URL(string: "about:blank")
      tab.isInitialBlank = true
    }
    tabList.append(tab)
    let created = ScriptedEvent(.tabCreated, tab: tab, browser: self)
    created.url = tab.url; created.title = tab.title; created.opener = tab.opener; created.origin = tab.origin
    facade.record(created)
    if active || self.active == nil { activate(tab) }
    created.isActive = tab.isActive
    if let url { tab.startLoad(url, title: nil) }
  }

  func activate(_ tab: ScriptedTab) {
    guard active !== tab, tabList.contains(where: { $0 === tab }) else { return }
    active = tab
    facade.record(ScriptedEvent(.activeTabChanged, tab: tab, browser: self))
  }

  /// Removes a tab; closing the active tab activates its right neighbour, else the left one.
  func remove(_ tab: ScriptedTab, reason: ArktCloseReason, reactivate: Bool = true) {
    guard let index = tabList.firstIndex(where: { $0 === tab }) else { return }
    tabList.remove(at: index)
    tab.owner = nil
    tab.isClosing = false
    tab.dialog = nil
    let closed = ScriptedEvent(.tabClosed, tab: tab, browser: self)
    closed.closeReason = reason
    facade.record(closed)
    if active === tab {
      active = nil
      if reactivate, !tabList.isEmpty { activate(tabList[min(index, tabList.count - 1)]) }
    }
  }

  /// Moves a tab out to another window (`chrome.tabs.move`): same handle, same container.
  func move(_ tab: ScriptedTab, to target: ScriptedBrowser) {
    guard let index = tabList.firstIndex(where: { $0 === tab }) else { return }
    tabList.remove(at: index)
    if active === tab { active = nil }
    target.tabList.append(tab)
    tab.owner = target
    facade.record(ScriptedEvent(.tabMoved, tab: tab, browser: target))
    if target.active == nil { target.activate(tab) }
  }

  /// Unload processing first: a tab with a `beforeunload` handler holds the whole window close.
  func close() {
    guard !isClosed, !isClosingWindow else { return }
    let holding = tabList.filter(\.wouldHoldClose)
    guard holding.isEmpty else {
      isClosingWindow = true
      for tab in holding {
        tab.isClosing = true
        tab.dialog = .window
      }
      return
    }
    finishClose(reason: .windowClosing)
  }

  func windowDialogAnswered(by tab: ScriptedTab, accept: Bool) {
    guard isClosingWindow else { return }
    if accept {
      tab.isClosing = false
      guard !tabList.contains(where: { $0.dialog != nil }) else { return }
      isClosingWindow = false
      finishClose(reason: .windowClosing)
    } else {
      isClosingWindow = false
      for held in tabList where held.isClosing {
        held.isClosing = false
        held.dialog = nil
        facade.record(ScriptedEvent(.closeCancelled, tab: held, browser: self))
      }
    }
  }

  func finishClose(reason: ArktCloseReason) {
    for tab in tabList { remove(tab, reason: reason, reactivate: false) }
    isClosed = true
    facade.closed(self)
  }
}

/// The facade. One instance per test; several `ChromiumEngine`s may share it.
final class ScriptedFacade: NSObject, ArktEngine {
  private var lastId: Int32 = 100
  private var pending: [any ArktEngineEvent] = []
  private var deferred: [() -> Void] = []
  private var sinks: [(token: NSObject, sink: ([any ArktEngineEvent]) -> Void)] = []
  private var flushScheduled = false
  private(set) var browserList: [ScriptedBrowser] = []
  private(set) var batches: [[any ArktEngineEvent]] = []
  private(set) var ready = false
  private(set) var failed = false
  private(set) var ranActions: [(id: String, window: Int32, anchor: NSView)] = []
  private var actions: [ObjectIdentifier: [ScriptedAction]] = [:]

  /// While set, mutators defer their work to the next batch (a nested run loop is up).
  var isNested = false
  /// Records a load's title and favicon clear after its load end (Risk 2).
  var titleAfterLoadEnd = false
  /// While set, batches wait for `flush()`.
  var holdsBatches = false
  var testAPIEnabled = true
  /// Answers engine window requests (`-hostForEngineWindowRequest:` on the embedder).
  var hostProvider: ((any ArktWindowRequest) -> any ArktWindowHost)?

  var browsers: [any ArktBrowserHandle] { browserList.filter { !$0.isClosed } }
  /// No event waits for delivery.
  var isIdle: Bool { pending.isEmpty && deferred.isEmpty && !flushScheduled }

  func nextId() -> Int32 { lastId += 1; return lastId }

  func record(_ event: any ArktEngineEvent) {
    pending.append(event)
    scheduleFlush()
  }

  func `defer`(_ work: @escaping () -> Void) {
    deferred.append(work)
    scheduleFlush()
  }

  private func scheduleFlush() {
    guard !flushScheduled, !holdsBatches else { return }
    flushScheduled = true
    Task { @MainActor in self.flush() }
  }

  /// Runs deferred work, then delivers one batch to every sink, in order.
  func flush() {
    flushScheduled = false
    let work = deferred
    deferred = []
    work.forEach { $0() }
    guard !pending.isEmpty else { return }
    let batch = pending
    pending = []
    batches.append(batch)
    for entry in sinks { entry.sink(batch) }
  }

  func closed(_ browser: ScriptedBrowser) {
    browser.host.closeRequested = nil
    browser.host.validateCommand = nil
    browser.host.executeCommand = nil
    record(ScriptedEvent(.windowClosed, tab: nil, browser: browser))
  }

  // MARK: ArktEngine

  func embedderReady() { ready = true }
  func embedderFailed() { failed = true }

  func createBrowser(host: any ArktWindowHost) -> any ArktBrowserHandle {
    makeBrowser(host: host)
  }

  @discardableResult
  private func makeBrowser(host: any ArktWindowHost) -> ScriptedBrowser {
    let browser = ScriptedBrowser(facade: self, host: host)
    browserList.append(browser)
    host.closeRequested = { [unowned browser] in browser.close() }
    host.validateCommand = { $0 > 0 }
    host.executeCommand = { [unowned browser] command, disposition in
      browser.executed.append((command, disposition))
    }
    record(ScriptedEvent(.windowOpened, tab: nil, browser: browser))
    return browser
  }

  func extensionActions(in browser: any ArktBrowserHandle) -> [any ArktExtensionAction] {
    actions[ObjectIdentifier(browser)] ?? []
  }

  func runExtensionAction(_ actionId: String, in browser: any ArktBrowserHandle, anchor: NSView) {
    ranActions.append((actionId, browser.windowId, anchor))
  }

  func addEventSink(_ sink: @escaping ([any ArktEngineEvent]) -> Void) -> any NSObjectProtocol {
    let token = NSObject()
    sinks.append((token, sink))
    return token
  }

  func removeEventSink(_ token: any NSObjectProtocol) {
    sinks.removeAll { $0.token === token }
  }

  var sinkCount: Int { sinks.count }

  /// The scripts the harness drivers send, as the W3-9 runner will through the real test API.
  func evaluateScript(_ script: String, in tab: any ArktTabHandle, userGesture: Bool,
                      completion: @escaping (Any?, (any Error)?) -> Void) {
    let answer: (Any?, (any Error)?)
    if !testAPIEnabled {
      answer = (nil, NSError(domain: "ScriptedFacade", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "the test API is disabled"]))
    } else if let tab = tab as? ScriptedTab, tab.owner != nil {
      answer = (run(script, in: tab, userGesture: userGesture), nil)
    } else {
      answer = (nil, NSError(domain: "ScriptedFacade", code: 2,
                             userInfo: [NSLocalizedDescriptionKey: "The page went away before the script answered"]))
    }
    // The real facade answers from a posted task.
    Task { @MainActor in completion(answer.0, answer.1) }
  }

  private func run(_ script: String, in tab: ScriptedTab, userGesture: Bool) -> Any? {
    if let title = script.firstMatch(of: #/^document\.title = "(.*)"$/#)?.output.1 {
      tab.setDocumentTitle(String(title))
      return String(title)
    }
    if script.hasPrefix("window.onbeforeunload") {
      // Chromium shows the leave-site dialog only with sticky user activation.
      tab.wouldHoldClose = userGesture
      return true
    }
    if let target = script.firstMatch(of: #/^window\.open\("(.*)"\)$/#)?.output.1, let url = URL(string: String(target)) {
      guard userGesture, let owner = tab.owner else { return false }
      let opened = owner.insertTab(opener: tab, origin: .engine, active: true)
      opened.startLoad(url, title: nil)
      return true
    }
    if script == "window.close()" {
      engineCloseTab(tab, reason: .page)
      return NSNull()
    }
    if script == "({sum: 1 + 2, list: [1, \"two\", null], ok: true})" {
      return ["sum": NSNumber(value: 3), "list": [NSNumber(value: 1), "two", NSNull()], "ok": NSNumber(value: true)]
    }
    return nil
  }

  func answerDialog(in tab: any ArktTabHandle, accept: Bool) -> Bool {
    guard testAPIEnabled, let tab = tab as? ScriptedTab else { return false }
    return tab.answer(accept: accept)
  }

  // MARK: Engine-side drivers (what a page, an extension or the user does)

  /// `chrome.tabs.create` from an extension.
  @discardableResult
  func engineCreateTab(in browser: ScriptedBrowser, url: URL?, opener: ScriptedTab?, active: Bool) -> ScriptedTab {
    let tab = browser.insertTab(opener: opener, origin: .engine, active: active)
    if let url { tab.startLoad(url, title: nil) }
    return tab
  }

  /// `chrome.tabs.remove` (`.extension`) or `window.close()` (`.page`); held by a `beforeunload` handler.
  func engineCloseTab(_ tab: ScriptedTab, reason: ArktCloseReason) {
    guard let owner = tab.owner else { return }
    if tab.wouldHoldClose {
      tab.isClosing = true
      tab.dialog = .tab(reason)
      return
    }
    owner.remove(tab, reason: reason)
  }

  /// `chrome.tabs.update({active: true})`.
  func engineActivate(_ tab: ScriptedTab) { tab.owner?.activate(tab) }

  /// `chrome.windows.create` and friends: asks the embedder for a host inside construction, then a first tab.
  @discardableResult
  func openEngineWindow(_ request: ScriptedRequest) -> ScriptedBrowser? {
    guard let hostProvider else { return nil }
    let browser = makeBrowser(host: hostProvider(request))
    engineCreateTab(in: browser, url: request.initialURL, opener: nil, active: true)
    return browser
  }

  /// A Dock reopen with no window (`applicationShouldHandleReopen:` -> `chrome::NewEmptyWindow`): asks the embedder
  /// for a host inside construction, then adds the New Tab page. `kind` lets a test give the same window another
  /// request kind.
  @discardableResult
  func dockReopen(kind: ArktWindowRequestKind = .reopen, urlAtInsert: Bool = true) -> (ScriptedBrowser, ScriptedTab)? {
    guard let hostProvider else { return nil }
    let browser = makeBrowser(host: hostProvider(ScriptedRequest(kind: kind)))
    return (browser, browser.insertNewTabPage(urlAtInsert: urlAtInsert))
  }

  /// Chromium's New Tab page URL.
  // A constant literal that always parses.
  static let newTabPage = URL(string: "chrome://newtab/")!

  func setActions(_ list: [ScriptedAction], in browser: ScriptedBrowser) {
    actions[ObjectIdentifier(browser)] = list
    record(ScriptedEvent(.extensionActionsChanged, tab: nil, browser: browser))
  }

  /// Quit: every tab closes with `.appTerminating`, then every window.
  func terminate() {
    for browser in browsers.compactMap({ $0 as? ScriptedBrowser }) { browser.finishClose(reason: .appTerminating) }
  }

  /// The page's title for a test URL: its last path component.
  static func title(of url: URL) -> String {
    url.scheme == "about" ? "" : url.lastPathComponent
  }
}
