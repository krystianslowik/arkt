import CoreGraphics
import Testing
@testable import ShellUI

struct FavoritesLayoutTests {
  /// Content widths of the narrow (150), default (190) and wide (400) sidebar.
  static let narrow: CGFloat = 134
  static let standard: CGFloat = 174
  static let wide: CGFloat = 384

  @Test func measuredSidebarGeometry() {
    // Measurement: 192 pt sidebar, 8 pt insets, 53.3 x 47 tiles, about 8.2 pt gaps, 63 pt section.
    let width = FavoritesLayout.contentWidth(sidebarWidth: 192)
    #expect(width == 176)
    #expect(FavoritesLayout.columns(itemCount: 3, contentWidth: width) == 3)
    let size = FavoritesLayout.itemSize(contentWidth: width, columns: 3)
    #expect(abs(size.width - 53.3) < 0.1)
    #expect(size.height == 47)
    let frames = (0..<3).map { FavoritesLayout.frame(ofItem: $0, itemCount: 3, contentWidth: width) }
    for (index, frame) in frames.enumerated() {
      #expect(abs(frame.minX - CGFloat(index) * 61.5) <= 0.5)
      #expect(abs(frame.width - 53.3) <= 0.71)
      #expect(frame.height == 47)
      if index > 0 { #expect(abs(frame.minX - frames[index - 1].maxX - 8.2) <= 0.3) }
    }
    #expect(frames.last?.maxX == 176)
    #expect(SidebarMetrics.favoritesTopGap + FavoritesLayout.height(itemCount: 3, contentWidth: width)
            + SidebarMetrics.favoritesBottomGap == 63)
  }

  @Test func tilesStretchWithSidebar() {
    let size = FavoritesLayout.itemSize(contentWidth: 201, columns: 3)
    #expect(size.height == 47)
    #expect(abs(size.width - 185.0 / 3.0) < 0.001)
  }

  @Test func gridHeight() {
    #expect(FavoritesLayout.height(itemCount: 0, contentWidth: Self.standard) == 0)
    #expect(FavoritesLayout.height(itemCount: 3, contentWidth: Self.standard) == 47)
    #expect(FavoritesLayout.height(itemCount: 4, contentWidth: Self.standard) == 102)
    #expect(FavoritesLayout.height(itemCount: 4, contentWidth: Self.wide) == 47, "one row of 4 in a wide sidebar")
  }

  // MARK: Columns

  /// Preserve the existing capacity thresholds independently of the rendering gap.
  @Test func columnCapacityFollowsTheMinimumTileWidth() {
    #expect(FavoritesLayout.columnCapacity(contentWidth: Self.narrow) == 2)
    #expect(FavoritesLayout.columnCapacity(contentWidth: Self.standard) == 3)
    #expect(FavoritesLayout.columnCapacity(contentWidth: Self.wide) == 4)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 112) == 1)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 113) == 2)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 173) == 2, "one point short of three")
    #expect(FavoritesLayout.columnCapacity(contentWidth: 174) == 3)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 234) == 3)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 235) == 4)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 2000) == 4, "never more than 4")
    // One column only below the sidebar's minimum width (a 150 pt sidebar already fits two).
    #expect(FavoritesLayout.columnCapacity(contentWidth: 100) == 1)
    #expect(FavoritesLayout.columnCapacity(contentWidth: 0) == 1)
  }

