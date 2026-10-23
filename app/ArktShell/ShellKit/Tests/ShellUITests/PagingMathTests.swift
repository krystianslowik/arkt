import CoreGraphics
import Testing
@testable import ShellUI

struct PagingMathTests {
  let w: CGFloat = 190

  @Test func slowShortDragStays() {
    #expect(PagingMath.targetIndex(current: 1, translation: -40, velocity: -50, pageWidth: w, count: 3) == 1)
  }

  @Test func slowPastHalfwayAdvances() {
    #expect(PagingMath.targetIndex(current: 1, translation: -100, velocity: 0, pageWidth: w, count: 3) == 2)
    #expect(PagingMath.targetIndex(current: 1, translation: 100, velocity: 0, pageWidth: w, count: 3) == 0)
  }

  @Test func flickAdvancesEvenWhenShort() {
    #expect(PagingMath.targetIndex(current: 0, translation: -30, velocity: -900, pageWidth: w, count: 3) == 1)
  }

  @Test func neverMovesMoreThanOnePageOrPastEnds() {
    #expect(PagingMath.targetIndex(current: 0, translation: -30, velocity: -9000, pageWidth: w, count: 3) == 1)
    #expect(PagingMath.targetIndex(current: 2, translation: -150, velocity: -900, pageWidth: w, count: 3) == 2)
    #expect(PagingMath.targetIndex(current: 0, translation: 150, velocity: 900, pageWidth: w, count: 3) == 0)
  }

  @Test func rubberBandsBeyondEnds() {
    // Past the first page the offset resists: less than the raw translation, never more than the page width.
    let banded = PagingMath.offset(index: 0, translation: 120, pageWidth: w, count: 3)
    #expect(banded > 0 && banded < 120 && banded < w)
    #expect(PagingMath.offset(index: 1, translation: -50, pageWidth: w, count: 3) == -w - 50)
    let last = PagingMath.offset(index: 2, translation: -120, pageWidth: w, count: 3)
    #expect(last < -2 * w && last > -2 * w - 120)
    #expect(PagingMath.offset(index: 0, translation: 100_000, pageWidth: w, count: 3) < w)
  }

  @Test func fractionalPositionForThemeBlend() {
    #expect(PagingMath.position(offset: -w * 1.25, pageWidth: w) == 1.25)
    #expect(PagingMath.position(offset: 10, pageWidth: 0) == 0)
  }

  @Test func singleOrEmptyStripStaysPut() {
    #expect(PagingMath.targetIndex(current: 0, translation: -150, velocity: -900, pageWidth: w, count: 1) == 0)
    #expect(PagingMath.targetIndex(current: 0, translation: -150, velocity: -900, pageWidth: w, count: 0) == 0)
  }
}
