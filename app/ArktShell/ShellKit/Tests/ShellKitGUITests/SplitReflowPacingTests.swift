import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Frame-time gate for the pane close reflow (#602, origin #388): a pane closes in a 4-pane and a 3-pane split
/// (`split-reflow`), and in a 2-pane split the page left grows into the single card (`card-reflow`). Measured on
/// the views' own pacers in a real shell window with `InMemoryEngine`, so the panes are plain views and the test
/// measures the shell's own frame work. NOT-MEASURABLE below 120 Hz or under load (`PacingEnvironment`); the hitch
/// count is asserted only with `ARKT_PACING_GATE=1` or when this class runs alone (`PacingEnvironment.gateAsserts`).
@MainActor
final class SplitReflowPacingTests: XCTestCase {
  private var controller: ShellWindowController!
  private var root: ShellRootView { controller.rootView }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    controller.showWindow(nil)                 // the reflow springs run on the window's display link
    root.reduceMotion = { false }
    root.split.reduceMotion = { false }
    root.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws { controller.close() }

  private func page() -> NSView {
    let view = NSView(frame: .zero)
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.systemTeal.cgColor
    return view
  }

  private func show(_ panes: [NSView], animated: Bool) {
    root.split.show(panes: panes, axis: .sideBySide,
                    factors: Array(repeating: 1 / Double(panes.count), count: panes.count), animated: animated)
    root.layoutSubtreeIfNeeded()
  }

  /// Closes the last pane of an `count`-pane split and waits for the reflow to settle.
  private func closeLastPane(of count: Int) -> FrameStats? {
    let pages = (0..<count).map { _ in page() }
    root.showsSplit = true
    show(pages, animated: false)
    show(Array(pages.dropLast()), animated: true)
    waitUntil("the \(count)-pane reflow settles") { !root.split.isReflowing }
    return root.split.lastPacing
  }

  /// Closes one pane of a 2-pane split: the other page grows from its pane into the single card.
  private func growLastPaneIntoTheCard() -> FrameStats? {
    let (left, right) = (page(), page())
    root.showsSplit = true
    show([left, right], animated: false)
    let paneFrame = root.convert(root.split.paneCards[0].frame, from: root.split)
    root.split.show(panes: [], axis: .sideBySide, factors: [])
    root.showsSplit = false
    root.card.setContent(left)
    root.reflowCard(from: paneFrame)
    waitUntil("the card reflow settles") { !root.isCardReflowing }
    return root.lastCardPacing
  }

  func testReflowPacing() async throws {
    try PacingEnvironment.skipIfNotMeasurable(screen: controller.window?.screen)
    // The window just appeared: measure from a steady display, as the pager gate does.
    let warmUp = 10
    let stable = await StableFrames.wait(on: root, count: warmUp, threshold: FrameStats().hitchThreshold)
    print("split.reflow.pacing warmup stableFrames=\(stable) of \(warmUp)")
    var results: [(String, FrameStats)] = []
    var details: [HitchDetail] = []
    for count in [4, 3] {
      results.append(("split-reflow-\(count)", try XCTUnwrap(closeLastPane(of: count))))
      details += root.split.pacer.hitchDetails
    }
    results.append(("card-reflow-2", try XCTUnwrap(growLastPaneIntoTheCard())))
    details += root.cardPacer.hitchDetails

    // What held the main thread across each late frame: app work (cpu near wall) or waiting (off CPU).
    for d in details {
      print(String(format: "split.reflow.hitch label=%@ frame=%d ms=%.2f busyMs=%.2f cpuMs=%.2f offCpuMs=%.2f passes=%d",
                   d.label, d.frame, d.interval * 1000, (d.longest?.wall ?? 0) * 1000, (d.longest?.cpu ?? 0) * 1000,
                   (d.longest?.offCPU ?? 0) * 1000, d.passes))
    }
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let gated = PacingEnvironment.gateAsserts(for: Self.self)
    print("split.reflow.pacing gate=\(gated ? "asserts" : "reports")")
    let fps = NSScreen.main?.maximumFramesPerSecond ?? 0
    for (label, stats) in results {
      let hitches = stats.intervals.enumerated().filter { $0.element > stats.hitchThreshold }
        .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) }
      let summary = String(
        format: "split.reflow.pacing label=%@ screenMaxFPS=%d frames=%d over8.6=%d overBudgetPct=%.2f maxMs=%.2f "
          + "p99Ms=%.2f leadInMs=%.2f load1=%.2f cores=%d asserted=%@ hitchesMs=[%@]",
        label, fps, stats.frameCount, stats.hitchCount, stats.overBudgetRatio * 100, stats.maxInterval * 1000,
        stats.p99 * 1000, (stats.leadInInterval ?? 0) * 1000, load[0], cores, loaded || !gated ? "no" : "yes",
        hitches.joined(separator: ","))
      print(summary)
      let attachment = XCTAttachment(string: summary)
      attachment.name = "split.reflow.pacing.\(label)"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertGreaterThan(stats.frameCount, 10, "\(label): the display link ran (is the display awake?)")
      if loaded {
        print("split.reflow.pacing skipped assert: 1-minute load \(load[0]) >= \(cores) active cores")
      } else if !gated {
        print("split.reflow.pacing reported only: set ARKT_PACING_GATE=1 or run SplitReflowPacingTests alone")
      } else {
        XCTAssertEqual(stats.hitchCount, 0, "\(label): frames over 8.6 ms")
      }
    }
  }
}
