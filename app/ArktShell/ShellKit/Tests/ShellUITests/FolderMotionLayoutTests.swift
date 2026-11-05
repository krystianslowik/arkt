import CoreGraphics
import Testing
@testable import ShellUI

/// The per-row offsets and opacities of a folder's open / close spring (#109): the rows that come and go slide under
/// the folder row and fade, and every row below them follows by the height still missing.
struct FolderMotionLayoutTests {
  private let pitch: CGFloat = 41

  /// Rows: 0 folder, 1 and 2 its children (changing), 3 the next row.
  private func closing(_ progress: Double) -> [FolderMotionLayout.RowStyle] {
    FolderMotionLayout.styles(
      rowHeights: Array(repeating: pitch, count: 4),
      transitions: [.init(changingRows: [1, 2], progress: progress)])
  }

  @Test func atFullProgressEveryRowRestsInPlace() {
    #expect(closing(1).allSatisfy { $0 == .rest })
  }

  @Test func atZeroProgressTheChangingRowsSitUnderTheFolderAndTheRestCloseTheGap() {
    let styles = closing(0)
    #expect(styles[0] == .rest)
    #expect(styles[1] == FolderMotionLayout.RowStyle(offsetY: 0, alpha: 0))
    #expect(styles[2] == FolderMotionLayout.RowStyle(offsetY: -pitch, alpha: 0))
    #expect(styles[3] == FolderMotionLayout.RowStyle(offsetY: -2 * pitch, alpha: 1))
  }

  @Test func halfwayMovesHalfTheGapAndHalfTheOpacity() {
    let styles = closing(0.5)
    #expect(styles[2].offsetY == -pitch / 2)
    #expect(styles[2].alpha == 0.5)
    #expect(styles[3].offsetY == -pitch)
    #expect(styles[3].alpha == 1)
  }

  /// A spring may overshoot its target a little: the offset follows it, the opacity stays in 0...1.
  @Test func overshootKeepsOpacityInRange() {
    #expect(closing(1.04)[1].alpha == 1)
    #expect(closing(-0.03)[1].alpha == 0)
  }

  /// A row that stays (the current tab peeking out, BH-092) keeps full opacity and rises by the rows above it that go.
  @Test func aStayingRowInsideTheBlockRisesOnlyByTheRowsAboveItThatGo() {
    let styles = FolderMotionLayout.styles(
      rowHeights: Array(repeating: pitch, count: 5),
      transitions: [.init(changingRows: [1, 3], progress: 0)])
    #expect(styles[2] == FolderMotionLayout.RowStyle(offsetY: -pitch, alpha: 1))
    #expect(styles[4].offsetY == -2 * pitch)
  }

  /// Two folders moving at once add their gaps for the rows below both.
  @Test func twoTransitionsAddUp() {
    let styles = FolderMotionLayout.styles(
      rowHeights: Array(repeating: pitch, count: 6),
      transitions: [.init(changingRows: [1], progress: 0), .init(changingRows: [3, 4], progress: 0.5)])
    #expect(styles[2].offsetY == -pitch)
    #expect(styles[5].offsetY == -pitch - pitch)
  }

  /// Heights come from the rows: the divider row is shorter than a tab row.
  @Test func usesEachRowsOwnHeight() {
    let styles = FolderMotionLayout.styles(
      rowHeights: [pitch, 12, pitch],
      transitions: [.init(changingRows: [1], progress: 0)])
    #expect(styles[2].offsetY == -12)
  }

  // MARK: One row at a time (#603)

  /// A small deterministic generator, so the cases are the same on every run.
  private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Styling one row from the captured blocks gives exactly the whole-outline result, for nested, overlapping and
  /// overshooting folders, rows of two heights, and an arrival on top.
  @Test func oneRowFromTheBlocksMatchesTheWholeOutline() {
    var random = SplitMix(state: 603)
    for _ in 0..<200 {
      let count = Int.random(in: 1...60, using: &random)
      let heights = (0..<count).map { _ in Bool.random(using: &random) ? pitch : 12 }
      let transitions = (0..<Int.random(in: 0...3, using: &random)).map { _ in
        FolderMotionLayout.Transition(
          changingRows: Set((0..<count).filter { _ in Int.random(in: 0..<4, using: &random) == 0 }),
          progress: Double.random(in: -0.05...1.05, using: &random))
      }
      var reference = FolderMotionLayout.styles(rowHeights: heights, transitions: transitions)
      let arrivalRow = Bool.random(using: &random) ? Int.random(in: 0..<count, using: &random) : -1
      let oldSelection = Int.random(in: -1..<count, using: &random)
      let room = Double.random(in: -0.05...1.05, using: &random)
      let appear = Double.random(in: -0.05...1.05, using: &random)
      if arrivalRow >= 0 {
        SidebarArrivalLayout.apply(to: &reference, arrivalHeight: heights[arrivalRow], arrivalRow: arrivalRow,
                                   oldSelectionRow: oldSelection, room: room, appear: appear)
      }
      let moving = transitions.map { transition in
        (block: FolderMotionLayout.Block(rows: transition.changingRows.map { ($0, heights[$0]) }),
         progress: transition.progress)
      }
      for row in 0..<count {
        var style = FolderMotionLayout.style(atRow: row, moving: moving)
        if arrivalRow >= 0 {
          SidebarArrivalLayout.apply(to: &style, atRow: row, arrivalHeight: heights[arrivalRow], arrivalRow: arrivalRow,
                                     oldSelectionRow: oldSelection, room: room, appear: appear)
        }
        #expect(style == reference[row], "row \(row) of \(count)")
      }
    }
  }

  /// A block is the changing rows in order and the height gone above each, whatever order they were captured in.
  @Test func aBlockSortsItsRowsAndSumsTheHeightsAbove() {
    let block = FolderMotionLayout.Block(rows: [(5, pitch), (2, 12), (9, pitch)])
    #expect(block.rows == [2, 5, 9])
    #expect(block.goneAbove == [0, 12, 12 + pitch, 12 + 2 * pitch])
    #expect(block.countAbove(0) == 0)
    #expect(block.countAbove(5) == 1)
    #expect(block.countAbove(6) == 2)
    #expect(block.countAbove(100) == 3)
  }
}
