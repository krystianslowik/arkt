import CoreGraphics
import Testing
@testable import ShellUI

/// The zoom pill's geometry (#579, design/extensions/prototype.html `.zoom`).
struct ZoomPillLayoutTests {
  private let page = CGRect(x: 0, y: 0, width: 900, height: 600)

  @Test func `the parts sit in a row, 2 points apart, Reset 4 points further`() {
    let parts = ZoomPillLayout.parts(resetWidth: 60)
    #expect(parts.zoomOut == CGRect(x: 6, y: 6, width: 24, height: 24))
    #expect(parts.percent == CGRect(x: 32, y: 8, width: 48, height: 20))
    #expect(parts.zoomIn == CGRect(x: 82, y: 6, width: 24, height: 24))
    #expect(parts.reset == CGRect(x: 112, y: 6, width: 60, height: 24))
    #expect(ZoomPillLayout.width(resetWidth: 60) == parts.reset.maxX + 6)
  }

  @Test func `the pill is 12 points from the top and trailing edges`() {
    let frame = ZoomPillLayout.frame(in: page, resetWidth: 60)
    #expect(frame == CGRect(x: 900 - 12 - 178, y: 600 - 12 - 36, width: 178, height: 36))
  }

  @Test func `below an open find bar with 8 points between them`() {
    let bar = CGRect(x: 516, y: 552, width: 372, height: 36)
    let frame = ZoomPillLayout.frame(in: page, resetWidth: 60, below: bar)
    #expect(frame.maxY == bar.minY - 8)
    #expect(frame.maxX == bar.maxX)
  }

  @Test func `a page narrower than the pill clamps it to the page minus the insets`() {
    let narrow = CGRect(x: 0, y: 0, width: 120, height: 300)
    let frame = ZoomPillLayout.frame(in: narrow, resetWidth: 60)
    #expect(frame.width == 96)
    #expect(frame.minX == 12)
    #expect(ZoomPillLayout.frame(in: .zero, resetWidth: 60).width == 0, "an empty page never goes negative")
  }
}
