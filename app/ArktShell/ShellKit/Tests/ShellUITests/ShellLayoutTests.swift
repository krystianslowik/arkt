import CoreGraphics
import Testing
@testable import ShellUI

struct ShellLayoutTests {
  let metrics = ShellMetrics.standard
  let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)   // flipped: y grows downward

  @Test func sidebarAndInsetCard() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: true, metrics: metrics)
    #expect(layout.sidebarFrame == CGRect(x: 0, y: 0, width: 190, height: 800))
    #expect(layout.cardFrame == CGRect(x: 190, y: 9, width: 1000, height: 781))
    #expect(layout.resizeHandleFrame == CGRect(x: 186, y: 0, width: 8, height: 800))
  }

  @Test func clampsSidebarWidth() {
    let narrow = ShellLayout.compute(bounds: bounds, sidebarWidth: 20, sidebarVisible: true, metrics: metrics)
    let wide = ShellLayout.compute(bounds: bounds, sidebarWidth: 900, sidebarVisible: true, metrics: metrics)
    #expect(narrow.sidebarFrame.width == metrics.sidebarMinWidth)
    #expect(wide.sidebarFrame.width == metrics.sidebarMaxWidth)
  }

  @Test func hiddenSidebarGivesCardEvenInsets() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: false, metrics: metrics)
    #expect(layout.sidebarFrame.width == 0)
    #expect(layout.cardFrame == CGRect(x: 10, y: 9, width: 1180, height: 781))
  }
}
