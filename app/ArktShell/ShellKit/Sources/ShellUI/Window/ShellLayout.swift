import CoreGraphics

/// Pure frame math for the root view (flipped coordinates). No Auto Layout on this hot path.
public struct ShellLayout: Equatable, Sendable {
  /// Where the sidebar is: the column at the window's left edge, or, while it is hidden, the floating overlay the left
  /// edge reveals (BH-004). Its width never changes with visibility, so hiding or revealing does not relayout rows.
  public var sidebarFrame: CGRect
  public var cardFrame: CGRect
  public var resizeHandleFrame: CGRect
  /// The strip at the window's left edge that reveals the hidden sidebar (GS-018); `.zero` while it is visible.
  public var revealEdgeFrame: CGRect

  /// What a drag of the sidebar edge to a proposed width does (BH-002, GS-017).
  public enum Drag: Equatable, Sendable {
    case resize(CGFloat)
    case hide
  }

  public static func clampedWidth(_ width: CGFloat, metrics: ShellMetrics) -> CGFloat {
    min(max(width, metrics.sidebarMinWidth), metrics.sidebarMaxWidth)
  }

  /// Fully left (below `sidebarHideWidth`) hides; anything else resizes, clamped.
  public static func resolveDrag(proposedWidth: CGFloat, metrics: ShellMetrics) -> Drag {
    proposedWidth < metrics.sidebarHideWidth ? .hide : .resize(clampedWidth(proposedWidth, metrics: metrics))
  }

  public static func compute(bounds: CGRect, sidebarWidth: CGFloat, sidebarVisible: Bool,
                             metrics: ShellMetrics) -> ShellLayout {
    let width = clampedWidth(sidebarWidth, metrics: metrics)
    let cardX = sidebarVisible ? width : metrics.cardInsetRight
    let card = CGRect(
      x: bounds.minX + cardX,
      y: bounds.minY + metrics.cardInsetTop,
      width: max(0, bounds.width - cardX - metrics.cardInsetRight),
      height: max(0, bounds.height - metrics.cardInsetTop - metrics.cardInsetBottom))
    guard sidebarVisible else {
      let inset = metrics.sidebarOverlayInset
      return ShellLayout(
        sidebarFrame: CGRect(x: bounds.minX + inset, y: bounds.minY + inset, width: width,
                             height: max(0, bounds.height - 2 * inset)),
        cardFrame: card, resizeHandleFrame: .zero,
        revealEdgeFrame: CGRect(x: bounds.minX, y: bounds.minY, width: metrics.sidebarRevealEdgeWidth,
                                height: bounds.height))
    }
    return ShellLayout(
      sidebarFrame: CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
      cardFrame: card,
      resizeHandleFrame: CGRect(x: bounds.minX + width - metrics.resizeHandleWidth / 2, y: bounds.minY,
                                width: metrics.resizeHandleWidth, height: bounds.height),
      revealEdgeFrame: .zero)
  }
}
