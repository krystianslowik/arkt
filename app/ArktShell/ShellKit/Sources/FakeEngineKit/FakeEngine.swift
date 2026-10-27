import AppKit
import struct ArcImport.ArcCookie
import struct ArcImport.BookmarkRecord
import struct ArcImport.ArcLogin
internal import WebKit
import EngineAPI

/// Development stand-in for the Chromium engine. Renders with WKWebView.
/// Windows and activation follow contract rules 11, 12 and 15. Every tab has `origin == .client` (WKWebView opens no
/// tabs of its own here) and closes never hold (`wouldHoldClose` is always false, so both close modes close at once);
/// rules 13, 14 and 16 are not applicable, and so is rule 17's audible state (no public WebKit signal). Find in page
/// (rule 22) selects with `window.find` and counts in page script; the hovered link (rule 23) comes from a script
/// that posts `mouseover` and `mouseout` of links.
/// Nothing outside this file may import WebKit, and the import is `internal`, so the compiler
/// rejects any WebKit type in the public surface (EngineAPI types and NSView only).
@MainActor
public final class FakeEngine: EngineClient, EngineImporting {
  /// What `importCookies` and `importPasswords` received, deduped as the engine does (#512). No profile is written.
  public private(set) var imports = ImportRecording()

  public func importCookies(_ batch: [ArcCookie]) async -> ImportWriteResult { imports.record(batch) }
  public func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult { imports.record(batch) }
  public func importHistory(_ batch: [ImportedHistoryEntry], after watermark: Date?) async -> ImportWriteResult {
    imports.record(batch, after: watermark)
  }
  public func importBookmarks(_ batch: [BookmarkRecord]) async -> ImportWriteResult { imports.record(batch) }

  private final class Entry {
    let webView: WKWebView
    let navigation: NavigationObserver
    var snapshot: TabSnapshot
    var observations: [NSKeyValueObservation] = []
    /// Host of the last committed navigation; a change resets the favicon (contract rule 6).
    var committedHost: String?
    /// Identifies the pending end-of-load step; nil when none is pending.
    var pendingFinish: Int?
    var finishCounter = 0
    /// Cloned history stacks (nearest last) when this tab was created by `duplicateTab(_:)` (#81, BH-027).
    var clonedHistory: (back: [HistoryEntry], forward: [HistoryEntry])?
    /// The text and case of the running find, nil when none runs; replies of an ended find are dropped by `findEpoch`.
    var findText: String?
    var findMatchCase = false
    var findEpoch = 0
    var findRequests = 0
    /// The link the pointer is over, as the hover script last reported it.
    var hoveredLink: URL?
    init(webView: WKWebView, navigation: NavigationObserver, snapshot: TabSnapshot) {
      self.webView = webView; self.navigation = navigation; self.snapshot = snapshot
    }
  }

  /// WKWebView holds its navigation delegate weakly; the entry keeps this alive.
  private final class NavigationObserver: NSObject, WKNavigationDelegate {
    var onCommit: (@MainActor () -> Void)?
    /// A user link activation in the main frame (#313): the link's URL and modifiers; true cancels it.
    var onLinkActivation: (@MainActor (URL, NSEvent.ModifierFlags) -> Bool)?
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { onCommit?() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
      guard action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true,
            let url = action.request.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let decide = onLinkActivation else {
        decisionHandler(.allow)
        return
      }
      decisionHandler(decide(url, action.modifierFlags) ? .cancel : .allow)
    }
  }

  /// How long the end of a load waits for `document.title` before using what WebKit already knows.
  static let titleTimeout: Duration = .milliseconds(500)

