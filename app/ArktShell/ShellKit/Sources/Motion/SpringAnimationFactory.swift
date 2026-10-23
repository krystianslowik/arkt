import QuartzCore

@MainActor
public enum SpringAnimationFactory {
  public static func make(keyPath: String, from: Double, to: Double, parameters p: SpringParameters,
                          initialVelocity pointsPerSecond: Double = 0) -> CASpringAnimation {
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.mass = CGFloat(p.mass)
    animation.stiffness = CGFloat(p.stiffness)
    animation.damping = CGFloat(p.damping)
    animation.initialVelocity = CGFloat(normalizedVelocity(pointsPerSecond: pointsPerSecond, from: from, to: to))
    animation.fromValue = from
    animation.toValue = to
    // Deliberate deviation from Arc, which uses settlingDuration alone: never cut the animation off before Core
    // Animation's own estimate of when it comes to rest. The curve itself is identical.
    animation.duration = max(p.settlingDuration(), animation.settlingDuration)
    return animation
  }

  /// CASpringAnimation.initialVelocity is in units of the total animated distance per second.
  /// When `from == to` there is no distance to normalize by, so the velocity is dropped (0): a
  /// zero-distance fling cannot be expressed with CASpringAnimation; use `SpringDriver` for that.
  public static func normalizedVelocity(pointsPerSecond v: Double, from: Double, to: Double) -> Double {
    let distance = to - from
    return distance == 0 ? 0 : v / distance
  }
}
