import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

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
    var requested: [RecoveryPage] = []
    let model = RestorePagesModel(recovery: engine.crashedSession) { requested = $0; return true }
    controller.presentRestorePages(model)
    controller.presentRestorePages(model)
    let panels = controller.rootView.subviews.compactMap { $0 as? RestorePagesView }
    XCTAssertEqual(panels.count, 1)
    let panel = try XCTUnwrap(panels.first)
    XCTAssertEqual(panel.rowLabels.count, 3)
    XCTAssertEqual(panel.overflowLabel?.accessibilityLabel(), "and 2 more pages")
    XCTAssertEqual(panel.restoreButton.accessibilityLabel(), "Restore 5 pages")
    XCTAssertEqual(panel.restoreButton.keyEquivalent, "")
    XCTAssertEqual(panel.dismissButton.keyEquivalent, "")
    panel.reduceMotion = { true }
    panel.layer?.removeAnimation(forKey: "recovery-appear")
    panel.appear()
    XCTAssertNil(panel.layer?.animation(forKey: "recovery-appear"))
    var finish: (@MainActor () -> Void)?
    panel.animateClose = { animations, completion in animations(); finish = completion }
    panel.restorePressed()
    panel.dismissPressed()
    XCTAssertEqual(requested, pages)
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
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession) { _ in true })
    XCTAssertNil(controller.toasts.current)
    engine.crashedSession.simulateCrashedExit()
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession) { _ in true })
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
    controller.presentRestorePages(RestorePagesModel(recovery: engine.crashedSession) { _ in true })
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

  func testTransferredOfferSkipsAWindowWithAHeldClose() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample(),
                             hostLookup: { [engine] in engine.host(of: $0) })
    let owner = set.openWindow()
    owner.window?.isReleasedWhenClosed = false
    set.beginSessionRecovery(engine.crashedSession)
    let closing = set.openWindow()
    closing.window?.isReleasedWhenClosed = false
    let available = set.openWindow(opensFirstTab: false)
    available.window?.isReleasedWhenClosed = false
    defer { owner.close(); closing.close(); available.close() }
    XCTAssertNotNil(owner.rootView.subviews.first { $0 is RestorePagesView })
    let tab = try XCTUnwrap(closing.currentTab)
    engine.holdClose(tab)
    defer { _ = engine.answerDialog(tab, accept: false) }
    let closingWindow = try XCTUnwrap(closing.window)
    closingWindow.performClose(nil)
    XCTAssertTrue(closing.isWindowCloseRequested)
    NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: closingWindow)
    XCTAssertTrue(set.primary === closing)

    owner.close()

    XCTAssertNotNil(available.rootView.subviews.first { $0 is RestorePagesView })
    XCTAssertFalse(closing.rootView.subviews.contains { $0 is RestorePagesView })
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testPendingOfferReturnsWhenHeldCloseIsCancelled() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample(),
                             hostLookup: { [engine] in engine.host(of: $0) })
    let owner = set.openWindow()
    owner.window?.isReleasedWhenClosed = false
    set.beginSessionRecovery(engine.crashedSession)
    let closing = set.openWindow()
    closing.window?.isReleasedWhenClosed = false
    defer { owner.close(); closing.close() }
    let tab = try XCTUnwrap(closing.currentTab)
    engine.holdClose(tab)
    try XCTUnwrap(closing.window).performClose(nil)
    XCTAssertTrue(closing.isWindowCloseRequested)
    owner.close()
    XCTAssertFalse(closing.rootView.subviews.contains { $0 is RestorePagesView })
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
    _ = engine.answerDialog(tab, accept: false)
    XCTAssertFalse(closing.isWindowCloseRequested)
    XCTAssertNotNil(closing.rootView.subviews.first { $0 is RestorePagesView })
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

  func testPrivatePrimaryDoesNotReceiveTransferredOffer() throws {
    _ = NSApplication.shared
    for mode in [ShellWindowSet.WindowKind.blank, .incognito] {
      let engine = InMemoryEngine()
      engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
      engine.crashedSession.simulateCrashedExit()
      let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
      let owner = set.openWindow()
      owner.window?.isReleasedWhenClosed = false
      set.beginSessionRecovery(engine.crashedSession)
      let regular = set.openWindow()
      regular.window?.isReleasedWhenClosed = false
      let privateWindow = set.openWindow(opensFirstTab: false, kind: mode)
      privateWindow.window?.isReleasedWhenClosed = false
      defer { owner.close(); regular.close(); privateWindow.close() }
      let privateNSWindow = try XCTUnwrap(privateWindow.window)
      NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: privateNSWindow)
      XCTAssertTrue(set.primary === privateWindow)
      owner.close()
      XCTAssertEqual(regular.rootView.subviews.filter { $0 is RestorePagesView }.count, 1)
      XCTAssertFalse(privateWindow.rootView.subviews.contains { $0 is RestorePagesView })
      XCTAssertEqual(engine.crashedSession.dismissals, 0)
    }
  }

  func testOfferWaitsThroughPrivateCreationAndOwnerClose() throws {
    _ = NSApplication.shared
    for mode in [ShellWindowSet.WindowKind.blank, .incognito] {
      let engine = InMemoryEngine()
      engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
      engine.crashedSession.simulateCrashedExit()
      let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
      set.beginSessionRecovery(engine.crashedSession)
      var privateHadOfferDuringConfiguration = false
      set.configure = { window in
        privateHadOfferDuringConfiguration = window.rootView.subviews.contains { $0 is RestorePagesView }
      }
      let privateWindow = set.openWindow(opensFirstTab: false, kind: mode)
      privateWindow.window?.isReleasedWhenClosed = false
      XCTAssertFalse(privateHadOfferDuringConfiguration)
      XCTAssertFalse(privateWindow.rootView.subviews.contains { $0 is RestorePagesView })
      let owner = set.openWindow()
      owner.window?.isReleasedWhenClosed = false
      XCTAssertEqual(owner.rootView.subviews.filter { $0 is RestorePagesView }.count, 1)
      owner.close()
      XCTAssertEqual(engine.crashedSession.dismissals, 0)
      XCTAssertFalse(privateWindow.rootView.subviews.contains { $0 is RestorePagesView })
      let later = set.openWindow()
      later.window?.isReleasedWhenClosed = false
      defer { owner.close(); privateWindow.close(); later.close() }
      let panel = try XCTUnwrap(later.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      panel.dismissPressed()
      XCTAssertEqual(engine.crashedSession.dismissals, 1)
    }
  }

  func testChangingOwnerToPrivateTransfersOffer() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let owner = set.openWindow()
    owner.window?.isReleasedWhenClosed = false
    let other = set.openWindow()
    other.window?.isReleasedWhenClosed = false
    defer { owner.close(); other.close() }
    let ownerWindow = try XCTUnwrap(owner.window)
    NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: ownerWindow)
    set.beginSessionRecovery(engine.crashedSession)
    XCTAssertEqual(owner.rootView.subviews.filter { $0 is RestorePagesView }.count, 1)
    owner.makeIncognito()
    XCTAssertFalse(owner.rootView.subviews.contains { $0 is RestorePagesView })
    XCTAssertEqual(other.rootView.subviews.filter { $0 is RestorePagesView }.count, 1)
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testReturnAndEscapeRouteToPanelActions() throws {
    _ = NSApplication.shared
    for (key, code, restores) in [("\r", UInt16(36), true), ("\u{1b}", UInt16(53), false)] {
      let recovery = InMemorySessionRecovery()
      recovery.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
      recovery.simulateCrashedExit()
      let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
      let window = try XCTUnwrap(controller.window)
      window.isReleasedWhenClosed = false
      defer { controller.close() }
      var called = false
      controller.presentRestorePages(RestorePagesModel(recovery: recovery) { _ in called = true; return true })
      let panel = try XCTUnwrap(controller.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      XCTAssertTrue(window.makeFirstResponder(panel))
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key,
        charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
      XCTAssertFalse(window.performKeyEquivalent(with: event))
      window.sendEvent(event)
      XCTAssertEqual(recovery.dismissals, 1)
      XCTAssertEqual(called, restores)
    }
  }

  func testRestoreUsesHostTabAndOpensEveryLittleArkt() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = (0..<4).map { RecoveryPage(title: "Page \($0)",
      url: URL(string: "https://example.invalid/\($0)")!, kind: .littleArkt) } +
      [RecoveryPage(title: "Peek", url: URL(string: "https://example.invalid/peek")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { set.littleArkts.forEach { $0.window.close() }; host.close() }
    let source = try XCTUnwrap(host.currentTab)
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    XCTAssertEqual(set.littleArkts.count, 4)
    XCTAssertEqual(host.peek.session?.source, source)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testURLBarReturnSubmitsWhileOfferRemains() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    _ = host.urlBar.accessibilityPerformPress()
    let bar = host.commandBar
    bar.setQueryForTesting("https://example.invalid/submitted")
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: bar.panel.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    XCTAssertFalse(try XCTUnwrap(host.window).performKeyEquivalent(with: event))
    XCTAssertTrue(bar.panel.firstResponder === editor)
    bar.panel.sendEvent(event)
    XCTAssertEqual(host.currentTab.flatMap { engine.snapshot(of: $0)?.url }?.path, "/submitted")
    XCTAssertNotNil(host.rootView.subviews.first { $0 is RestorePagesView })
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testEscapeInFindClosesFindAndKeepsOffer() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Page", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow()
    let window = try XCTUnwrap(host.window)
    window.isReleasedWhenClosed = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let tab = try XCTUnwrap(host.currentTab)
    XCTAssertTrue(host.engineHost.perform(.find, disposition: .currentTab))
    XCTAssertTrue(host.findBar.isOpen(tab))
    XCTAssertTrue(window.firstResponder is NSTextView)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    XCTAssertFalse(window.performKeyEquivalent(with: event))
    window.sendEvent(event)
    XCTAssertFalse(host.findBar.isOpen(tab))
    XCTAssertNotNil(host.rootView.subviews.first { $0 is RestorePagesView })
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testRecoveryPreservesExistingPeekForAnySource() throws {
    _ = NSApplication.shared
    for sameSource in [true, false] {
      let engine = InMemoryEngine()
      let recovered = URL(string: "https://example.invalid/recovered")!
      let original = URL(string: "https://example.invalid/original")!
      engine.crashedSession.recoveryPages = [RecoveryPage(title: "Window", url: recovered, kind: .littleArkt),
                                               RecoveryPage(title: "Peek", url: recovered, kind: .peek)]
      engine.crashedSession.simulateCrashedExit()
      let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
      let host = set.openWindow()
      host.window?.isReleasedWhenClosed = false
      defer { set.littleArkts.forEach { $0.window.close() }; host.close() }
      set.beginSessionRecovery(engine.crashedSession)
      let source = try XCTUnwrap(host.currentTab)
      let other = sameSource ? source : engine.createTab(url: original)
      host.peek.open(original, from: other)
      let existing = try XCTUnwrap(host.peek.session)
      let page = try XCTUnwrap(engine.contentView(for: existing.tab))
      let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      panel.restorePressed()
      XCTAssertEqual(host.peek.session, existing)
      XCTAssertEqual(engine.snapshot(of: existing.tab)?.url, original)
      XCTAssertTrue(engine.contentView(for: existing.tab) === page)
      XCTAssertTrue(set.littleArkts.isEmpty)
      XCTAssertNotNil(panel.superview)
      XCTAssertEqual(engine.crashedSession.dismissals, 0)
    }
  }

  func testRecoveryDoesNotCloseHiddenPeekForSource() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let url = URL(string: "https://example.invalid/page")!
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let first = sidebar.addTab(url: url, title: "First", in: .today(space))
    let second = sidebar.addTab(url: url, title: "Second", in: .today(space))
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Peek", url: url, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: sidebar)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { host.close() }
    host.activate(node: first)
    let source = try XCTUnwrap(host.currentTab)
    host.peek.open(url, from: source)
    let existing = try XCTUnwrap(host.peek.session)
    host.peek.animator.settleNow()
    host.activate(node: second)
    let hidden = try XCTUnwrap(host.peek.hiddenPeeks[source])
    XCTAssertEqual(hidden.tab, existing.tab)
    // A hidden Peek can coexist with a different visible source; it must remain live.
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    XCTAssertEqual(host.peek.hiddenPeeks[source], hidden)
    XCTAssertNotNil(engine.snapshot(of: existing.tab))
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
    XCTAssertNotNil(panel.superview)
  }

  func testMissingPeekViewLeavesNoPartialRecovery() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let recovered = URL(string: "https://example.invalid/recovered")!
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Window", url: recovered, kind: .littleArkt),
                                             RecoveryPage(title: "Peek", url: recovered, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { set.littleArkts.forEach { $0.window.close() }; host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let before = Set(engine.tabIDs)
    engine.unavailableContentURLs = [recovered]
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    XCTAssertEqual(Set(engine.tabIDs), before)
    XCTAssertNil(host.peek.session)
    XCTAssertTrue(set.littleArkts.isEmpty)
    XCTAssertNotNil(panel.superview)
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
    engine.unavailableContentURLs = []
    panel.restorePressed()
    XCTAssertNotNil(host.peek.session)
    XCTAssertEqual(set.littleArkts.count, 1)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testMultiplePeeksAreNotAcknowledgedOrPartiallyOpened() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = (0..<2).map { RecoveryPage(title: "Page \($0)",
      url: URL(string: "https://example.invalid/\($0)")!, kind: .peek) }
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    XCTAssertNil(host.peek.session)
    XCTAssertNotNil(panel.superview)
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }

  func testMissingPeekSourceKeepsOffer() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    engine.crashedSession.recoveryPages = [RecoveryPage(title: "Peek", url: URL(string: "https://example.invalid/")!, kind: .peek)]
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample())
    let host = set.openWindow(opensFirstTab: false)
    host.window?.isReleasedWhenClosed = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    XCTAssertNotNil(panel.superview)
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
  }
}
