import CoreGraphics
import Testing
@testable import ShellUI

/// The hybrid design's metrics (design/command-bar/README.md, Layout), all in points.
struct CommandBarGeometryTests {
  @Test func `the layout table`() {
    typealias G = CommandBarGeometry
    #expect(G.preferredWidth == 680)
    #expect(G.cornerRadius == 16)
    #expect(G.inputHeight == 58)
    #expect(G.inputLeading == 18)
    #expect(G.rowHeight == 40)
    #expect(G.selectedRowRadius == 9)
    #expect(G.rowHorizontalPadding == 12)
    #expect(G.slotWidth == 20)
    #expect(G.slotGap == 12)
    #expect(G.listPadding == 6)
    #expect(G.hintStripHeight == 34)
    #expect(G.tickWidth == 3)
    #expect(G.tickInset == 10)
    #expect(G.maxVisibleRows == 5)
  }

  @Test func `centered, with the top edge a fixed 22 percent down so results grow downward`() {
    // 176 pt from the top of the prototype's 800 pt window.
    let parent = CGRect(x: 100, y: 50, width: 1280, height: 800)
    let small = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 58)
    let tall = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 330)
    #expect(small.width == 680)
    #expect(small.midX == parent.midX)
    #expect(abs(small.maxY - (parent.maxY - 176)) < 0.001)
    #expect(small.maxY == tall.maxY, "the top edge does not move when rows are added")
    #expect(tall.height == 330)
  }

  @Test func `shrinks in narrow windows and keeps the side margin`() {
    let frame = CommandBarGeometry.frame(parentFrame: CGRect(x: 0, y: 0, width: 700, height: 600), contentHeight: 58)
    #expect(frame.width == CGFloat(700 - 2 * 24))   // typed: the macro evaluates bare literals as Int
  }

  @Test func `height for rows is the field, a hairline, the padded rows, a hairline and the hint strip`() {
    typealias G = CommandBarGeometry
    let threeRows: CGFloat = 58 + 1 + 6 + 120 + 6 + 1 + 34
    #expect(G.contentHeight(rowCount: 0) == 58)
    #expect(G.contentHeight(rowCount: 3) == threeRows)
    #expect(G.contentHeight(rowCount: 20) == G.contentHeight(rowCount: 5), "five rows without scrolling")
  }

  @Test func `group headers add their height and the empty state shows more rows`() {
    typealias G = CommandBarGeometry
    #expect(G.groupHeaderHeight == 26)
    let oneHeader = G.contentHeight(rowCount: 2) + 26
    let emptyState: CGFloat = 58 + 1 + 6 + 280 + 78 + 6 + 1 + 34
    #expect(G.contentHeight(rowCount: 2, headerCount: 1) == oneHeader)
    #expect(G.contentHeight(rowCount: 7, headerCount: 3, maxRows: G.maxEmptyStateRows) == emptyState)
    #expect(G.maxEmptyStateRows == 7)
  }

  /// BH-113: the notice strip adds its height, with and without result rows.
  @Test func `the notice adds its height`() {
    let rows = 1
    #expect(CommandBarGeometry.contentHeight(rowCount: rows, showsNotice: true)
            == CommandBarGeometry.contentHeight(rowCount: rows) + CommandBarGeometry.noticeHeight)
    #expect(CommandBarGeometry.contentHeight(rowCount: 0, showsNotice: true)
            == CommandBarGeometry.inputHeight + CommandBarGeometry.noticeHeight)
  }

  @Test func `Little Arkt keeps the metrics the command bar had before the hybrid design`() {
    #expect(LittleArktGeometry.preferredWidth == 766)
    #expect(LittleArktGeometry.rowHeight == 50)
    #expect(LittleArktGeometry.inputHeight == 60)
  }
}
