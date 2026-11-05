import CoreGraphics
import QuartzCore
import Testing
@testable import ShellUI

/// The in-between frames of a pane close reflow (#388): pure math, no views.
struct SplitReflowTests {
  // MARK: Frames

  @Test func frameAtTheEndsIsTheEndFrame() {
    let from = CGRect(x: 510, y: 0, width: 500, height: 600)
    let to = CGRect(x: 0, y: 0, width: 1010, height: 600)
    #expect(SplitReflow.frame(from: from, to: to, progress: 0, scale: 2) == from)
    #expect(SplitReflow.frame(from: from, to: to, progress: 1, scale: 2) == to)
  }

  /// Edges move linearly with progress and land on the pixel grid, so a page never draws between pixels.
  @Test func frameInterpolatesEdgesOnThePixelGrid() {
    let from = CGRect(x: 0, y: 0, width: 333, height: 600)
    let to = CGRect(x: 0, y: 0, width: 500, height: 600)
    let half = SplitReflow.frame(from: from, to: to, progress: 0.5, scale: 2)
    #expect(half == CGRect(x: 0, y: 0, width: 416.5, height: 600))
    let third = SplitReflow.frame(from: from, to: to, progress: 1.0 / 3, scale: 1)
    #expect(third.width == 389)                       // 333 + 167 / 3 = 388.67, rounded to whole points at 1x
  }

  /// A spring may overshoot past 1 a little; the frame then passes the target by as much, never inverting.
  @Test func frameNeverHasNegativeSize() {
    let from = CGRect(x: 0, y: 0, width: 10, height: 10)
    let to = CGRect(x: 100, y: 0, width: 0, height: 10)
    let frame = SplitReflow.frame(from: from, to: to, progress: 1.2, scale: 2)
    #expect(frame.width >= 0)
    #expect(frame.height >= 0)
  }

  // MARK: Dividers

  @Test func dividersFillTheGapsBetweenSideBySidePanes() {
    let panes = [CGRect(x: 0, y: 0, width: 300, height: 600), CGRect(x: 312, y: 0, width: 400, height: 600)]
    #expect(SplitReflow.dividers(between: panes, axis: .sideBySide) == [CGRect(x: 300, y: 0, width: 12, height: 600)])
  }

  /// Stacked panes run top to bottom in unflipped coordinates: pane 0 sits above pane 1.
  @Test func dividersFillTheGapsBetweenStackedPanes() {
    let panes = [CGRect(x: 0, y: 310, width: 800, height: 300), CGRect(x: 0, y: 0, width: 800, height: 300)]
    #expect(SplitReflow.dividers(between: panes, axis: .stacked) == [CGRect(x: 0, y: 300, width: 800, height: 10)])
  }

  // MARK: Transform (#602)

  /// The panes keep their real frames at the layout's targets for the whole reflow; each card's layer transform
  /// presents it where the spring has it. AppKit anchors a view's layer at its origin, so the transform maps the
  /// layer's bounds, placed at the real frame's origin, onto the presented frame.
  @Test func transformPresentsTheRealFrameAtTheInBetweenFrame() {
    let real = CGRect(x: 0, y: 0, width: 500, height: 600)
    let presented = CGRect(x: 120.5, y: 10, width: 416.5, height: 580)
    let transform = SplitReflow.transform(presenting: presented, in: real)
    let mapped = CGRect(origin: .zero, size: real.size)
      .applying(CATransform3DGetAffineTransform(transform))
      .offsetBy(dx: real.minX, dy: real.minY)
    #expect(abs(mapped.minX - presented.minX) < 1e-9)
    #expect(abs(mapped.minY - presented.minY) < 1e-9)
    #expect(abs(mapped.width - presented.width) < 1e-9)
    #expect(abs(mapped.height - presented.height) < 1e-9)
  }

  @Test func transformIsIdentityAtRest() {
    let real = CGRect(x: 510, y: 0, width: 500, height: 600)
    #expect(CATransform3DIsIdentity(SplitReflow.transform(presenting: real, in: real)))
  }

  /// A real frame with no size (a pane laid out before the window has one) moves without scaling.
  @Test func transformOfAnEmptyRealFrameOnlyTranslates() {
    let transform = SplitReflow.transform(presenting: CGRect(x: 30, y: 40, width: 100, height: 100),
                                          in: CGRect(x: 10, y: 10, width: 0, height: 0))
    let affine = CATransform3DGetAffineTransform(transform)
    #expect(affine.a == 1 && affine.d == 1)
    #expect(affine.tx == 20 && affine.ty == 30)
  }

  // MARK: Distance and interruption

  /// The spring runs in points along the longest edge move, so its rest threshold is half a pixel of real motion.
  @Test func distanceIsTheLongestEdgeMove() {
    let from = [CGRect(x: 0, y: 0, width: 300, height: 600), CGRect(x: 310, y: 0, width: 300, height: 600)]
    let to = [CGRect(x: 0, y: 0, width: 450, height: 600), CGRect(x: 460, y: 0, width: 300, height: 600)]
    #expect(SplitReflow.distance(from: from, to: to) == 150)
    #expect(SplitReflow.distance(from: to, to: to) == 0)
  }

  /// A reflow taken over mid-flight towards the same frames keeps its speed: what was left becomes the whole run.
  @Test func carriedVelocityKeepsTheSpeedOfAnInterruptedReflow() {
    // 300 pt run, at 40 % moving at 600 pt/s, retargeted onto a 180 pt run: still 600 pt/s.
    #expect(SplitReflow.carriedVelocity(600, distance: 300, progress: 0.4, newDistance: 180) == 600)
    #expect(SplitReflow.carriedVelocity(600, distance: 300, progress: 0.4, newDistance: 0) == 0)
    #expect(SplitReflow.carriedVelocity(.nan, distance: 300, progress: 0.4, newDistance: 180) == 0)
    #expect(SplitReflow.carriedVelocity(600, distance: 0, progress: 0, newDistance: 180) == 0)
  }
}
