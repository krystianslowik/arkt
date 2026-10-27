import AppKit
import Motion
import Testing
@testable import ShellUI

/// The selection fill and tick slide to the new row and retarget when the key repeats (design/command-bar/README.md,
/// Motion). Stepped by hand on an injected clock: no sleeps, no display link.
@MainActor
struct CommandBarSelectionMotionTests {
  private final class Clock {
    var t: Double = 100
  }

  private func motion(_ clock: Clock, reduce: Bool = false) -> CommandBarSelectionMotion {
    let motion = CommandBarSelectionMotion()
    motion.now = { clock.t }
    motion.reduceMotion = { reduce }
    motion.drivesFramesItself = false
    return motion
  }

  @Test func `a move starts at the old row and settles on the new one`() {
    let clock = Clock()
    let m = motion(clock)
    m.move(from: 0, to: 40)
    #expect(m.isRunning)
    #expect(m.offset(toward: 40) == -40, "at the start the fill is still on the old row")
    clock.t += 0.05
    let mid = m.offset(toward: 40) ?? 0
    #expect(mid < 0 && mid > -40, "on the way")
    clock.t += 1
    m.presentFrame()
    #expect(!m.isRunning, "settled: the motion ends and the model position is the place")
    #expect(m.offset(toward: 40) == nil)
  }

  @Test func `the offset shrinks toward zero and never overshoots with the firm fast preset`() {
    let clock = Clock()
    let m = motion(clock)
    m.move(from: 0, to: 80)
    var previous = -80.0
    for _ in 0..<40 {
      clock.t += 1.0 / 120
      let offset = m.offset(toward: 80) ?? 0
      #expect(offset >= previous - 0.001, "monotone toward the target")
      #expect(offset <= 0.5, "no visible overshoot")
      previous = offset
    }
  }

  @Test func `key repeat mid-flight retargets from where the fill is, not from zero`() {
    let clock = Clock()
    let m = motion(clock)
    m.move(from: 0, to: 40)
    clock.t += 0.04
    let here = 40 + (m.offset(toward: 40) ?? 0)          // the fill's current y
    m.move(from: 40, to: 80)                              // the next row, the old row was never reached
    let after = 80 + (m.offset(toward: 80) ?? 0)
    #expect(abs(after - here) < 0.01, "continuous: the retarget starts where the fill was (\(here), \(after))")
    #expect(here > 0 && here < 40)
  }

  @Test func `retargeting keeps the velocity so a repeating key does not stutter`() {
    let clock = Clock()
    let m = motion(clock)
    m.move(from: 0, to: 40)
    clock.t += 0.04
    let y1 = 40 + (m.offset(toward: 40) ?? 0)
    clock.t += 0.004
    let y2 = 40 + (m.offset(toward: 40) ?? 0)
    let speedBefore = (y2 - y1) / 0.004
    m.move(from: 40, to: 80)
    clock.t += 0.004
    let y3 = 80 + (m.offset(toward: 80) ?? 0)
    let speedAfter = (y3 - y2) / 0.004
    #expect(speedBefore > 0 && speedAfter > 0, "still moving down after the retarget")
    #expect(speedAfter > speedBefore * 0.5, "the velocity carried over")
  }

  @Test func `Reduce Motion moves instantly`() {
    let clock = Clock()
    let m = motion(clock, reduce: true)
    m.move(from: 0, to: 40)
    #expect(!m.isRunning)
    #expect(m.offset(toward: 40) == nil)
  }

  @Test func `settling now ends a running move`() {
    let clock = Clock()
    let m = motion(clock)
    m.move(from: 0, to: 40)
    m.settleNow()
    #expect(!m.isRunning)
  }

  @Test func `the spring is the firm fast preset`() {
    #expect(CommandBarSelectionMotion.parameters == SpringPreset.firmFast.parameters)
  }

  @Test func `frames are reported while it runs and once more at the end`() {
    let clock = Clock()
    let m = motion(clock)
    var frames = 0
    m.onFrame = { frames += 1 }
    m.move(from: 0, to: 40)
    clock.t += 0.03
    m.presentFrame()
    #expect(frames == 1)
    clock.t += 2
    m.presentFrame()
    #expect(frames == 2)
    #expect(!m.isRunning)
  }
}
