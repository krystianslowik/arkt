import CoreGraphics
import Testing
@testable import ShellUI

/// The grouped bar's metrics (design/command-bar/README.md, Layout), all in points.
struct CommandBarGeometryTests {
  typealias G = CommandBarGeometry

  @Test func `the layout table`() {
    #expect(G.maxWidth == 600)
    #expect(G.sideMargin == 24)
    #expect(G.cornerRadius == 14)
    #expect(G.inputHeight == 54)
    #expect(G.inputLeading == 20)
    #expect(G.magnifierSize == 18)
    #expect(G.magnifierGap == 12)
    #expect(G.rowHeight == 36)
    #expect(G.rowRadius == 8)
    #expect(G.rowHorizontalPadding == 10)
    #expect(G.slotWidth == 18)
    #expect(G.slotGap == 12)
    #expect(G.iconSize == 16)
    #expect(G.listSidePadding == 6)
    #expect(G.listTopPadding == 6)
    #expect(G.listBottomPadding == 8)
    #expect(G.groupHeaderHeight == 26)
    #expect(G.firstGroupHeaderHeight == 20)
    #expect(G.keyCapHeight == 20)
    #expect(G.keyCapRadius == 5)
    #expect(G.minimumURLWidth == 48)
  }

  /// clamp(48, 14 % of the window height, 110), rounded to a whole point.
  @Test func `the top edge`() {
    #expect(G.top(windowHeight: 420) == 59)
    #expect(G.top(windowHeight: 300) == 48)
    #expect(G.top(windowHeight: 700) == 98)
    #expect(G.top(windowHeight: 800) == 110)
    #expect(G.top(windowHeight: 1400) == 110)
  }

  /// The spec's height arithmetic: the worst case with a Go row, the 15-row worst screen, no results, an empty list.
  @Test func `content heights`() {
    #expect(G.contentHeight(rowCount: 16, headerCount: 5, firstRowHasHeader: false) == 775)
    #expect(G.contentHeight(rowCount: 15, headerCount: 5, firstRowHasHeader: true) == 733)
    #expect(G.contentHeight(rowCount: 1, headerCount: 1, firstRowHasHeader: true) == 125)
    #expect(G.contentHeight(rowCount: 0, headerCount: 0, firstRowHasHeader: false) == 54)
  }

  /// A row that starts a group is taller by its header: 20 at the top of the list, 26 elsewhere.
  @Test func `row heights`() {
    #expect(G.rowHeight(hasHeader: false, isFirst: true) == 36)
    #expect(G.rowHeight(hasHeader: true, isFirst: true) == 56)
    #expect(G.rowHeight(hasHeader: true, isFirst: false) == 62)
  }

  /// Centered, 600 wide from a 648 pt window up, top edge fixed so results grow downward.
  @Test func `the frame in a large window`() {
    let parent = CGRect(x: 100, y: 50, width: 1280, height: 800)
    let frame = G.frame(parentFrame: parent, contentHeight: 300)
    #expect(frame.width == 600)
    #expect(frame.midX == parent.midX)
    #expect(frame.maxY == parent.maxY - CGFloat(110))
    #expect(frame.height == 300)
  }

  /// At most `window height - top - 24` tall; then the list scrolls. 909 pt is the first window the worst case fits.
  @Test func `the panel stops 24 above the bottom`() {
    let parent = CGRect(x: 0, y: 0, width: 1280, height: 800)
    #expect(G.frame(parentFrame: parent, contentHeight: 775).height == CGFloat(800 - 110 - 24))
    let tall = CGRect(x: 0, y: 0, width: 1280, height: 909)
    #expect(G.frame(parentFrame: tall, contentHeight: 775).height == 775)
  }

  /// The smallest window, 640 x 420: 592 wide, top 59.
  @Test func `the smallest window`() {
    let parent = CGRect(x: 0, y: 0, width: 640, height: 420)
    let frame = G.frame(parentFrame: parent, contentHeight: 733)
    #expect(frame.width == 592)
    #expect(frame.minX == 24)
    #expect(frame.maxY == CGFloat(420 - 59))
    #expect(frame.height == CGFloat(420 - 59 - 24))
  }
}
