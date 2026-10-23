import CoreGraphics
import Testing
@testable import ShellUI

struct SplitLayoutTests {
  private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
  private let gap: CGFloat = 10

  // MARK: Axis (decision 1)

  /// The RT-31 anchor: if Arc's stored word means the opposite axis, only `axis(for:)` and this test change.
  @Test func axisForOrientation() {
    #expect(SplitLayout.axis(for: .horizontal) == .sideBySide)
    #expect(SplitLayout.axis(for: .vertical) == .stacked)
  }

  // MARK: Normalization (decision 2)

  @Test func normalizedPadsTruncatesAndRenormalizes() {
    // A count mismatch (pane added or removed without touching the factors) gives equal shares.
    let third: Double = 1.0 / 3
    #expect(SplitLayout.normalized([0.7, 0.3], count: 3) == [third, third, third])
    #expect(SplitLayout.normalized([0.5, 0.3, 0.2], count: 2) == [0.5, 0.5])
    // Shares that do not sum to 1 are rescaled.
    #expect(SplitLayout.normalized([2, 6], count: 2) == [0.25, 0.75])
    // Non-finite or non-positive entries are replaced by an equal share, then everything is renormalized.
    let repaired = SplitLayout.normalized([.nan, 0.5], count: 2)
    #expect(repaired == [0.5, 0.5])
    let mixed = SplitLayout.normalized([0.5, -1, .infinity, 0.5], count: 4)
    #expect(abs(mixed.reduce(0, +) - 1) < 1e-12)
    #expect(mixed.allSatisfy { $0 > 0 && $0.isFinite })
    // Nothing usable: equal shares; no panes: no shares.
    #expect(SplitLayout.normalized([0, 0], count: 2) == [0.5, 0.5])
    #expect(SplitLayout.normalized([], count: 0).isEmpty)
    #expect(SplitLayout.normalized([1], count: -1).isEmpty)
  }

  // MARK: Frames

  @Test func framesTwoPaneSideBySideSplitsWidthMinusGap() {
    let f = SplitLayout.frames(in: bounds, axis: .sideBySide, factors: [0.5, 0.5], gap: gap, scale: 1)
    #expect(f.panes == [CGRect(x: 0, y: 0, width: 495, height: 800), CGRect(x: 505, y: 0, width: 495, height: 800)])
    #expect(f.dividers == [CGRect(x: 495, y: 0, width: 10, height: 800)])
  }

