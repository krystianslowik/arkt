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

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    observation?.cancel()
    presenter.closeAll()
    window.isReleasedWhenClosed = false
    window.close()
    presenter = nil
    page = nil
    window = nil
    engine = nil
  }

  func testARaisedDialogShowsAPanelHangingFromThePagesTopEdge() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Delete it?"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(presenter.pending[tab]?.id, id)
    XCTAssertTrue(window.childWindows?.contains(panel.panel) == true)
    let anchor = window.convertToScreen(page.convert(page.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame, panel.frame(anchoredTo: anchor))
    XCTAssertEqual(panel.panel.frame.maxY, anchor.maxY, "on the page's top edge")
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

  func testAPromptKeepsItsTypedTextWhenHiddenAndShownAgain() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    let hiddenPanel = try XCTUnwrap(presenter.panel(for: tab))
    hiddenPanel.view.inputView?.field.stringValue = "Grace"

    shown = false
    presenter.refresh()
    XCTAssertNil(presenter.panel(for: tab), "the page is off screen: no panel")
    XCTAssertEqual(presenter.pending[tab]?.id, id, "still pending")
    XCTAssertTrue(engine.dialogAnswers.isEmpty)

    shown = true
    presenter.refresh()
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    XCTAssertEqual(panel.inputText, "Grace", "the text typed before the hide is still there")
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id], "exactly one answer")
    XCTAssertEqual(engine.dialogAnswers.first?.userInput, "Grace")
  }

  // MARK: The page dims under its dialog; every dialog on the top edge (#693)

  /// The dim of the tab's panel, which must be up.
  private func pageDim() throws -> PageDimView {
    try XCTUnwrap(try XCTUnwrap(presenter.panel(for: tab)).pageDim, "a page dialog dims its page")
  }

  private func screenFrame(of view: NSView) throws -> NSRect {
    let window = try XCTUnwrap(view.window)
    return window.convertToScreen(view.convert(view.bounds, to: nil))
  }

  /// The dim is on its way out: model opacity 0, a 0.10 s opacity fade, gone when it ends.
  private func assertLeaving(_ dim: PageDimView, _ message: String = "", line: UInt = #line) {
    XCTAssertTrue(dim.isLeaving, message, line: line)
    XCTAssertEqual(dim.layer?.opacity, 0, message, line: line)
    let fade = dim.layer?.animation(forKey: PageDimView.fadeKey) as? CABasicAnimation
    XCTAssertEqual(fade?.keyPath, "opacity", message, line: line)
    XCTAssertEqual(fade?.duration, 0.10, message, line: line)
    XCTAssertEqual(dim.layer?.animationKeys() ?? [], [PageDimView.fadeKey], "\(message): it never moves", line: line)
  }

  func testEveryKindHangsFromTheTopEdgeOverTheDimmedPage() throws {
    presenter.dimExitDuration = 0
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: kind, message: "Now?"))
      let panel = try XCTUnwrap(presenter.panel(for: tab))
      XCTAssertEqual(panel.attachment, .topEdge, "\(kind)")
      XCTAssertEqual(panel.panel.frame.maxY, anchorFrame().maxY, "\(kind): on the page's top edge")
      XCTAssertEqual(panel.panel.frame.minX, anchorFrame().minX + DialogPanel.anchorInset, "\(kind)")
      let dim = try pageDim()
      XCTAssertTrue(dim.page === page, "\(kind)")
      XCTAssertEqual(try screenFrame(of: dim), anchorFrame(), "\(kind): the dim covers the page")
      XCTAssertEqual(dim.layer?.opacity, 1, "\(kind)")
      XCTAssertEqual(dim.layer?.cornerRadius, 0, "\(kind): the card's clip view rounds it, not the dim")
      XCTAssertNil(dim.hitTest(NSPoint(x: dim.frame.midX, y: dim.frame.midY)), "\(kind): clicks pass through")
      XCTAssertFalse(dim.isAccessibilityElement(), "\(kind): VoiceOver skips it")
      engine.navigate(tab, to: URL(string: "arkt-test://page/Next")!)
      XCTAssertNil(dim.superview, "\(kind): the engine's end takes the dim down")
    }
  }

  /// In a page's own superview, the dim sits directly above the page view, so whatever the shell draws over the page
  /// (added after it) stays over the dim.
  func testTheDimSitsDirectlyAboveThePageInItsSuperview() throws {
    let root = NSView(frame: page.frame)
    let card = NSView(frame: root.bounds)
    let inner = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 460))
    let toolbar = NSView(frame: NSRect(x: 0, y: 460, width: 700, height: 40))
    let pill = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
    let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 500))
    window.contentView = root
    root.addSubview(card)
    root.addSubview(sidebar)
    card.addSubview(inner)
    card.addSubview(toolbar)
    card.addSubview(pill)
    page = inner
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Over the page"))
    let dim = try pageDim()
    XCTAssertTrue(dim.superview === card)
    XCTAssertEqual(card.subviews.map { ObjectIdentifier($0) },
                   [inner, dim, toolbar, pill].map { ObjectIdentifier($0) }, "toolbar and pill stay over the dim")
    XCTAssertTrue(root.subviews.last === sidebar, "the sidebar stays over the card and its dim")
    XCTAssertEqual(dim.frame, inner.frame, "framed in the superview's coordinates, under the toolbar")
  }

  func testTheDimTakesTheDesignedColorInLightAndDark() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Hi"))
    let dim = try pageDim()
    for (name, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      dim.appearance = NSAppearance(named: name)
      dim.updateLayer()
      XCTAssertEqual(dim.layer?.backgroundColor, AlertTokens.pageDim.resolve(flavor).cgColor, "\(flavor)")
    }
  }

  /// Every exit path fades the dim out over 0.10 s, even where the panel itself goes at once.
  func testEveryExitPathFadesTheDimOut() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Answer"))
    var dim = try pageDim()
    try XCTUnwrap(presenter.panel(for: tab)).view.primaryButton.performClick(nil)
    assertLeaving(dim, "answer")

    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "End"))
    dim = try pageDim()
    engine.navigate(tab, to: URL(string: "arkt-test://page/Next")!)
    assertLeaving(dim, "engine end")

    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Hide"))
    dim = try pageDim()
    shown = false
    presenter.refresh()
    assertLeaving(dim, "tab hidden")
    shown = true
    presenter.refresh()

    dim = try pageDim()
    let released = try XCTUnwrap(presenter.release(tab))
    assertLeaving(dim, "release")
    presenter.adopt(released)

    dim = try pageDim()
    presenter.closeAll()
    assertLeaving(dim, "window closing")
  }

  /// A key answer and Reduce Motion take the panel down at once; the dim still fades.
  func testTheDimFadesOutAfterAKeyAnswerAndUnderReduceMotion() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Key"))
    var dim = try pageDim()
    var panel = try XCTUnwrap(presenter.panel(for: tab))
    panel.panel.cancelOperation(nil)
    XCTAssertEqual(engine.dialogAnswers.count, 1, "Escape answered the alert")
    XCTAssertNil(panel.panel.parent, "the panel left at once")
    assertLeaving(dim, "key answer")

    presenter.reduceMotion = { true }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Reduce"))
    dim = try pageDim()
    panel = try XCTUnwrap(presenter.panel(for: tab))
    panel.view.primaryButton.performClick(nil)
    XCTAssertNil(panel.panel.parent, "the panel left at once")
    assertLeaving(dim, "Reduce Motion")
  }

  /// A dialog that comes up while the last one's dim is leaving takes that dim back: never two dims on one page.
  func testAFollowUpDialogTakesTheLeavingDimBack() throws {
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "One"))
    let first = try pageDim()
    try XCTUnwrap(presenter.panel(for: tab)).view.primaryButton.performClick(nil)
    XCTAssertTrue(first.isLeaving)

    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Two"))
    let second = try pageDim()
    XCTAssertTrue(second === first, "the same dim")
    XCTAssertFalse(second.isLeaving)
    XCTAssertEqual(second.layer?.opacity, 1)
    XCTAssertEqual(page.subviews.filter { $0 is PageDimView }.count, 1)

    // A later dialog replacing a shown one keeps the one dim too.
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Three"))
    XCTAssertTrue(try pageDim() === first)
    XCTAssertFalse(first.isLeaving)
    XCTAssertEqual(page.subviews.filter { $0 is PageDimView }.count, 1)
  }

  func testTheTestSeamEndsTheFadeAtOnce() throws {
    presenter.dimExitDuration = 0
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Now"))
    let dim = try pageDim()
    try XCTUnwrap(presenter.panel(for: tab)).view.primaryButton.performClick(nil)
    XCTAssertNil(dim.superview)
  }

  /// The real fade ends and the dim is gone, with nothing holding the panel.
  func testAMouseAnswerLeavesNoDimBehind() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Click me"))
    weak let dim = try pageDim()
    let ok = try XCTUnwrap(presenter.panel(for: tab)?.view.primaryButton)
    ok.performClick(nil)
    waitUntil("the faded dim to leave the page") { dim?.superview == nil }
  }

  /// The dim fades in with the panel and only fades: opacity, never a transform, with or without Reduce Motion.
  func testTheDimFadesInWithThePanelAndNeverMoves() throws {
    presenter.dimExitDuration = 0
    for reduce in [false, true] {
      presenter.reduceMotion = { reduce }
      _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Fade"))
      let layer = try XCTUnwrap(try pageDim().layer)
      let fade = try XCTUnwrap(layer.animation(forKey: PageDimView.fadeKey) as? CABasicAnimation, "reduce: \(reduce)")
      XCTAssertEqual(fade.keyPath, "opacity")
      XCTAssertEqual(fade.duration, DialogMotion.panelIn(reduceMotion: reduce).fadeDuration)
      XCTAssertEqual(layer.animationKeys() ?? [], [PageDimView.fadeKey], "reduce: \(reduce): no travel")
      presenter.closeAll()
      engine.navigate(tab, to: URL(string: "arkt-test://page/Next")!)
    }
  }

  func testTheDimFollowsThePage() throws {
    let inner = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    inner.autoresizingMask = []
    page.addSubview(inner)
    page = inner
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Sure?"))
    inner.setFrameSize(NSSize(width: 400, height: 300))
    XCTAssertEqual(try screenFrame(of: try pageDim()), anchorFrame())
  }

  /// The infobar rows stay clear: the dim and the panel start below them, and follow their height on a refresh.
  func testTheDimLeavesTheInfobarRowsClear() throws {
    presenter.host.topInset = { _ in 40 }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Under a row"))
    let dim = try pageDim()
    var below = anchorFrame()
    below.size.height -= 40
    XCTAssertEqual(try screenFrame(of: dim), below, "the dim starts below the rows")
    XCTAssertEqual(try XCTUnwrap(presenter.panel(for: tab)).panel.frame.maxY, below.maxY, "so does the panel")

    presenter.host.topInset = { _ in 80 }
    presenter.refresh()
    below.size.height -= 40
    XCTAssertEqual(try screenFrame(of: dim), below, "a second row arrived")
    XCTAssertTrue(try pageDim() === dim)
  }

  // MARK: Remaining dim gaps (#708)

  /// The dim covers the page view the host placed the panel on: the presenter takes it from the host instead of asking
  /// the anchor closure a second time, which could answer differently.
  func testTheDimCoversThePageTheHostPlacedThePanelOn() throws {
    var asks = 0
    presenter = JavaScriptDialogPresenter(engine: engine, anchor: { [unowned self] _ in
      asks += 1
      return page
    }, windowIsVisible: { _ in true })
    presenter.reduceMotion = { true }
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Once"))
    XCTAssertTrue(try pageDim().page === page)
    XCTAssertEqual(asks, 1, "one placement asks the anchor once")
  }

  /// A real appearance change of the window redraws the dim in the new appearance's color when Core Animation next
  /// commits, with no direct `updateLayer()` call. (`needsDisplay` cannot show it: an `updateLayer` view reports
  /// false, and its layer's flag stays set until the commit.)
  func testAWindowAppearanceChangeRedrawsTheDim() throws {
    window.appearance = NSAppearance(named: .aqua)
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Appearance"))
    let dim = try pageDim()
    CATransaction.flush()
    XCTAssertEqual(dim.layer?.backgroundColor, AlertTokens.pageDim.resolve(.light).cgColor)

    for (name, flavor) in [(NSAppearance.Name.darkAqua, ThemeFlavor.dark), (.aqua, .light)] {
      window.appearance = NSAppearance(named: name)
      CATransaction.flush()
      XCTAssertEqual(dim.layer?.backgroundColor, AlertTokens.pageDim.resolve(flavor).cgColor, "\(flavor)")
    }
  }

  /// Minimising the window takes the panel down unanswered and fades the dim out; the dialog stays pending and comes
  /// back over one dim when the window does. The window state is injected and the notifications are the ones AppKit
  /// posts, so nothing waits on the Dock animation.
  func testMinimisingTheWindowFadesTheDimAndTheWindowComingBackDimsAgain() throws {
    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Minimise"))
    let panel = try XCTUnwrap(presenter.panel(for: tab))
    let dim = try pageDim()

    windowVisible = false                                       // what `isVisible` reads while minimised
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)

    XCTAssertNil(presenter.panel(for: tab), "the panel went down with the window")
    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(panel.pageDim)
    assertLeaving(dim, "minimise")
    XCTAssertEqual(presenter.pending[tab]?.id, id, "still pending")
    XCTAssertTrue(engine.dialogAnswers.isEmpty, "no answer")

    windowVisible = true
    NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)

    XCTAssertNotNil(presenter.panel(for: tab), "the dialog is back")
    XCTAssertTrue(try pageDim() === dim, "the leaving dim is taken back")
    XCTAssertFalse(dim.isLeaving)
    XCTAssertEqual(dim.layer?.opacity, 1)
    XCTAssertEqual(page.subviews.filter { $0 is PageDimView }.count, 1, "one dim")
    XCTAssertTrue(engine.dialogAnswers.isEmpty)
  }
}
