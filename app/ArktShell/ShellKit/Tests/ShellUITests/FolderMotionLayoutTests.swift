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
}
