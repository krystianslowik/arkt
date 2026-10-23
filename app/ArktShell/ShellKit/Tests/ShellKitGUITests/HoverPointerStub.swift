import AppKit
import XCTest
@testable import ShellUI

/// Stands in for the pointer and the window server in hover resync tests: the pointer sits at `pointInWindow` of
/// one window, which is frontmost there unless `coveringWindowNumber` names another window. Counts window-server
/// queries. Independent of key-window state and of whether the test window is on screen.
@MainActor
final class HoverPointerStub {
  let window: NSWindow
  var pointInWindow: NSPoint
  var isVisible = true
  var coveringWindowNumber: Int?
  private(set) var windowServerQueries = 0

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

  /// Places the pointer at the center of `view`.
  func move(toCenterOf view: NSView) {
    pointInWindow = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
  }
}

extension XCTestCase {
  /// Lets the main queue run everything enqueued so far (a coalesced hover resync runs one turn later).
  @MainActor
  func drainMainQueue() {
    let drained = expectation(description: "main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }
}
