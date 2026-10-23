import AppKit

/// Opaque per-tab identity issued by the engine.
public struct TabID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
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

  public init(id: TabID, url: URL? = nil, title: String = "", faviconData: Data? = nil, isLoading: Bool = false,
              canGoBack: Bool = false, canGoForward: Bool = false) {
    self.id = id; self.url = url; self.title = title; self.faviconData = faviconData; self.isLoading = isLoading
    self.canGoBack = canGoBack; self.canGoForward = canGoForward
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
  case tabClosed(TabID)
  case urlChanged(TabID, URL?)
  case titleChanged(TabID, String)
  case faviconChanged(TabID, Data?)
  case loadingChanged(TabID, isLoading: Bool)
  /// Back or Forward availability changed; carries both, as in the snapshot (contract rule 8).
  case historyChanged(TabID, canGoBack: Bool, canGoForward: Bool)

  public var tabID: TabID {
    switch self {
    case .tabCreated(let id), .tabClosed(let id), .urlChanged(let id, _), .titleChanged(let id, _),
         .faviconChanged(let id, _), .loadingChanged(let id, _), .historyChanged(let id, _, _):
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
/// Implementations: FakeEngine (WKWebView stand-in), InMemoryEngine (tests), ChromiumEngine (later).
/// The behavioral contract every implementation must meet is spelled out and checked in
/// `EngineAPITestSupport/EngineContract.swift`.
@MainActor
public protocol EngineClient: AnyObject {
  /// Open tabs in creation order.
  var tabIDs: [TabID] { get }
  @discardableResult func createTab(url: URL?) -> TabID
  func closeTab(_ id: TabID)
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
  /// 10); nil when `id` is unknown or closed.
  @discardableResult func duplicateTab(_ id: TabID) -> TabID?
  func snapshot(of id: TabID) -> TabSnapshot?
  /// The view that draws the tab's page. Same instance for the tab's whole life; nil once closed.
  func contentView(for id: TabID) -> NSView?
  /// Ordered, main-thread delivery of every event. Delivery is synchronous, except that an
  /// event emitted from inside a handler is queued behind the event being delivered, so it
  /// arrives after the call that caused it returns. During queued delivery `snapshot(of:)`
  /// may already reflect a newer state than the event a handler is receiving.
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation
}
