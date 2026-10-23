import CoreGraphics
import Foundation

/// Finger velocity from scroll deltas: the average over the samples within `window` seconds of the newest.
public struct VelocityTracker: Sendable {
  public var window: Double
  private var samples: [(delta: CGFloat, time: Double)] = []

  public init(window: Double = 0.1) { self.window = window }

  public mutating func add(delta: CGFloat, at time: Double) {
    samples.append((delta, time))
    samples.removeAll { time - $0.time > window }
  }

  public mutating func reset() { samples.removeAll() }

  /// Points per second. Divides by the sampled span plus one average sample spacing, so N samples
  /// `dt` apart cover N * dt seconds.
  public var velocity: CGFloat {
    guard let first = samples.first, let last = samples.last else { return 0 }
    let total = samples.reduce(CGFloat(0)) { $0 + $1.delta }
    let span = max(last.time - first.time, 0)     // out-of-order timestamps do not flip the sign
    var spacing = samples.count > 1 ? span / Double(samples.count - 1) : 1.0 / 120
    if !(spacing > 0) { spacing = 1.0 / 120 }     // samples sharing one timestamp (or NaN)
    let duration = span + spacing
    guard duration > 0 else { return 0 }
    let velocity = total / CGFloat(duration)
    return velocity.isFinite ? velocity : 0
  }
}
