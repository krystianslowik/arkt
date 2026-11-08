import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Cmd-Opt-Down through a Space of 500 rows (#606): each step's main-thread CPU time is recorded (the issue sets no
/// budget for it, so it is printed, not asserted), and the window layout the reveal asks for runs no layout pass when
/// nothing is pending. Reduce Motion is on, so the reveal scroll lands at once and no display link runs.
@MainActor
final class TabSwitchStepBudgetTests: XCTestCase {
  static let rowCount = 500

  private var controller: ShellWindowController!
  private var tabs: [NodeID] = []
  private var rootLayouts = 0

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Space with a fairly long title for the switcher")
    let scripts = ["Notes", "Заметки по проекту", "会议记录和计划", "ملاحظات الاجتماع", "Ελληνικές σημειώσεις"]
    tabs = try (0..<Self.rowCount).map { index in
      let url = try XCTUnwrap(URL(string: "https://docs-\(index).example-company.com/reports/"
        + String(repeating: "segment/", count: 12) + "page-\(index)"))
      return try sidebar.addTab(url: url, title: "\(scripts[index % scripts.count]) \(index) "
        + String(repeating: "and a very long tail of words ", count: 6), in: .today(space))
    }
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: ModelSidebarSource(sidebar: sidebar))
    controller.window?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.sidebarReveal.reduceMotion = { true }
    controller.tabSwitcher.reduceMotion = { true }
    controller.activate(node: tabs[0])
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.rootView.onLayout = { [unowned self] in rootLayouts += 1 }
  }

  override func tearDown() async throws {
    controller?.rootView.onLayout = nil
    controller?.close()
    controller = nil
  }

  private func threadCPU() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

  /// One Cmd-Opt-Down and the commit that shows it.
  private func step() {
    controller.nextSidebarTab(nil)
    CATransaction.flush()
  }

  func testStepsThroughFiveHundredRowsWithoutAWindowLayoutPass() throws {
    var samples: [Double] = []
    for index in 1..<Self.rowCount {
      let start = threadCPU()
      step()
      samples.append(threadCPU() - start)
      XCTAssertEqual(controller.sidebarController.current, tabs[index])
    }
    XCTAssertEqual(rootLayouts, 0, "a step with nothing pending laid out the window")
    let outline = try XCTUnwrap(controller.sidebarController.currentPage)
    let lastRow = outline.outlineController.row(for: tabs[Self.rowCount - 1])
    XCTAssertTrue(outline.scrollView.contentView.bounds.contains(outline.outlineView.rect(ofRow: lastRow)),
                  "the last row was revealed")

    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    let p95 = sorted[Int(Double(sorted.count) * 0.95) - 1]
    let summary = String(format: "tabswitch.step rows=%d steps=%d median=%.3f p95=%.3f max=%.3f ms rootLayouts=%d",
                         Self.rowCount, samples.count, median * 1000, p95 * 1000, (sorted.last ?? 0) * 1000,
                         rootLayouts)
    print(summary)
    let attachment = XCTAttachment(string: summary)
    attachment.name = "tabswitch.step"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
  }

  /// The layout is there for a reason: work pending when the step runs (a resize, a Space switch the command caused)
  /// is laid out before the reveal measures the outline's visible height.
  func testPendingLayoutRunsOnceBeforeTheReveal() throws {
    controller.rootView.needsLayout = true
    step()
    XCTAssertEqual(rootLayouts, 1, "the pending layout ran in the step")
    step()
    XCTAssertEqual(rootLayouts, 1, "and the next step had nothing to lay out")
    XCTAssertEqual(controller.sidebarController.current, tabs[2])
  }
}
