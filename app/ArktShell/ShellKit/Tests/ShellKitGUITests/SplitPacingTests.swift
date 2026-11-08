import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import FakeEngineKit
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// Frame-time gate for the split divider drag (#59): the shell's divider is driven once per display frame, like a real
/// drag, in a real shell window with `InMemoryEngine`, so the panes are plain views and the test measures the shell's
/// own frame work. NOT-MEASURABLE below 120 Hz or under load (`PacingEnvironment`); the hitch count is asserted only
/// with `ARKT_PACING_GATE=1` or when this class runs alone (`PacingEnvironment.checkFrameGate`). The commit count and
/// the divider's movement are checked after every completed drag.
@MainActor
final class SplitPacingTests: XCTestCase {
  func testSplitDividerTwoPanes() async throws {
    try await measure(panes: 2, orientation: .horizontal, label: "split-divider-2")
  }

  func testSplitDividerFourPanes() async throws {
    try await measure(panes: 4, orientation: .horizontal, label: "split-divider-4")
  }

  func testSplitDividerFourStacked() async throws {
    try await measure(panes: 4, orientation: .vertical, label: "split-divider-4-stacked")
  }

  func testDividerDragCommitsOnce() throws {
    _ = NSApplication.shared
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let splitID = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let pane = try sidebar.addTab(url: URL(string: "https://example.com/one")!, title: "One", in: .split(splitID))
    _ = try sidebar.addTab(url: URL(string: "https://example.com/two")!, title: "Two", in: .split(splitID))
    let source = ModelSidebarSource(sidebar: sidebar)
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    defer { controller.close() }
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.activate(node: pane)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let split = controller.rootView.split
    let divider = try XCTUnwrap(split.dividers.first)
    XCTAssertFalse(split.isReflowing, "no reflow is running when the drag begins")
    let startFactors = split.liveFactors
    var changes = 0
    source.onDidChange = { _ in changes += 1 }
    divider.beginDrag()
    for frame in 1...60 {
      divider.drag(to: split.bounds.width * (0.5 + 0.1 * Double(frame) / 60))
    }
    XCTAssertEqual(changes, 0, "a drag does not write during frames")
    XCTAssertNotEqual(split.liveFactors, startFactors, "the drag moved the divider")
    divider.endDrag()
    XCTAssertEqual(changes, 1, "the completed drag commits exactly once")
  }

  func testSplitDividerWebKitInformational() async throws {
    let server = try await LoopbackServer.start(routes: [
      "/page": .init(mime: "text/html", body: Data("<!doctype html><title>Test page</title>".utf8))
    ])
    defer { server.stop() }
    let url = URL(string: "http://127.0.0.1:\(server.port)/page")!
    try await measure(panes: 2, orientation: .horizontal, label: "split-divider-webkit",
                      engine: FakeEngine(), page: url, timed: false)
  }

  private func measure(panes: Int, orientation: Orientation, label: String,
                       engine: any EngineClient = InMemoryEngine(), page: URL? = nil, timed: Bool = true) async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let splitID = try sidebar.addSplit(orientation: orientation,
      widthFactors: Array(repeating: 1.0 / Double(panes), count: panes), in: .today(space))
    let nodes = try (0..<panes).map { index in
      try sidebar.addTab(url: page ?? URL(string: "https://example.com/p\(index)")!, title: "Pane \(index)", in: .split(splitID))
    }
    let source = ModelSidebarSource(sidebar: sidebar)
    let controller = ShellWindowController(engine: engine, sidebar: source)
    defer { controller.close() }
    // Four panes leave a divider almost no room at the planned 1200 x 800 (four 240 pt minima): the side-by-side case
    // gets a wider window and the stacked case a taller one, so the sweep below has room.
    let width: CGFloat = orientation == .horizontal && panes == 4 ? 1400 : 1200
    let height: CGFloat = orientation == .vertical && panes == 4 ? 1100 : 800
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
    controller.showWindow(nil)
    controller.activate(node: nodes[0])
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    if timed { try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen) }
    if page != nil {
      for node in nodes {
        let id = try XCTUnwrap(controller.engineTab(of: node))
        try await EngineContract.waitUntil(timeout: .seconds(10)) {
          engine.snapshot(of: id).map { !$0.isLoading && $0.title == "Test page" } ?? false
        }
      }
    }
    let split = controller.rootView.split
    let stable = await StableFrames.wait(on: split, count: 10, threshold: FrameStats().hitchThreshold)
    print("split.pacing warmup stableFrames=\(stable) of 10")
    let index = (panes - 1) / 2
    let divider = try XCTUnwrap(split.dividers.dropFirst(index).first)
    let length = orientation == .horizontal ? split.bounds.width : split.bounds.height
    // The sweep covers the divider's allowed range: its two panes share `pair` points, and `SplitLayout.factors` keeps
    // each at `minimumPaneLength` or more. The amplitude stays 1 pt inside that clamp, so every frame changes the
    // factors. A sweep of a few points measures nothing useful: below the floor the case is NOT-MEASURABLE.
    let pair = 2 * (length - split.gap * CGFloat(panes - 1)) / CGFloat(panes)
    let center = split.dividerPosition(index)
    let amplitude = pair / 2 - SplitLayout.minimumPaneLength - 1
    let minimumAmplitude: CGFloat = 8
    if amplitude < minimumAmplitude {
      throw XCTSkip(String(format: "NOT-MEASURABLE (%@: split length %.0f pt leaves a sweep of +/-%.1f pt, under %.0f pt)",
                           label, length, amplitude, minimumAmplitude))
    }
    print(String(format: "split.pacing sweep label=%@ length=%.0f amplitude=%.1f", label, length, amplitude))
    // Precondition guard: since #665 a drag ends a running reflow into the same `lastPacing` (that takeover is covered
    // by `SplitPaneCloseTests`). Nothing may be reflowing here, so the stats read below are the drag's own.
    XCTAssertFalse(split.isReflowing, "\(label): no reflow is running when the drag begins")
    let startFactors = split.liveFactors
    var frame = 0
    var changes = 0
    source.onDidChange = { _ in changes += 1 }
    let finished = expectation(description: "divider drag finished")
    divider.beginDrag()
    XCTAssertEqual(split.pacer.label, "split-divider", "\(label): the drag's own pacing session runs")
    _ = FrameScript(view: split, frames: 60, step: { _ in
      frame += 1
      // One and a quarter periods over 60 frames: both ends of the range, ending at the trailing one.
      let position = center + amplitude * sin(Double(frame) * .pi / 24)
      divider.drag(to: position)
    }, done: { divider.endDrag(); finished.fulfill() })
    await fulfillment(of: [finished], timeout: 3)
    XCTAssertEqual(split.pacer.label, "split-divider", "\(label): the stats come from the divider drag")
    XCTAssertNotEqual(split.liveFactors, startFactors, "\(label): the drag moved the divider")
    let stats = try XCTUnwrap(split.lastPacing)
    XCTAssertEqual(changes, 1, "the completed drag commits exactly once")
    let fps = controller.window?.screen?.maximumFramesPerSecond ?? 0
    PacingEnvironment.checkFrameGate("split", results: [(label, stats)], details: split.pacer.hitchDetails,
                                     gate: Self.self, in: self, fps: fps, informational: !timed)
  }
}