  /// Receives the hover script's messages (#114). The user content controller holds it, so it holds the engine weakly.
  private final class LinkHoverBridge: NSObject, WKScriptMessageHandler {
    weak var engine: FakeEngine?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      MainActor.assumeIsolated {
        engine?.targetURLReported(by: message.webView, body: message.body)
      }
    }
  }

  private var entries: [TabID: Entry] = [:]
  private let hoverBridge = LinkHoverBridge()
  private let hub = EngineEventHub()
  public private(set) var windowIDs: [EngineWindowID] = []
  private var hosts: [EngineWindowID: any EngineWindowHosting] = [:]
  private var activeTabs: [EngineWindowID: TabID] = [:]
  private var lastActiveWindow: EngineWindowID?
  private let configuration: WKWebViewConfiguration
  private let faviconSession = URLSession(configuration: .ephemeral)
  /// Favicon fetches in flight per tab, and the test waits for the last one to finish (#442).
  private var faviconFetches: [TabID: Int] = [:]
  private var faviconFetchWaiters: [TabID: [FaviconFetchWaiter]] = [:]
  public private(set) var tabIDs: [TabID] = []

  public init() {
    configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    // Appended to WebKit's own platform and engine tokens, so only the Safari part is ours to set.
    configuration.applicationNameForUserAgent = SafariUserAgent.applicationName()
    hoverBridge.engine = self
    configuration.userContentController.add(hoverBridge, name: FakeEngineScripts.targetURLHandler)
    configuration.userContentController.addUserScript(
      WKUserScript(source: FakeEngineScripts.hover, injectionTime: .atDocumentStart, forMainFrameOnly: false))
  }

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    makeTab(url: url, window: lastActiveWindow.flatMap { windowIDs.contains($0) ? $0 : nil })
  }

  @discardableResult
  public func createTab(url: URL?, in window: EngineWindowID) -> TabID {
    precondition(windowIDs.contains(window), "createTab(url:in:) needs a listed window, got \(window)")
    lastActiveWindow = window
    return makeTab(url: url, window: window)
  }

  private func makeTab(url: URL?, window: EngineWindowID?) -> TabID {
    let id = TabID()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    let navigation = NavigationObserver()
    navigation.onCommit = { [weak self] in self?.didCommit(id) }
    navigation.onLinkActivation = { [weak self] url, flags in self?.linkActivated(id, url: url, flags: flags) ?? false }
    webView.navigationDelegate = navigation
    let entry = Entry(webView: webView, navigation: navigation, snapshot: TabSnapshot(id: id, window: window))
    entries[id] = entry
    tabIDs.append(id)
    hub.assign(id, to: window)
    hub.emit(.tabCreated(id))
    if let window, activeTabs[window] == nil { setActive(id) }
    // KVO handlers are not main-actor isolated in the SDK annotations, but WKWebView
    // always reports on the main thread, so assumeIsolated is a checked, correct hop.
    entry.observations = [
      webView.observe(\.url, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated { self?.update(id) { $0.url = web.url } event: { .urlChanged(id, web.url) } }
      },
      webView.observe(\.title, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated {
          let title = web.title ?? ""
          self?.update(id) { $0.title = title } event: { .titleChanged(id, title) }
        }
      },
      webView.observe(\.isLoading, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated {
          if web.isLoading { self?.startLoad(id) } else { self?.finishLoad(id) }
        }
      },
      webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.syncHistory(id) }
      },
      webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.syncHistory(id) }
      },
    ]
    if let url { navigate(id, to: url) }
    return id
  }

  public func closeTab(_ id: TabID) { closeTab(id, mode: .honourUnloadHandlers) }

  /// Never held: WKWebView offers no `beforeunload` hold here, so both modes close at once.
  public func closeTab(_ id: TabID, mode: CloseMode) { removeTab(id, reason: .client, reactivate: true) }

  private func removeTab(_ id: TabID, reason: CloseReason, reactivate: Bool) {
    guard let entry = entries[id] else { return }
    var successor: TabID?
    if let window = entry.snapshot.window, activeTabs[window] == id {
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
    entries[id] = nil
    faviconFetches[id] = nil
    for waiter in faviconFetchWaiters.removeValue(forKey: id) ?? [] { waiter.resume() }
    entry.observations.forEach { $0.invalidate() }
    entry.navigation.onCommit = nil
    entry.webView.navigationDelegate = nil
    entry.webView.stopLoading()
    entry.webView.removeFromSuperview()
    tabIDs.removeAll { $0 == id }
    hub.emit(.tabClosed(id, reason: reason))
    if let successor { setActive(successor) }
  }

  public func navigate(_ id: TabID, to url: URL) {
    guard let entry = entries[id] else { return }
    if entry.clonedHistory != nil, let current = entry.snapshot.url, current != url {
      entry.clonedHistory?.back.append(HistoryEntry(url: current, title: entry.snapshot.title))
      entry.clonedHistory?.forward.removeAll()
    }
    loadURL(url, in: entry.webView)
  }

  private func loadURL(_ url: URL, in web: WKWebView) {
    if url.isFileURL {
      web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
      web.load(URLRequest(url: url))
    }
  }

  public func reload(_ id: TabID) { entries[id]?.webView.reload() }

  /// WKWebView has no public mute: a muted tab suspends its media playback (HTML media, not Web Audio) until it is
  /// unmuted. `isAudible` is never reported here; WKWebView has no public audible signal.
  public func setMuted(_ id: TabID, muted: Bool) {
    guard let entry = entries[id], entry.snapshot.isMuted != muted else { return }
    entry.webView.setAllMediaPlaybackSuspended(muted, completionHandler: nil)
    update(id) { $0.isMuted = muted } event: { .mutedChanged(id, isMuted: muted) }
  }

  // MARK: - Find in page and link hover (#134, #114)

  /// `window.find` selects the match and the page text is counted for the reply; WKWebView's own find reports no
  /// count. A reply for a find that ended meanwhile is dropped.
  public func findInPage(_ id: TabID, text: String, forward: Bool, matchCase: Bool) {
    guard let entry = entries[id] else { return }
    guard !text.isEmpty else {
      endFind(entry, action: .clear)
      hub.emit(.findResult(id, requestID: 0, ordinal: 0, count: 0, isFinal: true))
      return
    }
    let isNew = entry.findText != text || entry.findMatchCase != matchCase
    entry.findText = text
    entry.findMatchCase = matchCase
    entry.findRequests += 1
    let request = entry.findRequests
    let epoch = entry.findEpoch
    let script = FakeEngineScripts.find(text: text, forward: forward, matchCase: matchCase, isNew: isNew)
    entry.webView.evaluateJavaScript(script) { [weak self, weak entry] result, _ in
      MainActor.assumeIsolated {
        guard let self, let entry, entry.findEpoch == epoch, self.entries[id] === entry else { return }
        let numbers = (result as? [NSNumber])?.map(\.intValue) ?? []
        let count = numbers.first ?? 0
        let ordinal = numbers.count > 1 ? numbers[1] : 0
        self.hub.emit(.findResult(id, requestID: request, ordinal: ordinal, count: count, isFinal: true))
      }
    }
  }

  public func stopFinding(_ id: TabID, action: FindStopAction) {
    guard let entry = entries[id] else { return }
    endFind(entry, action: action)
  }

  private func endFind(_ entry: Entry, action: FindStopAction) {
    entry.findText = nil
    entry.findEpoch += 1
    entry.webView.evaluateJavaScript(FakeEngineScripts.stopFind(action), completionHandler: nil)
  }

  private func targetURLReported(by web: WKWebView?, body: Any) {
    guard let (id, entry) = entries.first(where: { $0.value.webView === web }) else { return }
    let link = (body as? String).flatMap(URL.init(string:))
    guard entry.hoveredLink != link else { return }
    entry.hoveredLink = link
    hub.emit(.targetURLChanged(id, link))
  }

  /// A new document ends the page's find and its hovered link.
  private func endFindAndHover(_ id: TabID, _ entry: Entry) {
    entry.findText = nil
    entry.findEpoch += 1
    if entry.hoveredLink != nil {
      entry.hoveredLink = nil
      hub.emit(.targetURLChanged(id, nil))
    }
  }

  public func goBack(_ id: TabID) { goToHistory(id, offset: -1) }
  public func goForward(_ id: TabID) { goToHistory(id, offset: 1) }

  public func goToHistory(_ id: TabID, offset: Int) {
    guard offset != 0, let entry = entries[id] else { return }
    if var stack = entry.clonedHistory {
      var current: HistoryEntry? = entry.snapshot.url.map { HistoryEntry(url: $0, title: entry.snapshot.title) }
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
      entry.clonedHistory = stack
      syncHistory(id)
      loadURL(target.url, in: entry.webView)
      return
    }
    guard let item = entry.webView.backForwardList.item(at: offset) else { return }
    entry.webView.go(to: item)
  }

  public func history(of id: TabID) -> TabHistory? {
    guard let entry = entries[id] else { return nil }
    if let stack = entry.clonedHistory {
      return TabHistory(back: Array(stack.back.reversed()), forward: Array(stack.forward.reversed()))
    }
    let back = entry.webView.backForwardList.backList.reversed().map {
      HistoryEntry(url: $0.url, title: $0.title ?? "")
    }
    let forward = entry.webView.backForwardList.forwardList.map {
      HistoryEntry(url: $0.url, title: $0.title ?? "")
    }
    return TabHistory(back: back, forward: forward)
  }

  @discardableResult
  public func duplicateTab(_ id: TabID) -> TabID? {
    guard let sourceEntry = entries[id], let sourceHistory = history(of: id) else { return nil }
    let copy = makeTab(url: nil, window: sourceEntry.snapshot.window)
    guard let copyEntry = entries[copy] else { return nil }
    copyEntry.clonedHistory = (
      back: Array(sourceHistory.back.reversed()),
      forward: Array(sourceHistory.forward.reversed())
    )
    syncHistory(copy)
    if let url = sourceEntry.snapshot.url {
      loadURL(url, in: copyEntry.webView)
    }
    return copy
  }

  public func snapshot(of id: TabID) -> TabSnapshot? { entries[id]?.snapshot }
  public func contentView(for id: TabID) -> NSView? { entries[id]?.webView }

  /// WebKit's snapshot of the shown page (#370, #352), asked at the width that fits the pixel cap so WebKit does the
  /// downscale; the caps are applied by `PageImageEncoder` off the main thread. Nil for a tab that is not in a window
  /// or has no size (nothing drawn), and for one that closed meanwhile.
  public func pageImage(of id: TabID, _ request: PageImageRequest) async -> PageImage? {
    guard let web = entries[id]?.webView, web.url != nil, let window = web.window,
          web.bounds.width > 0, web.bounds.height > 0 else { return nil }
    let scale = window.backingScaleFactor
    let configuration = WKSnapshotConfiguration()
    if let cap = request.maxPixelSize {
      let factor = min(1, Double(cap.width) / (web.bounds.width * scale), Double(cap.height) / (web.bounds.height * scale))
      configuration.snapshotWidth = NSNumber(value: web.bounds.width * factor)
    }
    guard let snapshot = try? await web.takeSnapshot(configuration: configuration),
          let frame = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
          entries[id]?.webView === web else { return nil }
    // Pixels per point of the page: the snapshot's pixels over the page's width in points.
    let pageScale = Double(frame.width) / web.bounds.width
    return await PageImageEncoder.encode(frame, scale: pageScale, request)
  }

  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { hub.add(handler) }

  // MARK: - Windows

  @discardableResult
  public func createWindow(host: any EngineWindowHosting) -> EngineWindowID {
    let id = EngineWindowID()
    windowIDs.append(id)
    hosts[id] = host
    lastActiveWindow = id
    host.onCloseRequested = { [weak self] in self?.closeWindow(id) }
    // The page commands WKWebView can run on the window's active tab; everything else the host does not claim is
    // disabled (week-3 plan, W3-7 part D step 3).
    host.forward = EngineCommandForwarding(
      validate: { [weak self] command in self?.canExecute(command, in: id) ?? false },
      execute: { [weak self] command, _ in self?.execute(command, in: id) })
    hub.emit(.windowOpened(id))
    return id
  }

  public func closeWindow(_ id: EngineWindowID) { closeWindow(id, reason: .userClose) }

  /// Closes never hold here, so the window goes at once; its tabs close with `.windowClosing` (#401: FakeEngine has
  /// no extensions, so a window closes as the user's or as emptied by its last tab).
  private func closeWindow(_ id: EngineWindowID, reason: WindowCloseReason) {
    guard windowIDs.contains(id) else { return }
    for tab in tabs(in: id) { removeTab(tab, reason: .windowClosing, reactivate: false) }
    windowIDs.removeAll { $0 == id }
    activeTabs[id] = nil
    if let host = hosts.removeValue(forKey: id) {
      host.onCloseRequested = nil
      host.forward = nil
    }
    if lastActiveWindow == id { lastActiveWindow = windowIDs.last }
    hub.emit(.windowClosed(id, reason: reason))
  }

  public func activateTab(_ id: TabID) { setActive(id) }

  /// The web view moves with the tab: the shell remounts it in the new window, nothing reloads.
  public func moveTab(_ id: TabID, to window: EngineWindowID) {
    guard let entry = entries[id], let source = entry.snapshot.window, source != window,
          windowIDs.contains(window) else { return }
    if activeTabs[source] == id { activeTabs[source] = nil }
    entry.snapshot.window = window
    entry.snapshot.isActive = false
    tabIDs.removeAll { $0 == id }
    tabIDs.append(id)
    hub.assign(id, to: window)
    setActive(id)
    let left = tabs(in: source)
    if left.isEmpty {
      closeWindow(source, reason: .lastTabClosed)
    } else if activeTabs[source] == nil, let successor = left.last {
      setActive(successor)
      lastActiveWindow = window
    }
  }

  /// Asks the tab's window host about a link click (#313). WebKit runs a modified click in the same frame, so the
  /// disposition is the one Chromium would give it: Shift a new window, Command a background tab.
  private func linkActivated(_ id: TabID, url: URL, flags: NSEvent.ModifierFlags) -> Bool {
    guard let snapshot = entries[id]?.snapshot, let window = snapshot.window, let host = hosts[window] else {
      return false
    }
    let modifiers = EngineLinkModifiers(flags)
    let disposition: EngineDisposition = modifiers.contains(.command) ? .newBackgroundTab
      : modifiers.contains(.shift) ? .newWindow : .currentTab
    let activation = EngineLinkActivation(url: url, sourceTab: id, sourceURL: snapshot.url, modifiers: modifiers,
                                          disposition: disposition)
    return host.decideLinkActivation(activation) == .cancel
  }

  // MARK: - Page commands

  /// WKWebView's page zoom steps, as Safari's.
  private static let zoomSteps: [CGFloat] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

  /// Whether `command` runs on `window`'s active tab: reload, stop, back and forward with history, and zoom.
  func canExecute(_ command: EngineCommand, in window: EngineWindowID) -> Bool {
    guard let tab = activeTabs[window], let entry = entries[tab] else { return false }
    switch command {
    case .reload, .reloadBypassingCache: return true
    case .stop: return entry.snapshot.isLoading
    case .back: return entry.snapshot.canGoBack
    case .forward: return entry.snapshot.canGoForward
    case .zoomIn: return entry.webView.pageZoom < Self.zoomSteps[Self.zoomSteps.count - 1]
    case .zoomOut: return entry.webView.pageZoom > Self.zoomSteps[0]
    case .zoomReset: return entry.webView.pageZoom != 1
    default: return false
    }
  }

  func execute(_ command: EngineCommand, in window: EngineWindowID) {
    guard canExecute(command, in: window), let tab = activeTabs[window], let web = entries[tab]?.webView else {
      return
    }
    switch command {
    case .reload: web.reload()
    case .reloadBypassingCache: web.reloadFromOrigin()
    case .stop: web.stopLoading()
    case .back: goBack(tab)
    case .forward: goForward(tab)
    case .zoomIn: web.pageZoom = Self.zoomSteps.first { $0 > web.pageZoom + 0.001 } ?? web.pageZoom
    case .zoomOut: web.pageZoom = Self.zoomSteps.last { $0 < web.pageZoom - 0.001 } ?? web.pageZoom
    case .zoomReset: web.pageZoom = 1
    default: break
    }
  }

  public func activeTab(in window: EngineWindowID) -> TabID? { activeTabs[window] }

  public func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    hub.addWindowObserver(handler)
  }

  public func observe(window: EngineWindowID,
                      _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(window: window, handler)
  }

  private func tabs(in window: EngineWindowID) -> [TabID] {
    tabIDs.filter { entries[$0]?.snapshot.window == window }
  }

  private func setActive(_ id: TabID) {
    guard let window = entries[id]?.snapshot.window else { return }
    lastActiveWindow = window
    let previous = activeTabs[window]
    guard previous != id else { return }
    if let previous { entries[previous]?.snapshot.isActive = false }
    entries[id]?.snapshot.isActive = true
    activeTabs[window] = id
    hub.emit(.activeTabChanged(id))
  }

  /// Test hook (reachable through `@testable import`): runs page script and answers its string result.
  func scriptString(_ script: String, in id: TabID) async -> String? {
    guard let web = entries[id]?.webView else { return nil }
    return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
      web.evaluateJavaScript(script) { result, _ in done.resume(returning: result as? String) }
    }
  }

  /// Test hook (reachable through `@testable import`): runs page script, ignoring its result.
  func runScript(_ script: String, in id: TabID) async {
    guard let web = entries[id]?.webView else { return }
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      web.evaluateJavaScript(script) { _, _ in done.resume() }
    }
  }

  // MARK: - Load lifecycle

  /// Contract rule 2 wants urlChanged before loadingChanged(true). WKWebView usually reports url
  /// first; syncing it here makes the order hold regardless (the late url KVO then emits nothing).
  private func startLoad(_ id: TabID) {
    guard let entry = entries[id] else { return }
    entry.pendingFinish = nil
    endFindAndHover(id, entry)
    let url = entry.webView.url
    update(id) { $0.url = url } event: { .urlChanged(id, url) }
    update(id) { $0.isLoading = true } event: { .loadingChanged(id, isLoading: true) }
  }

  private func didCommit(_ id: TabID) {
    guard let entry = entries[id] else { return }
    let host = entry.webView.url?.host()
    guard host != entry.committedHost else { return }
    entry.committedHost = host
    update(id) { $0.faviconData = nil } event: { .faviconChanged(id, nil) }
  }

  /// WKWebView reports the end of a load (isLoading KVO and even didFinish) before its title KVO
  /// fires. The contract wants a title present in the document reported before loadingChanged(false),
  /// so read `document.title` first; the late title KVO then sees no change and emits nothing.
  /// If the script does not answer within `titleTimeout`, finish with the title WebKit has.
  private func finishLoad(_ id: TabID) {
    guard let entry = entries[id] else { return }
    entry.finishCounter += 1
    let token = entry.finishCounter
    entry.pendingFinish = token
    entry.webView.evaluateJavaScript("document.title") { [weak self] result, _ in
      MainActor.assumeIsolated { self?.completeLoad(id, token: token, documentTitle: result as? String) }
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: Self.titleTimeout)
      self?.completeLoad(id, token: token, documentTitle: nil)
    }
  }

  private func completeLoad(_ id: TabID, token: Int, documentTitle: String?) {
    // Runs once per finished load; a new navigation (or closing the tab) cancels it.
    guard let entry = entries[id], entry.pendingFinish == token, !entry.webView.isLoading else { return }
    entry.pendingFinish = nil
    let url = entry.webView.url
    let title = documentTitle ?? entry.webView.title ?? ""
    update(id) { $0.url = url } event: { .urlChanged(id, url) }
    update(id) { $0.title = title } event: { .titleChanged(id, title) }
    syncHistory(id)
    update(id) { $0.isLoading = false } event: { .loadingChanged(id, isLoading: false) }
    fetchFavicon(id)
  }

  /// Copies both history flags from WebKit, so one back-forward list change emits one `.historyChanged` whichever
  /// KVO fires first (contract rule 8). Also run before a load ends, so the snapshot is current by then.
  private func syncHistory(_ id: TabID) {
    guard let entry = entries[id] else { return }
    let (back, forward): (Bool, Bool)
    if let stack = entry.clonedHistory {
      back = !stack.back.isEmpty
      forward = !stack.forward.isEmpty
    } else {
      back = entry.webView.canGoBack
      forward = entry.webView.canGoForward
    }
    update(id) { $0.canGoBack = back; $0.canGoForward = forward } event: {
      .historyChanged(id, canGoBack: back, canGoForward: forward)
    }
  }

  /// Applies a change and emits its event only if the snapshot actually changed.
  private func update(_ id: TabID, _ mutate: (inout TabSnapshot) -> Void, event: () -> EngineEvent) {
    guard let entry = entries[id] else { return }
    var next = entry.snapshot
    mutate(&next)
    guard next != entry.snapshot else { return }
    entry.snapshot = next
    hub.emit(event())
  }

  // MARK: - Favicon

  /// One test waiter. Whichever of the fetch finishing or the deadline arrives first resumes it, and the
  /// continuation is dropped so the other path cannot resume it again.
  @MainActor
  private final class FaviconFetchWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func resume() {
      continuation?.resume()
      continuation = nil
    }
  }

  /// Test hook (reachable through `@testable import`): waits for the favicon fetch in flight for `id`, if any,
  /// but no longer than 10 s. The deadline only bounds a test; a fetch that finishes resumes at once.
  func waitForFaviconFetch(_ id: TabID) async {
    guard faviconFetches[id, default: 0] > 0 else { return }
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      let waiter = FaviconFetchWaiter(done)
      faviconFetchWaiters[id, default: []].append(waiter)
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(10))
        self?.expireFaviconFetchWaiter(waiter, for: id)
      }
    }
  }

  private func expireFaviconFetchWaiter(_ waiter: FaviconFetchWaiter, for id: TabID) {
    faviconFetchWaiters[id]?.removeAll { $0 === waiter }
    if faviconFetchWaiters[id]?.isEmpty == true { faviconFetchWaiters[id] = nil }
    waiter.resume()
  }

  private func beginFaviconFetch(_ id: TabID) {
    faviconFetches[id, default: 0] += 1
  }

  private func finishFaviconFetch(_ id: TabID) {
    guard let count = faviconFetches[id] else { return }
    guard count > 1 else {
      faviconFetches[id] = nil
      for waiter in faviconFetchWaiters.removeValue(forKey: id) ?? [] { waiter.resume() }
      return
    }
    faviconFetches[id] = count - 1
  }

  /// Prototype favicon: <link rel=icon> or /favicon.ico, fetched with an ephemeral URLSession and
  /// accepted only as an HTTP 200 image/* response. Real engines push it.
  private func fetchFavicon(_ id: TabID) {
    guard let web = entries[id]?.webView, let pageURL = web.url, !pageURL.isFileURL else { return }
    beginFaviconFetch(id)
    let script = "(document.querySelector('link[rel~=\"icon\"]') || {}).href || ''"
    let session = faviconSession
    web.evaluateJavaScript(script) { [weak self] result, _ in
      MainActor.assumeIsolated {
        let href = (result as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        guard let iconURL = href ?? URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL else {
          self?.finishFaviconFetch(id)
          return
        }
        Task { @MainActor [weak self] in
          guard let (data, response) = try? await session.data(from: iconURL),
                let http = response as? HTTPURLResponse, http.statusCode == 200,
                http.mimeType?.lowercased().hasPrefix("image/") == true,
                self?.entries[id]?.snapshot.url == pageURL else {
            self?.finishFaviconFetch(id)
            return
          }
          self?.update(id) { $0.faviconData = data } event: { .faviconChanged(id, data) }
          self?.finishFaviconFetch(id)
        }
      }
    }
  }
}
