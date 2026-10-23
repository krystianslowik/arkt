import CoreGraphics

/// Pure frame math for the root view (flipped coordinates). No Auto Layout on this hot path.
public struct ShellLayout: Equatable, Sendable {
  public var sidebarFrame: CGRect
  public var cardFrame: CGRect
  public var resizeHandleFrame: CGRect

  public static func clampedWidth(_ width: CGFloat, metrics: ShellMetrics) -> CGFloat {
    min(max(width, metrics.sidebarMinWidth), metrics.sidebarMaxWidth)
  }

  public static func compute(bounds: CGRect, sidebarWidth: CGFloat, sidebarVisible: Bool,
                             metrics: ShellMetrics) -> ShellLayout {
    let width = sidebarVisible ? clampedWidth(sidebarWidth, metrics: metrics) : 0
    let cardX = sidebarVisible ? width : metrics.cardInsetRight
    let card = CGRect(
      x: bounds.minX + cardX,
      y: bounds.minY + metrics.cardInsetTop,
      width: max(0, bounds.width - cardX - metrics.cardInsetRight),
      height: max(0, bounds.height - metrics.cardInsetTop - metrics.cardInsetBottom))
    let handle = sidebarVisible
      ? CGRect(x: bounds.minX + width - metrics.resizeHandleWidth / 2, y: bounds.minY,
               width: metrics.resizeHandleWidth, height: bounds.height)
      : .zero
    return ShellLayout(
      sidebarFrame: CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
      cardFrame: card, resizeHandleFrame: handle)
  }
}
