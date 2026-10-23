import Foundation

/// Closed-form solution of m x'' + c x' + k x = 0 for displacement x from the target.
public struct SpringSolver: Sendable {
  public let parameters: SpringParameters
  public let x0: Double
  public let v0: Double

  public init(parameters: SpringParameters, displacement: Double, velocity: Double) {
    self.parameters = parameters; x0 = displacement; v0 = velocity
  }

  private enum Regime { case under, critical, over }

  private var w0: Double { parameters.angularFrequency }
  private var zeta: Double { parameters.dampingRatio }
  /// Ratios within 1e-6 of 1 use the critical solution; the under/over forms divide by ~0 there.
  private var regime: Regime {
    if abs(zeta - 1) < 1e-6 { return .critical }
    return zeta < 1 ? .under : .over
  }

  public func displacement(at t: Double) -> Double { evaluate(t).x }
  public func velocity(at t: Double) -> Double { evaluate(t).v }

  /// Upper bound of |x(t)| used for settling.
  public func envelope(at t: Double) -> Double {
    switch regime {
    case .under:
      let (a, _, A, B) = underdamped()
      return exp(-a * t) * (A * A + B * B).squareRoot()
    case .critical:
      return exp(-w0 * t) * (abs(x0) + abs(v0 + w0 * x0) * t)
    case .over:
      let (c1, c2, r1, r2) = overdamped()
      return abs(c1) * exp(r1 * t) + abs(c2) * exp(r2 * t)
    }
  }

  /// Upper bound of |v(t)| used for settling.
  public func velocityEnvelope(at t: Double) -> Double {
    switch regime {
    case .under:
      let (a, wd, A, B) = underdamped()
      let P = B * wd - a * A, Q = A * wd + a * B
      return exp(-a * t) * (P * P + Q * Q).squareRoot()
    case .critical:
      let B = v0 + w0 * x0
      return exp(-w0 * t) * (abs(B - w0 * x0) + w0 * abs(B) * t)
    case .over:
      let (c1, c2, r1, r2) = overdamped()
      return abs(c1 * r1) * exp(r1 * t) + abs(c2 * r2) * exp(r2 * t)
    }
  }

  private func underdamped() -> (a: Double, wd: Double, A: Double, B: Double) {
    let a = zeta * w0, wd = w0 * (1 - zeta * zeta).squareRoot()
    return (a, wd, x0, (v0 + a * x0) / wd)
  }

  private func overdamped() -> (Double, Double, Double, Double) {
    let root = (zeta * zeta - 1).squareRoot()
    let r1 = -w0 * (zeta - root), r2 = -w0 * (zeta + root)
    let c1 = (v0 - r2 * x0) / (r1 - r2)
    return (c1, x0 - c1, r1, r2)
  }

  private func evaluate(_ t: Double) -> (x: Double, v: Double) {
    switch regime {
    case .under:
      let (a, wd, A, B) = underdamped()
      let e = exp(-a * t), c = cos(wd * t), s = sin(wd * t)
      return (e * (A * c + B * s), e * ((B * wd - a * A) * c - (A * wd + a * B) * s))
    case .critical:
      let A = x0, B = v0 + w0 * x0, e = exp(-w0 * t)
      return (e * (A + B * t), e * (B - w0 * (A + B * t)))
    case .over:
      let (c1, c2, r1, r2) = overdamped()
      let e1 = exp(r1 * t), e2 = exp(r2 * t)
      return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }
  }
}
