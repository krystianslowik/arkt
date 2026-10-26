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
    presenter = JavaScriptDialogPresenter(engine: engine) { [unowned self] _ in shown ? page : nil }
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
}
