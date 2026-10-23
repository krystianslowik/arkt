import CoreGraphics

/// Where a sidebar tab dropped on the page goes (GS-011, BH-117), from the pointer's place in the content area.
///
/// Decision 11: the left third drops on the left, side by side; the right third and the middle band on the right;
/// the top and bottom quarters of the middle column stack the pane above or below. The parity spec wins over the
/// design's "page edge" wording. PARITY(NEEDS-RUNTIME-CHECK RT-32)
public enum SplitDropZone: Sendable, Equatable {
  case left, right, top, bottom

  /// The zone of `point` in `bounds`, nil outside it or for an empty `bounds`. Rects are unflipped, like
  /// `SplitLayout`: the top quarter is the one at `maxY`.
  public static func zone(for point: CGPoint, in bounds: CGRect) -> SplitDropZone? {
    guard !bounds.isNull, bounds.width > 0, bounds.height > 0, closedContains(bounds, point) else { return nil }
    let third = bounds.width / 3
    let quarter = bounds.height / 4
    if point.x - bounds.minX < third { return .left }
    if bounds.maxX - point.x < third { return .right }
    if bounds.maxY - point.y < quarter { return .top }
    if point.y - bounds.minY < quarter { return .bottom }
    return .right
  }

  /// The orientation of the split a drop on a plain tab makes: side by side for left and right, stacked for top and
  /// bottom.
  public var orientation: SplitOrientation { self == .left || self == .right ? .horizontal : .vertical }

  /// `orientation` as an axis, through the one place that maps it (decision 1).
  public var axis: SplitAxis { SplitLayout.axis(for: orientation) }

  /// The dropped pane goes before the others (left or top) rather than after them.
  public var isBefore: Bool { self == .left || self == .top }

  /// Like `CGRect.contains`, but with the max edges: a pointer on the right or top edge is still over the content.
  private static func closedContains(_ bounds: CGRect, _ point: CGPoint) -> Bool {
    (bounds.minX...bounds.maxX).contains(point.x) && (bounds.minY...bounds.maxY).contains(point.y)
  }
}
