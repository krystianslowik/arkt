import SidebarModel
import Testing

struct SmokeTests {
  /// Proves CoreBridgeTests resolves ArktCore through the relative package dependency.
  @Test func sidebarModelIsReachable() {
    #expect(SidebarModelVersion.current == 1)
  }
}
