import AppKit
import Testing
@testable import Motion

@MainActor
final class Clock {
  var now: CFTimeInterval = 100
}

/// Drives SpringDriver through its internal start/tick entry points with an injected clock, so no
/// window or display link is needed.
@MainActor
struct SpringDriverTests {
  let p = SpringParameters(dampingRatio: 0.75, response: 0.3)
  let clock = Clock()

  func makeDriver(reduceMotion: Bool = false) -> SpringDriver {
    let clock = clock
    return SpringDriver(now: { clock.now }, reduceMotion: { reduceMotion })
  }

  @Test func completesOnceWithTrueAfterSettling() {
    let driver = makeDriver()
    var updates: [Double] = []
    var completions: [Bool] = []
    #expect(driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                         onUpdate: { updates.append($0) }, completion: { completions.append($0) }))
    #expect(driver.isRunning)
    var t = clock.now
    while driver.isRunning && t < clock.now + 20 {
      t += 1.0 / 120
      driver.tick(at: t)
    }
    #expect(completions == [true])
    #expect(updates.last == 200)
    #expect(!driver.isRunning)
    driver.tick(at: t + 1)
    #expect(completions == [true])
    #expect(driver.stop() == nil)
  }

  @Test func stopCompletesFalseOnceAndSecondStopReturnsNil() {
    let driver = makeDriver()
    var completions: [Bool] = []
    driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                 onUpdate: { _ in }, completion: { completions.append($0) })
    driver.tick(at: clock.now + 0.05)
    #expect(driver.stop() != nil)
    #expect(completions == [false])
    #expect(driver.stop() == nil)
    #expect(completions == [false])
  }

  @Test func stopReturnsTheLastPresentedValue() {
    let driver = makeDriver()
    var last = Double.nan
    driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                 onUpdate: { last = $0 }, completion: nil)
    driver.tick(at: clock.now + 1.0 / 120)
    driver.tick(at: clock.now + 2.0 / 120)
    clock.now += 5   // wall clock moving on must not change the handoff state
    let state = driver.stop()
    #expect(state?.value == last)
    let expected = SpringSolver(parameters: p, displacement: -200, velocity: 0).velocity(at: 2.0 / 120)
    #expect(abs(state!.velocity - expected) < 1e-9)
  }

  @Test func stopBeforeFirstTickReturnsFromAndInitialVelocity() {
    let driver = makeDriver()
    driver.start(from: 30, to: 200, initialVelocity: -150, parameters: p, threshold: 0.25,
                 onUpdate: { _ in }, completion: nil)
    let state = driver.stop()
    #expect(abs(state!.value - 30) < 1e-9)
    #expect(abs(state!.velocity + 150) < 1e-6)
  }

  @Test func animateStartedInsideOnUpdateSurvivesTheOldRun() {
    let driver = makeDriver()
    var firstCompletions: [Bool] = []
    var secondCompletions: [Bool] = []
    var secondUpdates: [Double] = []
    var restarted = false
    let p = p
    let settle = SpringRun(from: 0, to: 200, initialVelocity: 0, parameters: p, start: 0, threshold: 0.25).duration
    driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                 onUpdate: { _ in
                   guard !restarted else { return }
                   restarted = true
                   driver.start(from: 200, to: 0, initialVelocity: 0, parameters: p, threshold: 0.25,
                                onUpdate: { secondUpdates.append($0) },
                                completion: { secondCompletions.append($0) })
                 },
                 completion: { firstCompletions.append($0) })
    // A frame past the first run's settle time: the old run would finish, but must not kill the new one.
    driver.tick(at: clock.now + settle + 0.1)
    #expect(restarted)
    #expect(firstCompletions == [false])
    #expect(secondCompletions.isEmpty)
    #expect(driver.isRunning)
    driver.tick(at: clock.now + 0.01)
    #expect(secondUpdates.count == 1)
  }

  @Test func animateStartedInsideCompletionSurvives() {
    let driver = makeDriver()
    var second: [Bool] = []
    let p = p
    driver.start(from: 0, to: 0, initialVelocity: 0, parameters: p, threshold: 0.25,
                 onUpdate: { _ in },
                 completion: { _ in
                   driver.start(from: 0, to: 100, initialVelocity: 0, parameters: p, threshold: 0.25,
                                onUpdate: { _ in }, completion: { second.append($0) })
                 })
    driver.tick(at: clock.now)   // zero-distance run finishes on its first frame
    #expect(driver.isRunning)
    #expect(second.isEmpty)
  }

  @Test func reduceMotionJumpsToTargetSynchronously() {
    let driver = makeDriver(reduceMotion: true)
    var updates: [Double] = []
    var completions: [Bool] = []
    let started = driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                               onUpdate: { updates.append($0) }, completion: { completions.append($0) })
    #expect(!started)
    #expect(updates == [200])
    #expect(completions == [true])
    #expect(!driver.isRunning)
  }

  @Test func windowlessViewJumpsToTargetSynchronously() {
    let driver = makeDriver()
    var updates: [Double] = []
    var completions: [Bool] = []
    driver.animate(in: NSView(), from: 0, to: 120, initialVelocity: 0, parameters: p,
                   onUpdate: { updates.append($0) }, completion: { completions.append($0) })
    #expect(updates == [120])
    #expect(completions == [true])
    #expect(!driver.isRunning)
  }

  @Test func immediatePathStopsThePreviousRunFirst() {
    let driver = makeDriver()
    var first: [Bool] = []
    driver.start(from: 0, to: 200, initialVelocity: 0, parameters: p, threshold: 0.25,
                 onUpdate: { _ in }, completion: { first.append($0) })
    driver.animate(in: NSView(), from: 0, to: 120, initialVelocity: 0, parameters: p, onUpdate: { _ in })
    #expect(first == [false])
    #expect(!driver.isRunning)
  }

  // C4 review follow-up: a completion that always restarts must not recurse or loop forever.

  @Test func immediatePathCompletionThatAlwaysRestartsStopsAtTheDepthLimit() {
    SpringDriver.assertsOnDroppedCompletion = false
    defer { SpringDriver.assertsOnDroppedCompletion = true }
    let driver = makeDriver()
    let view = NSView()
    var completions = 0
    let p = p
    func again() {
      driver.animate(in: view, from: 0, to: 10, initialVelocity: 0, parameters: p, onUpdate: { _ in },
                     completion: { _ in completions += 1; again() })
    }
    again()
    #expect(completions == SpringDriver.maxImmediateDepth)
    #expect(!driver.isRunning)
  }

  @Test func reduceMotionCompletionThatAlwaysRestartsStopsAtTheDepthLimit() {
    SpringDriver.assertsOnDroppedCompletion = false
    defer { SpringDriver.assertsOnDroppedCompletion = true }
    let driver = makeDriver(reduceMotion: true)
    var completions = 0
    let p = p
    func again() {
      driver.start(from: 0, to: 10, initialVelocity: 0, parameters: p, threshold: 0.25, onUpdate: { _ in },
                   completion: { _ in completions += 1; again() })
    }
    again()
    #expect(completions == SpringDriver.maxImmediateDepth)
  }

  @Test func interruptedCompletionThatAlwaysRestartsDoesNotHangStopAll() {
    SpringDriver.assertsOnDroppedCompletion = false
    defer { SpringDriver.assertsOnDroppedCompletion = true }
    let driver = makeDriver()
    var interrupted = 0
    let p = p
    func again() {
      driver.start(from: 0, to: 10, initialVelocity: 0, parameters: p, threshold: 0.25, onUpdate: { _ in },
                   completion: { done in if !done { interrupted += 1; again() } })
    }
    again()
    var second: [Bool] = []
    driver.start(from: 0, to: 50, initialVelocity: 0, parameters: p, threshold: 0.25, onUpdate: { _ in },
                 completion: { second.append($0) })
    #expect(interrupted == SpringDriver.maxStopPasses)
    #expect(driver.isRunning, "the new run replaces the restarted one")
    var t = clock.now
    while driver.isRunning && t < clock.now + 20 { t += 1.0 / 120; driver.tick(at: t) }
    #expect(second == [true])
  }

  @Test func oneRestartFromAnImmediateCompletionStillRuns() {
    let driver = makeDriver()
    var updates: [Double] = []
    let p = p
    driver.animate(in: NSView(), from: 0, to: 10, initialVelocity: 0, parameters: p, onUpdate: { _ in },
                   completion: { _ in
                     driver.animate(in: NSView(), from: 10, to: 20, initialVelocity: 0, parameters: p,
                                    onUpdate: { updates.append($0) })
                   })
    #expect(updates == [20])
  }
}
