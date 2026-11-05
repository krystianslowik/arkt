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
