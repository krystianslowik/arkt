import CoreGraphics

/// Where the parts of a Peek go (docs/design/peek.md, Layout). Flipped coordinates, in the space of `content`.
public struct PeekGeometry: Equatable, Sendable {
  /// What the Peek covers: the scrim and the recede apply here, and a click here outside the card closes the Peek.
  public var coverage: CGRect
  public var card: CGRect
  /// Close, Open as Tab, Add to Split View, top to bottom.
  public var controls: [CGRect]
  public var grabber: CGRect
  /// The controls sit inside the card's top-right corner (a content area below `PeekLayout.minimumWidth`).
  public var controlsInside: Bool
}

public enum PeekLayout {
  /// Below this width the side insets shrink and the controls move inside the card; a split pane narrower than
  /// this gets a Peek over the whole content area (decided 2026-10-25).
  public static let minimumWidth: CGFloat = 600
  /// Content card insets: left and right, top, bottom.
  public static let sideInset: CGFloat = 56
  public static let topInset: CGFloat = 34
  public static let bottomInset: CGFloat = 26
  /// The minimum margin, and the side insets of a narrow content area and of a split pane's left edge.
  public static let narrowInset: CGFloat = 24
  /// A split pane's right inset: the control gutter.
  public static let paneGutter: CGFloat = 52
  public static let controlSize: CGFloat = 28
  public static let controlSpacing: CGFloat = 8
  /// From the card's right edge to the controls, and inside the card's corner when they move in.
  public static let controlOffset: CGFloat = 12
  public static let grabberSize = CGSize(width: 36, height: 5)
  public static let grabberOffset: CGFloat = 12

  /// The Peek over `content` (the content card's frame), or over `sourcePane` inside a split when that pane is at
  /// least `minimumWidth` wide.
  public static func compute(content: CGRect, sourcePane: CGRect? = nil) -> PeekGeometry {
    if let pane = sourcePane, pane.width >= minimumWidth {
      let card = inset(pane, left: narrowInset, top: topInset, right: paneGutter, bottom: bottomInset)
      return geometry(coverage: pane, card: card, inside: false)
    }
    if content.width < minimumWidth {
      let card = inset(content, left: narrowInset, top: topInset, right: narrowInset, bottom: bottomInset)
      return geometry(coverage: content, card: card, inside: true)
    }
    let card = inset(content, left: sideInset, top: topInset, right: sideInset, bottom: bottomInset)
    return geometry(coverage: content, card: card, inside: false)
  }

  private static func inset(_ r: CGRect, left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect {
    CGRect(x: r.minX + left, y: r.minY + top, width: max(0, r.width - left - right),
           height: max(0, r.height - top - bottom))
  }

  private static func geometry(coverage: CGRect, card: CGRect, inside: Bool) -> PeekGeometry {
    let x = inside ? card.maxX - controlOffset - controlSize : card.maxX + controlOffset
    let top = inside ? card.minY + controlOffset : card.minY
    let controls = (0..<3).map { i in
      CGRect(x: x, y: top + CGFloat(i) * (controlSize + controlSpacing), width: controlSize, height: controlSize)
    }
    let grabber = CGRect(x: card.midX - grabberSize.width / 2, y: card.minY - grabberOffset,
                         width: grabberSize.width, height: grabberSize.height)
    return PeekGeometry(coverage: coverage, card: card, controls: controls, grabber: grabber, controlsInside: inside)
  }
}
