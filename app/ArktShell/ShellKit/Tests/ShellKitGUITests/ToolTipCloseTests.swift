import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// #301 item 3: a tool tip shown when a shell window closed (the Space title's "Drag to Reorder Space", 131 x 20 pt
/// at window layer 103) stayed on screen after the window was gone. Closing the window takes its tool tips down.
@MainActor
final class ToolTipCloseTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testClosingTheWindowRemovesEveryToolTipOfItsViews() throws {
    let source = StubSidebar()
    let space = source.addSpace(title: "Space 1")
    let url = try XCTUnwrap(URL(string: "about:blank"))
    _ = source.addTab(url: url, title: "Page", in: .today(space))
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    let window = try XCTUnwrap(controller.window)
    let root = try XCTUnwrap(window.contentView)
    root.layoutSubtreeIfNeeded()
    let page = try XCTUnwrap(controller.sidebarController.currentPage)
    XCTAssertTrue(page.showsHeaderToolTipForTesting, "the header has its reorder tool tip while the window is open")
    XCTAssertFalse(Self.toolTips(in: root).isEmpty, "the window's views have tool tips while it is open")

    controller.close()

    XCTAssertEqual(Self.toolTips(in: root), [], "no view of a closed window keeps a tool tip")
    XCTAssertFalse(page.showsHeaderToolTipForTesting, "the header's rect tool tip is removed too")
  }

  private static func toolTips(in view: NSView) -> [String] {
    (view.toolTip.map { [$0] } ?? []) + view.subviews.flatMap { toolTips(in: $0) }
  }
}
