import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Frame-time gate for the pane close reflow (#602, origin #388): a pane closes in a 4-pane and a 3-pane split
/// (`split-reflow`), and in a 2-pane split the page left grows into the single card (`card-reflow`). Measured on
/// the views' own pacers in a real shell window with `InMemoryEngine`, so the panes are plain views and the test
/// measures the shell's own frame work. NOT-MEASURABLE below 120 Hz or under load (`PacingEnvironment`); the hitch
/// count is asserted only with `ARKT_PACING_GATE=1` or when this class runs alone (`PacingEnvironment.checkFrameGate`).
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

    PacingEnvironment.checkFrameGate("split.reflow", results: results, details: details, gate: Self.self, in: self,
                                     fps: controller.window?.screen?.maximumFramesPerSecond ?? 0)
  }
}
