import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Peek in a real shell window (#313, docs/design/peek.md): a link activation opens it over the source tab, every
/// close leaves the source as it was, Open as Tab and Add to Split View move the same engine tab into the sidebar,
/// Esc goes to the page first, and a split pane of 600 pt or more gets a Peek of its own.
@MainActor
final class PeekWindowTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let mail = URL(string: "https://mail.example.com/inbox")!
  private static let atlas = URL(string: "https://atlas.example/lisbon")!

  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var today: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var announcements: [String] = []

    init(_ sidebar: SidebarModel.Sidebar, width: CGFloat = 1200, reduceMotion: Bool = false) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { PeekWindowTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: width, height: 800), display: false)
      layout()
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: PeekWindowTests.now) }
      controller.peek.reduceMotion = { reduceMotion }
      controller.peek.linkSettings = { PeekLinkSettings() }
      controller.peek.announce = { [unowned self] text, _ in announcements.append(text) }
    }

    var peek: PeekController { controller.peek }
    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
    func layout() { controller.window?.contentView?.layoutSubtreeIfNeeded() }

    /// Clicks a link in `node`'s page and lets the Peek open (the window answers, then opens after the call).
    @discardableResult
    func click(_ url: URL, in node: UUID, modifiers: EngineLinkModifiers = [],
               disposition: EngineDisposition = .currentTab) throws -> EngineLinkDecision {
      let tab = try XCTUnwrap(self.tab(node))
      let decision = engine.simulateLinkActivation(in: tab, url: url, modifiers: modifiers, disposition: disposition)
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      return decision
    }

    func settle() { peek.animator.settleNow() }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: mail, title: "Mail", in: .pinned(space))
    let t0 = try sidebar.addTab(url: URL(string: "https://notes.example/t0")!, title: "T0", in: .today(space))
    let t1 = try sidebar.addTab(url: URL(string: "https://notes.example/t1")!, title: "T1", in: .today(space))
    return World(sidebar: sidebar, space: space, pinned: pinned, today: [t0, t1])
  }

  private func openPeek(_ harness: Harness, _ world: World) throws -> PeekSession {
    harness.controller.activate(node: world.pinned)
    XCTAssertEqual(try harness.click(Self.atlas, in: world.pinned), .cancel)
    return try XCTUnwrap(harness.peek.session)
  }

  // MARK: Opening

  /// BH-144: a link to another site in a pinned tab opens a Peek; the source tab does not navigate and no sidebar
  /// row is added for the Peek's tab (BH-152).
  func testACrossSiteLinkInAPinnedTabOpensAPeekWithoutARow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let rows = harness.source.children(of: .today(world.space))
    let session = try openPeek(harness, world)
    let sourceTab = try XCTUnwrap(harness.tab(world.pinned))

    XCTAssertEqual(session.source, sourceTab)
    XCTAssertEqual(harness.engine.snapshot(of: sourceTab)?.url, Self.mail, "the source stays where it was")
    XCTAssertEqual(harness.engine.snapshot(of: session.tab)?.url, Self.atlas)
    XCTAssertNil(harness.controller.nodeByTab[session.tab], "no row for the Peek")
    XCTAssertEqual(harness.source.children(of: .today(world.space)), rows)
    let overlay = try XCTUnwrap(harness.peek.overlay)
    XCTAssertTrue(overlay.card.page === harness.engine.contentView(for: session.tab))
    XCTAssertEqual(harness.controller.currentTab, sourceTab, "the source stays the current tab")
    XCTAssertEqual(harness.controller.urlBar.url, Self.atlas, "the URL bar shows the Peek (KB-013, KB-014)")
    harness.settle()
    XCTAssertEqual(harness.peek.session?.phase, .open)
    XCTAssertTrue(harness.announcements.contains { $0.hasPrefix("Peek opened") })
    harness.controller.close()
  }

  /// Layout per the design: insets 56 / 34 / 26 in the content card, controls outside on the right, the source
  /// card receded to 0.985.
  func testThePeekCardSitsAtTheDesignInsetsAndTheSourceRecedes() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    let content = harness.controller.rootView.card.frame
    XCTAssertEqual(overlay.card.frame, CGRect(x: content.minX + 56, y: content.minY + 34, width: content.width - 112,
                                              height: content.height - 60))
    XCTAssertEqual(overlay.controlsView.frame.minX, overlay.card.frame.maxX + 12)
    let transform = try XCTUnwrap(harness.controller.rootView.card.layer?.transform)
    XCTAssertEqual(transform.m11, 0.985, accuracy: 1e-6)
    XCTAssertEqual(overlay.closeButton.accessibilityLabel(), "Close Peek")
    XCTAssertEqual(overlay.card.accessibilitySubrole(), .dialog)
    harness.controller.close()
  }

  func testASameSiteLinkAndATodayLinkNavigate() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let same = URL(string: "https://docs.example.com/page")!
    XCTAssertEqual(try harness.click(same, in: world.pinned), .navigate)
    XCTAssertNil(harness.peek.session)
    harness.controller.activate(node: world.today[0])
    XCTAssertEqual(try harness.click(Self.atlas, in: world.today[0]), .navigate)
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  /// BH-145: Shift-click opens a Peek from a Today tab too.
  func testAShiftClickInATodayTabOpensAPeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    XCTAssertEqual(try harness.click(Self.atlas, in: world.today[0], modifiers: .shift, disposition: .newWindow),
                   .cancel)
    XCTAssertNotNil(harness.peek.session)
    harness.controller.close()
  }

  /// A second request for the same source while the Peek opens replaces the URL; the open is not restarted.
  func testASecondLinkWhileOpeningReplacesTheURLInTheSamePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    let other = URL(string: "https://maps.example/route")!
    harness.peek.open(other, from: session.source)
    XCTAssertEqual(harness.peek.session?.tab, session.tab)
    XCTAssertEqual(harness.engine.snapshot(of: session.tab)?.url, other)
    harness.controller.close()
  }

  // MARK: Closing (BH-149)

  func testTheCloseControlClosesThePeekAndKeepsTheSource() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    overlay.closeButton.performClick(nil)
    XCTAssertEqual(harness.peek.session?.phase, .closing)
    harness.settle()
    XCTAssertNil(harness.peek.session)
    XCTAssertNil(overlay.superview, "the overlay is gone")
    XCTAssertNil(harness.engine.snapshot(of: session.tab), "the Peek's tab closed")
    XCTAssertEqual(harness.engine.snapshot(of: session.source)?.url, Self.mail)
    XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(harness.controller.rootView.card.layer?.transform)))
    XCTAssertEqual(harness.controller.urlBar.url, Self.mail)
    XCTAssertTrue(harness.announcements.contains("Peek closed."))
    harness.controller.close()
  }

  func testAClickOnTheScrimClosesThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    let corner = CGPoint(x: overlay.scrim.frame.minX + 5, y: overlay.scrim.frame.minY + 5)
    XCTAssertTrue(overlay.hitTest(corner) === overlay.scrim, "the scrim takes clicks outside the card")
    overlay.scrim.onClick?()
    harness.settle()
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  /// KB-078: Cmd-W closes the Peek, not the source tab.
  func testCommandWClosesThePeekOnly() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()
    harness.controller.closeTab(nil)
    harness.settle()
    XCTAssertNil(harness.peek.session)
    XCTAssertNotNil(harness.engine.snapshot(of: session.source), "the pinned page stays open")
    harness.controller.close()
  }

  /// Esc goes to the page first (decided 2026-10-25): only an Esc the page passed on reaches the Peek, which closes.
  func testAnEscThePageDidNotUseClosesThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()
    XCTAssertTrue(harness.engine.simulateUnhandledKeyDown(try Self.key(53), in: session.tab))
    harness.settle()
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  func testOtherUnhandledKeysAndEscFromAnotherTabLeaveThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try Self.key(36), in: session.tab), "Return")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try Self.key(53), in: session.source))
    XCTAssertEqual(harness.peek.session?.phase, .open)
    harness.controller.close()
  }

  /// Every transition is interruptible: an Esc during the open closes from where the card is.
  func testAnEscDuringTheOpenRetargetsTheClose() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    XCTAssertEqual(harness.peek.session?.phase, .opening)
    XCTAssertTrue(harness.peek.handleEscape(in: session.tab))
    XCTAssertEqual(harness.peek.session?.phase, .closing)
    harness.settle()
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  func testTheAccessibilityCancelActionClosesThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    harness.settle()
    XCTAssertTrue(try XCTUnwrap(harness.peek.overlay).card.accessibilityPerformCancel())
    harness.settle()
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  /// Closing the source tab takes its Peek with it.
  func testClosingTheSourceTabClosesThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.engine.engineCloseTab(session.source, reason: .page)
    XCTAssertNil(harness.peek.session)
    XCTAssertNil(harness.engine.snapshot(of: session.tab))
    harness.controller.close()
  }

  /// Switching to another tab removes the Peek (it is not kept for a return yet).
  func testShowingAnotherTabRemovesThePeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.controller.activate(node: world.today[0])
    XCTAssertNil(harness.peek.session)
    XCTAssertNil(harness.engine.snapshot(of: session.tab))
    harness.controller.close()
  }

  // MARK: Drag (GS-022)

  func testADragPastTheThresholdDismissesAndAShortOneSnapsBack() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    harness.settle()
    let handle = try XCTUnwrap(harness.peek.overlay).dragHandle
    handle.onBegan?()
    handle.onChanged?(60)
    XCTAssertEqual(try XCTUnwrap(harness.peek.overlay).scene[.cardY], 60)
    handle.onEnded?(60, 100)
    XCTAssertEqual(harness.peek.session?.phase, .open)
    harness.settle()
    XCTAssertEqual(try XCTUnwrap(harness.peek.overlay).scene, .rest)

    handle.onBegan?()
    handle.onChanged?(40)
    handle.onEnded?(40, 1200)
    XCTAssertEqual(harness.peek.session?.phase, .closing, "a fast flick dismisses")
    harness.settle()
    XCTAssertNil(harness.peek.session)
    harness.controller.close()
  }

  // MARK: Open as Tab (BH-148, KB-076)

  func testOpenAsTabMakesTheSameEngineTabATodayRowAtTheTopSelected() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()
    let tabs = harness.engine.tabIDs
    let page = harness.engine.contentView(for: session.tab)

    harness.peek.openAsTab()
    XCTAssertEqual(harness.peek.session?.phase, .expanding)
    harness.settle()

    XCTAssertNil(harness.peek.session)
    XCTAssertEqual(harness.engine.tabIDs, tabs, "no tab was created or closed")
    let top = try XCTUnwrap(harness.source.children(of: .today(world.space)).first)
    XCTAssertEqual(harness.tab(top), session.tab)
    XCTAssertEqual(harness.controller.currentTab, session.tab, "the new row is selected")
    XCTAssertTrue(harness.controller.rootView.card.contentView === page, "the same page view, in the content card")
    XCTAssertEqual(harness.source.children(of: .pinned(world.space)), [world.pinned], "the source stays pinned")
    harness.controller.close()
  }

  func testCommandOOpensThePeekAsATab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                               windowNumber: harness.controller.window?.windowNumber ?? 0,
                                               context: nil, characters: "o", charactersIgnoringModifiers: "o",
                                               isARepeat: false, keyCode: 31))
    XCTAssertTrue(overlay.performKeyEquivalent(with: event))
    XCTAssertEqual(harness.peek.session?.phase, .expanding)
    harness.controller.close()
  }

  // MARK: Add to Split View (BH-117, BH-148)

  func testAddToSplitViewPutsThePeekRightOfTheSourceWithFocus() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try openPeek(harness, world)
    harness.settle()

    try XCTUnwrap(harness.peek.overlay).splitButton.performClick(nil)
    harness.settle()

    XCTAssertNil(harness.peek.session)
    guard case .split(let split)? = harness.source.parent(of: world.pinned) else {
      return XCTFail("the source is a pane now")
    }
    let panes = harness.source.children(of: .split(split))
    XCTAssertEqual(panes.count, 2)
    XCTAssertEqual(panes.first, world.pinned)
    XCTAssertEqual(harness.tab(panes[1]), session.tab, "the Peek's own tab is the right pane")
    XCTAssertEqual(harness.controller.currentTab, session.tab)
    XCTAssertFalse(harness.controller.rootView.split.isHidden)
    harness.controller.close()
  }

  func testAFullSplitDisablesAddToSplitView() throws {
    var world = try Self.makeWorld()
    let split = try world.sidebar.addSplit(orientation: .horizontal, widthFactors: [0.25, 0.25, 0.25, 0.25],
                                           in: .today(world.space))
    let panes = try (0..<4).map {
      try world.sidebar.addTab(url: URL(string: "https://notes.example/p\($0)")!, title: "P\($0)", in: .split(split))
    }
    let harness = Harness(world.sidebar, width: 2200)
    harness.controller.activate(node: panes[0])
    harness.layout()
    try harness.click(Self.atlas, in: panes[0], modifiers: .shift, disposition: .newWindow)
    let overlay = try XCTUnwrap(harness.peek.overlay)
    XCTAssertTrue(harness.peek.isSplitFull)
    XCTAssertFalse(overlay.splitButton.isEnabled)
    XCTAssertEqual(overlay.splitButton.toolTip, "Split View is full")
    harness.controller.close()
  }

  // MARK: Split View panes (decided 2026-10-25)

  private func splitWorld() throws -> (World, panes: [UUID]) {
    var world = try Self.makeWorld()
    let split = try world.sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(world.space))
    let panes = try (0..<2).map {
      try world.sidebar.addTab(url: URL(string: "https://notes.example/s\($0)")!, title: "S\($0)", in: .split(split))
    }
    return (world, panes)
  }

  func testAWidePaneGetsAPeekOverThatPaneOnlyAndAClickOnTheOtherPaneClosesIt() throws {
    let (world, panes) = try splitWorld()
    let harness = Harness(world.sidebar, width: 1720)
    harness.controller.activate(node: panes[0])
    harness.layout()
    try harness.click(Self.atlas, in: panes[0], modifiers: .shift, disposition: .newWindow)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    let root = harness.controller.rootView
    let paneFrame = root.convert(root.split.paneCards[0].frame, from: root.split)
    XCTAssertGreaterThanOrEqual(paneFrame.width, 600)
    XCTAssertEqual(overlay.scrim.frame, paneFrame, "the scrim covers the source pane only")
    XCTAssertEqual(overlay.card.frame.minX, paneFrame.minX + 24)
    XCTAssertEqual(overlay.card.frame.maxX, paneFrame.maxX - 52)
    let other = root.convert(root.split.paneCards[1].frame, from: root.split)
    XCTAssertNil(overlay.hitTest(CGPoint(x: other.midX, y: other.midY)), "the other pane stays live")
    XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(root.split.paneCards[1].layer?.transform)))

    let window = try XCTUnwrap(harness.controller.window)
    let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                                                 location: root.convert(CGPoint(x: other.midX, y: other.midY), to: nil),
                                                 modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: 1))
    NSApp.sendEvent(click)                    // local monitors run in NSApp.sendEvent
    XCTAssertEqual(harness.peek.session?.phase, .closing)
    harness.controller.close()
  }

  func testANarrowPaneGetsAPeekOverTheWholeContentArea() throws {
    let (world, panes) = try splitWorld()
    let harness = Harness(world.sidebar, width: 1280)
    harness.controller.activate(node: panes[0])
    harness.layout()
    try harness.click(Self.atlas, in: panes[0], modifiers: .shift, disposition: .newWindow)
    harness.settle()
    let overlay = try XCTUnwrap(harness.peek.overlay)
    let root = harness.controller.rootView
    XCTAssertLessThan(root.split.paneCards[0].frame.width, 600)
    XCTAssertEqual(overlay.scrim.frame, root.card.frame)
    XCTAssertEqual(try XCTUnwrap(root.split.layer?.transform).m11, 0.985, accuracy: 1e-6, "every pane recedes")
    harness.controller.close()
  }

  // MARK: Reduce Motion

  func testReduceMotionFadesWithoutTravelScaleOrRecede() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar, reduceMotion: true)
    _ = try openPeek(harness, world)
    let overlay = try XCTUnwrap(harness.peek.overlay)
    XCTAssertEqual(overlay.scene[.cardScale], 1)
    XCTAssertEqual(overlay.scene[.cardX], 0)
    XCTAssertLessThan(overlay.scene[.cardOpacity], 0.1, "the open starts transparent")
    harness.settle()
    XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(harness.controller.rootView.card.layer?.transform)))
    XCTAssertEqual(overlay.scene[.cardOpacity], 1)
    harness.controller.close()
  }

  // MARK: Tokens on screen

  func testTheGrabberAndScrimUseThePeekTokens() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try openPeek(harness, world)
    let overlay = try XCTUnwrap(harness.peek.overlay)
    overlay.flavor = .dark
    XCTAssertEqual(overlay.grabber.layer?.backgroundColor, ShellTokens.peekGrabber.dark.cgColor)
    XCTAssertEqual(overlay.scrim.layer?.backgroundColor, ShellTokens.peekScrim.dark.cgColor)
    overlay.reducesTransparency = true
    XCTAssertEqual(overlay.closeButton.layer?.backgroundColor, ShellTokens.toolbarSurface.dark.cgColor,
                   "Reduce Transparency: opaque controls")
    harness.controller.close()
  }

  private static func key(_ code: UInt16) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: code == 53 ? "\u{1b}" : "\r",
                                   charactersIgnoringModifiers: code == 53 ? "\u{1b}" : "\r", isARepeat: false,
                                   keyCode: code))
  }
}
