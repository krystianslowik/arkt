import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A page's JavaScript dialogs in a Little Arkt window (#471): the panel points at the small window's page, a pending
/// dialog travels with the page when Open in moves it to the main window (the #467 release / adopt pair), and closing
/// the small window ends the dialog without answering it.
///
/// The flight is stepped by hand (`tick(at:)`), the window's motion settles with `finishMotion()`, and no test waits on
/// the clock.
@MainActor
final class LittleArktDialogTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let popupURL = URL(string: "arkt-test://page/SignIn")!
  private static let frame = 1.0 / 120

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts {
        little.flight?.abort(.closeRequested)
        little.window.orderOut(nil)
      }
    }
    sets = []
  }

  // MARK: Harness

  private struct Scene {
    let set: ShellWindowSet
    let engine: InMemoryEngine
    let main: ShellWindowController
    let little: LittleArktWindowController
    let littleWindow: EngineWindowID
    let tab: TabID
  }

  /// A main window and a Little Arkt popup, both with Reduce Motion as given. The popup's motion and flight are
  /// stepped by hand; its appear is at rest.
  /// `raisingRightAfterOpen` raises that kind of dialog on the popup's tab in the same turn as `openEngineWindow`,
  /// before its appear is settled and before any layout pass.
  private func makeScene(reduceMotion: Bool = false, raisingRightAfterOpen: JavaScriptDialog.Kind? = nil) throws
    -> Scene {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { reduceMotion }
    set.littleArktConfigure = { little in
      little.drivesDisplayLink = false
      little.snapshotSource = { _ in nil }
      little.javaScriptDialogs.reduceMotion = { reduceMotion }
    }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let main = set.openWindow()
    main.window?.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 800), display: false)
    main.window?.contentView?.layoutSubtreeIfNeeded()
    main.javaScriptDialogs.reduceMotion = { reduceMotion }
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: popupURL, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    if let kind = raisingRightAfterOpen { engine.raiseDialog(in: tab, kind: kind, message: "Now?") }
    little.finishMotion()
    little.window.contentView?.layoutSubtreeIfNeeded()
    return Scene(set: set, engine: engine, main: main, little: little, littleWindow: id, tab: tab)
  }

  /// Steps the flight 120 Hz frame by frame until it has landed the page, at most 5 s of flight time.
  private func land(_ flight: LittleArktFlight) {
    var t = 0.0
    while flight.stage == .waitingForFrame || flight.stage == .flying, t < 5 {
      flight.tick(at: t)
      t += Self.frame
    }
  }

  private func assertNoPanel(in controller: ShellWindowController, _ scene: Scene, _ message: String,
                             windowIsClear: Bool = true, line: UInt = #line) {
    XCTAssertNil(controller.javaScriptDialogs.panel(for: scene.tab), message, line: line)
    XCTAssertNil(controller.javaScriptDialogs.pending[scene.tab], message, line: line)
    if windowIsClear { XCTAssertEqual(controller.window?.childWindows?.count ?? 0, 0, message, line: line) }
  }

  /// The small window has no panel and no pending dialog for the tab. `windowIsClear` also wants no child window,
  /// which an answered panel only reaches after its exit animation.
  private func assertLittleHasNothing(_ scene: Scene, _ message: String, windowIsClear: Bool = true,
                                      line: UInt = #line) {
    XCTAssertNil(scene.little.javaScriptDialogs.panel(for: scene.tab), message, line: line)
    XCTAssertNil(scene.little.javaScriptDialogs.pending[scene.tab], message, line: line)
    if windowIsClear { XCTAssertEqual(scene.little.window.childWindows?.count ?? 0, 0, message, line: line) }
  }

  // MARK: A page in a Little Arkt window

  func testEachKindOfDialogShowsInThePanelOfTheLittleArktWindowAndAnswersOnce() throws {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      let scene = try makeScene()
      let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: kind, message: "Now?"))

      let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab), "\(kind): up in the small window")
      XCTAssertTrue(panel.panel.parent === scene.little.window, "\(kind): anchored to the small window")
      assertNoPanel(in: scene.main, scene, "\(kind): nothing in the main window")
      let card = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
      let anchor = try XCTUnwrap(card.window).convertToScreen(card.convert(card.bounds, to: nil))
      XCTAssertEqual(panel.panel.frame.maxY, anchor.maxY - DialogPanel.anchorInset, accuracy: 0.5,
                     "\(kind): 12 pt inside the page's top edge")

      panel.view.primaryButton.performClick(nil)

      XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "\(kind): answered once")
      assertLittleHasNothing(scene, "\(kind): answered", windowIsClear: false)
    }
  }

  func testThePanelWidthFollowsTheLittleArktWindow() throws {
    let scene = try makeScene()
    scene.little.window.setFrame(NSRect(x: 100, y: 100, width: 360, height: 500), display: false)
    scene.little.window.contentView?.layoutSubtreeIfNeeded()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))

    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))
    let card = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let anchor = try XCTUnwrap(card.window).convertToScreen(card.convert(card.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame.width, min(420, max(260, anchor.width - 2 * DialogPanel.anchorInset)))

    scene.little.window.setFrame(NSRect(x: 100, y: 100, width: 700, height: 500), display: false)
    scene.little.window.contentView?.layoutSubtreeIfNeeded()
    scene.little.javaScriptDialogs.refresh()
    XCTAssertEqual(panel.panel.frame.width, 420, "a wider window gives the full width")
  }

  func testTheEngineEndingTheDialogTakesThePanelDownWithoutAnAnswer() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Now?"))
    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))

    scene.engine.navigate(scene.tab, to: URL(string: "arkt-test://page/Other")!)

    XCTAssertNil(panel.panel.parent)
    assertLittleHasNothing(scene, "ended by a navigation")
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }

  /// Pins the event ordering: the popup's observer starts when its window is announced, which is before the page's
  /// first script can raise a dialog, so a dialog raised right after `openEngineWindow` is seen and shown.
  func testADialogRaisedRightAfterThePopupOpensShowsItsPanel() throws {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      let scene = try makeScene(raisingRightAfterOpen: kind)

      let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab), "\(kind): up in the small window")
      XCTAssertTrue(panel.panel.parent === scene.little.window)
      panel.view.primaryButton.performClick(nil)
      XCTAssertEqual(scene.engine.dialogAnswers.count, 1, "\(kind): answered once")
    }
  }

  // MARK: Open in with a pending dialog

  func testOpenInCarriesThePendingDialogToTheMainWindow() throws {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      let scene = try makeScene()
      let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: kind, message: "Now?",
                                                      defaultPromptText: "Ada"))
      let oldPanel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))
      if kind == .prompt { oldPanel.view.inputView?.field.stringValue = "Grace" }

      scene.little.openIn()
      let flight = try XCTUnwrap(scene.little.flight)
      flight.tick(at: 0)

      assertLittleHasNothing(scene, "\(kind): the small window lets go as the flight starts")
      XCTAssertNil(oldPanel.onAnswer, "\(kind): the old panel can no longer answer")
      XCTAssertTrue(scene.engine.dialogAnswers.isEmpty, "\(kind): letting go answers nothing")

      land(flight)

      XCTAssertEqual(scene.main.currentTab, scene.tab, "\(kind): the page landed")
      let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab), "\(kind): up in the main window")
      XCTAssertTrue(panel.panel.parent === scene.main.window)
      XCTAssertEqual(scene.main.javaScriptDialogs.pending[scene.tab]?.id, id)
      assertLittleHasNothing(scene, "\(kind): nothing left in the small window")
      if kind == .prompt { XCTAssertEqual(panel.inputText, "Grace", "the typed text came along") }

      panel.view.primaryButton.performClick(nil)

      XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "\(kind): answered once")
      XCTAssertEqual(scene.engine.dialogAnswers.map(\.userInput), [kind == .prompt ? "Grace" : nil])
      assertNoPanel(in: scene.main, scene, "\(kind): answered", windowIsClear: false)
    }
  }

  func testOpenInWithoutTheFlightCarriesTheDialogToo() throws {
    let scene = try makeScene(reduceMotion: true)
    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))

    scene.little.openIn()
    XCTAssertNil(scene.little.flight, "Reduce Motion has no flight")
    scene.little.finishMotion()

    XCTAssertEqual(scene.main.currentTab, scene.tab)
    let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab))
    assertLittleHasNothing(scene, "handed off")
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id])
  }

  func testTheEndOfACarriedDialogClosesItsPanelInTheMainWindow() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Now?"))
    scene.little.openIn()
    land(try XCTUnwrap(scene.little.flight))
    let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab))

    scene.engine.navigate(scene.tab, to: URL(string: "arkt-test://page/Other")!)

    XCTAssertNil(panel.panel.parent)
    assertNoPanel(in: scene.main, scene, "ended after the move")
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }

  func testADialogThatEndsMidFlightIsNotCarried() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)

    scene.engine.navigate(scene.tab, to: URL(string: "arkt-test://page/Other")!)
    land(flight)

    XCTAssertEqual(scene.main.currentTab, scene.tab)
    assertNoPanel(in: scene.main, scene, "the dialog ended while it was in the air")
    assertLittleHasNothing(scene, "and nothing came back")
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }

  /// The main window refuses the page at the no-flight handoff: the page stays in the small window, which shows the
  /// dialog again and answers it once.
  func testARefusedMoveGivesTheDialogBackToTheLittleArktWindow() throws {
    let scene = try makeScene(reduceMotion: true)
    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))
    scene.little.onOpenIn = { _, _, _ in false }

    scene.little.openIn()
    assertLittleHasNothing(scene, "the fade has begun")
    scene.little.finishMotion()                             // the fade ends, the move is refused

    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "the page stayed")
    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab), "the dialog came back")
    XCTAssertTrue(panel.panel.parent === scene.little.window)
    XCTAssertEqual(scene.little.javaScriptDialogs.pending[scene.tab]?.id, id)
    assertNoPanel(in: scene.main, scene, "nothing in the main window")
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)

    panel.view.primaryButton.performClick(nil)

    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "answered once")
  }

  func testARefusedMoveKeepsADialogRaisedDuringTheFade() throws {
    let scene = try makeScene(reduceMotion: true)
    scene.little.onOpenIn = { _, _, _ in false }
    scene.little.openIn()

    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Late"))
    assertLittleHasNothing(scene, "no panel while the window fades")
    scene.little.finishMotion()

    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id])
  }

  /// A dialog raised after the hand-off began is not lost: it goes with the page, in either path.
  func testADialogRaisedDuringTheFadeIsCarried() throws {
    let scene = try makeScene(reduceMotion: true)
    scene.little.openIn()

    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .prompt, message: "Late"))
    scene.little.finishMotion()

    let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab))
    assertLittleHasNothing(scene, "handed off")
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id])
  }

  func testADialogRaisedInTheAirIsCarried() throws {
    let scene = try makeScene()
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    flight.tick(at: 0.1)

    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Late"))
    assertLittleHasNothing(scene, "no panel over the flying window")
    land(flight)

    let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab))
    assertLittleHasNothing(scene, "landed")
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id])
  }

  // MARK: The flight's abort path keeps the dialog

  /// The main window goes away mid-flight: the page stays in the small window, and so does its dialog, with a panel
  /// that answers once.
  func testTheMainWindowClosingMidFlightKeepsTheDialogInTheLittleArktWindow() throws {
    let scene = try makeScene()
    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    flight.tick(at: 0.1)
    XCTAssertEqual(flight.stage, .flying)

    scene.main.window?.close()

    XCTAssertEqual(scene.engine.snapshot(of: scene.tab)?.window, scene.littleWindow, "the page stayed")
    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab), "the dialog stayed")
    XCTAssertTrue(panel.panel.parent === scene.little.window)
    XCTAssertEqual(scene.little.javaScriptDialogs.pending[scene.tab]?.id, id)
    XCTAssertNil(scene.main.javaScriptDialogs.pending[scene.tab])

    panel.view.primaryButton.performClick(nil)

    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "answered once")
  }

  /// The aborts that land the page without the flight carry the dialog to the main window like a landing does.
  func testTheAbortsThatLandThePageCarryTheDialogToTheMainWindow() throws {
    let reasons: [LittleArktFlightAbort] = [.mainWindowMiniaturized, .framesStopped, .appTerminating,
                                            .smallWindowClosing, .closeRequested]
    for reason in reasons {
      let scene = try makeScene()
      let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Now?"))
      scene.little.openIn()
      let flight = try XCTUnwrap(scene.little.flight)
      flight.tick(at: 0)
      flight.tick(at: 0.1)

      flight.abort(reason)

      XCTAssertEqual(scene.main.currentTab, scene.tab, "\(reason): the page landed")
      let panel = try XCTUnwrap(scene.main.javaScriptDialogs.panel(for: scene.tab), "\(reason): the dialog landed")
      assertLittleHasNothing(scene, "\(reason)")
      panel.view.primaryButton.performClick(nil)
      XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "\(reason): answered once")
    }
  }

  func testThePageClosingItselfMidFlightLeavesNoPanelAndNoAnswer() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .prompt, message: "Now?"))
    scene.little.openIn()
    let flight = try XCTUnwrap(scene.little.flight)
    flight.tick(at: 0)
    flight.tick(at: 0.1)

    scene.engine.closeTab(scene.tab)

    assertNoPanel(in: scene.main, scene, "the page closed")
    assertLittleHasNothing(scene, "the page closed")
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }

  // MARK: Closing Little Arkt with a pending dialog

  /// Chromium ends a tab's dialog when its tab closes and nothing answers it; the page's call returns false or null.
  func testClosingTheLittleArktWindowEndsTheDialogWithoutAnAnswer() throws {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      let scene = try makeScene()
      _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: kind, message: "Now?"))
      let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))

      scene.little.window.performClose(nil)

      XCTAssertNil(panel.panel.parent, "\(kind): the panel goes as the window starts to close")
      XCTAssertNil(panel.onAnswer, "\(kind)")
      scene.little.finishMotion()                           // the close motion ends, the engine closes the window

      XCTAssertFalse(scene.engine.windowIDs.contains(scene.littleWindow), "\(kind): the engine closed it")
      XCTAssertTrue(scene.little.isClosed, "\(kind)")
      XCTAssertNil(scene.little.javaScriptDialogs.pending[scene.tab], "\(kind): the engine ended the dialog")
      XCTAssertEqual(scene.little.window.childWindows?.count ?? 0, 0, "\(kind)")
      XCTAssertTrue(scene.engine.dialogAnswers.isEmpty, "\(kind): nothing answered it")
    }
  }

  func testThePageClosingItsPopupEndsTheDialogWithoutAnAnswer() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))
    let panel = try XCTUnwrap(scene.little.javaScriptDialogs.panel(for: scene.tab))

    scene.engine.closeWindow(scene.littleWindow)            // window.close() in the page
    scene.little.finishMotion()

    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(scene.little.javaScriptDialogs.pending[scene.tab])
    XCTAssertEqual(scene.little.window.childWindows?.count ?? 0, 0)
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }
}
