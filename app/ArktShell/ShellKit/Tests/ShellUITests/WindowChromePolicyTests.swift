import Testing
@testable import ShellUI

struct WindowChromePolicyTests {
  @Test func doubleClickFollowsSystemSetting() {
    #expect(TitlebarDoubleClickAction(defaultsValue: "Maximize") == .zoom)
    #expect(TitlebarDoubleClickAction(defaultsValue: "Fill") == .zoom)
    #expect(TitlebarDoubleClickAction(defaultsValue: "Minimize") == .minimize)
    #expect(TitlebarDoubleClickAction(defaultsValue: "None") == .none)
    #expect(TitlebarDoubleClickAction(defaultsValue: nil) == .zoom)
    #expect(TitlebarDoubleClickAction(defaultsValue: "Unexpected") == .zoom)
  }

  @Test func resizeCursorShowsOnlyPossibleDirections() {
    let m = ShellMetrics.standard
    #expect(SidebarResizeHandle.allowedDirections(width: 190, metrics: m) == .both)
    #expect(SidebarResizeHandle.allowedDirections(width: m.sidebarMinWidth, metrics: m) == .widenOnly)
    #expect(SidebarResizeHandle.allowedDirections(width: m.sidebarMaxWidth, metrics: m) == .narrowOnly)
  }
}
