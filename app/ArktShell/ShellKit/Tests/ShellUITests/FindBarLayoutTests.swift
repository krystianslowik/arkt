import CoreGraphics
import Testing
@testable import ShellUI

/// The find bar's geometry (direction A, design/find-in-page/README.md and prototype.html `.fa`): a 372 x 36 pill, 12
/// points from the top and trailing edges of the page, padding 13 before and 6 after, 8 between the parts.
struct FindBarLayoutTests {
  @Test func `the pill is 372 by 36 with a radius of 18`() {
    #expect(FindBarLayout.preferredWidth == 372)
    #expect(FindBarLayout.height == 36)
    #expect(FindBarLayout.cornerRadius == 18)
  }

  @Test func `it sits 12 points from the top and trailing edges of the card`() {
    let card = CGRect(x: 0, y: 0, width: 900, height: 600)
    #expect(FindBarLayout.frame(in: card) == CGRect(x: 900 - 12 - 372, y: 600 - 12 - 36, width: 372, height: 36))
  }

  @Test func `below the Toolbar when it shows`() {
    let belowToolbar = CGRect(x: 0, y: 0, width: 900, height: 567)           // a 600 high card minus the 33 high Toolbar
    let expectedTop: CGFloat = 555
    #expect(FindBarLayout.frame(in: belowToolbar).maxY == expectedTop)
  }

  @Test func `in a narrow card it shrinks to the card width minus 24`() {
    let card = CGRect(x: 0, y: 0, width: 380, height: 600)
    #expect(FindBarLayout.frame(in: card).width == 356)
    #expect(FindBarLayout.frame(in: card).minX == 12)
  }

  @Test func `a split pane anchors the bar to that pane, not the card around it`() {
    let pane = CGRect(x: 510, y: 0, width: 400, height: 600)
    #expect(FindBarLayout.frame(in: pane) == CGRect(x: 510 + 400 - 12 - 372, y: 600 - 12 - 36, width: 372, height: 36))
    let narrow = CGRect(x: 20, y: 40, width: 240, height: 500)             // the shortest pane
    let shrunk = FindBarLayout.frame(in: narrow)
    #expect(shrunk.width == 216)
    #expect(shrunk.maxX == narrow.maxX - 12)
    #expect(shrunk.maxY == narrow.maxY - 12)
    #expect(shrunk.minX == narrow.minX + 12)
  }

  @Test func `the parts at 372 with the minimum count width`() {
    let parts = FindBarLayout.parts(width: 372, countWidth: 56)
    #expect(parts.glyph == CGRect(x: 13, y: 11, width: 14, height: 14))
    #expect(parts.close == CGRect(x: 342, y: 6, width: 24, height: 24))
    #expect(parts.next == CGRect(x: 310, y: 6, width: 24, height: 24))
    #expect(parts.previous == CGRect(x: 278, y: 6, width: 24, height: 24))
    #expect(parts.separator == CGRect(x: 267, y: 11, width: 1, height: 14))
    #expect(parts.count == CGRect(x: 201, y: 8, width: 56, height: 20))
    #expect(parts.field == CGRect(x: 35, y: 8, width: 158, height: 20))
  }

  @Test func `a wider count takes its room from the field, never from the buttons`() {
    let parts = FindBarLayout.parts(width: 372, countWidth: 70)
    #expect(parts.count.width == 70)
    #expect(parts.count.maxX == 257)
    #expect(parts.field.maxX == parts.count.minX - 8)
    #expect(parts.field.width == 144)
    #expect(parts.previous.minX == 278)
  }

  @Test func `a long query scrolls inside the field, so the field never grows the bar`() {
    let parts = FindBarLayout.parts(width: 372, countWidth: 56)
    #expect(parts.field.width == 158, "its width is what is left, whatever the text")
  }

  @Test func `the count width is at least 56 and follows the text`() {
    #expect(FindBarLayout.countWidth(textWidth: 30) == 56)
    #expect(FindBarLayout.countWidth(textWidth: 61.2) == 62)
  }

  @Test func `the field never has a negative width`() {
    let parts = FindBarLayout.parts(width: 200, countWidth: 200)
    #expect(parts.field.width >= 0)
  }
}
