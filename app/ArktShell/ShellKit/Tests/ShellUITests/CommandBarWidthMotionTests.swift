import AppKit
import Motion
import Testing
@testable import ShellUI

/// The bar's width springs between 680 and 968 and retargets when the selection changes mid-flight (#372).
/// Stepped on an injected clock: no sleep, no display link.
@MainActor
struct CommandBarWidthMotionTests {
  private final class Clock {
    var t: Double = 100
  }

  private func motion(_ clock: Clock, reduce: Bool = false) -> CommandBarWidthMotion {
    let motion = CommandBarWidthMotion()
    motion.now = { clock.t }
    motion.reduceMotion = { reduce }
    motion.drivesFramesItself = false
    return motion
  }

  @Test func `a widen starts at the narrow width and settles on the wide one`() {
    let clock = Clock()
    let m = motion(clock)
    m.retarget(to: 968, from: 680)
    #expect(m.isRunning)
    #expect(m.width == 680)
    clock.t += 0.05
    let mid = m.width
    #expect(mid > 680 && mid < 968)
    clock.t += 2
    m.presentFrame()
    #expect(!m.isRunning)
    #expect(m.width == 968)
  }

  @Test func `up or down mid-flight retargets from the current width`() {
    let clock = Clock()
    let m = motion(clock)
    m.retarget(to: 968, from: 680)
    clock.t += 0.04
    let here = m.width
    #expect(here > 680 && here < 968)
    m.retarget(to: 680, from: 968)
    #expect(abs(m.width - here) < 0.01, "continuous: \(m.width) vs \(here)")
    // Velocity is still toward 968, so the turnaround is not the next instant.
    var turned = false
    for _ in 0..<40 {
      clock.t += 1.0 / 120
      m.presentFrame()
      if m.width < here - 0.5 { turned = true; break }
    }
    #expect(turned, "heads back toward the narrow width")
    let after = m.width
    m.retarget(to: 968, from: 680)
    #expect(abs(m.width - after) < 0.01, "a second retarget also continues from here")
  }

  @Test func `the same target does not restart the spring`() {
    let clock = Clock()
    let m = motion(clock)
    m.retarget(to: 968, from: 680)
    clock.t += 0.05
    let here = m.width
    m.retarget(to: 968, from: here)
    #expect(abs(m.width - here) < 0.01)
    #expect(m.isRunning)
  }

  @Test func `Reduce Motion snaps the width`() {
    let clock = Clock()
    let m = motion(clock, reduce: true)
    var settled: Double?
    m.onSettled = { settled = $0 }
    m.retarget(to: 968, from: 680)
    #expect(!m.isRunning)
    #expect(m.width == 968)
    #expect(settled == 968)
  }

  @Test func `the widen interval stays open across a retarget and closes when the spring rests`() {
    let clock = Clock()
    let m = motion(clock)
    m.retarget(to: 968, from: 680)
    #expect(m.isSignpostOpen)
    clock.t += 0.04
    m.retarget(to: 680, from: 968)
    #expect(m.isSignpostOpen, "a retarget does not open a second interval")
    clock.t += 2
    m.presentFrame()
    #expect(!m.isSignpostOpen)
  }

  @Test func `Reduce Motion does not leave a width interval open`() {
    let clock = Clock()
    let m = motion(clock, reduce: true)
    m.retarget(to: 968, from: 680)
    #expect(!m.isRunning)
    #expect(!m.isSignpostOpen)
  }

  @Test func `presenting a frame does not require a view`() {
    let clock = Clock()
    let m = motion(clock)
    var frames: [Double] = []
    m.onFrame = { frames.append($0) }
    m.retarget(to: 968, from: 680)
    #expect(frames == [680])
    clock.t += 1.0 / 120
    m.presentFrame()
    #expect(frames.count == 2)
    #expect(frames[1] > 680 && frames[1] < 968)
  }
}
