import Testing
@testable import ShellUI

struct FrameStatsTests {
  @Test func countsHitchesAgainstBothThresholds() {
    var stats = FrameStats(hitchThreshold: 0.0086, designBudget: 0.00834)
    stats.record(interval: 1.0 / 120)                        // lead-in, not counted
    for _ in 0..<98 { stats.record(interval: 1.0 / 120) }   // 8.333 ms
    stats.record(interval: 0.0085)                           // over design budget only
    stats.record(interval: 0.0167)                           // dropped frame
    #expect(stats.frameCount == 100)
    #expect(stats.hitchCount == 1)
    #expect(stats.overBudgetCount == 2)
    #expect(abs(stats.overBudgetRatio - 0.02) < 1e-9)
    #expect(abs(stats.maxInterval - 0.0167) < 1e-9)
  }

  // C6 re-review: the first interval spans display-link start-up; it is reported but not gated.
  @Test func firstIntervalIsLeadInAndNotGated() {
    var stats = FrameStats()
    stats.record(interval: 0.0125)
    #expect(stats.leadInInterval == 0.0125)
    #expect(stats.frameCount == 0)
    #expect(stats.hitchCount == 0)
    #expect(stats.overBudgetCount == 0)
    #expect(stats.maxInterval == 0)
    stats.record(interval: 0.0125)
    #expect(stats.leadInInterval == 0.0125)
    #expect(stats.frameCount == 1)
    #expect(stats.hitchCount == 1)
    #expect(stats.intervals == [0.0125])
  }

  @Test func emptyStatsAreZero() {
    let stats = FrameStats()
    #expect(stats.overBudgetRatio == 0)
    #expect(stats.p99 == 0)
    #expect(stats.leadInInterval == nil)
  }
}
