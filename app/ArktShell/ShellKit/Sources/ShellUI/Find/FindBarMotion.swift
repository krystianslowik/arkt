import QuartzCore

/// The find bar's motion, as data (design/find-in-page/README.md, Motion). The bar opens from the keyboard, often, so
/// opening is short and travels six points; closing and stepping do not animate. A search with no match nudges the
/// field once. Reduce Motion keeps the fade and drops the movement and the nudge. Transform and opacity only; layout
/// never animates.
enum FindBarMotion {
  struct Curve: Equatable {
    let c1x: Float, c1y: Float, c2x: Float, c2y: Float
    init(_ c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
      self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
    }

    /// A new instance each time: the class is not Sendable.
    var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: c1x, c1y, c2x, c2y) }
  }

  /// `cubic-bezier(0.23, 1, 0.32, 1)`, the design's `--ease-out`.
  static let strongEaseOut = Curve(0.23, 1, 0.32, 1)
  /// CSS `ease-out`, the Reduce Motion fade.
  static let systemEaseOut = Curve(0, 0, 0.58, 1)

  struct Entrance: Equatable {
    /// Points above the resting place where the bar starts (the design's `translateY(-6px)`, y up here).
    var startOffset: CGFloat
    var duration: CFTimeInterval
    var curve: Curve
    var movesInTransform: Bool { startOffset != 0 }
  }

  static func entrance(reduceMotion: Bool) -> Entrance {
    reduceMotion ? Entrance(startOffset: 0, duration: 0.12, curve: systemEaseOut)
      : Entrance(startOffset: 6, duration: 0.12, curve: strongEaseOut)
  }

  struct Nudge: Equatable {
    var duration: CFTimeInterval
    var keyTimes: [Double]
    /// Points to the right of the resting place at each key time.
    var offsets: [Double]
    var curve: Curve
  }

  /// 3 points left, 3 right, 2 left and home in 0.24 s (CSS `shake`, an ease-out on each step); nil with Reduce Motion.
  static func nudge(reduceMotion: Bool) -> Nudge? {
    reduceMotion ? nil
      : Nudge(duration: 0.24, keyTimes: [0, 0.2, 0.45, 0.7, 1], offsets: [0, -3, 3, -2, 0], curve: strongEaseOut)
  }

  struct Press: Equatable {
    var scale: CGFloat
    var duration: CFTimeInterval
  }

  /// A pressed round button shrinks to 0.94 in 0.12 s; nil with Reduce Motion.
  static func press(reduceMotion: Bool) -> Press? {
    reduceMotion ? nil : Press(scale: 0.94, duration: 0.12)
  }

  // MARK: Animations

  static func fadeAnimation(_ entrance: Entrance) -> CABasicAnimation {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0.0
    fade.toValue = 1.0
    fade.duration = entrance.duration
    fade.timingFunction = entrance.curve.timingFunction
    return fade
  }

  /// The rise into place; nil when the entrance does not move.
  static func riseAnimation(_ entrance: Entrance) -> CABasicAnimation? {
    guard entrance.movesInTransform else { return nil }
    let rise = CABasicAnimation(keyPath: "transform.translation.y")
    rise.fromValue = Double(entrance.startOffset)
    rise.toValue = 0.0
    rise.duration = entrance.duration
    rise.timingFunction = entrance.curve.timingFunction
    return rise
  }

  static func nudgeAnimation(_ nudge: Nudge) -> CAKeyframeAnimation {
    let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
    shake.values = nudge.offsets
    shake.keyTimes = nudge.keyTimes.map { NSNumber(value: $0) }
    shake.timingFunctions = (1..<nudge.offsets.count).map { _ in nudge.curve.timingFunction }
    shake.duration = nudge.duration
    return shake
  }
}
