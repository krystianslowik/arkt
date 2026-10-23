import AppKit
internal import WebKit
import EngineAPI

/// Development stand-in for the Chromium engine. Renders with WKWebView.
/// Nothing outside this file may import WebKit, and the import is `internal`, so the compiler
/// rejects any WebKit type in the public surface (EngineAPI types and NSView only).
@MainActor
public final class FakeEngine: EngineClient {
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
    init(webView: WKWebView, navigation: NavigationObserver, snapshot: TabSnapshot) {
      self.webView = webView; self.navigation = navigation; self.snapshot = snapshot
    }
  }

  /// WKWebView holds its navigation delegate weakly; the entry keeps this alive.
  private final class NavigationObserver: NSObject, WKNavigationDelegate {
    var onCommit: (@MainActor () -> Void)?
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { onCommit?() }
  }

  /// How long the end of a load waits for `document.title` before using what WebKit already knows.
  static let titleTimeout: Duration = .milliseconds(500)

  private var entries: [TabID: Entry] = [:]
  private let hub = EngineEventHub()
  private let configuration: WKWebViewConfiguration
  private let faviconSession = URLSession(configuration: .ephemeral)
  public private(set) var tabIDs: [TabID] = []

  public init() {
    configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    // Appended to WebKit's own platform and engine tokens, so only the Safari part is ours to set.
    configuration.applicationNameForUserAgent = SafariUserAgent.applicationName()
  }

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    let id = TabID()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    let navigation = NavigationObserver()
    navigation.onCommit = { [weak self] in self?.didCommit(id) }
    webView.navigationDelegate = navigation
    let entry = Entry(webView: webView, navigation: navigation, snapshot: TabSnapshot(id: id))
    entries[id] = entry
    tabIDs.append(id)
    hub.emit(.tabCreated(id))
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

  public func closeTab(_ id: TabID) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.observations.forEach { $0.invalidate() }
    entry.navigation.onCommit = nil
    entry.webView.navigationDelegate = nil
    entry.webView.stopLoading()
    entry.webView.removeFromSuperview()
    tabIDs.removeAll { $0 == id }
    hub.emit(.tabClosed(id))
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
    let copy = createTab(url: nil)
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
  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { hub.add(handler) }

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

  /// Prototype favicon: <link rel=icon> or /favicon.ico, fetched with an ephemeral URLSession and
  /// accepted only as an HTTP 200 image/* response. Real engines push it.
  private func fetchFavicon(_ id: TabID) {
    guard let web = entries[id]?.webView, let pageURL = web.url, !pageURL.isFileURL else { return }
    let script = "(document.querySelector('link[rel~=\"icon\"]') || {}).href || ''"
    let session = faviconSession
    web.evaluateJavaScript(script) { [weak self] result, _ in
      MainActor.assumeIsolated {
        let href = (result as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        guard let iconURL = href ?? URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL else { return }
        Task { @MainActor [weak self] in
          guard let (data, response) = try? await session.data(from: iconURL),
                let http = response as? HTTPURLResponse, http.statusCode == 200,
                http.mimeType?.lowercased().hasPrefix("image/") == true,
                self?.entries[id]?.snapshot.url == pageURL else { return }
          self?.update(id) { $0.faviconData = data } event: { .faviconChanged(id, data) }
        }
      }
    }
  }
}
