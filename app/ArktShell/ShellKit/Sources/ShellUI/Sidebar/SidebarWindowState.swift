import Foundation

/// The sidebar width and hidden state one window saves (#331): written whenever the width or the visibility changes
/// (Cmd-S, the View menu, the edge drag, the double-click reset, a toast's action), read back by the session's first
/// window at open. Stored as Arc stores its own window state ([O] `sidebarWidth` and friends, values private): two
/// values in the app's user defaults.
public struct SidebarWindowState: Equatable, Sendable {
  public var width: Double
  public var isVisible: Bool

  public init(width: Double, isVisible: Bool) {
    self.width = width
    self.isVisible = isVisible
  }
}

/// The user-defaults side of `SidebarWindowState`, injected like `ToolbarSetting` (the app passes the real defaults;
/// tests pass a suite). The stored width is clamped to `sidebarMinWidth`...`sidebarMaxWidth` when it is read, so a
/// hand-edited or stale value never reaches a window out of range.
@MainActor
public final class SidebarWindowStateStore {
  public static let widthDefaultsKey = "sidebarWidth"
  public static let visibleDefaultsKey = "sidebarVisible"

  private let defaults: UserDefaults?

  /// Reads and writes `defaults`.
  public init(defaults: UserDefaults) { self.defaults = defaults }
  private init(store: UserDefaults?) { self.defaults = store }

  /// Never touches user defaults (tests and the smoke).
  public static func ephemeral() -> SidebarWindowStateStore { SidebarWindowStateStore(store: nil) }

  /// The stored state, clamped to `metrics`; nil when nothing was ever saved (a profile that never changed its
  /// sidebar opens on the defaults).
  public func state(metrics: ShellMetrics = .standard) -> SidebarWindowState? {
    guard let defaults, defaults.object(forKey: Self.widthDefaultsKey) != nil else { return nil }
    let width = defaults.double(forKey: Self.widthDefaultsKey)
    let visible = defaults.object(forKey: Self.visibleDefaultsKey) as? Bool ?? true
    return SidebarWindowState(width: min(max(width, metrics.sidebarMinWidth), metrics.sidebarMaxWidth),
                              isVisible: visible)
  }

  /// Writes both values (any change of one saves both, so a window state is never half-stale).
  public func save(width: CGFloat, isVisible: Bool) {
    defaults?.set(Double(width), forKey: Self.widthDefaultsKey)
    defaults?.set(isVisible, forKey: Self.visibleDefaultsKey)
  }
}
