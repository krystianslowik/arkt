import AppKit
import XCTest
@testable import ShellUI

/// Stands in for the pointer and the window server in hover resync tests: the pointer sits at `pointInWindow` of
/// one window, which is frontmost there unless `coveringWindowNumber` names another window. Counts window-server
/// queries and holds the resync a host coalesces to the next main-queue turn until the test runs it. Independent of
/// key-window state and of whether the test window is on screen.
@MainActor
final class HoverPointerStub {
  let window: NSWindow
  var pointInWindow: NSPoint
  var isVisible = true
  var coveringWindowNumber: Int?
  private(set) var windowServerQueries = 0
  /// Resyncs the host scheduled for the next main-queue turn; `runNextTurn()` runs them instead of the main queue.
  private(set) var pendingTurns: [@MainActor () -> Void] = []

  init(window: NSWindow, pointInWindow: NSPoint = .zero) {
    self.window = window
    self.pointInWindow = pointInWindow
  }

  var lookup: HoverPointerLookup {
    HoverPointerLookup(
      isVisible: { [unowned self] _ in isVisible },
      mouseLocation: { [unowned self] in window.convertPoint(toScreen: pointInWindow) },
      windowNumber: { [unowned self] _ in
        windowServerQueries += 1
        return coveringWindowNumber ?? window.windowNumber
      })
  }

  /// Install as the host's `hoverResyncEnqueue`: the coalesced resync waits here, not on the main queue.
  var enqueue: @MainActor (@escaping @MainActor () -> Void) -> Void {
    { [weak self] work in self?.pendingTurns.append(work) }
  }

  /// Runs what the host scheduled for the next main-queue turn.
  func runNextTurn() {
    let turns = pendingTurns
    pendingTurns = []
    for turn in turns { turn() }
  }

  /// Runs main run-loop passes without waiting until the host has a resync pending, at most `maxPasses` of them:
  /// bounded by passes, never by wall time.
  func runLoopUntilResyncIsPending(maxPasses: Int = 200) -> Bool {
    for _ in 0..<maxPasses where pendingTurns.isEmpty {
      RunLoop.main.run(mode: .default, before: .distantPast)
    }
    return !pendingTurns.isEmpty
  }

  /// Places the pointer at the center of `view`.
  func move(toCenterOf view: NSView) {
    pointInWindow = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
  }
}
