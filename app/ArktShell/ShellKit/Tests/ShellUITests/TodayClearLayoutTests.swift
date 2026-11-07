import CoreGraphics
import Testing
@testable import ShellUI

/// Where the rows draw while Clear archives them (#413, design/clear-today-tabs): every archived row collapses upward
/// at once (fades, lifts 6 pt, shrinks to 0.38 from its top) and the rows below close the gap on the same spring.
/// Reduce Motion fades the archived rows in place and moves nothing.
struct TodayClearLayoutTests {
  private let pitch: CGFloat = 41

  /// Rows: 0 a kept row above, 1 and 2 archived, 3 a kept row below (a playing tab).
  private func styles(_ gone: Double, moves: Bool = true) -> [FolderMotionLayout.RowStyle] {
    let block = FolderMotionLayout.Block(rows: [(1, pitch), (2, pitch)])
    return (0..<4).map { row in
      var style = FolderMotionLayout.RowStyle.rest
      TodayClearLayout.apply(to: &style, atRow: row, block: block, gone: gone, moves: moves)
      return style
    }
  }

  @Test func `at rest every row draws in place`() {
    #expect(styles(0).allSatisfy { $0 == .rest })
  }

  @Test func `gone, the archived rows have collapsed upward and the row below has closed the gap`() {
    let end = styles(1)
    #expect(end[0] == .rest)
    #expect(end[1] == FolderMotionLayout.RowStyle(offsetY: -TodayClearLayout.lift, alpha: 0,
                                                  scaleY: TodayClearLayout.endScaleY))
    #expect(end[2] == FolderMotionLayout.RowStyle(offsetY: -pitch - TodayClearLayout.lift, alpha: 0,
                                                  scaleY: TodayClearLayout.endScaleY))
    #expect(end[3] == FolderMotionLayout.RowStyle(offsetY: -2 * pitch, alpha: 1))
  }

  @Test func `halfway, every archived row is halfway at once`() {
    let half = styles(0.5)
    #expect(half[1].alpha == 0.5)
    #expect(half[2].alpha == 0.5, "no stagger")
    #expect(half[1].offsetY == -3)
    #expect(abs(half[1].scaleY - 0.69) < 1e-9)
    #expect(half[3].offsetY == -pitch)
    #expect(half[3].alpha == 1)
  }

  @Test func `an overshooting spring never draws a negative opacity or an inverted row`() {
    let past = styles(1.04)
    #expect(past[1].alpha == 0)
    #expect(past[1].scaleY == TodayClearLayout.endScaleY)
  }

  @Test func `Reduce Motion fades the archived rows in place and moves nothing`() {
    let half = styles(0.5, moves: false)
    #expect(half[0] == .rest)
    #expect(half[1] == FolderMotionLayout.RowStyle(offsetY: 0, alpha: 0.5))
    #expect(half[2] == FolderMotionLayout.RowStyle(offsetY: 0, alpha: 0.5))
    #expect(half[3] == .rest)
  }

  @Test func `a leaving folder's shown rows fade with it and their heights close the gap`() {
    // Rows: 0 a leaving folder (41), 1 and 2 its open tabs (41, 30), 3 a kept row below.
    let block = FolderMotionLayout.Block(rows: [(0, 41), (1, 41), (2, 30)])
    let styles = (0..<4).map { row in
      var style = FolderMotionLayout.RowStyle.rest
      TodayClearLayout.apply(to: &style, atRow: row, block: block, gone: 0.5, moves: true)
      return style
    }
    #expect(styles[1].alpha == 0.5)
    #expect(styles[2].alpha == 0.5)
    #expect(styles[2].offsetY == -0.5 * 82 - 3)
    #expect(styles[3] == FolderMotionLayout.RowStyle(offsetY: -0.5 * 112, alpha: 1))
  }
}
