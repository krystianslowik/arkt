import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
@testable import FakeEngineKit
import SidebarModel
import XCTest
@testable import ShellUI

/// The crashed tab view in the shell window (#578): shown over the crashed tab's page only, on the card or the split
/// pane that shows it; it survives tab and Space switches, Reload or a new navigation takes it down, Close Tab closes
/// the tab (or its pane). InMemoryEngine stands in for the page process that dies (`crash(_:status:)`).
@MainActor
final class CrashedTabWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var source: ModelSidebarSource!
  private var spaces: [NodeID] = []
  private var first: NodeID!
  private var second: NodeID!
  private var elsewhere: NodeID!
  private var spoken: [String] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let home = sidebar.addSpace(title: "Home")
    spaces = [work, home]
    first = try sidebar.addTab(url: URL(string: "https://fieldguide.example/lichens")!, title: "A", in: .today(work))
    second = try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(work))
    elsewhere = try sidebar.addTab(url: URL(string: "https://example.com/c")!, title: "C", in: .today(home))
    makeController(sidebar)
  }

  private func makeController(_ sidebar: SidebarModel.Sidebar) {
    controller?.close()
    engine = InMemoryEngine()
    source = ModelSidebarSource(sidebar: sidebar, now: { .now })
    controller = ShellWindowController(engine: engine, sidebar: source)
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    spoken = []
    controller.crashedTabs.reduceMotion = { true }
    controller.crashedTabs.announce = { [unowned self] text, _ in spoken.append(text) }
  }

  override func tearDown() async throws {
    controller.close()
  }

  private var card: ContentCardView { controller.rootView.card }
  private func crashedView(on card: ContentCardView) -> CrashedTabView? { controller.crashedTabs.view(on: card) }

  // MARK: Shown for the crashed tab only

  func testACrashOfTheShownTabCoversItsPageWithReloadFocused() throws {
    controller.activate(node: first)
    controller.returnFocusToPage()
    let tab = try XCTUnwrap(controller.currentTab)
    XCTAssertNil(crashedView(on: card))

    engine.crash(tab, status: .crashed)

    let view = try XCTUnwrap(crashedView(on: card))
    XCTAssertEqual(view.tab, tab)
    XCTAssertTrue(view.superview === card.clipView)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.frame, card.contentView?.frame, "the page area, below the Toolbar")
    XCTAssertEqual(view.titleLabel.stringValue, "This page quit unexpectedly")
    XCTAssertEqual(view.bodyLabel.stringValue,
                   "Something went wrong while showing fieldguide.example. Your other tabs are not affected.")
    XCTAssertTrue(view.isDefault, "Return reloads")
    if view.reloadButton.canBecomeKeyView {                         // Full Keyboard Access on
      XCTAssertTrue(controller.window?.firstResponder === view.reloadButton, "Reload takes focus")
    }
    XCTAssertEqual(spoken, ["This page quit unexpectedly. " + view.bodyLabel.stringValue], "one VoiceOver alert")
    XCTAssertEqual(view.accessibilityIdentifier(), AXID.CrashedTab.root)
  }

  func testACrashDoesNotTakeTheFocusFromTextBeingTyped() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    let window = try XCTUnwrap(controller.window)
    let field = NSTextField(string: "Renaming")
    field.frame = NSRect(x: 10, y: 10, width: 120, height: 22)
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = window.firstResponder

    engine.crash(tab, status: .crashed)

    let view = try XCTUnwrap(crashedView(on: card))
    XCTAssertTrue(window.firstResponder === editor, "the field keeps editing")
    XCTAssertTrue(view.isDefault)
    XCTAssertFalse(window.performKeyEquivalent(with: try Self.returnKey(in: window)), "the field's Return is its own")
    XCTAssertNotNil(engine.snapshot(of: tab)?.crash)
    field.removeFromSuperview()
  }

  func testEveryTerminationStatusShowsTheView() throws {
    for status in [TabTerminationStatus.crashed, .killed, .outOfMemory, .launchFailed] {
      controller.activate(node: first)
      let tab = try XCTUnwrap(controller.currentTab)
      engine.crash(tab, status: status)
      XCTAssertNotNil(crashedView(on: card), "\(status)")
      engine.reload(tab)
      XCTAssertNil(crashedView(on: card), "\(status): recovered")
    }
  }

  func testTheViewSurvivesATabSwitchAndComesBackWithoutMotion() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)
    XCTAssertNotNil(crashedView(on: card)?.entrance, "the crash on screen plays the entrance")

    controller.activate(node: second)
    XCTAssertNil(crashedView(on: card), "the healthy tab shows its page")
    XCTAssertNotNil(engine.snapshot(of: tab)?.crash)

    controller.activate(node: first)
    let view = try XCTUnwrap(crashedView(on: card))
    XCTAssertEqual(view.tab, tab)
    XCTAssertNil(view.entrance, "a tab switch shows it at once")
    XCTAssertEqual(spoken.count, 2, "announced each time it appears")
  }

  func testTheViewSurvivesASpaceSwitch() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)

    controller.sidebarController.showSpace(spaces[1])
    controller.activate(node: elsewhere)
    XCTAssertNil(crashedView(on: card))

    controller.sidebarController.showSpace(spaces[0])
    controller.activate(node: first)
    XCTAssertEqual(crashedView(on: card)?.tab, tab)
  }

  func testABackgroundTabCrashShowsNothingUntilTheTabIsShown() throws {
    controller.activate(node: second)
    let background = try XCTUnwrap(controller.engineTab(of: second))
    controller.activate(node: first)
    let shown = try XCTUnwrap(controller.currentTab)

    engine.crash(background, status: .killed)

    XCTAssertNil(crashedView(on: card), "the shown page is fine")
    XCTAssertTrue(spoken.isEmpty, "nothing on screen, nothing said")
    XCTAssertTrue(controller.window?.firstResponder !== nil)
    XCTAssertNotEqual(shown, background)

    controller.activate(node: second)
    XCTAssertEqual(crashedView(on: card)?.tab, background)
  }

  // MARK: Reload, navigation, Close Tab

  func testReloadRestoresThePageAndGivesItTheFocus() throws {
    controller.activate(node: first)
    controller.returnFocusToPage()
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)
    let view = try XCTUnwrap(crashedView(on: card))

    view.reloadButton.performClick(nil)

    XCTAssertNil(engine.snapshot(of: tab)?.crash)
    XCTAssertNil(crashedView(on: card))
    XCTAssertNil(view.superview)
    XCTAssertTrue(controller.window?.firstResponder === engine.contentView(for: tab))
  }

  func testReturnReloadsWhenTheFocusIsOnThePage() throws {
    controller.activate(node: first)
    controller.returnFocusToPage()
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)
    XCTAssertNotNil(crashedView(on: card))

    let window = try XCTUnwrap(controller.window)
    XCTAssertTrue(window.performKeyEquivalent(with: try Self.returnKey(in: window)))

    XCTAssertNil(engine.snapshot(of: tab)?.crash)
    XCTAssertNil(crashedView(on: card))
  }

  static func returnKey(in window: NSWindow?) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: window?.windowNumber ?? 0, context: nil, characters: "\r",
                                   charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  }

  /// The Favorites grid has the focus (a keyboard user walking the tiles): its Return opens a Favorite, it never
  /// reloads the crashed page, and the crash does not take the focus from it.
  func testTheFavoritesGridKeepsItsReturn() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    _ = try sidebar.addTab(url: URL(string: "https://example.com/f")!, title: "Fav", in: .favorites(profile: "default"))
    let page = try sidebar.addTab(url: URL(string: "https://example.com/p")!, title: "P", in: .today(space))
    makeController(sidebar)
    controller.activate(node: page)
    let tab = try XCTUnwrap(controller.currentTab)
    let window = try XCTUnwrap(controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    let grid = try XCTUnwrap(Self.descendant(of: FavoritesCollectionView.self, in: window.contentView))
    XCTAssertTrue(window.makeFirstResponder(grid))

    engine.crash(tab, status: .crashed)

    XCTAssertTrue(crashedView(on: card)?.isDefault == true)
    XCTAssertTrue(window.firstResponder === grid, "the grid keeps the focus")
    _ = window.performKeyEquivalent(with: try Self.returnKey(in: window))
    XCTAssertNotNil(engine.snapshot(of: tab)?.crash, "Return was not Reload")
    XCTAssertNotNil(crashedView(on: card))
  }

  /// A Peek open over the crashed tab answers the keyboard: Return is the Peek page's, not Reload, and the crash
  /// does not take the focus from the Peek.
  func testAPeekOverTheCrashedTabKeepsReturn() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: URL(string: "https://mail.example.com/inbox")!, title: "Mail",
                                    in: .pinned(space))
    makeController(sidebar)
    controller.peek.reduceMotion = { true }
    controller.peek.linkSettings = { PeekLinkSettings() }
    controller.peek.announce = { _, _ in }
    controller.activate(node: pinned)
    controller.returnFocusToPage()
    let tab = try XCTUnwrap(controller.currentTab)
    // A link to another site in a pinned tab opens a Peek (BH-144); it opens after the call returns.
    XCTAssertEqual(engine.simulateLinkActivation(in: tab, url: URL(string: "https://atlas.example/lisbon")!,
                                                 modifiers: [], disposition: .currentTab), .cancel)
    waitUntil("the Peek opens") { controller.peek.isOpen }
    let responder = controller.window?.firstResponder

    engine.crash(tab, status: .crashed)

    let view = try XCTUnwrap(crashedView(on: card), "the source's card shows the view under the Peek")
    XCTAssertTrue(controller.window?.firstResponder === responder, "the Peek keeps the focus")
    XCTAssertFalse(controller.window?.firstResponder === view.reloadButton)
    let window = try XCTUnwrap(controller.window)
    _ = window.performKeyEquivalent(with: try Self.returnKey(in: window))
    XCTAssertNotNil(engine.snapshot(of: tab)?.crash, "Return was not Reload")
  }

  static func descendant<T: NSView>(of type: T.Type, in view: NSView?) -> T? {
    guard let view else { return nil }
    if let match = view as? T { return match }
    for child in view.subviews { if let match = descendant(of: type, in: child) { return match } }
    return nil
  }

  func testANewNavigationTakesTheViewDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)

    engine.navigate(tab, to: URL(string: "https://example.com/elsewhere")!)

    XCTAssertNil(crashedView(on: card))
  }

  func testCloseTabClosesTheCrashedTab() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.crash(tab, status: .crashed)

    try XCTUnwrap(crashedView(on: card)).closeButton.performClick(nil)

    XCTAssertNil(engine.snapshot(of: tab), "the page is gone")
    XCTAssertNil(controller.engineTab(of: first))
    XCTAssertTrue(crashedView(on: card)?.tab != tab)
  }

  /// A close held behind a leave-site prompt, then the page crashes: the view shows (the tab is still listed), Close
  /// Tab asks nothing more of the engine, and the view goes with the tab when the close finishes. A cancelled close
  /// keeps the tab and its view.
  func testACrashDuringAHeldClose() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.holdClose(tab)
    controller.close(node: first)
    XCTAssertEqual(engine.snapshot(of: tab)?.isClosing, true, "held")

    engine.crash(tab, status: .crashed)
    let view = try XCTUnwrap(crashedView(on: card))
    view.closeButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: tab)?.isClosing, true, "still the one held close")

    XCTAssertTrue(engine.answerDialog(tab, accept: false))
    XCTAssertNotNil(crashedView(on: card), "the user stayed: the tab and its view stay")

    view.closeButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: tab)?.isClosing, true, "held again")
    XCTAssertTrue(engine.answerDialog(tab, accept: true))
    XCTAssertNil(engine.snapshot(of: tab))
    XCTAssertTrue(crashedView(on: card)?.tab != tab, "the view went with its tab")
  }

  // MARK: Split View

  func testACrashInASplitPaneCoversThatPaneOnlyAndCloseTabClosesThePane() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let left = try sidebar.addTab(url: URL(string: "https://example.com/l")!, title: "L", in: .split(split))
    let right = try sidebar.addTab(url: URL(string: "https://example.com/r")!, title: "R", in: .split(split))
    makeController(sidebar)
    controller.rootView.split.reduceMotion = { true }
    controller.activate(node: left)
    let cards = controller.rootView.split.paneCards
    XCTAssertEqual(cards.count, 2)
    let rightTab = try XCTUnwrap(controller.engineTab(of: right))

    engine.crash(rightTab, status: .crashed)

    XCTAssertNil(crashedView(on: cards[0]), "the other pane keeps its page")
    let view = try XCTUnwrap(crashedView(on: cards[1]))
    XCTAssertEqual(view.tab, rightTab)
    XCTAssertFalse(controller.window?.firstResponder === view.reloadButton, "focus stays with the focused pane")
    XCTAssertFalse(view.isDefault, "Return belongs to the focused pane")
    let window = try XCTUnwrap(controller.window)
    controller.returnFocusToPage()                                 // the focused (left) pane's page
    XCTAssertFalse(window.performKeyEquivalent(with: try Self.returnKey(in: window)))
    XCTAssertNotNil(engine.snapshot(of: rightTab)?.crash)

    view.closeButton.performClick(nil)

    XCTAssertNil(engine.snapshot(of: rightTab), "the pane's page closed")
    XCTAssertNotNil(controller.engineTab(of: left), "the other pane stays")
    waitUntil("no crashed view left") {
      controller.rootView.split.paneCards.allSatisfy { crashedView(on: $0) == nil } && crashedView(on: card) == nil
    }
  }

  // MARK: Motion

  func testTheEntranceScalesAndFadesAndReduceMotionOnlyFades() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    controller.crashedTabs.reduceMotion = { false }
    engine.crash(tab, status: .crashed)
    let full = try XCTUnwrap(crashedView(on: card)?.entrance)
    XCTAssertEqual(full.scale, 0.97)
    XCTAssertNotNil(full.spring)
    XCTAssertNotNil(crashedView(on: card)?.content.layer?.animation(forKey: "crashedTransform"))

    engine.reload(tab)
    controller.crashedTabs.reduceMotion = { true }
    engine.crash(tab, status: .crashed)
    let reduced = try XCTUnwrap(crashedView(on: card)?.entrance)
    XCTAssertEqual(reduced.scale, 1)
    XCTAssertNil(reduced.spring)
    XCTAssertEqual(reduced.fadeDuration, 0.15)
    XCTAssertNil(crashedView(on: card)?.content.layer?.animation(forKey: "crashedTransform"))
  }

  // MARK: Worst case

  func testAPageWithNoHostAndANarrowCardStillFit() throws {
    let view = CrashedTabView(tab: TabID(), host: nil)
    XCTAssertEqual(view.bodyLabel.stringValue,
                   "Something went wrong while showing this page. Your other tabs are not affected.")
    let long = CrashedTabView(tab: TabID(), host: String(repeating: "verylonghostname", count: 8) + ".example")
    long.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
    long.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(long.bodyLabel.frame.width, 300 - 32)
    XCTAssertTrue(long.bounds.contains(long.content.frame) || long.content.frame.width <= long.bounds.width + 1)
    XCTAssertGreaterThan(long.reloadButton.frame.width, 0)
    long.appearance = NSAppearance(named: .darkAqua)
    XCTAssertEqual(long.bodyLabel.textColor, ShellTokens.secondaryText.dark.nsColor(), "follows the appearance")
  }
}

