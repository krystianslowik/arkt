import AppKit

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

  public init(frame: CGRect, screenFrame: CGRect? = nil, space: SpaceID? = nil, currentTab: NodeID? = nil,
              selectedTabs: [SpaceID: NodeID] = [:]) {
    self.frame = frame
    self.screenFrame = screenFrame
    self.space = space
    self.currentTab = currentTab
    self.selectedTabs = selectedTabs
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
