import CoreGraphics
import Testing
@testable import ShellUI

/// The hover close (X) fade covers only the distance left, at the speed of a full fade.
struct HoverCloseFadeTests {
  @Test func fullFadeTakesTheFullDuration() {
    #expect(HoverCloseFade.duration(from: 0, to: 1, full: 0.12) == 0.12)
    #expect(HoverCloseFade.duration(from: 1, to: 0, full: 0.12) == 0.12)
  }

  @Test func interruptedFadeTakesTheRemainingShare() {
    let duration = HoverCloseFade.duration(from: 0.25, to: 0, full: 0.2)
    #expect(abs(duration - 0.05) < 1e-9)
  }

  @Test func noDistanceTakesNoTime() {
    #expect(HoverCloseFade.duration(from: 1, to: 1, full: 0.12) == 0)
  }

  @Test func opacityOutsideTheUnitRangeIsClamped() {
    #expect(HoverCloseFade.duration(from: 1.5, to: 0, full: 0.1) == 0.1)
    #expect(HoverCloseFade.duration(from: -1, to: 1, full: 0.1) == 0.1)
  }
}