/// The same view against FakeEngine's real WebKit page (#578): the web content process really exits, the window shows
/// the view over that page, and Reload brings the page back. Skipped when WebKit no longer publishes the process id.
@MainActor
final class FakeEngineCrashedTabWindowTests: XCTestCase {
  func testAKilledWebContentProcessShowsTheViewAndReloadRecovers() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    guard FakeEngine.canReadWebContentProcessIdentifier else {
      throw XCTSkip("this WebKit does not publish the web content process id")
    }
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let url = try XCTUnwrap(URL(string: "data:text/html,%3Ctitle%3ECrash%3C/title%3E%3Cp%3ECrash%3C/p%3E"))
    let node = try sidebar.addTab(url: url, title: "Crash", in: .today(space))
    let engine = FakeEngine()
    let controller = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    defer { controller.close() }
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.crashedTabs.reduceMotion = { true }
    controller.crashedTabs.announce = { _, _ in }
    controller.activate(node: node)
    let tab = try XCTUnwrap(controller.currentTab)
    let card = controller.rootView.card
    waitUntil("the page loaded", timeout: 10) {
      engine.snapshot(of: tab).map { !$0.isLoading && $0.title == "Crash" } ?? false
    }

    let pid = try XCTUnwrap(engine.webContentProcessIdentifier(of: tab), "the page has a web content process")
    XCTAssertEqual(kill(pid, SIGKILL), 0)
    waitUntil("the crashed view", timeout: 10) { controller.crashedTabs.view(on: card)?.tab == tab }
    XCTAssertTrue(controller.window?.isVisible == true, "the window stays up")

    try XCTUnwrap(controller.crashedTabs.view(on: card)).reloadButton.performClick(nil)
    waitUntil("the page recovered", timeout: 10) {
      engine.snapshot(of: tab)?.crash == nil && controller.crashedTabs.view(on: card) == nil
    }
  }
}
