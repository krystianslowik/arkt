import QuartzCore
import Testing
@testable import Motion

@MainActor
struct SpringAnimationFactoryTests {
  @Test func copiesPhysicsIntoCASpringAnimation() {
    let p = SpringPreset.springyFast.parameters
    let a = SpringAnimationFactory.make(keyPath: "position.x", from: 0, to: 200, parameters: p,
                                        initialVelocity: 600)
    #expect(abs(Double(a.mass) - p.mass) < 1e-9)
    #expect(abs(Double(a.stiffness) - p.stiffness) < 1e-6)
    #expect(abs(Double(a.damping) - p.damping) < 1e-6)
    #expect(abs(Double(a.initialVelocity) - 3) < 1e-9, "600 pt/s over 200 pt = 3 distances/s")
    #expect(a.duration == max(p.settlingDuration(), a.settlingDuration))
    #expect(a.duration >= p.settlingDuration())
  }

  @Test func zeroDistanceHasZeroNormalizedVelocity() {
    #expect(SpringAnimationFactory.normalizedVelocity(pointsPerSecond: 500, from: 10, to: 10) == 0)
  }
}
