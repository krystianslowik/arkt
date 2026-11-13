import CoreGraphics
import Testing
@testable import ShellUI

/// The infobar row height is shared with the engine (#923 review).
struct InfobarMetricsTests {
  /// The engine reserves the same height at the top of the tab's container while the shell draws the row:
  /// `kArktInfobarRowHeight` in engine/arkt/browser/arkt_infobar_view.mm. Change both together.
  @Test func `the row height matches the engine's kArktInfobarRowHeight`() {
    #expect(InfobarMetrics.rowHeight == 40)
  }
}
