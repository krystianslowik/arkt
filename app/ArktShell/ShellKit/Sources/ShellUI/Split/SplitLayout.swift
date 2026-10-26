import CoreGraphics

/// The axis a split's panes are laid out along.
public enum SplitAxis: Sendable, Equatable {
  /// Left to right, with vertical gaps between the panes.
  case sideBySide
  /// Top to bottom, with horizontal gaps between the panes.
  case stacked
}

/// Pane and divider rects of one split. `dividers[i]` is the gap between `panes[i]` and `panes[i + 1]`.
public struct SplitFrames: Equatable, Sendable {
  public var panes: [CGRect]
  public var dividers: [CGRect]

  public init(panes: [CGRect], dividers: [CGRect]) {
    self.panes = panes
    self.dividers = dividers
  }
}

/// Pure layout math for a split: normalization of stored factors, pane and divider frames, and divider drags.
///
/// Rects are in unflipped coordinates (like `ContentCardView`): pane 0 is the leftmost pane side by side and the
/// topmost pane stacked, so it sits at `maxY`. Positions along the main axis are measured from the leading edge:
/// the left edge side by side, the top edge stacked.
public enum SplitLayout {
  /// Shortest pane along the main axis while dragging a divider. [I] PARITY(NEEDS-RUNTIME-CHECK RT-33)
  public static let minimumPaneLength: CGFloat = 240

  /// Decision 1: the only place a stored orientation becomes an axis. PARITY(NEEDS-RUNTIME-CHECK RT-31)
  public static func axis(for orientation: SplitOrientation) -> SplitAxis {
    switch orientation {
    case .horizontal: .sideBySide
    case .vertical: .stacked
    }
  }

  /// Decision 2: `count` shares that sum to 1. A count mismatch gives equal shares; non-finite or non-positive
  /// entries are replaced by an equal share; the result is renormalized.
  public static func normalized(_ factors: [Double], count: Int) -> [Double] {
    guard count > 0 else { return [] }
    let equal = equalShares(count)
    guard factors.count == count else { return equal }
    let valid = factors.map { $0.isFinite && $0 > 0 }
    guard valid.contains(true) else { return equal }
    let repaired = zip(factors, valid).map { $1 ? $0 : equal[0] }
    let total = repaired.reduce(0, +)
    guard total.isFinite, total > 0 else { return equal }
    return repaired.map { $0 / total }
  }

  /// Pane and divider frames for `factors` (normalized first). Pane edges are rounded to the pixel grid at `scale`,
  /// so the panes and the `gap`-wide dividers tile `bounds` without holes or overlaps.
  public static func frames(in bounds: CGRect, axis: SplitAxis, factors: [Double], gap: CGFloat,
                            scale: CGFloat) -> SplitFrames {
    let shares = normalized(factors, count: factors.count)
    let count = shares.count
    guard count > 0 else { return SplitFrames(panes: [], dividers: []) }
    let length = mainLength(of: bounds, axis: axis)
    let available = max(0, length - gap * CGFloat(count - 1))
    let pixel = scale > 0 ? scale : 1
    var panes: [CGRect] = []
    var dividers: [CGRect] = []
    var cumulative: Double = 0
    var start: CGFloat = 0
    for (index, share) in shares.enumerated() {
      cumulative += share
      let isLast = index == count - 1
      // Rounding the running edge (not each length) keeps every gap exactly `gap` wide.
      let end = isLast ? length : min(length, ((available * CGFloat(cumulative) + gap * CGFloat(index)) * pixel)
        .rounded() / pixel)
      panes.append(rect(from: start, to: max(start, end), in: bounds, axis: axis))
      if !isLast {
        let gapEnd = min(length, max(start, end) + gap)
        dividers.append(rect(from: max(start, end), to: gapEnd, in: bounds, axis: axis))
        start = gapEnd
      }
    }
    return SplitFrames(panes: panes, dividers: dividers)
  }

  /// New factors after divider `index` moved so that pane `index` ends at main-axis `position` (measured from the
  /// leading edge of `bounds`). Only panes `index` and `index + 1` change; the other entries are returned unchanged.
  /// Each of the two keeps at least `minimum` when together they are at least `2 * minimum` long; otherwise (a window
  /// shrank after uneven shares) both get half their total, since a drag never takes length from other panes.
  /// When `bounds` cannot fit every pane at `minimum`, all shares are equal.
  public static func factors(dragging index: Int, to position: CGFloat, in bounds: CGRect, axis: SplitAxis,
                             factors: [Double], gap: CGFloat, minimum: CGFloat) -> [Double] {
    var shares = normalized(factors, count: factors.count)
    let count = shares.count
    guard count >= 2, (0..<(count - 1)).contains(index) else { return shares }
    let length = mainLength(of: bounds, axis: axis)
    let available = length - gap * CGFloat(count - 1)
    guard available > 0, available >= minimum * CGFloat(count) else { return equalShares(count) }
    let lengths = shares.map { available * CGFloat($0) }
    let start = lengths[..<index].reduce(0, +) + gap * CGFloat(index)
    let pair = lengths[index] + lengths[index + 1]
    let low = min(minimum, pair / 2)
    let lead = min(max(position - start, low), pair - low)
    shares[index] = Double(lead / available)
    shares[index + 1] = Double((pair - lead) / available)
    return shares
  }

  /// Main-axis position (from the leading edge of `bounds`) of `point`, for divider drags.
  public static func position(of point: CGPoint, in bounds: CGRect, axis: SplitAxis) -> CGFloat {
    switch axis {
    case .sideBySide: point.x - bounds.minX
    case .stacked: bounds.maxY - point.y
    }
  }

  /// The factors of a split after a closed pane comes back (#403): `share` at `index` (clamped), the panes already
  /// there scaled into the rest, so they keep their proportions; the result sums to 1. Without a usable share (nil,
  /// not finite, or not strictly between 0 and 1) every pane gets an equal share, as for any added pane (RT-35).
  public static func inserting(share: Double?, at index: Int, into factors: [Double]) -> [Double] {
    let count = factors.count + 1
    guard let share, share.isFinite, share > 0, share < 1 else { return equalShares(count) }
    guard !factors.isEmpty else { return [1] }
    var result = normalized(factors, count: factors.count).map { $0 * (1 - share) }
    result.insert(share, at: min(max(index, 0), result.count))
    return result
  }

  static func equalShares(_ count: Int) -> [Double] {
    count > 0 ? Array(repeating: 1 / Double(count), count: count) : []
  }

  private static func mainLength(of bounds: CGRect, axis: SplitAxis) -> CGFloat {
    axis == .sideBySide ? bounds.width : bounds.height
  }

  /// The rect spanning main-axis distances `from...to` measured from the leading edge, full length across.
  private static func rect(from: CGFloat, to: CGFloat, in bounds: CGRect, axis: SplitAxis) -> CGRect {
    switch axis {
    case .sideBySide:
      CGRect(x: bounds.minX + from, y: bounds.minY, width: to - from, height: bounds.height)
    case .stacked:
      CGRect(x: bounds.minX, y: bounds.maxY - to, width: bounds.width, height: to - from)
    }
  }
}
