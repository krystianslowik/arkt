import Testing
@testable import Motion

extension SpringParameters: CustomTestStringConvertible {
  public var testDescription: String { "ratio \(dampingRatio) response \(response)" }
}

struct SpringSolverTests {
  static let regimes: [SpringParameters] = [
    SpringParameters(dampingRatio: 0.5, response: 0.4),   // under
    SpringParameters(dampingRatio: 1.0, response: 0.4),   // critical
    SpringParameters(dampingRatio: 1.6, response: 0.4),   // over
  ]

  @Test(arguments: regimes)
  func initialConditions(p: SpringParameters) {
    let s = SpringSolver(parameters: p, displacement: 100, velocity: -300)
    #expect(abs(s.displacement(at: 0) - 100) < 1e-9)
    #expect(abs(s.velocity(at: 0) + 300) < 1e-6)
  }

  @Test(arguments: regimes)
  func satisfiesTheSpringODE(p: SpringParameters) {
    // m x'' + c x' + k x = 0, checked with a central difference.
    let s = SpringSolver(parameters: p, displacement: 100, velocity: 50)
    let t = 0.07, h = 1e-5
    let accel = (s.velocity(at: t + h) - s.velocity(at: t - h)) / (2 * h)
    let residual = p.mass * accel + p.damping * s.velocity(at: t) + p.stiffness * s.displacement(at: t)
    #expect(abs(residual) < 1e-3 * p.stiffness)
  }

  @Test func underdampedOvershootsCriticalDoesNot() {
    let under = SpringSolver(parameters: .init(dampingRatio: 0.5, response: 0.4), displacement: 100, velocity: 0)
    let critical = SpringSolver(parameters: .init(dampingRatio: 1, response: 0.4), displacement: 100, velocity: 0)
    let samples = stride(from: 0.0, through: 1.0, by: 0.001)
    #expect(samples.map(under.displacement(at:)).min()! < -1)
    #expect(samples.map(critical.displacement(at:)).min()! >= -1e-9)
  }

  @Test(arguments: regimes)
  func settlesWithinSettlingDuration(p: SpringParameters) {
    let s = SpringSolver(parameters: p, displacement: 100, velocity: 0)
    let t = p.settlingDuration(epsilon: 0.001)
    #expect(t > 0 && t < 5)
    for time in stride(from: t, through: t + 1, by: 0.01) {
      #expect(abs(s.displacement(at: time)) <= 0.1 + 1e-6)   // 0.001 of 100 pt
    }
  }
}
