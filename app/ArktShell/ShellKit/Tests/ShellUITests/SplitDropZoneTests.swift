import CoreGraphics
import Testing
@testable import ShellUI

/// Decision 11 (GS-011, BH-117): the left third drops on the left; the right third and the middle band on the right;
/// the top and bottom quarters of the middle column stack. Rects are unflipped, like `SplitLayout`: the top is `maxY`.
struct SplitDropZoneTests {
  /// 300 x 400 at an offset origin, so the thirds are 100 wide and the quarters 100 tall.
  private let bounds = CGRect(x: 50, y: 20, width: 300, height: 400)

  private func zone(_ x: CGFloat, _ y: CGFloat) -> SplitDropZone? {
    SplitDropZone.zone(for: CGPoint(x: x, y: y), in: bounds)
  }

  @Test func leftThirdIsLeftAtEveryHeight() {
    #expect(zone(50, 220) == .left)
    #expect(zone(149.9, 220) == .left)
    #expect(zone(100, 419) == .left, "the top of the left third is still left")
    #expect(zone(100, 21) == .left, "the bottom of the left third is still left")
  }

  @Test func rightThirdIsRightAtEveryHeight() {
    #expect(zone(250, 220) == .right, "the right third starts at two thirds")
    #expect(zone(350, 220) == .right)
    #expect(zone(300, 419) == .right, "the top of the right third is still right")
    #expect(zone(300, 21) == .right, "the bottom of the right third is still right")
  }

  @Test func middleBandIsRight() {
    #expect(zone(150, 220) == .right, "the middle column starts at one third")
    #expect(zone(200, 220) == .right)
    #expect(zone(249.9, 220) == .right)
    #expect(zone(200, 320) == .right, "the top quarter starts above 320")
    #expect(zone(200, 120) == .right, "the bottom quarter ends below 120")
  }

  @Test func topQuarterOfTheMiddleColumnIsTop() {
    #expect(zone(200, 320.1) == .top)
    #expect(zone(200, 420) == .top)
    #expect(zone(150, 400) == .top)
    #expect(zone(249.9, 400) == .top)
  }

  @Test func bottomQuarterOfTheMiddleColumnIsBottom() {
    #expect(zone(200, 20) == .bottom)
    #expect(zone(200, 119.9) == .bottom)
    #expect(zone(150, 40) == .bottom)
    #expect(zone(249.9, 40) == .bottom)
  }

  @Test func pointsOutsideTheBoundsHaveNoZone() {
    #expect(zone(49.9, 220) == nil)
    #expect(zone(350.1, 220) == nil)
    #expect(zone(200, 19.9) == nil)
    #expect(zone(200, 420.1) == nil)
  }

  @Test func degenerateBoundsHaveNoZone() {
    #expect(SplitDropZone.zone(for: .zero, in: .zero) == nil)
    #expect(SplitDropZone.zone(for: CGPoint(x: 10, y: 0), in: CGRect(x: 0, y: 0, width: 100, height: 0)) == nil)
    #expect(SplitDropZone.zone(for: CGPoint(x: 0, y: 10), in: CGRect(x: 0, y: 0, width: 0, height: 100)) == nil)
    #expect(SplitDropZone.zone(for: CGPoint(x: 1, y: 1), in: .null) == nil)
  }

  /// Left and right lay the panes side by side, top and bottom stack them; left and top put the new pane first.
  @Test func zonesMapToAxisOrientationAndSide() {
    #expect(SplitDropZone.left.axis == .sideBySide)
    #expect(SplitDropZone.right.axis == .sideBySide)
    #expect(SplitDropZone.top.axis == .stacked)
    #expect(SplitDropZone.bottom.axis == .stacked)
    #expect(SplitDropZone.left.orientation == .horizontal)
    #expect(SplitDropZone.top.orientation == .vertical)
    #expect(SplitDropZone.left.isBefore && SplitDropZone.top.isBefore)
    #expect(!SplitDropZone.right.isBefore && !SplitDropZone.bottom.isBefore)
  }
}
