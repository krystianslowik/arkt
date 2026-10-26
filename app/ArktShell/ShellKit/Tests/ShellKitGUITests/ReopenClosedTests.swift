import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Reopen the most recently closed tab or Peek (#346, #110: BH-074, BH-150, KB-010, KB-011, KB-079): one stack per
/// window for both, Cmd-Shift-T and Cmd-Z walk it back, each page comes back with its history (an unloaded copy
/// parked at the close), a Today tab at the place it had, and a Peek over its source without the travel from the
/// link. A closed Peek offers "Reopen" in a toast.
@MainActor
final class ReopenClosedTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let atlas = URL(string: "https://atlas.example/lisbon")!
  private static let atlasNext = URL(string: "https://atlas.example/porto")!

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
    /// What Cmd-W archived, by id, as the app's ArchiveCoordinator keeps it.
    var archived: [UUID: ArchivedItem] = [:]

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { ReopenClosedTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        for item in source.archive(ids, reason: .manual, at: ReopenClosedTests.now) { archived[item.id] = item }
      }
      controller.onReopenArchived = { [unowned self] id in
        guard let item = archived.removeValue(forKey: id), let space = source.sidebar.spaceOrder.first else {
          return nil
        }
        return try? source.restore(item, fallbackSpace: space).nodeID
      }
      controller.peek.reduceMotion = { false }
      controller.peek.linkSettings = { PeekLinkSettings() }
      controller.peek.closedToastDelay = 0
    }

    var peek: PeekController { controller.peek }
    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
    func settle() { peek.animator.settleNow() }

    /// Opens a Peek from a link in `node` (a Shift-click in a Today tab, BH-145) and lets it settle.
    func openPeek(over node: UUID, shift: Bool = false) throws -> PeekSession {
      controller.activate(node: node)
      let tab = try XCTUnwrap(self.tab(node))
      let decision = shift
        ? engine.simulateLinkActivation(in: tab, url: ReopenClosedTests.atlas, modifiers: .shift,
                                        disposition: .newWindow)
        : engine.simulateLinkActivation(in: tab, url: ReopenClosedTests.atlas)
      XCTAssertEqual(decision, .cancel)
      waitUntil("the Peek opens") { peek.session != nil }
      settle()
      return try XCTUnwrap(peek.session)
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://notes.example/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: URL(string: "https://mail.example.com/inbox")!, title: "Mail",
                                    in: .pinned(space))
    let today = try (0..<3).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    return World(sidebar: sidebar, space: space, pinned: pinned, today: today)
  }

  // MARK: Tabs (BH-074, KB-010)

  /// Cmd-W archives the Today tab; Cmd-Shift-T puts it back where it was, current, with its page's history.
  func testCommandShiftTReopensAnArchivedTodayTabInPlaceWithItsHistory() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    let tab = try XCTUnwrap(harness.tab(world.today[1]))
    harness.engine.navigate(tab, to: Self.url("t1-next"))
    XCTAssertFalse(harness.controller.canReopenClosed)

    harness.controller.closeTab(nil)
    XCTAssertNil(harness.source.node(world.today[1]))
    XCTAssertTrue(harness.controller.canReopenClosed)

    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.source.children(of: .today(world.space)), world.today, "back at its place")
    XCTAssertEqual(harness.controller.currentNode, world.today[1])
    let reopened = try XCTUnwrap(harness.tab(world.today[1]))
    XCTAssertNotEqual(reopened, tab, "the page closed; its parked copy came back")
    XCTAssertEqual(harness.engine.snapshot(of: reopened)?.url, Self.url("t1-next"))
    XCTAssertEqual(harness.engine.history(of: reopened)?.back.map(\.url), [Self.url("t1")], "Back works")
    XCTAssertFalse(harness.controller.canReopenClosed)
    harness.controller.close()
  }

  /// BH-074: repeating walks back further.
  func testRepeatingWalksBackThroughEarlierCloses() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.closeTab(nil)
    harness.controller.activate(node: world.today[2])
    harness.controller.closeTab(nil)

    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.controller.currentNode, world.today[2])
    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.controller.currentNode, world.today[0])
    XCTAssertEqual(harness.source.children(of: .today(world.space)), world.today)
    harness.controller.close()
  }

  /// A pinned tab's Cmd-W closes its page and keeps the row (BH-067); reopening brings the page back with history.
  func testAPinnedTabsClosedPageComesBackWithItsHistory() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let tab = try XCTUnwrap(harness.tab(world.pinned))
    let next = URL(string: "https://mail.example.com/thread")!
    harness.engine.navigate(tab, to: next)
    harness.controller.closeTab(nil)
    XCTAssertNil(harness.tab(world.pinned))

    harness.controller.reopenClosedTab(nil)
    let reopened = try XCTUnwrap(harness.tab(world.pinned))
    XCTAssertEqual(harness.controller.currentTab, reopened)
    XCTAssertEqual(harness.engine.snapshot(of: reopened)?.url, next)
    XCTAssertEqual(harness.engine.history(of: reopened)?.back.count, 1)
    harness.controller.close()
  }

  /// The parked copy is a tab without a row: it never shows in the sidebar and never takes the engine's activation.
  func testTheParkedCopyHasNoRowAndStaysInTheBackground() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.closeTab(nil)
    let parked = try XCTUnwrap(harness.controller.reopenStack.parkedTabs.first)
    XCTAssertNil(harness.controller.nodeByTab[parked])
    XCTAssertEqual(harness.source.children(of: .today(world.space)).count, 2)
    harness.engine.engineActivate(parked)
    XCTAssertEqual(harness.engine.activeTab(in: try XCTUnwrap(harness.controller.engineWindow)),
                   harness.controller.currentTab, "the shell answers with its own tab")
    harness.controller.close()
  }

  /// A close the user cancelled at a leave-site prompt did not happen: nothing to reopen, no copy left behind.
  func testACancelledCloseLeavesNothingToReopen() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.tab(world.today[0]))
    harness.engine.holdClose(tab)
    harness.controller.closeTab(nil)
    let parked = harness.controller.reopenStack.parkedTabs
    XCTAssertTrue(harness.engine.answerDialog(tab, accept: false))
    XCTAssertFalse(harness.controller.canReopenClosed)
    for copy in parked { XCTAssertNil(harness.engine.snapshot(of: copy), "the copy closed") }
    harness.controller.close()
  }

  /// File > Reopen Closed Tab is enabled only with something to reopen.
  func testTheMenuItemFollowsTheStack() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let item = NSMenuItem(title: "Reopen Closed Tab", action: #selector(ShellWindowController.reopenClosedTab(_:)),
                          keyEquivalent: "T")
    XCTAssertFalse(harness.controller.validateMenuItem(item))
    harness.controller.activate(node: world.today[0])
    harness.controller.closeTab(nil)
    XCTAssertTrue(harness.controller.validateMenuItem(item))
    harness.controller.close()
  }

  // MARK: Peek (BH-150, KB-079)

  /// After a close, a "Peek closed" toast offers Reopen with its key; Reopen brings the same page back, with its
  /// history, over the same source, without the travel from the link.
  func testAClosedPeekOffersReopenInAToastAndComesBackWithItsHistory() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try harness.openPeek(over: world.pinned)
    harness.engine.navigate(session.tab, to: Self.atlasNext)
    try XCTUnwrap(harness.peek.overlay).closeButton.performClick(nil)
    harness.settle()
    XCTAssertNil(harness.peek.session)
    waitUntil("the toast shows") { harness.controller.toasts.current != nil }
    let toast = try XCTUnwrap(harness.controller.toasts.current)
    XCTAssertEqual(toast.text, "Peek closed")
    XCTAssertEqual(toast.actionTitle, "Reopen")
    XCTAssertEqual(toast.shortcut, "\u{2318}Z")
    XCTAssertEqual(toast.spokenText, "Peek closed. Press Command-Z to reopen.")
    XCTAssertTrue(toast.isPolite)

    harness.controller.toasts.performActionForTesting()
    let reopened = try XCTUnwrap(harness.peek.session)
    XCTAssertEqual(reopened.source, session.source)
    XCTAssertNotEqual(reopened.tab, session.tab, "a parked copy, not a new load of the link")
    XCTAssertEqual(harness.engine.snapshot(of: reopened.tab)?.url, Self.atlasNext)
    XCTAssertEqual(harness.engine.history(of: reopened.tab)?.back.map(\.url), [Self.atlas])
    let scale = harness.peek.animator.currentScene[.cardScale]
    XCTAssertTrue(scale >= 0.96 && scale < 0.99, "in place, from 0.96: \(scale)")
    XCTAssertEqual(harness.peek.animator.currentScene[.cardX], 0)
    harness.settle()
    XCTAssertEqual(harness.peek.session?.phase, .open)
    XCTAssertNil(harness.controller.toasts.current)
    harness.controller.close()
  }

  /// Cmd-Z reopens a closed Peek when no text is being edited (the menu's Undo goes through the router), and the
  /// reopen toast goes away.
  func testCommandZReopensAClosedPeek() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    _ = try harness.openPeek(over: world.pinned)
    harness.peek.close(.keyboard)
    harness.settle()
    waitUntil("the toast shows") { harness.controller.toasts.current != nil }
    let router = ReopenUndoRouter(window: { [weak harness] in harness?.controller.window })
    let undo = NSMenuItem(title: "Undo", action: #selector(ReopenUndoRouter.undo(_:)), keyEquivalent: "z")
    undo.target = router
    XCTAssertTrue(router.validateMenuItem(undo))

    router.undo(undo)
    XCTAssertNotNil(harness.peek.session)
    XCTAssertNil(harness.controller.toasts.current, "the toast goes with the reopen")
    harness.controller.close()
  }

  /// Cmd-Z belongs to the text being edited: the router leaves the reopen stack alone and passes Undo on.
  func testCommandZWhileEditingTextUndoesTheTextInstead() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.closeTab(nil)
    let window = try XCTUnwrap(harness.controller.window)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    XCTAssertTrue(ReopenUndoRouter.isEditingText(window.firstResponder), "the field editor")

    let router = ReopenUndoRouter(window: { window })
    router.undo(nil)
    XCTAssertTrue(harness.controller.canReopenClosed, "nothing was reopened")
    XCTAssertNil(harness.source.node(world.today[0]))
    field.removeFromSuperview()
    harness.controller.close()
  }

  /// #349: switching tab closes the Peek; Cmd-Shift-T brings back its source and the Peek over it.
  func testAPeekClosedByATabSwitchComesBackOverItsSource() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try harness.openPeek(over: world.pinned)
    harness.controller.activate(node: world.today[0])
    XCTAssertNil(harness.peek.session)

    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.controller.currentNode, world.pinned)
    let reopened = try XCTUnwrap(harness.peek.session)
    XCTAssertEqual(reopened.source, session.source)
    XCTAssertEqual(harness.engine.snapshot(of: reopened.tab)?.url, Self.atlas)
    harness.controller.close()
  }

  /// Closing the source tab closes its Peek; Cmd-Shift-T brings both back together.
  func testClosingTheSourceClosesItsPeekAndBothReopenTogether() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try harness.openPeek(over: world.today[2], shift: true)
    harness.controller.close(node: world.today[2])            // the row's X
    XCTAssertNil(harness.peek.session)
    XCTAssertNil(harness.source.node(world.today[2]))
    XCTAssertEqual(harness.controller.reopenStack.items.count, 1, "one item for both")

    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.controller.currentNode, world.today[2])
    let reopened = try XCTUnwrap(harness.peek.session)
    XCTAssertEqual(reopened.source, harness.tab(world.today[2]))
    XCTAssertNotEqual(reopened.source, session.source)
    XCTAssertEqual(harness.engine.snapshot(of: reopened.tab)?.url, Self.atlas)
    XCTAssertFalse(harness.controller.canReopenClosed)
    harness.controller.close()
  }

  /// A reopen asked for while the Peek is still closing takes the close back from where the card is.
  func testReopenDuringTheCloseReversesIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let session = try harness.openPeek(over: world.pinned)
    harness.peek.close(.control)
    XCTAssertEqual(harness.peek.session?.phase, .closing)
    XCTAssertTrue(harness.controller.canReopenClosed)
    harness.controller.reopenClosedTab(nil)
    XCTAssertEqual(harness.peek.session?.tab, session.tab, "the same tab, never closed")
    harness.settle()
    XCTAssertEqual(harness.peek.session?.phase, .open)
    XCTAssertFalse(harness.controller.canReopenClosed)
    harness.controller.close()
  }
}
