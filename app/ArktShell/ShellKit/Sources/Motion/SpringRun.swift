import Foundation

/// One spring animation from `from` to `to`, as a pure function of time. `SpringDriver` feeds it
/// display-link timestamps; tests feed it any clock.
public struct SpringRun: Sendable {
  /// Default position threshold in points (half a pixel on a 2x display).
  public static let defaultThreshold = 0.25
  /// Speed below which the spring counts as at rest, in points/second.
  public static let velocityThreshold = 2.0

  public let from: Double
  public let to: Double
  public let start: Double
  /// Seconds after `start` at which the run snaps to `to` and reports done.
  public let duration: Double
  private let solver: SpringSolver

  public init(from: Double, to: Double, initialVelocity: Double, parameters: SpringParameters,
              start: Double, threshold: Double = SpringRun.defaultThreshold) {
    self.from = from; self.to = to; self.start = start
    solver = SpringSolver(parameters: parameters, displacement: from - to, velocity: initialVelocity)
    duration = parameters.settlingDuration(displacement: from - to, velocity: initialVelocity,
                                           threshold: threshold)
  }

  /// Value to present at time `t` (times before `start` clamp to `start`); `done` once settled,
  /// in which case `value` is exactly `to`.
  public func frame(at t: Double) -> (value: Double, done: Bool) {
    let elapsed = max(t - start, 0)
    if elapsed >= duration { return (to, true) }
    return (to + solver.displacement(at: elapsed), false)
  }

  /// Position and velocity at time `t`, for handing an interrupted spring to a gesture or a new run.
  public func interrupt(at t: Double) -> (value: Double, velocity: Double) {
    let elapsed = max(t - start, 0)
    return (to + solver.displacement(at: elapsed), solver.velocity(at: elapsed))
  }
}
