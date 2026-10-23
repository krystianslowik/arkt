import CoreGraphics
import Testing
@testable import ShellUI

struct CommandBarGeometryTests {
  @Test func centeredAThirdDown() {
    // Arc measurement window: 1800 x 1072, screen coordinates (origin bottom-left).
    let parent = CGRect(x: 100, y: 50, width: 1800, height: 1072)
    let frame = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 300)
    #expect(frame.width == 766)
    #expect(frame.midX == parent.midX)
    #expect(abs(frame.maxY - (parent.maxY - 0.34 * 1072)) < 0.001)
    #expect(frame.height == 300)
  }

  @Test func shrinksInNarrowWindows() {
    let frame = CommandBarGeometry.frame(parentFrame: CGRect(x: 0, y: 0, width: 700, height: 600), contentHeight: 60)
    #expect(frame.width == CGFloat(700 - 2 * 24))   // typed: the macro evaluates bare literals as Int
  }

  @Test func heightForRows() {
    #expect(CommandBarGeometry.contentHeight(rowCount: 0) == 60)
    #expect(CommandBarGeometry.contentHeight(rowCount: 3) == CGFloat(60 + 1 + 3 * 50 + 16))
    #expect(CommandBarGeometry.contentHeight(rowCount: 20) == CommandBarGeometry.contentHeight(rowCount: 8))
  }
}
