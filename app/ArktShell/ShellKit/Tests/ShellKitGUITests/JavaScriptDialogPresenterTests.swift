import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// A page's dialogs as panels over its page (#400): shown only while the tab is on screen, one per tab, answered once,
/// and taken down with no answer when the engine ends them.
@MainActor
final class JavaScriptDialogPresenterTests: XCTestCase {
  private var window: NSWindow!
  private var page: NSView!
  private var engine: InMemoryEngine!
  private var tab: TabID!
  private var presenter: JavaScriptDialogPresenter!
  private var observation: EngineObservation?
  private var shown = true
  /// The window state the presenter reads: false models a minimized window or a hidden app.
  private var windowVisible = true

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500), styleMask: [.titled],
                      backing: .buffered, defer: false)
    page = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = page
    window.orderFront(nil)
    engine = InMemoryEngine()
    tab = engine.createTab(url: URL(string: "arkt-test://page/Dialog")!, in: engine.createWindow(host: StubWindowHost()))
    presenter = JavaScriptDialogPresenter(engine: engine, anchor: { [unowned self] _ in shown ? page : nil },
                                          windowIsVisible: { [unowned self] _ in windowVisible })
    presenter.reduceMotion = { true }
    observation = engine.observe { [unowned self] in presenter.handle($0) }
  }

  override func tearDown() async throws {
    observation?.cancel()
    presenter.closeAll()
    window.orderOut(nil)
  }

  func testARaisedDialogShowsAPanelOverThePageAnchoredAtItsTopLeadingCorner() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Delete it?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(presenter.pending[tab]?.id, id)
    XCTAssertTrue(window.childWindows?.contains(panel.panel) == true)
    let anchor = window.convertToScreen(page.convert(page.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame, panel.frame(anchoredTo: anchor))
    XCTAssertEqual(panel.content.title, "page says")
    XCTAssertEqual(panel.content.primaryTitle, "OK")
    XCTAssertEqual(panel.content.cancelTitle, "Cancel")
  }

  func testOKAnswersTheEngineOnceAndTakesThePanelDown() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertEqual(engine.dialogAnswers.first?.accepted, true)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(presenter.pending.isEmpty)
  }

  func testCancelAnswersFalse() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    try XCTUnwrap(presenter.panel(for: tab)).view.cancelButton?.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.first?.accepted, false)
  }

  func testEscapeOnAnAlertAnswersOK() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Saved"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertTrue(panel.view.escape())
    XCTAssertEqual(engine.dialogAnswers.first?.accepted, true)
  }

  func testAPromptReturnsTheTextTheUserTyped() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(panel.inputText, "Ada")
    XCTAssertTrue(panel.view.initialFocus === panel.view.inputView?.field, "focus starts in the field")
    panel.view.inputView?.field.stringValue = "Grace"
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.first?.userInput, "Grace")
    XCTAssertEqual(engine.dialogAnswers.first?.accepted, true)
  }

  func testTheEnginesEndTakesThePanelDownWithoutAnAnswer() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertNil(panel.panel.parent)
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
  }

  func testALaterDialogReplacesTheEarlierPanel() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "One"))
    let first = try XCTUnwrap(presenter.panel(for: tab))
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Two"))
    let second = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertFalse(first === second)
    XCTAssertNil(first.panel.parent)
    XCTAssertEqual(second.content.paragraphs.map(\.text), ["Two"])
    XCTAssertEqual(window.childWindows?.filter { $0 === second.panel || $0 === first.panel }.count, 1)
  }

  func testADialogOfATabOffScreenWaitsAndAppearsWhenTheTabIsShown() throws {
    shown = false
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Later"))
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertEqual(presenter.pending[tab]?.id, id, "still pending: the page may be waiting")
    shown = true
    presenter.refresh()
    XCTAssertNotNil(presenter.panel(for: tab))
    shown = false
    presenter.refresh()
    XCTAssertNil(presenter.panel(for: tab), "the tab left the screen: no panel, no answer")
    XCTAssertNotNil(presenter.pending[tab])
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
  }

  func testAClosedTabLeavesNoPanel() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(presenter.pending.isEmpty)
  }

  /// Worst case: Chromium's 24 lines of 80 characters, in a narrow pane. The panel stays short and the body scrolls.
  func testALongMessageScrollsInsideACappedBody() throws {
    let line = String(repeating: "wide message text ", count: 5)
    let message = Array(repeating: line, count: 24).joined(separator: "\n")
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: message))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    let scroll = try XCTUnwrap(panel.view.bodyScroll)
    XCTAssertEqual(scroll.frame.height, 240)
    XCTAssertLessThan(panel.panel.frame.height, 400)
    XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, 240)
  }

  func testANarrowPagePutsThePanelInsideIt() throws {
    page.setFrameSize(NSSize(width: 300, height: 500))
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Hi"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(panel.panel.frame.width, 276, "page width minus the 12 pt inset on each side")
  }

  // MARK: A dialog that arrives with nothing to show it on (#400 review)

  /// Each way a window comes back (or a page view arrives) shows the dialog that waited for it.
  func testADialogRaisedInAMinimizedWindowAppearsWhenTheWindowComesBack() throws {
    let comebacks: [(String, () -> Void)] = [
      ("deminiaturize", { NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: self.window) }),
      ("occlusion", { NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self.window) }),
      ("unhide", { NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApp) }),
    ]
    for (name, comeBack) in comebacks {
      windowVisible = false
      let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "While away (\(name))"))
      XCTAssertNil(presenter.panel(for: tab), "\(name): nothing to show it on yet")
      XCTAssertEqual(presenter.pending[tab]?.id, id, "\(name): still pending")

      windowVisible = true
      comeBack()

      XCTAssertNotNil(presenter.panel(for: tab), "\(name): the dialog must appear without a tab switch")
      XCTAssertTrue(engine.dialogAnswers.isEmpty, "\(name): no answer was given")
      presenter.closeAll()
      engine.navigate(tab, to: URL(string: "arkt-test://page/Next-\(name)")!)     // the engine ends it
      XCTAssertTrue(presenter.pending.isEmpty)
    }
  }

  /// A dialog that arrives before the page view is attached shows after the next layout of the window.
  func testADialogWithNoAnchorAppearsAfterTheNextLayout() throws {
    shown = false
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Early"))
    XCTAssertNil(presenter.panel(for: tab))

    shown = true
    presenter.layoutDidFinish()

    XCTAssertNotNil(presenter.panel(for: tab))
  }

  func testALayoutWithNothingPendingDoesNothing() {
    shown = true
    presenter.layoutDidFinish()
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(presenter.pending.isEmpty)
  }

  // MARK: Reduce Motion (#400 review)

  /// The panel travels in on a spring (scale and 4 pt from above) with the usual setting, and only fades under Reduce
  /// Motion: no transform animation at all.
  func testReduceMotionPanelFadesWithoutTravel() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Moving"))
    let moving = try XCTUnwrap(presenter.panel(for: tab)).container.layer
    XCTAssertNotNil(moving?.animation(forKey: "dialogFade"))
    XCTAssertNotNil(moving?.animation(forKey: "dialogTransform"), "the usual entrance travels")
    presenter.closeAll()
    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)

    presenter.reduceMotion = { true }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Still"))
    let still = try XCTUnwrap(presenter.panel(for: tab)).container.layer
    XCTAssertNotNil(still?.animation(forKey: "dialogFade"), "Reduce Motion keeps the fade")
    XCTAssertNil(still?.animation(forKey: "dialogTransform"), "Reduce Motion has no travel")
  }

  /// A click on OK fades the panel out over 0.10 s and then the panel must be gone: no invisible window left over the
  /// page. The presenter lets go of its `DialogPanel` at the answer, so the fade's completion must not depend on it
  /// (found in the real app, where a mouse answer left the window ordered in at opacity 0).
  func testAMouseAnswerLeavesNoPanelBehind() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Click me"))
    var held = presenter.panel(for: tab)
    let window = try XCTUnwrap(held?.panel)
    let ok = try XCTUnwrap(held?.view.primaryButton)
    held = nil
    ok.performClick(nil)
    waitUntil("the faded panel to leave its parent window") { window.parent == nil && !window.isVisible }
  }

  // MARK: Width follows the page (#464)

  /// The panel width the design gives a page `anchorWidth` wide: 420 pt, narrower in a narrow page, never under 260.
  private func expectedWidth(_ anchorWidth: CGFloat) -> CGFloat {
    min(420, max(260, anchorWidth - 2 * DialogPanel.anchorInset))
  }

  private func anchorFrame() -> NSRect { window.convertToScreen(page.convert(page.bounds, to: nil)) }

  func testThePanelWidthFollowsTheWindowAcrossTheClamps() throws {
    let message = String(repeating: "Eine sehr lange Nachricht mit langen Wörtern und 日本語のテキスト. ", count: 6)
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: kind, message: message, defaultPromptText: "x"))
      let panel = try XCTUnwrap(presenter.panel(for: tab))
      // Wider than 420 + 24 (the upper clamp), unclamped, narrower than 260 + 24 (the lower clamp), and back.
      for width: CGFloat in [900, 300, 150, 700, 450] {
        window.setContentSize(NSSize(width: width, height: 500))
        let anchor = anchorFrame()
        let expected = expectedWidth(anchor.width)
        XCTAssertEqual(panel.panel.frame.width, expected, "\(kind) at \(width): the panel follows the page")
        XCTAssertTrue(presenter.panel(for: tab) === panel, "\(kind): the same panel, not a new one")
        XCTAssertEqual(panel.panel.frame, panel.frame(anchoredTo: anchor), "\(kind): top-leading corner stays put")
        XCTAssertLessThanOrEqual(panel.view.primaryButton.frame.maxX, expected, "\(kind): the buttons fit")
        XCTAssertEqual(panel.container.frame.size, panel.panel.frame.size)
      }
      let id = try XCTUnwrap(presenter.pending[tab]?.id)
      engine.respond(to: id, accepted: true, userInput: nil)
    }
  }

  func testThePanelReachesBothClampsAtTheSizesTheTestUses() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Saved"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    window.setContentSize(NSSize(width: 900, height: 500))
    XCTAssertEqual(panel.panel.frame.width, 420)
    window.setContentSize(NSSize(width: 150, height: 500))
    XCTAssertLessThan(anchorFrame().width, 260 + 2 * DialogPanel.anchorInset, "the window is small enough to clamp")
    XCTAssertEqual(panel.panel.frame.width, 260)
  }

  /// The page view narrows inside a window that keeps its size (a sidebar opening): the panel follows the view.
  func testTheAnchorResizingAloneChangesThePanelWidth() throws {
    let inner = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    inner.autoresizingMask = []
    page.addSubview(inner)
    page = inner
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(panel.panel.frame.width, 420)
    for width: CGFloat in [330, 100, 640] {
      inner.setFrameSize(NSSize(width: width, height: 500))
      XCTAssertEqual(panel.panel.frame.width, expectedWidth(width), "the view is \(width) wide")
      XCTAssertEqual(panel.panel.frame, panel.frame(anchoredTo: anchorFrame()))
    }
  }

  func testAPromptKeepsItsTypedTextWhenTheWidthChanges() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    panel.view.inputView?.field.stringValue = "Grace"
    window.setContentSize(NSSize(width: 200, height: 500))
    XCTAssertEqual(panel.inputText, "Grace")
    window.setContentSize(NSSize(width: 800, height: 500))
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.userInput), ["Grace"], "one answer, with the text typed before the resizes")
  }

  func testAnUnchangedWidthLeavesThePanelSizeAlone() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    let size = panel.panel.frame.size
    panel.resize(width: size.width)
    presenter.refresh()
    XCTAssertEqual(panel.panel.frame.size, size)
  }

  // MARK: Release and adopt (#464)

  func testReleaseTakesThePanelDownWithoutAnsweringAndAdoptShowsItAgain() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    panel.view.inputView?.field.stringValue = "Grace"

    let released = try XCTUnwrap(presenter.release(tab))

    XCTAssertEqual(released.id, id)
    XCTAssertEqual(released.defaultPromptText, "Grace", "the text typed so far travels as the initial text")
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(presenter.pending.isEmpty)
    XCTAssertNil(panel.onAnswer, "the old panel can no longer answer")
    XCTAssertNil(panel.panel.parent)
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
    XCTAssertNil(presenter.release(tab), "nothing left to release")

    presenter.adopt(released)
    let again = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(again.inputText, "Grace")
    again.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertEqual(engine.dialogAnswers.first?.userInput, "Grace")
  }

  func testTheEnginesEndAfterAReleaseDoesNothingHere() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    _ = presenter.release(tab)
    engine.navigate(tab, to: URL(string: "arkt-test://page/Other")!)
    XCTAssertTrue(presenter.pending.isEmpty)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
  }

  // MARK: The page view reaches another window or view without a hand-off (#464 review)

  func testAPageViewMovedToAnotherWindowTakesItsPanelAlongAndAnswersOnce() throws {
    let other = NSWindow(contentRect: NSRect(x: 900, y: 200, width: 500, height: 400), styleMask: [.titled],
                         backing: .buffered, defer: false)
    other.orderFront(nil)
    defer { other.orderOut(nil) }
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    let oldPanel = try XCTUnwrap(presenter.panel(for: tab))
    oldPanel.view.inputView?.field.stringValue = "Grace"

    window.contentView = NSView()
    other.contentView = page
    presenter.refresh()

    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertFalse(panel === oldPanel)
    XCTAssertNil(oldPanel.panel.parent)
    XCTAssertNil(oldPanel.onAnswer, "the old panel can no longer answer")
    XCTAssertEqual(window.childWindows?.count ?? 0, 0, "none in the old window")
    XCTAssertEqual(other.childWindows?.filter { $0 === panel.panel }.count, 1)
    XCTAssertEqual(panel.panel.frame.width, expectedWidth(anchorFrame().width))
    XCTAssertEqual(panel.inputText, "Grace")
    XCTAssertTrue(engine.dialogAnswers.isEmpty, "moving the view answers nothing")

    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertEqual(engine.dialogAnswers.first?.userInput, "Grace")
  }

  func testAPageViewReplacedInTheSameWindowWatchesTheNewViewOnly() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    let oldPanel = try XCTUnwrap(presenter.panel(for: tab))
    let old = try XCTUnwrap(page)
    let fresh = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    old.addSubview(fresh)
    page = fresh
    presenter.refresh()

    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertFalse(panel === oldPanel)
    XCTAssertNil(oldPanel.panel.parent)
    XCTAssertEqual(window.childWindows?.count, 1)
    let before = panel.panel.frame.width
    old.setFrameSize(NSSize(width: 300, height: 500))              // the old view no longer drives the panel
    XCTAssertEqual(panel.panel.frame.width, before)
    fresh.setFrameSize(NSSize(width: 300, height: 500))
    XCTAssertEqual(panel.panel.frame.width, expectedWidth(300))
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
  }
}
