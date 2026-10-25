import CoreGraphics
import Testing
@testable import ShellUI

struct ShellLayoutTests {
  let metrics = ShellMetrics.standard
  let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)   // flipped: y grows downward

  @Test func sidebarAndInsetCard() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: true, metrics: metrics)
    #expect(layout.sidebarFrame == CGRect(x: 0, y: 0, width: 190, height: 800))
    #expect(layout.cardFrame == CGRect(x: 190, y: 10, width: 1000, height: 780))
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
    #expect(layout.sidebarFrame.width == 190, "hidden keeps the width for the overlay (#102)")
    #expect(layout.cardFrame == CGRect(x: 10, y: 10, width: 1180, height: 780))
  }

  /// Arc 1.168 values from `docs/plans/2026-10-23-arc-measurements.md` (#186). The strip height is the Toolbar-on
  /// layout; Arc was not measured with the Toolbar off.
  @Test func measuredWindowMetrics() {
    #expect(metrics.trafficLightOrigin == CGPoint(x: 12, y: 16))
    #expect(metrics.trafficLightSpacing == 23)
    #expect(metrics.sidebarTopBarHeight == 36)
    #expect(metrics.cardInsetTop == 10)
  }
}

@MainActor
struct ContentToolbarMetricsTests {
  /// Arc 1.168 values from `docs/plans/2026-10-23-arc-measurements.md` (#186): a 32 pt strip and a 1 pt hairline.
  @Test func measuredToolbarMetrics() {
    #expect(ContentToolbarView.stripHeight == 32)
    #expect(ContentToolbarView.hairlineHeight == 1)
    #expect(ContentToolbarView.height == 33)
    #expect(ContentToolbarView.buttonSize == CGSize(width: 32, height: 24))
    #expect(ContentToolbarView.buttonSpacing == 5)
    #expect(ContentToolbarView.iconSize == 14)
    #expect(ContentToolbarView.horizontalPadding == 5)
    #expect(ContentToolbarView.urlBarHeight == 24)
  }
}
