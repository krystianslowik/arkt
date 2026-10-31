import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import FakeEngineKit
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// The shell's divider is driven once per display frame, like a real drag. Timing is meaningful only on a quiet
/// 120 Hz display; the commit count is checked after each completed drag.
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
    var changes = 0
    source.onDidChange = { _ in changes += 1 }
    divider.beginDrag()
    for frame in 1...60 {
      divider.drag(to: split.bounds.width * (0.5 + 0.1 * Double(frame) / 60))
    }
    XCTAssertEqual(changes, 0, "a drag does not write during frames")
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
                      engine: FakeEngine(), page: url, gated: false)
  }

  private func measure(panes: Int, orientation: Orientation, label: String,
                       engine: any EngineClient = InMemoryEngine(), page: URL? = nil, gated: Bool = true) async throws {
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
    let height: CGFloat = orientation == .vertical && panes == 4 ? 1100 : 800
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: height), display: false)
    controller.showWindow(nil)
    controller.activate(node: nodes[0])
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    if gated { try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen) }
    if page != nil {
      for node in nodes {
        let id = try XCTUnwrap(controller.engineTab(of: node))
        try await EngineContract.waitUntil(timeout: .seconds(10)) {
          engine.snapshot(of: id).map { !$0.isLoading && $0.title == "Test page" } ?? false
        }
      }
    }
    let split = controller.rootView.split
    if orientation == .vertical && panes == 4 && split.bounds.height < 990 {
      throw XCTSkip("NOT-MEASURABLE (four stacked panes require at least 990 pt)")
    }
    let stable = await StableFrames.wait(on: split, count: 10, threshold: FrameStats().hitchThreshold)
    print("split.pacing warmup stableFrames=\(stable) of 10")
    let divider = try XCTUnwrap(split.dividers.dropFirst((panes - 1) / 2).first)
    let length = orientation == .horizontal ? split.bounds.width : split.bounds.height
    let center = length / 2
    var frame = 0
    var changes = 0
    source.onDidChange = { _ in changes += 1 }
    let finished = expectation(description: "divider drag finished")
    divider.beginDrag()
    _ = FrameScript(view: split, frames: 60, step: { _ in
      frame += 1
      let position = center + 20 + 15 * sin(Double(frame) * .pi / 30)
      divider.drag(to: position)
    }, done: { divider.endDrag(); finished.fulfill() })
    await fulfillment(of: [finished], timeout: 3)
    let stats = try XCTUnwrap(split.lastPacing)
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let fps = controller.window?.screen?.maximumFramesPerSecond ?? 0
    let hitches = stats.intervals.enumerated().filter { $0.element > stats.hitchThreshold }
      .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) }
    let summary = String(format: "split.pacing label=%@ screenMaxFPS=%d frames=%d over8.6=%d overBudgetPct=%.2f maxMs=%.2f p99Ms=%.2f leadInMs=%.2f load1=%.2f cores=%d asserted=%@ hitchesMs=[%@]",
      label, fps, stats.frameCount, stats.hitchCount, stats.overBudgetRatio * 100, stats.maxInterval * 1000,
      stats.p99 * 1000, (stats.leadInInterval ?? 0) * 1000, load[0], cores, (loaded || !gated) ? "no" : "yes",
      hitches.joined(separator: ","))
    print(summary)
    let attachment = XCTAttachment(string: summary)
    attachment.name = "split.pacing.\(label)"
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
    XCTAssertGreaterThan(stats.frameCount, 10)
    XCTAssertEqual(changes, 1, "the completed drag commits exactly once")
    if gated && !loaded { XCTAssertEqual(stats.hitchCount, 0, "\(label): frames over 8.6 ms") }
  }
}
