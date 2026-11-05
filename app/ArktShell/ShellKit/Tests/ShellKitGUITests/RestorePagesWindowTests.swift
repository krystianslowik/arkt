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
    let panels = controller.rootView.subviews.compactMap { $0 as? RestorePagesView }
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
  func testOfferSurvivesSplitSwitch() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: String(repeating: "Long title ", count: 50),
      url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    controller.window?.isReleasedWhenClosed = false
    defer { controller.close() }
    controller.rootView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
    controller.rootView.layoutSubtreeIfNeeded()
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession))
    let panel = try XCTUnwrap(controller.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    XCTAssertEqual(panel.frame.width, 340)
    XCTAssertEqual(panel.frame.maxX, controller.rootView.card.frame.maxX - 22, accuracy: 0.01)
    XCTAssertEqual(panel.rowLabels.first?.lineBreakMode, .byTruncatingTail)
    controller.rootView.showsSplit = true
    XCTAssertFalse(panel.isHiddenOrHasHiddenAncestor)
    controller.rootView.showsSplit = false
    XCTAssertFalse(panel.isHiddenOrHasHiddenAncestor)
  }

  func testDeferredLaunchTransfersUnansweredOfferThroughWindowLifecycle() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    set.beginSessionRecovery(engine.crashedSession)
    set.beginSessionRecovery(engine.crashedSession)
    let first = set.openWindow()
    first.window?.isReleasedWhenClosed = false
    XCTAssertEqual(first.rootView.subviews.filter { $0 is RestorePagesView }.count, 1)
    first.close()
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
    let second = set.openWindow()
    second.window?.isReleasedWhenClosed = false
    defer { second.close() }
    let panel = try XCTUnwrap(second.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.dismissPressed()
    set.beginSessionRecovery(engine.crashedSession)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testExistingWindowReceivesOfferAndTransfersToAnotherOpenWindow() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let first = set.openWindow()
    let second = set.openWindow()
    first.window?.isReleasedWhenClosed = false
    second.window?.isReleasedWhenClosed = false
    defer { first.close(); second.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let owner = try XCTUnwrap([first, second].first { $0.rootView.subviews.contains { $0 is RestorePagesView } })
    let other = owner === first ? second : first
    owner.close()
    XCTAssertNotNil(other.rootView.subviews.first { $0 is RestorePagesView })
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testLaunchNoticesAppearInSequence() {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let window = set.openWindow()
    window.window?.isReleasedWhenClosed = false
    defer { window.close() }
    let databaseNotice = Toast(text: "Database recovery", kind: .persistent)
    window.toasts.show(databaseNotice)
    engine.crashedSession.simulateCrashedExit()
    set.beginSessionRecovery(engine.crashedSession)
    XCTAssertEqual(window.toasts.current?.kind, .recovery)
    window.toasts.dismiss()
    XCTAssertEqual(window.toasts.current, databaseNotice)
  }

  func testReturnAndEscapeRouteToTheirActions() throws {
    _ = NSApplication.shared
    for (key, code, restores) in [("\r", UInt16(36), true), ("\u{1b}", UInt16(53), false)] {
      let engine = InMemoryEngine()
      engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
      engine.crashedSession.simulateCrashedExit()
      let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
      let window = try XCTUnwrap(controller.window)
      window.isReleasedWhenClosed = false
      defer { controller.close() }
      controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession))
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key,
        charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
      XCTAssertTrue(window.performKeyEquivalent(with: event))
      XCTAssertEqual(engine.crashedSession.dismissals, 1)
      XCTAssertEqual(!engine.crashedSession.restoredPages.isEmpty, restores)
    }
  }

}
