import CoreGraphics
import Testing
@testable import ShellUI

struct ScrollAxisLockTests {
  /// Feeds `steps` events of (dx, dy) after a zero-delta start; returns the decided axis.
  private func decide(dx: CGFloat, dy: CGFloat, steps: Int = 6) -> ScrollAxisLock<Int>.Axis {
    var lock = ScrollAxisLock<Int>()
    _ = lock.feed(0, dx: 0, dy: 0, starts: true, ends: false)
    for i in 1...steps { _ = lock.feed(i, dx: dx, dy: dy, starts: false, ends: false) }
    return lock.axis
  }

  @Test func buffersUntilTheGestureMovesThenReleasesInOrder() {
    var lock = ScrollAxisLock<Int>()
    #expect(lock.feed(1, dx: 0, dy: 0, starts: true, ends: false).isEmpty)
    #expect(lock.feed(2, dx: -3, dy: 0, starts: false, ends: false).isEmpty)
    #expect(lock.feed(3, dx: -5, dy: 1, starts: false, ends: false) == [1, 2, 3])
    #expect(lock.axis == .horizontal)
    #expect(lock.feed(4, dx: 0, dy: 30, starts: false, ends: false) == [4], "the axis stays locked")
  }

  @Test func waitsForSeveralPointsOfTravel() {
    var lock = ScrollAxisLock<Int>()
    _ = lock.feed(1, dx: 0, dy: 0, starts: true, ends: false)
    #expect(lock.feed(2, dx: 3, dy: 0, starts: false, ends: false).isEmpty)
    #expect(lock.feed(3, dx: 2, dy: 0, starts: false, ends: false).isEmpty)
    #expect(lock.axis == .undecided)
  }

  @Test func diagonalTravelIsBiasedVertical() {
    #expect(decide(dx: 1.5, dy: 1) == .vertical, "exactly 1.5x is not enough")
    #expect(decide(dx: 4, dy: 3) == .vertical)
    #expect(decide(dx: 1, dy: 6) == .vertical)
  }

  @Test func clearlyHorizontalLocksHorizontal() {
    #expect(decide(dx: 8, dy: 1, steps: 1) == .horizontal)
    #expect(decide(dx: -4, dy: 2) == .horizontal)
  }

  @Test func mayBeginThenBeganIsOneGesture() {
    var lock = ScrollAxisLock<Int>()
    _ = lock.feed(1, dx: 0, dy: 0, starts: true, ends: false)      // mayBegin
    _ = lock.feed(2, dx: 0, dy: 0, starts: true, ends: false)      // began
    #expect(lock.feed(3, dx: 9, dy: 0, starts: false, ends: false) == [1, 2, 3])
  }

  @Test func endingBeforeMovingFlushesAsVertical() {
    var lock = ScrollAxisLock<Int>()
    _ = lock.feed(1, dx: 0, dy: 0, starts: true, ends: false)
    #expect(lock.feed(2, dx: 2, dy: 0, starts: false, ends: true) == [1, 2])
    #expect(lock.axis == .vertical)
  }

  @Test func nextGestureStartsUndecided() {
    var lock = ScrollAxisLock<Int>()
    _ = lock.feed(1, dx: 9, dy: 0, starts: true, ends: false)
    #expect(lock.axis == .horizontal)
    #expect(lock.feed(2, dx: 0, dy: 0, starts: true, ends: false).isEmpty)
    #expect(lock.axis == .undecided)
    #expect(lock.feed(3, dx: 0, dy: 8, starts: false, ends: false) == [2, 3])
    #expect(lock.axis == .vertical)
  }
}
