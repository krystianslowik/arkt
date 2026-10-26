import Testing
@testable import ShellUI

/// The particle field's fallback trigger (onboarding spec, section 7.4; decision of #375): the 8,192-mote 60 Hz tier
/// takes over when 30 of the last 60 frames went over 2 ms of GPU time, a sliding window rather than a streak.
struct ParticleFallbackTriggerTests {
  typealias Window = GPUBudgetWindow

  private static func window(_ frames: [Double]) -> Window {
    var window = Window()
    for milliseconds in frames { window.record(milliseconds) }
    return window
  }

  @Test func alternatingSlowAndFastFramesTripIt() {
    // Never two slow frames in a row, so a streak count would stay at 1 forever.
    let alternating = (0..<60).map { $0.isMultiple(of: 2) ? 2.6 : 0.4 }
    let window = Self.window(alternating)
    #expect(window.overBudget == 30)
    #expect(window.tripsFallback)
  }

  @Test func aSingleSpikeDoesNotTripIt() {
    let frames = Array(repeating: 0.4, count: 59) + [9.0] + Array(repeating: 0.4, count: 120)
    let window = Self.window(frames)
    #expect(window.overBudget == 0, "the spike left the window")
    #expect(!window.tripsFallback)
    #expect(!Self.window(Array(repeating: 0.4, count: 30) + [9.0]).tripsFallback)
  }

  @Test func twentyNineOfSixtyStaysOnTheFullTier() {
    let frames = (0..<60).map { $0 < 29 ? 3.0 : 0.5 }
    #expect(Self.window(frames).overBudget == 29)
    #expect(!Self.window(frames).tripsFallback)
  }

  @Test func onlyTheLastSixtyFramesCount() {
    // 30 slow frames, then 31 fast ones: the oldest slow frame has slid out.
    let frames = Array(repeating: 3.0, count: 30) + Array(repeating: 0.5, count: 31)
    #expect(Self.window(frames).overBudget == 29)
    #expect(!Self.window(frames).tripsFallback)
    #expect(Self.window(Array(repeating: 3.0, count: 30)).tripsFallback, "a sustained overload still trips it")
  }

  @Test func exactlyTwoMillisecondsIsWithinBudget() {
    #expect(Self.window(Array(repeating: 2.0, count: 60)).overBudget == 0)
    #expect(Self.window(Array(repeating: 2.01, count: 60)).overBudget == 60)
  }

  @Test func gpuTimesExposeTheWindowAndResetIt() {
    let times = GPUFrameTimes(budgetMilliseconds: 2)
    for frame in 0..<60 { times.record(frame.isMultiple(of: 2) ? 2.6 : 0.4) }
    #expect(times.tripsFallback)
    times.reset()
    #expect(!times.tripsFallback)
  }
}
