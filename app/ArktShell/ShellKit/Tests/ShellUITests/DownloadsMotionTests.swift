import QuartzCore
import Testing
@testable import ShellUI

/// Downloads motion as data (design/downloads, Motion): the numbers, and the progress tween that retargets from where it
/// is. No clock, no sleeps: every time is an argument.
struct DownloadsMotionTests {
  @Test func `rows rise eight points over 0.24 s on firm, and fade only under Reduce Motion`() {
    let step = DownloadsMotion.rowAppears(reduceMotion: false)
    #expect(step.offset == 8 && step.scale == 1 && step.duration == 0.24 && step.curve == DownloadsMotion.firm)
    let reduced = DownloadsMotion.rowAppears(reduceMotion: true)
    #expect(reduced.offset == 0 && reduced.scale == 1 && reduced.duration == 0.15)
  }

  @Test func `the popover scales from 0.97 over 0.22 s, and fades only under Reduce Motion`() {
    let step = DownloadsMotion.popoverAppears(reduceMotion: false)
    #expect(step.scale == 0.97 && step.offset == 0 && step.duration == 0.22 && step.curve == DownloadsMotion.firmFast)
    #expect(DownloadsMotion.popoverAppears(reduceMotion: true).scale == 1)
  }

  @Test func `the small numbers of the design`() {
    #expect(DownloadsMotion.removeDuration == 0.16 && DownloadsMotion.swapDuration == 0.12)
    #expect(DownloadsMotion.pillPressScale == 0.97 && DownloadsMotion.iconPressScale == 0.94)
    #expect(DownloadsMotion.pressDuration == 0.12 && DownloadsMotion.progressDuration == 0.5)
    #expect(DownloadsMotion.removeDuration < DownloadsMotion.rowAppears(reduceMotion: false).duration,
            "leaving is faster than arriving")
  }

  @Test func `a tween is linear over half a second`() {
    var tween = ProgressTween()
    tween.retarget(to: 1, at: 10, reduceMotion: false)
    #expect(tween.value(at: 10) == 0)
    #expect(abs(tween.value(at: 10.25) - 0.5) < 1e-9)
    #expect(tween.value(at: 10.5) == 1 && tween.value(at: 99) == 1)
    #expect(tween.isSettled(at: 10.5) && !tween.isSettled(at: 10.1))
  }

  @Test func `a new target starts from the value shown now, never from the old target`() {
    var tween = ProgressTween()
    tween.retarget(to: 0.4, at: 0, reduceMotion: false)
    let from = tween.retarget(to: 0.8, at: 0.25, reduceMotion: false)      // half way to 0.4
    #expect(abs(from - 0.2) < 1e-9)
    #expect(abs(tween.value(at: 0.25) - 0.2) < 1e-9, "no jump when retargeted")
    #expect(abs(tween.value(at: 0.5) - 0.5) < 1e-9)
    #expect(tween.value(at: 0.75) == 0.8)
  }

  @Test func `a stream of updates keeps the value continuous and moving forward`() {
    var tween = ProgressTween()
    var last = 0.0
    for tick in 0..<40 {
      let now = Double(tick) * 0.1                                         // an update every 100 ms
      tween.retarget(to: min(1, Double(tick + 1) / 40), at: now, reduceMotion: false)
      let shown = tween.value(at: now + 0.05)
      #expect(shown >= last, "never backwards")
      last = shown
    }
  }

  @Test func `reduce motion jumps to the value`() {
    var tween = ProgressTween()
    tween.retarget(to: 0.6, at: 5, reduceMotion: true)
    #expect(tween.value(at: 5) == 0.6 && tween.isSettled(at: 5))
  }
}
