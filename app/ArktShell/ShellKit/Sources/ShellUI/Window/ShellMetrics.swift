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
  /// Height of the sidebar strip that hosts the traffic lights (and later back/forward/reload).
  public var sidebarTopBarHeight: CGFloat

  public static let standard = ShellMetrics(
    sidebarDefaultWidth: 190,
    sidebarMinWidth: 150,          // TODO(measure): Arc's minimum
    sidebarMaxWidth: 400,          // TODO(measure): Arc's maximum
    cardInsetTop: 9,
    cardInsetRight: 10,
    cardInsetBottom: 10,
    cardCornerRadius: 10,
    resizeHandleWidth: 8,
    trafficLightOrigin: CGPoint(x: 16, y: 16),   // TODO(measure)
    trafficLightSpacing: 20,                     // AppKit default pitch
    sidebarTopBarHeight: 44                      // TODO(measure)
  )
}
