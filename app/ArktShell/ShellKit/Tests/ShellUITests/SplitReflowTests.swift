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

  // MARK: Drawing a card in flight (#602)

  /// A growing pane is drawn at the spring's frame: its real frame is already the larger target, cropped.
  @Test func drawnFrameOfAGrowingPaneIsTheSpringFrame() {
    let real = CGRect(x: 0, y: 0, width: 500, height: 600)
    let spring = CGRect(x: 0, y: 0, width: 416.5, height: 600)
    #expect(SplitReflow.drawnFrame(presenting: spring, in: real, flipped: false) == spring)
    #expect(SplitReflow.drawnFrame(presenting: spring, in: real, flipped: true) == spring)
  }

  /// A shrinking pane has nothing beyond its real (target) size: it is drawn at that size from the spring frame's
  /// top leading corner, so the Toolbar stays in view. Unflipped, the top is `maxY`.
  @Test func drawnFrameOfAShrinkingPaneKeepsItsTopLeadingCorner() {
    let real = CGRect(x: 680, y: 0, width: 330, height: 280)
    let spring = CGRect(x: 600, y: 20, width: 410, height: 300)
    #expect(SplitReflow.drawnFrame(presenting: spring, in: real, flipped: false)
              == CGRect(x: 600, y: 40, width: 330, height: 280))
    #expect(SplitReflow.drawnFrame(presenting: spring, in: real, flipped: true)
              == CGRect(x: 600, y: 20, width: 330, height: 280))
  }

  /// Only a translation, never a scale: the top leading corners meet.
  @Test func translationMovesTheTopLeadingCornerOnly() {
    let real = CGRect(x: 510, y: 0, width: 500, height: 600)
    let drawn = CGRect(x: 600, y: 100, width: 410, height: 500)
    let unflipped = CATransform3DGetAffineTransform(SplitReflow.translation(drawing: drawn, in: real, flipped: false))
    #expect(unflipped == CGAffineTransform(translationX: 90, y: 0))       // maxY 600 meets maxY 600
    let flipped = CATransform3DGetAffineTransform(SplitReflow.translation(drawing: drawn, in: real, flipped: true))
    #expect(flipped == CGAffineTransform(translationX: 90, y: 100))       // minY 0 to minY 100
    #expect(CATransform3DIsIdentity(SplitReflow.translation(drawing: real, in: real, flipped: false)))
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
