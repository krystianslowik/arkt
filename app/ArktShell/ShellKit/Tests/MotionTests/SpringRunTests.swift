import Testing
@testable import Motion

struct SpringRunTests {
  let p = SpringParameters(dampingRatio: 0.75, response: 0.3)

  @Test func startsAtFromWithInitialVelocity() {
    let run = SpringRun(from: 10, to: 210, initialVelocity: 400, parameters: p, start: 5, threshold: 0.25)
    #expect(run.frame(at: 5) == (value: 10, done: false))
    let state = run.interrupt(at: 5)
    #expect(abs(state.value - 10) < 1e-9)
    #expect(abs(state.velocity - 400) < 1e-6)
  }

  @Test func timesBeforeStartClampToStart() {
    let run = SpringRun(from: 10, to: 210, initialVelocity: 0, parameters: p, start: 5, threshold: 0.25)
    #expect(run.frame(at: 4).value == 10)
  }

  @Test func endsExactlyOnTargetAfterDuration() {
    let run = SpringRun(from: 0, to: 300, initialVelocity: 0, parameters: p, start: 1, threshold: 0.25)
    #expect(run.duration > 0)
    #expect(run.frame(at: 1 + run.duration) == (value: 300, done: true))
    #expect(run.frame(at: 1 + run.duration * 0.5).done == false)
  }

  @Test func zeroDistanceAtRestIsDoneImmediately() {
    let run = SpringRun(from: 50, to: 50, initialVelocity: 0, parameters: p, start: 0, threshold: 0.25)
    #expect(run.frame(at: 0) == (value: 50, done: true))
  }

  @Test func zeroDistanceWithVelocityStillMoves() {
    let run = SpringRun(from: 50, to: 50, initialVelocity: 800, parameters: p, start: 0, threshold: 0.25)
    #expect(run.duration > 0)
    #expect(run.frame(at: 0.02).value > 50)
  }

  @Test(arguments: [
    SpringParameters(dampingRatio: 0.5, response: 0.4),
    SpringParameters(dampingRatio: 1.0, response: 0.4),
    SpringParameters(dampingRatio: 1.6, response: 0.4),
  ])
  func absoluteSettleHoldsAfterDuration(p: SpringParameters) {
    let s = SpringSolver(parameters: p, displacement: 800, velocity: -2000)
    let t = p.settlingDuration(displacement: 800, velocity: -2000, threshold: 0.25)
    #expect(t > 0 && t < SpringParameters.maxSettlingDuration)
    for time in stride(from: t, through: t + 2, by: 0.001) {
      #expect(abs(s.displacement(at: time)) < 0.25)
      #expect(abs(s.velocity(at: time)) < SpringRun.velocityThreshold)
    }
  }

  @Test func longerDistancesTakeLongerToSettle() {
    let short = p.settlingDuration(displacement: 10, velocity: 0, threshold: 0.25)
    let long = p.settlingDuration(displacement: 1000, velocity: 0, threshold: 0.25)
    #expect(short < long)
  }
}
