import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

@MainActor
final class RestorePagesWindowTests: XCTestCase {
  func testLaunchWindowOffersAllPagesAndAnswersOnce() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let pages = (0..<5).map { index in
      RecoveryPage(title: "Page \(index)", url: URL(string: "https://example.invalid/\(index)")!, kind: .peek)
    }
    engine.crashedSession.recoveryPages = pages
    engine.crashedSession.simulateCrashedExit()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    controller.window?.isReleasedWhenClosed = false
    defer { controller.close() }
    let model = RestorePagesModel(recovery: engine.crashedSession)
    controller.presentRestorePages(model)
    controller.presentRestorePages(model)
    let panels = controller.rootView.card.subviews.compactMap { $0 as? RestorePagesView }
    XCTAssertEqual(panels.count, 1)
    let panel = try XCTUnwrap(panels.first)
    XCTAssertEqual(panel.rowLabels.count, 3)
    XCTAssertEqual(panel.overflowLabel?.accessibilityLabel(), "and 2 more pages")
    XCTAssertEqual(panel.restoreButton.accessibilityLabel(), "Restore 5 pages")
    XCTAssertEqual(panel.restoreButton.keyEquivalent, "\r")
    XCTAssertEqual(panel.dismissButton.keyEquivalent, "\u{1b}")
    panel.reduceMotion = { true }
    panel.layer?.removeAnimation(forKey: "recovery-appear")
    panel.appear()
    XCTAssertNil(panel.layer?.animation(forKey: "recovery-appear"))
    var finish: (@MainActor () -> Void)?
    panel.animateClose = { finish = $0 }
    panel.restorePressed()
    panel.dismissPressed()
    XCTAssertEqual(engine.crashedSession.restoredPages, [pages])
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
    XCTAssertNotNil(panel.superview)
    finish?()
    XCTAssertNil(panel.superview)
  }

  func testEmptyCrashShowsSixSecondStatusAndCleanExitShowsNothing() {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    controller.window?.isReleasedWhenClosed = false
    defer { controller.close() }
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession))
    XCTAssertNil(controller.toasts.current)
    engine.crashedSession.simulateCrashedExit()
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession))
    XCTAssertEqual(controller.toasts.current?.text, "Arkt quit unexpectedly. Your Spaces and tabs are back.")
    XCTAssertEqual(controller.toasts.current?.duration, .seconds(6))
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }
}