  /// Expected columns for 1...12 Favorites: rows fill evenly (4 is one row of 4 when 4 fit, never 3 + 1).
  static let expectedColumns: [CGFloat: [Int]] = [
    narrow: [1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
    standard: [1, 2, 3, 2, 3, 3, 3, 3, 3, 3, 3, 3],
    wide: [1, 2, 3, 4, 3, 3, 4, 4, 3, 4, 4, 4],
  ]

  @Test(arguments: [narrow, standard, wide], 1...12)
  func columnsFillRowsEvenly(contentWidth: CGFloat, count: Int) throws {
    let columns = FavoritesLayout.columns(itemCount: count, contentWidth: contentWidth)
    #expect(columns == Self.expectedColumns[contentWidth]?[count - 1])
    #expect((1...FavoritesLayout.maxColumns).contains(columns))
    let rows = FavoritesLayout.rows(itemCount: count, columns: columns)
    let fewestRows = (count + FavoritesLayout.columnCapacity(contentWidth: contentWidth) - 1)
      / FavoritesLayout.columnCapacity(contentWidth: contentWidth)
    #expect(rows == fewestRows, "as few rows as the width allows")
    #expect(count - (rows - 1) * columns >= 1, "the last row is not empty")
    #expect(rows * columns - count < rows, "rows differ by at most one tile per row")
  }

  @Test(arguments: [narrow, standard, wide], 1...12)
  func framesFillTheRowAndKeepTheMinimumWidth(contentWidth: CGFloat, count: Int) {
    let columns = FavoritesLayout.columns(itemCount: count, contentWidth: contentWidth)
    let frames = (0..<count).map { FavoritesLayout.frame(ofItem: $0, itemCount: count, contentWidth: contentWidth) }
    for (index, frame) in frames.enumerated() {
      #expect(frame.width >= FavoritesLayout.minimumTileWidth - 0.5)
      #expect(frame.height == FavoritesLayout.tileHeight)
      #expect(frame.minY == CGFloat(index / columns) * (FavoritesLayout.tileHeight + FavoritesLayout.gap))
      #expect(frame.minX >= 0 && frame.maxX <= contentWidth + 0.001)
      if index % columns == 0 { #expect(frame.minX == 0) }
      if index % columns == columns - 1 { #expect(abs(frame.maxX - contentWidth) <= 0.5, "full rows reach the edge") }
      if index % columns > 0 {
        #expect(abs(frame.minX - frames[index - 1].maxX - FavoritesLayout.gap) <= 1, "rounded measured gaps")
      }
      #expect(frame.minX == frame.minX.rounded() && frame.maxX == frame.maxX.rounded(), "whole points")
    }
    #expect(frames.last?.maxY == FavoritesLayout.height(itemCount: count, contentWidth: contentWidth))
  }

  /// A short last row keeps the grid's columns: its tiles line up under the ones above.
  @Test func shortLastRowAlignsWithTheColumnsAbove() {
    let frames = (0..<5).map { FavoritesLayout.frame(ofItem: $0, itemCount: 5, contentWidth: Self.wide) }
    #expect(frames[3].minX == frames[0].minX && frames[3].width == frames[0].width)
    #expect(frames[4].minX == frames[1].minX)
  }

  // MARK: Slots and interpolation

  @Test func slotFrameMatchesTheGrid() {
    let slot = FavoritesLayout.slot(ofItem: 5, columns: 4)
    #expect(slot == FavoritesLayout.Slot(left: 0.25, width: 0.25, row: 1))
    #expect(FavoritesLayout.frame(of: slot, contentWidth: Self.wide)
            == FavoritesLayout.frame(ofItem: 5, itemCount: 8, contentWidth: Self.wide))
  }

  @Test func heightOfFractionalRows() {
    #expect(FavoritesLayout.height(rows: 1) == 47)
    #expect(FavoritesLayout.height(rows: 1.5) == 47 + 0.5 * 55)
    #expect(FavoritesLayout.height(rows: 0) == 0)
  }

  // MARK: Keyboard neighbors

  @Test func horizontalNeighborsRunInOrder() {
    #expect(FavoritesLayout.neighbor(of: 2, deltaColumns: 1, deltaRows: 0, itemCount: 6, columns: 3) == 3)
    #expect(FavoritesLayout.neighbor(of: 3, deltaColumns: -1, deltaRows: 0, itemCount: 6, columns: 3) == 2)
    #expect(FavoritesLayout.neighbor(of: 5, deltaColumns: 1, deltaRows: 0, itemCount: 6, columns: 3) == nil)
    #expect(FavoritesLayout.neighbor(of: 0, deltaColumns: -1, deltaRows: 0, itemCount: 6, columns: 3) == nil)
  }

  @Test func verticalNeighborsFollowTheColumns() {
    #expect(FavoritesLayout.neighbor(of: 1, deltaColumns: 0, deltaRows: 1, itemCount: 8, columns: 4) == 5)
    #expect(FavoritesLayout.neighbor(of: 5, deltaColumns: 0, deltaRows: -1, itemCount: 8, columns: 4) == 1)
    #expect(FavoritesLayout.neighbor(of: 1, deltaColumns: 0, deltaRows: 1, itemCount: 8, columns: 2) == 3)
    #expect(FavoritesLayout.neighbor(of: 1, deltaColumns: 0, deltaRows: -1, itemCount: 8, columns: 4) == nil)
    #expect(FavoritesLayout.neighbor(of: 5, deltaColumns: 0, deltaRows: 1, itemCount: 8, columns: 4) == nil,
            "Down from the last row leaves the grid")
  }

  /// Down above a gap in a short last row lands on that row's last tile instead of leaving the grid.
  @Test func downIntoAShortLastRowTakesItsLastTile() {
    // 5 tiles in 3 columns: 3 + 2.
    #expect(FavoritesLayout.neighbor(of: 2, deltaColumns: 0, deltaRows: 1, itemCount: 5, columns: 3) == 4)
    #expect(FavoritesLayout.neighbor(of: 0, deltaColumns: 0, deltaRows: 1, itemCount: 5, columns: 3) == 3)
    #expect(FavoritesLayout.neighbor(of: 4, deltaColumns: 0, deltaRows: 1, itemCount: 5, columns: 3) == nil)
  }
}
