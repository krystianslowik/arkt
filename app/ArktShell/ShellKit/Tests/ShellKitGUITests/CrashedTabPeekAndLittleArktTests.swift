import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The crashed tab view over a Peek's page and a Little Arkt window's page (#683, follow-up to #578): the same view,
/// on the Peek card only or in that window only; Reload recovers the page; Close Tab closes the Peek or the window.
/// With a Peek open, Return and Esc are the Peek's: a crashed source under it never takes Return or the focus.
/// Motion is stepped by hand (no display link) and the Peek opens through `open(_:from:)`, so nothing waits on time.
@MainActor
final class CrashedPeekTests: XCTestCase {
  private static let mail = URL(string: "https://mail.example.com/inbox")!
  private static let atlas = URL(string: "https://atlas.example/lisbon")!

  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var pinned: NodeID!
  private var today: NodeID!
  private var spoken: [String] = []
  /// "Peek closed" toasts the Peek scheduled; a test runs them by hand.
  private var scheduledToasts: [@MainActor @Sendable () -> Void] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    pinned = try sidebar.addTab(url: Self.mail, title: "Mail", in: .pinned(space))
    today = try sidebar.addTab(url: URL(string: "https://notes.example/t0")!, title: "T0", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.peek.reduceMotion = { true }
    controller.peek.animator.drivesDisplayLink = false
    controller.peek.linkSettings = { PeekLinkSettings() }
    controller.peek.announce = { _, _ in }
    scheduledToasts = []
    controller.peek.scheduleClosedToast = { [unowned self] _, show in scheduledToasts.append(show) }
    controller.crashedTabs.reduceMotion = { true }
    controller.crashedTabs.announce = { [unowned self] text, _ in spoken.append(text) }
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    controller.close()
    controller = nil
    engine = nil
  }

  private var window: NSWindow { controller.window! }
  private var sourceCard: ContentCardView { controller.rootView.card }
  private func peekCard() throws -> PeekCardView { try XCTUnwrap(controller.peek.overlay).card }
  private func peekView() throws -> CrashedTabView? { controller.crashedTabs.view(on: try peekCard()) }

  /// Opens a Peek over the pinned tab and lets its motion settle. Returns (source, peek) tabs.
  private func openPeek() throws -> (source: TabID, peek: TabID) {
    controller.activate(node: pinned)
    let source = try XCTUnwrap(controller.currentTab)
    controller.peek.open(Self.atlas, from: source)
    controller.peek.animator.settleNow()
    let session = try XCTUnwrap(controller.peek.session)
    XCTAssertEqual(session.phase, .open)
    return (source, session.tab)
  }

  private func focusPeekPage(_ tab: TabID) throws {
    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(window.makeFirstResponder(page))
  }

  private static func key(_ code: UInt16, in window: NSWindow) throws -> NSEvent {
    let characters = code == 53 ? "\u{1b}" : "\r"
    return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  // MARK: Shown on the Peek card only

  func testAPeekPageCrashCoversThePeekCardOnly() throws {
    let (source, peek) = try openPeek()
    XCTAssertNil(try peekView())

    engine.crash(peek, status: .crashed)

    let view = try XCTUnwrap(try peekView(), "the Peek's card shows the view")
    XCTAssertEqual(view.tab, peek)
    XCTAssertTrue(view.superview === (try peekCard()).surface, "over the Peek's page, inside its rounded surface")
    XCTAssertNil(controller.crashedTabs.view(on: sourceCard), "the source card is unaffected")
    XCTAssertNil(engine.snapshot(of: source)?.crash)
    window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.frame, (try peekCard()).surface.bounds)
    XCTAssertTrue(view.isDefault, "the Peek answers the keyboard")
    XCTAssertEqual(spoken, ["This page quit unexpectedly. " +
                            "Something went wrong while showing atlas.example. Your other tabs are not affected."])
  }

  func testReloadRecoversThePeekPage() throws {
    let (_, peek) = try openPeek()
    try focusPeekPage(peek)
    engine.crash(peek, status: .crashed)
    let view = try XCTUnwrap(try peekView())

    view.reloadButton.performClick(nil)

    XCTAssertNil(engine.snapshot(of: peek)?.crash)
    XCTAssertNil(try peekView())
    XCTAssertNil(view.superview)
    XCTAssertTrue(controller.peek.isOpen, "the Peek stays")
    XCTAssertTrue(window.firstResponder === engine.contentView(for: peek), "the page gets the focus back")
  }

  func testCloseTabClosesThePeekAndKeepsTheSource() throws {
    let (source, peek) = try openPeek()
    engine.crash(peek, status: .crashed)

    try XCTUnwrap(try peekView()).closeButton.performClick(nil)
    controller.peek.animator.settleNow()

    XCTAssertFalse(controller.peek.isOpen)
    XCTAssertNil(engine.snapshot(of: peek), "the Peek's page is gone")
    XCTAssertNotNil(engine.snapshot(of: source), "the source tab stays")
    XCTAssertEqual(controller.currentTab, source)
    XCTAssertNil(controller.crashedTabs.view(on: sourceCard))

    XCTAssertEqual(scheduledToasts.count, 1, "the close schedules the Peek closed toast")
    for show in scheduledToasts { show() }
    XCTAssertEqual(controller.toasts.current?.spokenText, "Peek closed. Press Command-Z to reopen.")

    XCTAssertTrue(controller.reopenClosed())
    controller.peek.animator.settleNow()
    XCTAssertTrue(controller.peek.isOpen, "Reopen brings the Peek back")
    XCTAssertEqual(controller.peek.session?.source, source, "over its source")
    XCTAssertNil(controller.toasts.current)
  }

  /// The page crashes while the Peek closes, then Reopen turns the close around: the view comes up on the Peek.
  func testACrashDuringTheCloseShowsTheViewWhenReopenTurnsItAround() throws {
    let (_, peek) = try openPeek()
    controller.peek.close(.control)
    XCTAssertTrue(controller.peek.isClosing)
    engine.crash(peek, status: .crashed)
    XCTAssertNil(try peekView(), "a closing Peek gets no view")

    XCTAssertTrue(controller.reopenClosed())

    XCTAssertEqual(controller.peek.session?.tab, peek, "the same Peek, turned around")
    XCTAssertEqual(try peekView()?.tab, peek, "the crashed page is covered, not blank")
    controller.peek.animator.settleNow()
    XCTAssertEqual(controller.peek.session?.phase, .open)
  }

  /// The page recovers while the Peek closes, then Reopen turns the close around: the old view goes.
  func testARecoveryDuringTheCloseTakesTheViewDownWhenReopenTurnsItAround() throws {
    let (_, peek) = try openPeek()
    engine.crash(peek, status: .crashed)
    XCTAssertNotNil(try peekView())
    controller.peek.close(.control)
    engine.reload(peek)
    XCTAssertNil(engine.snapshot(of: peek)?.crash)

    XCTAssertTrue(controller.reopenClosed())

    XCTAssertEqual(controller.peek.session?.tab, peek)
    XCTAssertNil(try peekView(), "no stale view over the live page")
  }

  func testAHiddenPeekThatCrashedComesBackWithTheViewAndNoMotion() throws {
    let (source, peek) = try openPeek()
    controller.activate(node: today)
    XCTAssertFalse(controller.peek.isOpen, "hidden with its source")
    engine.crash(peek, status: .killed)
    XCTAssertTrue(spoken.isEmpty, "nothing on screen, nothing said")

    controller.activate(node: pinned)
    controller.peek.animator.settleNow()

    XCTAssertEqual(controller.peek.session?.tab, peek)
    XCTAssertEqual(controller.currentTab, source)
    let view = try XCTUnwrap(try peekView())
    XCTAssertNil(view.entrance, "the crash was not on screen: no entrance")
    XCTAssertEqual(spoken.count, 1)
  }

  // MARK: Keys beside the Peek

  func testReturnReloadsThePeekPageWhenTheFocusIsOnIt() throws {
    let (_, peek) = try openPeek()
    try focusPeekPage(peek)
    engine.crash(peek, status: .crashed)

    XCTAssertTrue(window.performKeyEquivalent(with: try Self.key(36, in: window)))

    XCTAssertNil(engine.snapshot(of: peek)?.crash)
    XCTAssertNil(try peekView())
  }

  func testReturnIsNotReloadWhenTheFocusIsInATextField() throws {
    let (_, peek) = try openPeek()
    let field = NSTextField(string: "Typing")
    field.frame = NSRect(x: 10, y: 10, width: 120, height: 22)
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = window.firstResponder
    engine.crash(peek, status: .crashed)

    XCTAssertTrue(window.firstResponder === editor, "the crash does not take the focus")
    XCTAssertFalse(window.performKeyEquivalent(with: try Self.key(36, in: window)))
    XCTAssertNotNil(engine.snapshot(of: peek)?.crash, "Return was not Reload")
    field.removeFromSuperview()
  }

  /// Both pages crashed: Return reloads the Peek's page only; the source under the Peek keeps its view and never
  /// takes Return or the focus.
  func testWithBothCrashedReturnReloadsThePeekOnly() throws {
    let (source, peek) = try openPeek()
    try focusPeekPage(peek)
    engine.crash(source, status: .crashed)
    let sourceView = try XCTUnwrap(controller.crashedTabs.view(on: sourceCard), "the source shows its view under it")
    XCTAssertTrue(window.firstResponder === engine.contentView(for: peek), "the source never takes the focus")
    engine.crash(peek, status: .crashed)
    XCTAssertFalse(window.firstResponder === sourceView.reloadButton)

    XCTAssertTrue(window.performKeyEquivalent(with: try Self.key(36, in: window)))

    XCTAssertNil(engine.snapshot(of: peek)?.crash, "the Peek reloaded")
    XCTAssertNotNil(engine.snapshot(of: source)?.crash, "the source did not")
    XCTAssertTrue(controller.crashedTabs.view(on: sourceCard) === sourceView)

    XCTAssertFalse(window.performKeyEquivalent(with: try Self.key(36, in: window)), "nothing else takes Return")
    XCTAssertNotNil(engine.snapshot(of: source)?.crash)
  }

  /// The window's focus on nothing in particular, which would let a view take Return: the crashed source under the
  /// Peek still does not, and the crash does not move the focus to its Reload.
  func testACrashedSourceUnderAPeekNeverTakesReturnWithTheFocusNowhere() throws {
    let (source, _) = try openPeek()
    XCTAssertTrue(window.makeFirstResponder(nil))
    engine.crash(source, status: .crashed)
    let sourceView = try XCTUnwrap(controller.crashedTabs.view(on: sourceCard))
    XCTAssertFalse(window.firstResponder === sourceView.reloadButton)

    XCTAssertFalse(window.performKeyEquivalent(with: try Self.key(36, in: window)))

    XCTAssertNotNil(engine.snapshot(of: source)?.crash, "Return was not Reload")
  }

  /// Esc on a crashed Peek closes the Peek, as it does today; the crashed source's view stays.
  func testEscClosesACrashedPeek() throws {
    let (source, peek) = try openPeek()
    try focusPeekPage(peek)
    engine.crash(source, status: .crashed)
    engine.crash(peek, status: .crashed)
    XCTAssertNotNil(try peekView(), "the Peek shows its view when Esc comes")

    window.sendEvent(try Self.key(53, in: window))
    controller.peek.animator.settleNow()

    XCTAssertFalse(controller.peek.isOpen, "Esc closed the Peek")
    XCTAssertNotNil(engine.snapshot(of: source)?.crash, "Esc did not reload the source")
    XCTAssertNotNil(controller.crashedTabs.view(on: sourceCard), "the source keeps its view")
  }

  // MARK: Motion

  func testThePeekEntranceScalesAndFadesAndReduceMotionOnlyFades() throws {
    let (_, peek) = try openPeek()
    controller.crashedTabs.reduceMotion = { false }
    engine.crash(peek, status: .crashed)
    let full = try XCTUnwrap(try peekView()?.entrance)
    XCTAssertEqual(full.scale, 0.97)
    XCTAssertNotNil(full.spring)

    engine.reload(peek)
    controller.crashedTabs.reduceMotion = { true }
    engine.crash(peek, status: .crashed)
    let reduced = try XCTUnwrap(try peekView()?.entrance)
    XCTAssertEqual(reduced.scale, 1)
    XCTAssertNil(reduced.spring)
    XCTAssertNil(try peekView()?.content.layer?.animation(forKey: "crashedTransform"))
  }
}

/// The crashed tab view in a Little Arkt window (#683): over that window's page only, Reload recovers it, Close Tab
/// closes the window (as Cmd-W does there), Return reloads when the focus is on the page.
@MainActor
final class CrashedLittleArktTests: XCTestCase {
  private var set: ShellWindowSet!
  private var engine: InMemoryEngine!
  private var spoken: [String] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let engine = InMemoryEngine()
    self.engine = engine
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { true }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    spoken = []
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    for controller in set.controllers { controller.close() }
    for little in set.littleArkts { little.window.close() }
    set.closeAllForTesting()
    set = nil
    engine = nil
  }

  private func openPopup() throws -> (LittleArktWindowController, EngineWindowID, TabID) {
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: URL(string: "https://signin.example/start")!, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    little.finishMotion()
    little.drivesDisplayLink = false
    little.crashedTabs.reduceMotion = { true }
    little.crashedTabs.announce = { [unowned self] text, _ in spoken.append(text) }
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    return (little, id, tab)
  }

  private static func returnKey(in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "\r",
                                   charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  }

  func testALittleArktPageCrashShowsTheViewInThatWindowOnly() throws {
    let main = set.openWindow()
    let (little, _, tab) = try openPopup()

    engine.crash(tab, status: .crashed)

    let view = try XCTUnwrap(little.crashedTabs.view(on: little.card))
    XCTAssertEqual(view.tab, tab)
    XCTAssertTrue(view.superview === little.card.clipView)
    little.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.frame, little.card.contentView?.frame)
    XCTAssertTrue(view.isDefault)
    XCTAssertNil(main.crashedTabs.view(on: main.rootView.card), "the main window is unaffected")
    XCTAssertEqual(spoken, ["This page quit unexpectedly. " +
                            "Something went wrong while showing signin.example. Your other tabs are not affected."])
  }

  func testReloadRecoversThePageAndGivesItTheFocus() throws {
    _ = set.openWindow()
    let (little, _, tab) = try openPopup()
    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(little.window.makeFirstResponder(page))
    engine.crash(tab, status: .crashed)
    let view = try XCTUnwrap(little.crashedTabs.view(on: little.card))

    view.reloadButton.performClick(nil)

    XCTAssertNil(engine.snapshot(of: tab)?.crash)
    XCTAssertNil(little.crashedTabs.view(on: little.card))
    XCTAssertNil(view.superview)
    XCTAssertTrue(little.window.firstResponder === page)
  }

  func testReturnReloadsWhenTheFocusIsOnThePage() throws {
    _ = set.openWindow()
    let (little, _, tab) = try openPopup()
    XCTAssertTrue(little.window.makeFirstResponder(engine.contentView(for: tab)))
    engine.crash(tab, status: .crashed)

    XCTAssertTrue(little.window.performKeyEquivalent(with: try Self.returnKey(in: little.window)))

    XCTAssertNil(engine.snapshot(of: tab)?.crash)
    XCTAssertNil(little.crashedTabs.view(on: little.card))
  }

  func testCloseTabClosesTheLittleArktWindow() throws {
    _ = set.openWindow()
    let (little, id, tab) = try openPopup()
    engine.crash(tab, status: .crashed)

    try XCTUnwrap(little.crashedTabs.view(on: little.card)).closeButton.performClick(nil)
    little.finishMotion()

    XCTAssertFalse(engine.windowIDs.contains(id), "the window closed, as Cmd-W does there")
    XCTAssertNil(engine.snapshot(of: tab))
  }

  /// Open in fails after the page left the card, and the page crashed meanwhile: the page comes back covered.
  func testAPageThatCrashedDuringAFailedOpenInComesBackWithTheView() throws {
    _ = set.openWindow()
    let (little, _, tab) = try openPopup()
    little.flightDestination = { nil }                      // the fade-out path, not the flight
    little.onOpenIn = { [engine] moving, _, _ in
      engine?.crash(moving, status: .crashed)             // the page is off the card now
      return false
    }

    little.openIn()
    little.finishMotion()

    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(little.card.contentView === page, "the page came back")
    XCTAssertEqual(little.crashedTabs.view(on: little.card)?.tab, tab, "covered, not blank")
  }

  func testTheEntranceScalesAndFadesAndReduceMotionOnlyFades() throws {
    _ = set.openWindow()
    let (little, _, tab) = try openPopup()
    little.crashedTabs.reduceMotion = { false }
    engine.crash(tab, status: .crashed)
    let full = try XCTUnwrap(little.crashedTabs.view(on: little.card)?.entrance)
    XCTAssertEqual(full.scale, 0.97)
    XCTAssertNotNil(full.spring)

    engine.reload(tab)
    little.crashedTabs.reduceMotion = { true }
    engine.crash(tab, status: .crashed)
    let reduced = try XCTUnwrap(little.crashedTabs.view(on: little.card)?.entrance)
    XCTAssertEqual(reduced.scale, 1)
    XCTAssertNil(reduced.spring)
  }
}
