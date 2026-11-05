import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Folder open and close in a Space at its worst (#603): a folder of 200 tabs at the top of 1,000 rows. A frame's
/// work is bounded by the rows on screen: the folder's rows are captured once when its transition starts, and each
/// frame styles only the row views the outline has. Frames are driven by hand on the test's own clock.
@MainActor
final class FolderMotionBudgetTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let folderSize = 200
  private static let todayCount = 799

  private var controller: ShellWindowController!
  private var clock: CFTimeInterval = 1000
  private var folder: UUID!
  private var folderTabs: [UUID] = []
  private var today: [UUID] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let url = { (path: String) in URL(string: "https://example.com/\(path)")! }
    folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    folderTabs = try (0..<Self.folderSize).map {
      try sidebar.addTab(url: url("f\($0)"), title: "F\($0)", in: .folder(folder))
    }
    today = try (0..<Self.todayCount).map {
      try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space))
    }
    let source = ModelSidebarSource(sidebar: sidebar, now: { Self.now })
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
    controller.showWindow(nil)
    controller.activate(node: today[0])
    let motion = try outline().folderMotion
    motion.now = { [unowned self] in self.clock }
    motion.drivesFramesItself = false
    motion.reduceMotion = { false }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws {
    controller?.close()
    controller = nil
  }

  private func outline() throws -> SidebarOutlineController {
    try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
  }

  private func clickFolder() throws {
    let outline = try outline()
    let row = outline.row(for: folder)
    XCTAssertGreaterThanOrEqual(row, 0)
    outline.handleClick(row: row, modifiers: [])
  }

  private struct Frames {
    /// The click's own pass: the folder's rows inserted or kept, and the row views the outline makes for them.
    var clickCPU = 0.0
    var cpu: [Double] = []
    var rowsStyled: [Int] = []
    var captures = 0
  }

  /// Clicks the folder and presents 120 Hz frames by hand until the spring settles; each frame's main-thread CPU
  /// time and the rows it styled. The click's pass (with the layout it leaves for the next commit) is measured on
  /// its own: it runs once per click, not per frame. The settling frame (rows leave or stay for good) is the
  /// transition's end, not a motion frame.
  private func clickAndRunFrames() throws -> Frames {
    let outline = try outline()
    var frames = Frames()
    let capturesBefore = outline.motionCaptureCount
    let clickStart = threadCPU()
    try clickFolder()
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    CATransaction.flush()
    frames.clickCPU = threadCPU() - clickStart
    for _ in 0..<240 where outline.folderMotion.isRunning {
      clock += 1.0 / 120
      let start = threadCPU()
      outline.folderMotion.presentFrame()
      CATransaction.flush()
      let spent = threadCPU() - start
      guard outline.folderMotion.isRunning else { break }
      frames.cpu.append(spent)
      frames.rowsStyled.append(outline.lastMotionFrameRowsStyled)
    }
    frames.captures = outline.motionCaptureCount - capturesBefore
    XCTAssertFalse(outline.folderMotion.isRunning, "the spring settled within two seconds of frames")
    return frames
  }

  /// Prints the frames' CPU time and returns its 95th percentile and maximum.
  private func report(_ label: String, _ frames: Frames) -> (p95: Double, max: Double) {
    let cpu = frames.cpu.sorted()
    guard !cpu.isEmpty else { return (0, 0) }
    let median = cpu[cpu.count / 2]
    let p95 = cpu[max(0, Int(Double(cpu.count) * 0.95) - 1)]
    let worst = cpu[cpu.count - 1]
    print(String(format: "foldermotion.frame label=%@ rows=%d frames=%d cpuMedianMs=%.3f cpuP95Ms=%.3f "
                 + "cpuMaxMs=%.3f rowsStyledMax=%d captures=%d clickPassMs=%.3f", label,
                 (try? outline().outlineView.numberOfRows) ?? -1, cpu.count, median * 1000, p95 * 1000,
                 worst * 1000, frames.rowsStyled.max() ?? 0, frames.captures, frames.clickCPU * 1000))
    return (p95, worst)
  }

  /// Closing and opening the 200-tab folder: no frame reads the outline's rows again (the blocks are captured when
  /// the transition starts and when it settles, not per frame), and a frame styles no more rows than have views.
  func testAFrameStylesOnlyTheRowsOnScreen() throws {
    let outline = try outline()
    let available = { outline.outlineView.rows(in: outline.outlineView.visibleRect).length + 40 }
    XCTAssertGreaterThanOrEqual(outline.outlineView.numberOfRows, 1000)

    let close = try clickAndRunFrames()
    _ = report("close", close)
    XCTAssertGreaterThan(close.cpu.count, 10, "the close ran on frames")
    XCTAssertEqual(close.captures, 1, "the close captured its rows once, when it started")
    XCTAssertLessThanOrEqual(close.rowsStyled.max() ?? 0, available(), "a frame styled only rows with views")
    XCTAssertEqual(outline.row(for: folderTabs[0]), -1, "settled: the folder's rows left")

    let open = try clickAndRunFrames()
    _ = report("open", open)
    XCTAssertGreaterThan(open.cpu.count, 10, "the open ran on frames")
    XCTAssertEqual(open.captures, 1, "the open captured its rows once, when it started")
    XCTAssertLessThanOrEqual(open.rowsStyled.max() ?? 0, available(), "a frame styled only rows with views")
    XCTAssertGreaterThanOrEqual(outline.row(for: folderTabs[Self.folderSize - 1]), 0, "settled: the rows are back")
    XCTAssertEqual(outline.rowStyle(for: today[0]), .rest)
  }

  /// Per-frame main-thread CPU time of the close and the open stays under 2 ms (95th percentile), and no frame takes
  /// a whole 120 Hz refresh. Thread CPU time does not depend on load; a screen below 120 Hz (CI's virtual display) is
  /// not the machine this budget is for. Before #603 the frames read every row of the outline: in a Debug build,
  /// median 1.4 ms (close) and 1.7 ms (open), up to 3.2 ms; after, they style only the row views the outline has.
  func testEachFrameStaysUnderTwoMillisecondsOfMainThreadCPU() throws {
    try PacingEnvironment.skipIfScreenBelow120Hz(fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
    let close = report("close", try clickAndRunFrames())
    let open = report("open", try clickAndRunFrames())
    XCTAssertLessThan(close.p95, 0.002, "close frames went over 2 ms of main-thread CPU")
    XCTAssertLessThan(open.p95, 0.002, "open frames went over 2 ms of main-thread CPU")
    XCTAssertLessThan(max(close.max, open.max), FrameStats().designBudget, "a frame took a whole 120 Hz refresh")
  }

  private func threadCPU() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
  }
}
