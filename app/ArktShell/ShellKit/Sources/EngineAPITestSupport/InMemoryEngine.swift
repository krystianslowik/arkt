import AppKit
import EngineAPI

/// Pure in-memory engine for tests and previews. Loads complete only when `finishLoad` is called,
/// which makes event order fully deterministic.
@MainActor
public final class InMemoryEngine: EngineClient {
  private var snapshots: [TabID: TabSnapshot] = [:]
  private var views: [TabID: NSView] = [:]
  /// Per-tab history: URLs behind and ahead of the current one (nearest last).
  private var history: [TabID: (back: [URL], forward: [URL])] = [:]
  private let hub = EngineEventHub()
  public private(set) var tabIDs: [TabID] = []

  public init() {}

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    let id = TabID()
    snapshots[id] = TabSnapshot(id: id)
    tabIDs.append(id)
    hub.emit(.tabCreated(id))
    if let url { navigate(id, to: url) }
    return id
  }

  public func closeTab(_ id: TabID) {
    guard snapshots.removeValue(forKey: id) != nil else { return }
    tabIDs.removeAll { $0 == id }
    views[id]?.removeFromSuperview()
    views[id] = nil
    history[id] = nil
    hub.emit(.tabClosed(id))
  }

  /// Starts a load and commits it at once: url, loading, then (on a host change) the favicon reset. A new
  /// navigation drops the forward history; navigating to the URL the tab already shows leaves the history alone,
  /// like a reload.
  public func navigate(_ id: TabID, to url: URL) {
    guard let previous = snapshots[id] else { return }
    if let current = previous.url, current != url {
      history[id, default: ([], [])].back.append(current)
      history[id, default: ([], [])].forward.removeAll()
    }
    load(id, url, previous: previous)
  }

  public func goBack(_ id: TabID) {
    guard let previous = snapshots[id], let target = history[id]?.back.popLast() else { return }
    if let current = previous.url { history[id, default: ([], [])].forward.append(current) }
    load(id, target, previous: previous)
  }

  public func goForward(_ id: TabID) {
    guard let previous = snapshots[id], let target = history[id]?.forward.popLast() else { return }
    if let current = previous.url { history[id, default: ([], [])].back.append(current) }
    load(id, target, previous: previous)
  }

  private func load(_ id: TabID, _ url: URL, previous: TabSnapshot) {
    snapshots[id]?.url = url
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

  public func reload(_ id: TabID) {
    guard let current = snapshots[id], current.url != nil, !current.isLoading else { return }
    snapshots[id]?.isLoading = true
    hub.emit(.loadingChanged(id, isLoading: true))
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
}

/// The page view of an in-memory tab. It accepts first responder like a real engine's page, so focus tests can
/// check where the window put it.
@MainActor
final class InMemoryPageView: NSView {
  override var acceptsFirstResponder: Bool { true }
}
