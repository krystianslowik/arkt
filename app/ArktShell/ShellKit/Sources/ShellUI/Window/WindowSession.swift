import AppKit
import EngineAPI

/// What a relaunch restores of the main window (#116): its frame and screen, the Space it showed, the tab that was
/// current and each Space's selected tab. Ids that no longer exist are ignored when it is applied, so a deleted Space
/// or tab falls back to the first-launch behavior.
public struct WindowSessionState: Codable, Equatable, Sendable {
  public var frame: CGRect
  /// The frame of the screen the window was on, so a rearranged or disconnected screen can be told apart.
  public var screenFrame: CGRect?
  public var space: SpaceID?
  /// The shown tab; a Favorite when no Space tab was current.
  public var currentTab: NodeID?
  public var selectedTabs: [SpaceID: NodeID]
  /// The window was in full screen; `frame` is then the windowed frame from before. Not re-entered at launch.
  public var isFullScreen: Bool

  public init(frame: CGRect, screenFrame: CGRect? = nil, space: SpaceID? = nil, currentTab: NodeID? = nil,
              selectedTabs: [SpaceID: NodeID] = [:], isFullScreen: Bool = false) {
    self.isFullScreen = isFullScreen
    self.frame = frame
    self.screenFrame = screenFrame
    self.space = space
    self.currentTab = currentTab
    self.selectedTabs = selectedTabs
  }
}

extension WindowSessionState {
  /// A state saved before `isFullScreen` existed still loads.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    frame = try values.decode(CGRect.self, forKey: .frame)
    screenFrame = try values.decodeIfPresent(CGRect.self, forKey: .screenFrame)
    space = try values.decodeIfPresent(SpaceID.self, forKey: .space)
    currentTab = try values.decodeIfPresent(NodeID.self, forKey: .currentTab)
    selectedTabs = try values.decodeIfPresent([SpaceID: NodeID].self, forKey: .selectedTabs) ?? [:]
    isFullScreen = try values.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
  }

  /// The state of a window now. In full screen the window's own frame is the whole screen, so the frame from before
  /// entering full screen is saved instead (the screen frame when none was seen).
  static func capturing(frame: CGRect, windowedFrame: CGRect?, isFullScreen: Bool, screenFrame: CGRect?,
                        space: SpaceID?, currentTab: NodeID?, selectedTabs: [SpaceID: NodeID]) -> WindowSessionState {
    WindowSessionState(frame: isFullScreen ? (windowedFrame ?? frame) : frame, screenFrame: screenFrame,
                       space: space, currentTab: currentTab, selectedTabs: selectedTabs, isFullScreen: isFullScreen)
  }
}

/// Which kind of window is being built, for deciding which one owns the session.
public enum SessionWindowOrigin: Equatable, Sendable {
  /// The shell opened it (launch, New Window).
  case shell
  /// The engine asked for it on a Dock click or a menu command, with no opener.
  case dockReopen
  /// Any other engine request: a startup URL, an extension's window, a page's popup or new window.
  case engineRequested
  /// Dragged out of a window's sidebar.
  case dragOut
}

/// The session (frame, Space, tabs) belongs to the main window the shell opens: the first one, and the next one when
/// that window has closed. A window the engine builds for its own request never owns it.
enum SessionWindowPolicy {
  static func origin(for request: EngineWindowRequest) -> SessionWindowOrigin {
    request.kind == .reopen && request.openerWindow == nil ? .dockReopen : .engineRequested
  }

  static func takesSession(_ origin: SessionWindowOrigin, ownerIsAlive: Bool) -> Bool {
    !ownerIsAlive && (origin == .shell || origin == .dockReopen)
  }
}

/// The user-defaults side of `WindowSessionState`, injected like `SidebarWindowStateStore`: one JSON value, written
/// whenever the window's state changes, read once by the session's first window. App-level, so it stays in the user
/// defaults and not in the database.
@MainActor
public final class WindowSessionStore {
  public static let defaultsKey = "windowSession"

  private let defaults: UserDefaults?

  public init(defaults: UserDefaults) { self.defaults = defaults }
  private init(store: UserDefaults?) { self.defaults = store }

  /// Never touches user defaults (tests and the smoke).
  public static func ephemeral() -> WindowSessionStore { WindowSessionStore(store: nil) }

  /// The stored state; nil when nothing was saved, the value cannot be read, or its frame is empty or not finite.
  public func load() -> WindowSessionState? {
    guard let data = defaults?.data(forKey: Self.defaultsKey),
          let state = try? JSONDecoder().decode(WindowSessionState.self, from: data),
          WindowFramePlacement.isUsable(state.frame) else { return nil }
    return state
  }

  public func save(_ state: WindowSessionState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    defaults?.set(data, forKey: Self.defaultsKey)
  }
}

/// A screen's full and usable (below the menu bar and above the Dock) frames, in screen coordinates.
public struct ScreenGeometry: Equatable, Sendable {
  public var frame: CGRect
  public var visibleFrame: CGRect

  public init(frame: CGRect, visibleFrame: CGRect) {
    self.frame = frame
    self.visibleFrame = visibleFrame
  }

  /// The connected screens, the main one first.
  @MainActor
  public static func current() -> [ScreenGeometry] {
    NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
  }
}

/// Where a saved frame lands on the screens connected now.
public enum WindowFramePlacement {
  static func isUsable(_ frame: CGRect) -> Bool {
    let values = [frame.origin.x, frame.origin.y, frame.width, frame.height]
    return values.allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
  }

  /// `saved` kept on the screen it overlaps most; when no screen shows any of it, on the screen with `savedScreen`'s
  /// frame, else on the first (main) screen. The size shrinks to the screen's usable area (never below `minSize`) and
  /// the origin moves in until the whole window is inside it. Nil for an unusable frame or no screens.
  public static func restoredFrame(saved: CGRect, savedScreen: CGRect?, screens: [ScreenGeometry],
                                   minSize: CGSize) -> CGRect? {
    guard isUsable(saved), let first = screens.first else { return nil }
    let target = bestScreen(for: saved, savedScreen: savedScreen, screens: screens) ?? first
    let area = target.visibleFrame
    let size = CGSize(width: max(min(saved.width, area.width), minSize.width),
                      height: max(min(saved.height, area.height), minSize.height))
    let x = min(max(saved.minX, area.minX), max(area.maxX - size.width, area.minX))
    let y = min(max(saved.minY, area.minY), max(area.maxY - size.height, area.minY))
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  private static func bestScreen(for saved: CGRect, savedScreen: CGRect?, screens: [ScreenGeometry])
    -> ScreenGeometry? {
    var best: (screen: ScreenGeometry, area: CGFloat)?
    for screen in screens {
      let overlap = saved.intersection(screen.visibleFrame)
      let area = overlap.isNull ? 0 : overlap.width * overlap.height
      if area > 0, area > (best?.area ?? 0) { best = (screen, area) }
    }
    if let best { return best.screen }
    return savedScreen.flatMap { frame in screens.first { $0.frame == frame } }
  }
}
