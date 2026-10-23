import CoreGraphics

public enum ShellUIVersion { public static let current = 1 }

/// Every chrome dimension in one place. Values measured from Arc's layout (+-2 pt).
public struct ShellMetrics: Sendable, Equatable {
  public var sidebarDefaultWidth: CGFloat
  public var sidebarMinWidth: CGFloat
  public var sidebarMaxWidth: CGFloat
  public var cardInsetTop: CGFloat
  public var cardInsetRight: CGFloat
  public var cardInsetBottom: CGFloat
  public var cardCornerRadius: CGFloat
  public var resizeHandleWidth: CGFloat
  /// Close button origin measured from the window's top-left corner.
  public var trafficLightOrigin: CGPoint
  public var trafficLightSpacing: CGFloat
  /// Height of the sidebar strip that hosts the traffic lights (and later back/forward/reload); also the height of
  /// the titlebar container, so it never covers the sidebar URL bar below the strip.
  public var sidebarTopBarHeight: CGFloat

  /// "Arc 1.168" marks a value from `docs/plans/2026-10-23-arc-measurements.md` (one 2x window, dark, not key,
  /// Toolbar on).
  public static let standard = ShellMetrics(
    sidebarDefaultWidth: 190,
    sidebarMinWidth: 150,          // TODO(measure): Arc's minimum
    sidebarMaxWidth: 400,          // TODO(measure): Arc's maximum
    cardInsetTop: 10,                            // Arc 1.168
    cardInsetRight: 10,
    cardInsetBottom: 10,
    cardCornerRadius: 10,
    resizeHandleWidth: 8,
    trafficLightOrigin: CGPoint(x: 12, y: 16),   // Arc 1.168: close button frame (16 x 16)
    trafficLightSpacing: 23,                     // Arc 1.168: close x 12, minimize x 35, zoom x 58
    sidebarTopBarHeight: 36                      // Arc 1.168, Toolbar-on layout only (window top to Favorites)
  )
}
