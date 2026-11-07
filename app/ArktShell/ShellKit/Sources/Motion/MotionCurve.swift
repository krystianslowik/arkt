import QuartzCore

/// A cubic-bezier timing curve as its four control numbers, so a test can read it. The shell's eased (non-spring)
/// motion uses the named curves below instead of spelling the numbers out.
public struct MotionCurve: Equatable, Sendable {
  public let c1x: Float, c1y: Float, c2x: Float, c2y: Float

  public init(_ c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
    self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
  }

  /// A new instance each time: the class is not Sendable.
  public var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: c1x, c1y, c2x, c2y) }

  /// The curve's output at `progress` (0 to 1, clamped), for a fade presented frame by frame on a clock rather than
  /// handed to Core Animation. Solves the curve's x for its parameter by bisection, exact enough for any curve whose
  /// x runs monotonically from 0 to 1 (every CSS timing curve).
  public func value(at progress: Double) -> Double {
    guard progress > 0 else { return 0 }
    guard progress < 1 else { return 1 }
    func bezier(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
      let u = 1 - t
      return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
    var low = 0.0, high = 1.0
    for _ in 0..<40 {
      let mid = (low + high) / 2
      if bezier(Double(c1x), Double(c2x), mid) < progress { low = mid } else { high = mid }
    }
    return bezier(Double(c1y), Double(c2y), (low + high) / 2)
  }

  /// The design system's `--ease-out`, `cubic-bezier(0.23, 1, 0.32, 1)`: everything that enters, fades or changes
  /// state.
  public static let strongEaseOut = MotionCurve(0.23, 1, 0.32, 1)
  /// CSS `ease-out`, for Reduce Motion fades that should not snap.
  public static let systemEaseOut = MotionCurve(0, 0, 0.58, 1)
}

/// The shell's fade durations, in seconds: quick for overlays that open from the keyboard and dismiss fades, standard
/// for hover and row fades, slow for content swaps.
public enum FadeDuration {
  public static let quick: CFTimeInterval = 0.1
  public static let standard: CFTimeInterval = 0.15
  public static let slow: CFTimeInterval = 0.2
}
