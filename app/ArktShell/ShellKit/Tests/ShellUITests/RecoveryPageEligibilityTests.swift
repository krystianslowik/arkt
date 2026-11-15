import Foundation
import Testing
@testable import ShellUI

@MainActor
struct RecoveryPageEligibilityTests {
  @Test func keepsOnlyTheLastPeekForExistingSources() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let url = URL(string: "https://example.invalid/")!
    let live = sidebar.addTab(url: url, title: "Source", in: .today(space))
    let deleted = sidebar.addTab(url: url, title: "Deleted", in: .today(space))
    sidebar.removeNode(deleted)
    let old = ShellRecoveryPage(title: "Old", url: url, kind: .peek, sourceNode: live)
    let missing = ShellRecoveryPage(title: "Missing", url: url, kind: .peek, sourceNode: deleted)
    let noSource = ShellRecoveryPage(title: "No source", url: url, kind: .peek)
    let window = ShellRecoveryPage(title: "Window", url: url, kind: .littleArkt)
    let last = ShellRecoveryPage(title: "Last", url: url, kind: .peek, sourceNode: live)
    #expect(eligibleRecoveryPages([old, missing, noSource, window, last], sidebar: sidebar) == [window, last])
    #expect(eligibleRecoveryPages([missing, noSource], sidebar: sidebar).isEmpty)
  }
}
