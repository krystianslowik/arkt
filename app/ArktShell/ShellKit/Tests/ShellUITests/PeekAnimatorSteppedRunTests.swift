import AppKit
import CoreGraphics
import Testing
@testable import ShellUI

/// A stepped run (no display link) shows its first frame at the instant the run started, however long the machine
/// takes to get from the start of `run` to its first frame (#437).
@MainActor
struct PeekAnimatorSteppedRunTests {
  /// A clock that moves on at every read, as a busy runner's does between two lines of code.
  private final class StallingClock {
    private var time = 100.0
    let stallPerRead: Double
    init(stallPerRead: Double) { self.stallPerRead = stallPerRead }
    func read() -> Double {
      defer { time += stallPerRead }
      return time
    }
  }

  @Test func steppedRunShowsItsFirstFrameAtTheStartInstantNoMatterHowLongTheClockStalls() {
    let clock = StallingClock(stallPerRead: 0.5)
    let animator = PeekAnimator(scene: .rest, now: { clock.read() })
    animator.drivesDisplayLink = false
    var frames: [PeekScene] = []
    animator.onFrame = { frames.append($0) }

    animator.jump(to: PeekMotion.openStart(linkOffset: .zero, reduceMotion: false))
    animator.run(PeekMotion.targets(for: .open, reduceMotion: false), label: "open", in: NSView())

    #expect(frames.last?[.cardOpacity] == 0, "no time has passed in the run's first frame")
    #expect(frames.last?[.cardScale] == 0.90)
  }
}
