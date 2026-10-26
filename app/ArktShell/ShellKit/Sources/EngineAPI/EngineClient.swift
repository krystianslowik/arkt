import AppKit

/// Opaque per-tab identity issued by the engine.
public struct TabID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// Who created a tab.
public enum TabOrigin: Equatable, Sendable {
  /// This client: `createTab`, `duplicateTab`.
  case client
  /// The engine on its own: a link with `target=_blank`, `window.open`, `chrome.tabs.create`, a startup URL.
  case engine
}

/// How a close treats the page's unload handlers (Decision 11).
public enum CloseMode: Equatable, Sendable {
  /// Chrome's behaviour: a `beforeunload` handler may hold the close behind a leave-site dialog. Cmd-W.
  case honourUnloadHandlers
  /// Closes without firing `beforeunload`; never held by a page. Unload handlers still run without blocking.
  case skipUnloadHandlers
}

/// Why a tab closed (Decision 12). The shell removes a sidebar row only for `.page` and `.extension`;
/// `.windowClosing` and `.appTerminating` only unload.
public enum CloseReason: Equatable, Sendable {
  /// This client asked (`closeTab`).
  case client
  /// The page closed itself (`window.close()`).
  case page
  /// An extension closed it (`chrome.tabs.remove`, `chrome.windows.remove`).
  case `extension`
  /// Its window is being closed (`closeWindow`, the window's close button).
  case windowClosing
  /// The application is quitting.
  case appTerminating
}

/// Latest known state of a tab. Value type; safe to hand to any layer.
public struct TabSnapshot: Equatable, Sendable {
  public var id: TabID
  public var url: URL?
  public var title: String
  /// Raw favicon bytes (PNG or ICO). Data, not NSImage, so snapshots stay Sendable.
  public var faviconData: Data?
  public var isLoading: Bool
  /// The tab's history has an entry behind the current one (Toolbar Back; contract rule 8).
  public var canGoBack: Bool
  /// The tab's history has an entry ahead of the current one (Toolbar Forward; contract rule 8).
  public var canGoForward: Bool
  /// The window the tab is in (contract rule 11). Nil only for a tab created with `createTab(url:)` while the engine
  /// has no window, which in-process engines (InMemoryEngine, FakeEngine) allow.
  public var window: EngineWindowID?
  /// The tab that opened it, when there is one (contract rule 13).
  public var opener: TabID?
  public var origin: TabOrigin
  /// The tab is its window's active tab (contract rule 12).
  public var isActive: Bool
  /// A held close is pending: the tab stays listed until `.tabClosed` or `.closeCancelled` (contract rule 16).
  public var isClosing: Bool
  /// A close with `.honourUnloadHandlers` would be held now (the page has a `beforeunload` handler). Auto-archive
  /// skips such a tab (Decision 11).
  public var wouldHoldClose: Bool

  public init(id: TabID, url: URL? = nil, title: String = "", faviconData: Data? = nil, isLoading: Bool = false,
              canGoBack: Bool = false, canGoForward: Bool = false, window: EngineWindowID? = nil,
              opener: TabID? = nil, origin: TabOrigin = .client, isActive: Bool = false, isClosing: Bool = false,
              wouldHoldClose: Bool = false) {
    self.id = id; self.url = url; self.title = title; self.faviconData = faviconData; self.isLoading = isLoading
    self.canGoBack = canGoBack; self.canGoForward = canGoForward
    self.window = window; self.opener = opener; self.origin = origin; self.isActive = isActive
    self.isClosing = isClosing; self.wouldHoldClose = wouldHoldClose
  }
}

/// One entry in a tab's back or forward history (#81, GS-024, GS-025).
public struct HistoryEntry: Equatable, Sendable {
  public var url: URL
  public var title: String

  public init(url: URL, title: String = "") {
    self.url = url
    self.title = title
  }
}

/// Back and forward history of a tab, ordered nearest-first (`back.first` is one step back; `forward.first` is one
/// step forward; #81, GS-024, GS-025).
public struct TabHistory: Equatable, Sendable {
  public var back: [HistoryEntry]
  public var forward: [HistoryEntry]

  public init(back: [HistoryEntry] = [], forward: [HistoryEntry] = []) {
    self.back = back
    self.forward = forward
  }
}

public enum EngineEvent: Equatable, Sendable {
  case tabCreated(TabID)
  /// Terminal: nothing follows for the tab (contract rule 4). Carries why it closed (Decision 12).
  case tabClosed(TabID, reason: CloseReason)
  case urlChanged(TabID, URL?)
  case titleChanged(TabID, String)
  case faviconChanged(TabID, Data?)
  case loadingChanged(TabID, isLoading: Bool)
  /// Back or Forward availability changed; carries both, as in the snapshot (contract rule 8).
  case historyChanged(TabID, canGoBack: Bool, canGoForward: Bool)
  /// The tab became its window's active tab, by `activateTab` or by the engine (contract rules 12, 13).
  case activeTabChanged(TabID)
  /// A held close was cancelled (the user stayed on the page); the tab stays open (contract rule 16).
  case closeCancelled(TabID)

  public var tabID: TabID {
    switch self {
    case .tabCreated(let id), .tabClosed(let id, _), .urlChanged(let id, _), .titleChanged(let id, _),
         .faviconChanged(let id, _), .loadingChanged(let id, _), .historyChanged(let id, _, _),
         .activeTabChanged(let id), .closeCancelled(let id):
      return id
    }
  }
}

/// Handle returned by `observe`. Delivery stops on `cancel()` or when the handle is released,
/// so keep it alive for as long as you want events.
@MainActor
public final class EngineObservation {
  private var onCancel: (@MainActor () -> Void)?
  init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }
  public func cancel() { onCancel?(); onCancel = nil }
  isolated deinit { onCancel?() }
}