  @Test func framesStackedFourPanes() {
    // Unflipped coordinates (like ContentCardView): pane 0 is the top one, so it sits at maxY.
    let f = SplitLayout.frames(in: CGRect(x: 0, y: 0, width: 600, height: 430), axis: .stacked,
                               factors: [0.25, 0.25, 0.25, 0.25], gap: gap, scale: 1)
    #expect(f.panes == [
      CGRect(x: 0, y: 330, width: 600, height: 100),
      CGRect(x: 0, y: 220, width: 600, height: 100),
      CGRect(x: 0, y: 110, width: 600, height: 100),
      CGRect(x: 0, y: 0, width: 600, height: 100),
    ])
    #expect(f.dividers == [
      CGRect(x: 0, y: 320, width: 600, height: 10),
      CGRect(x: 0, y: 210, width: 600, height: 10),
      CGRect(x: 0, y: 100, width: 600, height: 10),
    ])
  }

  @Test func framesHonorTheBoundsOrigin() {
    let f = SplitLayout.frames(in: CGRect(x: 20, y: 30, width: 410, height: 100), axis: .sideBySide,
                               factors: [0.5, 0.5], gap: gap, scale: 1)
    #expect(f.panes == [CGRect(x: 20, y: 30, width: 200, height: 100), CGRect(x: 230, y: 30, width: 200, height: 100)])
  }

  @Test func framesArePixelAligned() {
    let scale: CGFloat = 2
    let f = SplitLayout.frames(in: CGRect(x: 0, y: 0, width: 1001, height: 703), axis: .sideBySide,
                               factors: [0.3, 0.3, 0.4], gap: gap, scale: scale)
    for rect in f.panes + f.dividers {
      for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
        #expect((edge * scale).rounded() == edge * scale, "edge \(edge) is not on a pixel")
      }
    }
    // Edges are aligned, not widths: panes and gaps tile the bounds with no hole or overlap.
    #expect(f.panes[0].minX == 0)
    #expect(f.panes[2].maxX == 1001)
    for i in 0..<2 {
      #expect(f.dividers[i].minX == f.panes[i].maxX)
      #expect(f.dividers[i].maxX == f.panes[i + 1].minX)
      #expect(f.dividers[i].width == gap)
    }
    let stacked = SplitLayout.frames(in: CGRect(x: 0, y: 0, width: 500, height: 703), axis: .stacked,
                                     factors: [Double](repeating: 1.0 / 3, count: 3), gap: gap, scale: scale)
    for rect in stacked.panes + stacked.dividers {
      #expect((rect.minY * scale).rounded() == rect.minY * scale)
      #expect((rect.maxY * scale).rounded() == rect.maxY * scale)
    }
    #expect(stacked.panes[0].maxY == 703)
    #expect(stacked.panes[2].minY == 0)
  }

  // MARK: Divider drag (decision 4)

  @Test func draggingChangesOnlyAdjacentPanes() {
    let start = [0.25, 0.25, 0.25, 0.25]
    // Available length 1000 - 3 * 10 = 970; pane 1 ends at 485 + 10 = 495 today. Move that end to 595.
    let factors = SplitLayout.factors(dragging: 1, to: 595, in: bounds, axis: .sideBySide, factors: start, gap: gap,
                                      minimum: 100)
    #expect(factors[0] == start[0])
    #expect(factors[3] == start[3])
    #expect(abs(factors[1] - (342.5 / 970)) < 1e-12)
    #expect(abs(factors[2] - (142.5 / 970)) < 1e-12)
    #expect(abs(factors.reduce(0, +) - 1) < 1e-12)
  }

  @Test func draggingStackedMeasuresFromTheTop() {
    // Position is measured from the leading edge: the top for stacked panes.
    let factors = SplitLayout.factors(dragging: 0, to: 300, in: CGRect(x: 0, y: 0, width: 400, height: 810),
                                      axis: .stacked, factors: [0.5, 0.5], gap: gap, minimum: 100)
    #expect(abs(factors[0] - 0.375) < 1e-12)
    #expect(abs(factors[1] - 0.625) < 1e-12)
  }

  @Test func draggingClampsToMinimum() {
    let start = [0.5, 0.5]
    let narrow = SplitLayout.factors(dragging: 0, to: 20, in: bounds, axis: .sideBySide, factors: start, gap: gap,
                                     minimum: 240)
    #expect(abs(narrow[0] - 240.0 / 990) < 1e-12)
    let wide = SplitLayout.factors(dragging: 0, to: 2000, in: bounds, axis: .sideBySide, factors: start, gap: gap,
                                   minimum: 240)
    #expect(abs(wide[1] - 240.0 / 990) < 1e-12)
    // A divider index out of range changes nothing.
    #expect(SplitLayout.factors(dragging: 1, to: 300, in: bounds, axis: .sideBySide, factors: start, gap: gap,
                                minimum: 240) == start)
  }

  @Test func tooSmallBoundsGiveEqualShares() {
    // 3 * 240 + 2 * 10 = 740 > 700.
    let factors = SplitLayout.factors(dragging: 0, to: 100, in: CGRect(x: 0, y: 0, width: 700, height: 500),
                                      axis: .sideBySide, factors: [0.6, 0.2, 0.2], gap: gap, minimum: 240)
    let third: Double = 1.0 / 3
    #expect(factors == [third, third, third])
  }

  @Test func syntheticArcFixtureFactorsLayOut() {
    // The synthetic Arc fixture's split: `vertical`, `[0.5, 0.5]`.
    let axis = SplitLayout.axis(for: .vertical)
    let f = SplitLayout.frames(in: CGRect(x: 0, y: 0, width: 800, height: 610), axis: axis,
                               factors: SplitLayout.normalized([0.5, 0.5], count: 2), gap: gap, scale: 2)
    #expect(f.panes == [CGRect(x: 0, y: 310, width: 800, height: 300), CGRect(x: 0, y: 0, width: 800, height: 300)])
    #expect(f.dividers == [CGRect(x: 0, y: 300, width: 800, height: 10)])
  }
}
