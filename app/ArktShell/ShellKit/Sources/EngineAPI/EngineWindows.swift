import AppKit

// MARK: - Window identity and events

/// Opaque per-window identity issued by the engine (one engine window, one Chromium `Browser`).
public struct EngineWindowID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// Opaque profile identity. One profile this week; the value is the engine's profile id.
public struct EngineProfileID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
}

/// Why an engine window closed (#401). The shell keeps its window without an engine window only after
/// `.lastTabClosed`; every other close takes the shell window with it.
public enum WindowCloseReason: Equatable, Sendable {
  /// The user or the shell asked: `closeWindow`, the host's `onCloseRequested` (close button, Close Window), or the
  /// engine's own Close Window command.
  case userClose
  /// An extension closed it (`chrome.windows.remove`).
  case `extension`
  /// Its last tab closed or moved to another window, and the engine closed the emptied window (Chromium closes a
  /// `Browser` with its last tab).
  case lastTabClosed
  /// The application is quitting.
  case appQuit
}

/// Window events, on their own stream (`EngineClient.observeWindows(_:)`): an `EngineEvent` always has a tab.
/// Delivered through the same FIFO as tab events, so a window's `.windowClosed` follows the `.tabClosed` events of
/// its tabs (contract rule 11). Nothing follows `.windowClosed` for that window.
public enum EngineWindowEvent: Equatable, Sendable {
  /// The window was created and is listed in `windowIDs`.
  case windowOpened(EngineWindowID)
  /// The window is gone, after the `.tabClosed` events of its tabs, with the reason it closed.
  case windowClosed(EngineWindowID, reason: WindowCloseReason)
  /// The extension action list of the window changed (`EngineExtensions`).
  case extensionActionsChanged(EngineWindowID)

  public var windowID: EngineWindowID {
    switch self {
    case .windowOpened(let id), .windowClosed(let id, _), .extensionActionsChanged(let id): id
    }
  }
}

// MARK: - Hosting

/// The shell's answer for a command it implements itself (`EngineWindowHosting.claim(_:)`).
public struct CommandClaim: Equatable, Sendable {
  public var isEnabled: Bool
  public init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

/// Set by the engine on a host: validates and runs the commands the host does not claim
/// (`chrome::IsCommandEnabled`, `chrome::ExecuteCommandWithDisposition` in the Chromium engine).
@MainActor
public struct EngineCommandForwarding {
  public let validate: @MainActor (EngineCommand) -> Bool
  public let execute: @MainActor (EngineCommand, EngineDisposition) -> Void

  public init(validate: @escaping @MainActor (EngineCommand) -> Bool,
              execute: @escaping @MainActor (EngineCommand, EngineDisposition) -> Void) {
    self.validate = validate
    self.execute = execute
  }
}

/// A shell window that hosts one engine window (week-3 plan, Decisions 2 and 6). AppKit types only.
///
/// The engine never creates or lays out the window. It reads `window` and `cardView`, and sets `forward` and
/// `onCloseRequested` when the window is created (`EngineClient.createWindow(host:)` or a host provider); it clears
/// them when the window closes. The host mounts tab containers (`EngineClient.contentView(for:)`) itself.
@MainActor
public protocol EngineWindowHosting: AnyObject {
  var window: NSWindow { get }
  /// Fallback host for tab-modal dialogs and for the content size when no tab is mounted. The engine never fills it.
  var cardView: NSView { get }
  /// The shell's answer for a command it implements (enabled state), or nil to let the engine decide.
  func claim(_ command: EngineCommand) -> CommandClaim?
  /// Runs a claimed command; true when the shell handled it.
  func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool
  /// Set by the engine: `validate` and `execute` for the commands the host does not claim.
  var forward: EngineCommandForwarding? { get set }
  /// Set by the engine. The host calls it when the user asks to close the window (close button, Close Window) and
  /// never closes the window itself: the engine closes its tabs and then reports `.windowClosed` (`.userClose`).
  var onCloseRequested: (@MainActor () -> Void)? { get set }
  /// A user link activation in one of this window's tabs, before the engine navigates (#313). Called from inside the
  /// engine's navigation start: it must not call the engine. To open the link elsewhere, answer `.cancel` and act
  /// after the call returns. Default (`EngineLinks.swift`): `.navigate`.
  func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision
  /// A key down that a page of this window did not handle (Esc the page did not use), with the tab it was sent to.
  /// True when the host took it. Called after the engine finished with the event, never from inside the page's own
  /// handling. Default: false.
  func handleUnhandledKeyDown(_ event: NSEvent, in tab: TabID?) -> Bool
}

/// Why the engine asks for a window of its own (Decision 2).
public enum EngineWindowRequestKind: Equatable, Sendable {
  /// `chrome.windows.create`, or a tab an extension moves to a new window.
  case `extension`
  /// A page asked (`window.open` with window features): always a popup (#314). The Chromium engine tells it by the
  /// popup Browser it creates; a page's new window without features is still `.reopen` (week-3 results, W3-4).
  case page
  /// Dock reopen, or a new window from a Chromium menu command.
  case reopen
  /// A URL passed at startup or opened by another application.
  case startupURL
}

/// A window the engine creates on its own. The target Space is the shell's choice: the Space shown in
/// `openerWindow`, else the last active Space.
public struct EngineWindowRequest: Equatable, Sendable {
  public var kind: EngineWindowRequestKind
  /// The window the request came from, when there is one.
  public var openerWindow: EngineWindowID?
  /// The requested frame in screen coordinates; nil when none was asked for.
  public var bounds: CGRect?
  public var profile: EngineProfileID
  public var initialURL: URL?
  /// A popup window: a page's `window.open` with window features, or `chrome.windows.create({type: "popup"})`.
  /// False for a normal window (#314: popups open in Little Arkt).
  public var isPopup: Bool

  public init(kind: EngineWindowRequestKind, openerWindow: EngineWindowID? = nil, bounds: CGRect? = nil,
              profile: EngineProfileID, initialURL: URL? = nil, isPopup: Bool = false) {
    self.kind = kind; self.openerWindow = openerWindow; self.bounds = bounds
    self.profile = profile; self.initialURL = initialURL; self.isPopup = isPopup
  }
}

/// Builds the shell window for an engine-initiated window and returns its host. Runs inside the engine's window
/// construction: it must not call the engine; the window is usable after its `.windowOpened`.
public typealias EngineWindowHostProvider = @MainActor (EngineWindowRequest) -> any EngineWindowHosting
