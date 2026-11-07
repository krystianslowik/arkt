import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The leave-site prompt as the shell's panel (#584): a held close shows it hung from the page's top edge with Stay as
/// the primary. Stay (or Escape) cancels the close, Leave lets it go on, through the same held-close paths as before:
/// the tab close, the Little Arkt close, the window close and the quit. Scripted with `InMemoryEngine`'s reported
/// leave-site dialogs; motion is stepped by hand.
@MainActor
final class LeaveSiteDialogWindowTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let popupURL = URL(string: "arkt-test://page/Draft")!
  /// The input protection's clock, in seconds. Starts past the protection, so presses count unless a test rewinds.
  private var now: TimeInterval = 0

  /// Hands the clock to `presenter` and treats its panels as on screen, so the protection runs on `now` only.
  private func drive(_ presenter: JavaScriptDialogPresenter) {
    presenter.clock = { [unowned self] in now }
    presenter.isOnScreen = { true }
  }

  /// Moves the clock past the input protection of a panel that just appeared.
  private func pastProtection() { now += DialogContent.leaveSiteInputProtection + 0.01 }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
  }

  private func makeSet() throws -> (ShellWindowSet, InMemoryEngine, ShellWindowController) {
    let engine = InMemoryEngine()
    engine.reportsLeaveSiteDialogs = true
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { true }
    set.littleArktConfigure = { little in
      little.drivesDisplayLink = false
      little.snapshotSource = { _ in nil }
      little.javaScriptDialogs.reduceMotion = { true }
      self.drive(little.javaScriptDialogs)
    }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let main = set.openWindow()
    main.window?.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 800), display: false)
    main.window?.contentView?.layoutSubtreeIfNeeded()
    main.javaScriptDialogs.reduceMotion = { true }
    drive(main.javaScriptDialogs)
    return (set, engine, main)
  }

  private func openPopup(_ engine: InMemoryEngine, _ set: ShellWindowSet) throws
    -> (LittleArktWindowController, EngineWindowID, TabID) {
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: popupURL, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    little.finishMotion()
    little.window.contentView?.layoutSubtreeIfNeeded()
    return (little, id, tab)
  }

  // MARK: Little Arkt (Cmd-W)

  func testTheLeaveSitePanelHangsFromThePagesTopEdgeWithStayAsThePrimary() throws {
    let (set, engine, _) = try makeSet()
    let (little, _, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)

    let panel = try XCTUnwrap(little.javaScriptDialogs.panel(for: tab), "the prompt is up in the small window")
    XCTAssertEqual(little.javaScriptDialogs.pending[tab]?.kind, .beforeUnload)
    XCTAssertEqual(panel.attachment, .topEdge)
    XCTAssertEqual(panel.view.primaryButton.title, "Stay")
    XCTAssertEqual(panel.view.secondaryButton?.title, "Leave")
    XCTAssertNil(panel.view.cancelButton)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let anchor = try XCTUnwrap(page.window).convertToScreen(page.convert(page.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame.maxY, anchor.maxY, accuracy: 0.5, "on the page's top edge")
    XCTAssertEqual(panel.panel.frame.minX, anchor.minX + DialogPanel.anchorInset, accuracy: 0.5)
    let dim = try XCTUnwrap(panel.pageDim, "the page dims under the prompt (#693)")
    let dimFrame = try XCTUnwrap(dim.window).convertToScreen(dim.convert(dim.bounds, to: nil))
    XCTAssertEqual(dimFrame, anchor, "the dim covers the page")
  }

  func testStayKeepsTheLittleArktWindowAndItsPage() throws {
    let (set, engine, _) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)

    pastProtection()
    try XCTUnwrap(little.javaScriptDialogs.panel(for: tab)).view.primaryButton.performClick(nil)
    little.finishMotion()

    XCTAssertEqual(engine.dialogAnswers.map(\.accepted), [false])
    XCTAssertEqual(engine.snapshot(of: tab)?.isClosing, false)
    XCTAssertTrue(engine.windowIDs.contains(id))
    XCTAssertFalse(little.isClosed)
    XCTAssertNil(little.javaScriptDialogs.panel(for: tab))
    XCTAssertNil(little.javaScriptDialogs.pending[tab])
  }

  func testAPressRightAfterThePromptAppearsCannotLeave() throws {
    let (set, engine, _) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)
    let panel = try XCTUnwrap(little.javaScriptDialogs.panel(for: tab))

    now += DialogContent.leaveSiteInputProtection - 0.01                  // a click already on its way
    try XCTUnwrap(panel.view.secondaryButton).performClick(nil)
    XCTAssertTrue(engine.dialogAnswers.isEmpty, "Leave is held right after the prompt appears")
    XCTAssertTrue(engine.windowIDs.contains(id))

    now += 0.02
    try XCTUnwrap(panel.view.secondaryButton).performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.accepted), [true], "a deliberate Leave after it counts")
  }

  func testEscapeStaysToo() throws {
    let (set, engine, _) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)

    XCTAssertTrue(try XCTUnwrap(little.javaScriptDialogs.panel(for: tab)).view.escape())

    XCTAssertEqual(engine.dialogAnswers.map(\.accepted), [false])
    XCTAssertTrue(engine.windowIDs.contains(id))
  }

  func testLeaveClosesTheLittleArktWindow() throws {
    let (set, engine, _) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)

    pastProtection()
    try XCTUnwrap(little.javaScriptDialogs.panel(for: tab)?.view.secondaryButton).performClick(nil)
    little.finishMotion()

    XCTAssertEqual(engine.dialogAnswers.map(\.accepted), [true])
    XCTAssertFalse(engine.windowIDs.contains(id))
    XCTAssertTrue(little.isClosed)
  }

  // MARK: Main window

  func testStayCancelsAHeldWindowClose() throws {
    let (_, engine, main) = try makeSet()
    let tab = try XCTUnwrap(main.currentTab)
    let window = try XCTUnwrap(main.engineWindow)
    engine.holdClose(tab)
    main.window?.performClose(nil)
    XCTAssertTrue(main.isWindowCloseRequested, "the close waits on the prompt")

    let panel = try XCTUnwrap(main.javaScriptDialogs.panel(for: tab), "the prompt is up over the page")
    XCTAssertEqual(panel.attachment, .topEdge)
    pastProtection()
    panel.view.primaryButton.performClick(nil)

    XCTAssertFalse(main.isWindowCloseRequested, "staying cancels the window close")
    XCTAssertTrue(engine.windowIDs.contains(window))
    XCTAssertEqual(main.currentTab, tab)
  }

  func testStayDuringAQuitReachesTheCancelledClosePath() throws {
    let (_, engine, main) = try makeSet()
    let tab = try XCTUnwrap(main.currentTab)
    let window = try XCTUnwrap(main.engineWindow)
    let recorder = EventRecorder(engine)
    engine.holdClose(tab)
    engine.engineCloseWindow(window, reason: .appQuit)

    pastProtection()
    try XCTUnwrap(main.javaScriptDialogs.panel(for: tab)).view.primaryButton.performClick(nil)

    XCTAssertEqual(recorder.events(for: tab).last, .closeCancelled(tab))
    XCTAssertTrue(engine.windowIDs.contains(window))
    XCTAssertEqual(main.currentTab, tab)
  }

  func testLeaveLetsTheHeldWindowCloseFinish() throws {
    let (set, engine, main) = try makeSet()
    let tab = try XCTUnwrap(main.currentTab)
    let window = try XCTUnwrap(main.engineWindow)
    engine.holdClose(tab)
    main.window?.performClose(nil)

    pastProtection()
    try XCTUnwrap(main.javaScriptDialogs.panel(for: tab)?.view.secondaryButton).performClick(nil)

    XCTAssertFalse(engine.windowIDs.contains(window))
    XCTAssertFalse(set.controllers.contains { $0 === main })
  }
}
