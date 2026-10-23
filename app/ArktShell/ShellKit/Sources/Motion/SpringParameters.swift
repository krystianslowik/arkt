import Foundation

/// Spring in Arc's parameterization: damping ratio + response (seconds per undamped oscillation).
public struct SpringParameters: Equatable, Sendable {
  /// Upper bound for every settling-time search; a spring that has not settled by then is cut off.
  public static let maxSettlingDuration = 10.0

  public var dampingRatio: Double
  public var response: Double
  public var mass: Double

  /// `dampingRatio` must be > 0: an undamped spring never settles.
  public init(dampingRatio: Double, response: Double, mass: Double = 1) {
    precondition(response > 0 && mass > 0 && dampingRatio > 0)
    self.dampingRatio = dampingRatio; self.response = response; self.mass = mass
  }

  /// k = (2 pi / response)^2 * m
  public var stiffness: Double { pow(2 * .pi / response, 2) * mass }
  /// c = 4 pi * dampingRatio * m / response  (= 2 * dampingRatio * sqrt(k m))
  public var damping: Double { 4 * .pi * dampingRatio * mass / response }
  /// Undamped angular frequency w0 = sqrt(k / m) = 2 pi / response.
  public var angularFrequency: Double { 2 * .pi / response }

  /// First time after which the solution's envelope stays below `epsilon` (as a fraction of a unit
  /// displacement released from rest). Distance-independent; used for CASpringAnimation.duration.
  public func settlingDuration(epsilon: Double = 0.001) -> Double {
    let solver = SpringSolver(parameters: self, displacement: 1, velocity: 0)
    var t = 0.0
    while t < Self.maxSettlingDuration {
      if solver.envelope(at: t) < epsilon { return t }
      t += 1.0 / 1000
    }
    return Self.maxSettlingDuration
  }

  /// Absolute settling time for a concrete start state (displacement from target in points, velocity
  /// in points/second): the earliest time after which both |x| stays below `threshold` points and |v|
  /// stays below `velocityThreshold` points/second (checked on their decaying upper bounds).
  public func settlingDuration(displacement: Double, velocity: Double, threshold: Double,
                               velocityThreshold: Double = SpringRun.velocityThreshold) -> Double {
    let solver = SpringSolver(parameters: self, displacement: displacement, velocity: velocity)
    let step = 1.0 / 1000
    // Scan backwards so the result is the last violation, which stays correct even where an
    // envelope rises before it decays (critical / overdamped with opposing velocity).
    var i = Int((Self.maxSettlingDuration / step).rounded())
    while i >= 0 {
      let t = Double(i) * step
      if solver.envelope(at: t) >= threshold || solver.velocityEnvelope(at: t) >= velocityThreshold {
        return min(t + step, Self.maxSettlingDuration)
      }
      i -= 1
    }
    return 0
  }
}