/// The only surface the UI uses to talk to a browser engine (design section 1).
/// Implementations: FakeEngine (WKWebView stand-in), InMemoryEngine (tests), ChromiumEngine (ChromiumEngineKit).
/// The behavioral contract every implementation must meet is spelled out and checked in
/// `EngineAPITestSupport/EngineContract.swift`.
@MainActor
public protocol EngineClient: AnyObject {
  /// Open tabs in creation order.
  var tabIDs: [TabID] { get }
  /// Creates a tab in the most recently active window (contract rule 15): the window that last got `createWindow`,
  /// `createTab(url:in:)` or an activation. With no window the tab has none (in-process engines only; the Chromium
  /// engine requires a window). Kept for the existing contract checks; shell code calls `createTab(url:in:)`
  /// (lint test in ShellUITests).
  @discardableResult func createTab(url: URL?) -> TabID
  /// Creates a tab in `window`, which must be listed in `windowIDs`. The first tab of a window becomes its active
  /// tab; later tabs leave the active tab alone until `activateTab`.
  @discardableResult func createTab(url: URL?, in window: EngineWindowID) -> TabID
  /// Same as `closeTab(_:mode: .honourUnloadHandlers)`.
  func closeTab(_ id: TabID)
  /// Closes the tab. Not held: `.tabClosed(reason: .client)` before the call returns (contract rule 4). Held (a
  /// `beforeunload` page with `.honourUnloadHandlers`): the tab stays listed with `isClosing` until
  /// `.tabClosed(reason: .client)` or `.closeCancelled` (contract rule 16); another close while held does nothing.
  /// Closing a window's active tab makes another tab of that window active (`.activeTabChanged`).
  func closeTab(_ id: TabID, mode: CloseMode)
  func navigate(_ id: TabID, to url: URL)
  func reload(_ id: TabID)
  /// Moves one entry back in the tab's history (Toolbar Back); no-op when there is none (contract rule 7).
  func goBack(_ id: TabID)
  /// Moves one entry forward in the tab's history (Toolbar Forward); no-op when there is none (contract rule 7).
  func goForward(_ id: TabID)
  /// Moves `offset` entries in the tab's history (`-1` is one step back, `+1` is one step forward); `0` or an
  /// out-of-range offset is a no-op (#81, GS-024, contract rule 9).
  func goToHistory(_ id: TabID, offset: Int)
  /// The tab's back and forward entries (nearest-first); nil once closed (#81, GS-024, GS-025, contract rule 9).
  func history(of id: TabID) -> TabHistory?
  /// Creates a new tab copying `id`'s current URL, title and back/forward history (#81, GS-026, BH-027, contract rule
  /// 10), in `id`'s window; nil when `id` is unknown or closed.
  @discardableResult func duplicateTab(_ id: TabID) -> TabID?
  func snapshot(of id: TabID) -> TabSnapshot?
  /// The view that draws the tab's page. Same instance for the tab's whole life; nil once closed.
  func contentView(for id: TabID) -> NSView?
  /// Gives the tab's page the keyboard focus (#313: a Peek's page, the source page after a close). The default makes
  /// `contentView(for:)` its window's first responder; an engine whose content view is a container focuses the page
  /// inside it.
  func focusPage(of id: TabID)
  /// Ordered, main-thread delivery of every event. Delivery is synchronous, except that an
  /// event emitted from inside a handler is queued behind the event being delivered, so it
  /// arrives after the call that caused it returns. During queued delivery `snapshot(of:)`
  /// may already reflect a newer state than the event a handler is receiving.
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation

  // MARK: Windows (contract rules 11, 12, 15)

  /// Open windows in creation order.
  var windowIDs: [EngineWindowID] { get }
  /// Creates an engine window hosted by `host`, synchronously, and announces it with `.windowOpened`. The engine
  /// sets the host's `forward` and `onCloseRequested`.
  @discardableResult func createWindow(host: any EngineWindowHosting) -> EngineWindowID
  /// Closes the window: unload processing for its tabs first. Then `.tabClosed(reason: .windowClosing)` for each
  /// tab and `.windowClosed`. If a tab holds and its close is cancelled, the window stays open: `.closeCancelled`
  /// for that tab and no `.windowClosed`.
  func closeWindow(_ id: EngineWindowID)
  /// Makes the tab its window's active tab: `.activeTabChanged` and `isActive` (contract rule 12); no event when it
  /// already is.
  func activateTab(_ id: TabID)
  /// The window's active tab; nil when the window has no tabs or is unknown.
  func activeTab(in window: EngineWindowID) -> TabID?
  /// The engine's latest active tab, including changes whose events have not arrived yet. A read only: never
  /// adopts tabs or emits events. Nil for an unknown window, no active tab, or a live tab not mapped by this client.
  /// Batched engines override this query; `activeTab(in:)` and snapshots retain their event-consistent semantics.
  func latestActiveTab(in window: EngineWindowID) -> TabID?
  /// Window events (`.windowOpened`, `.windowClosed`, `.extensionActionsChanged`), through the same FIFO as `observe`.
  func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation
  /// Per-window routing: only the events of tabs that were in `window` when the event was emitted, including their
  /// `.tabCreated` (engine-origin ones too) and `.tabClosed`. Events of window-less tabs reach only `observe`.
  func observe(window: EngineWindowID, _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation
}

extension EngineClient {
  public func focusPage(of id: TabID) {
    guard let view = contentView(for: id) else { return }
    view.window?.makeFirstResponder(view)
  }

  /// Immediate-state engines already expose the latest selection through `activeTab(in:)`.
  public func latestActiveTab(in window: EngineWindowID) -> TabID? { activeTab(in: window) }
}
