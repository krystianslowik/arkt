import CoreGraphics
import Testing
@testable import ShellUI

/// Peek geometry (docs/design/peek.md, Layout and "Peek inside Split View"). Flipped coordinates, points.
struct PeekLayoutTests {
  @Test func theDesignContentCardGetsTheDesignCard() {
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 1080, height: 780))
    #expect(g.card == CGRect(x: 56, y: 34, width: 968, height: 720))
    #expect(g.coverage == CGRect(x: 0, y: 0, width: 1080, height: 780))
    #expect(!g.controlsInside)
  }

  @Test func controlsSitOutsideInTheRightGutterTopAligned() {
    let g = PeekLayout.compute(content: CGRect(x: 10, y: 10, width: 1080, height: 780))
    let x = g.card.maxX + 12
    #expect(g.controls == [
      CGRect(x: x, y: g.card.minY, width: 28, height: 28),
      CGRect(x: x, y: g.card.minY + 36, width: 28, height: 28),
      CGRect(x: x, y: g.card.minY + 72, width: 28, height: 28),
    ])
    #expect(g.controls[0].maxX <= g.coverage.maxX - 12, "the gutter keeps a margin on the right")
  }

  @Test func theGrabberIsCenteredTwelveAboveTheCard() {
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 1080, height: 780))
    #expect(g.grabber == CGRect(x: g.card.midX - 18, y: g.card.minY - 12, width: 36, height: 5))
  }

  @Test func belowSixHundredTheSidesShrinkAndTheControlsMoveInside() {
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 560, height: 700))
    #expect(g.card == CGRect(x: 24, y: 34, width: 512, height: 640))
    #expect(g.controlsInside)
    #expect(g.controls[0] == CGRect(x: g.card.maxX - 12 - 28, y: g.card.minY + 12, width: 28, height: 28))
    #expect(g.controls.allSatisfy { g.card.contains($0) })
  }

  @Test func atExactlySixHundredTheNormalLayoutHolds() {
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 600, height: 700))
    #expect(g.card.minX == 56 && !g.controlsInside)
  }

  @Test func aWideSourcePaneGetsThePaneLayout() {
    let content = CGRect(x: 0, y: 0, width: 1320, height: 800)
    let pane = CGRect(x: 0, y: 0, width: 655, height: 800)
    let g = PeekLayout.compute(content: content, sourcePane: pane)
    #expect(g.coverage == pane)
    #expect(g.card == CGRect(x: 24, y: 34, width: 655 - 24 - 52, height: 800 - 34 - 26))
    #expect(g.controls[0].minX == g.card.maxX + 12)
    #expect(g.controls[0].maxX == pane.maxX - 12)
    #expect(!g.controlsInside)
  }

  @Test func aNarrowSourcePaneCoversTheWholeContentArea() {
    let content = CGRect(x: 0, y: 0, width: 1080, height: 780)
    let pane = CGRect(x: 0, y: 0, width: 535, height: 780)
    let g = PeekLayout.compute(content: content, sourcePane: pane)
    #expect(g.coverage == content)
    #expect(g.card == PeekLayout.compute(content: content).card)
  }

  @Test func aSourcePaneOnTheRightIsOffsetByItsOrigin() {
    let pane = CGRect(x: 665, y: 0, width: 655, height: 800)
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 1320, height: 800), sourcePane: pane)
    #expect(g.card.minX == CGFloat(665 + 24))
  }

  @Test func aTinyContentAreaNeverGoesNegative() {
    let g = PeekLayout.compute(content: CGRect(x: 0, y: 0, width: 30, height: 40))
    #expect(g.card.width >= 0 && g.card.height >= 0)
  }
}
