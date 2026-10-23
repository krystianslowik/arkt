import Testing
@testable import ShellUI

struct VelocityTrackerTests {
  @Test func averagesRecentSamples() {
    var tracker = VelocityTracker(window: 0.1)
    for i in 0..<10 { tracker.add(delta: -10, at: Double(i) * 0.01) }   // -10 pt every 10 ms
    #expect(abs(tracker.velocity - (-1000)) < 1)
  }

  @Test func ignoresStaleSamples() {
    var tracker = VelocityTracker(window: 0.1)
    tracker.add(delta: 500, at: 0)
    tracker.add(delta: -5, at: 0.5)
    tracker.add(delta: -5, at: 0.51)
    #expect(tracker.velocity < 0)
  }

  @Test func samplesSharingATimestampStayFinite() {
    var tracker = VelocityTracker(window: 0.1)
    tracker.add(delta: -10, at: 1)
    tracker.add(delta: -10, at: 1)
    #expect(tracker.velocity.isFinite)
    #expect(tracker.velocity < 0)
  }

  // C6 re-review: a timestamp earlier than the first sample must not flip the sign or blow up.
  @Test func outOfOrderTimestampsKeepTheSign() {
    var tracker = VelocityTracker(window: 0.1)
    tracker.add(delta: 10, at: 1.0)
    tracker.add(delta: 10, at: 0.99)
    #expect(tracker.velocity.isFinite)
    #expect(tracker.velocity > 0)
  }

  @Test func emptyAndResetAreZero() {
    var tracker = VelocityTracker(window: 0.1)
    #expect(tracker.velocity == 0)
    tracker.add(delta: 40, at: 1)
    tracker.reset()
    #expect(tracker.velocity == 0)
  }
}
