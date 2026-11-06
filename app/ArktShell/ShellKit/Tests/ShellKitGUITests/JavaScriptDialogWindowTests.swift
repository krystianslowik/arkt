import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A page's dialog in the shell window (#400): the window's tab events reach the presenter, the panel sits over the
/// tab that is shown and follows the tab switching, and an answer reaches the engine.
@MainActor
final class JavaScriptDialogWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var first: NodeID!
  private var second: NodeID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    first = try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .today(space))
    second = try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine,
                                       sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.javaScriptDialogs.reduceMotion = { true }
  }

  override func tearDown() async throws {
    controller.close()
  }

  func testTheShownTabsDialogGetsAPanelOverTheWindow() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)

    let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .confirm, message: "Delete it?"))

    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    XCTAssertTrue(controller.window?.childWindows?.contains(panel.panel) == true)
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.dialogAnswers.map(\.id), [id])
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testSwitchingTabsHidesTheDialogWithoutAnsweringAndShowingTheTabBringsItBack() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Saved")
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))

    controller.activate(node: second)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab), "the page is off screen: no panel")
    XCTAssertNotNil(controller.javaScriptDialogs.pending[tab], "still pending: the page may be waiting")
    XCTAssertTrue(engine.dialogAnswers.isEmpty)

    controller.activate(node: first)
    XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab))
  }

  func testAClosingWindowTakesItsPanelsDown() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = engine.raiseDialog(in: tab, kind: .alert, message: "Bye")
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))

    controller.window?.close()

    XCTAssertNil(panel.panel.parent)
    XCTAssertNil(controller.javaScriptDialogs.panel(for: tab))
  }

  // MARK: Tab switching with the panel key

  /// A real click on a sidebar row, through the window's own event dispatch (the first-click rule included).
  private func clickRow(of node: NodeID) throws {
    let window = try XCTUnwrap(controller.window)
    let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    let view = outline.outlineView
    window.contentView?.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    let rect = view.rect(ofRow: outline.row(for: node))
    let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    func event(_ type: NSEvent.EventType) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1))
    }
    window.postEvent(try event(.leftMouseUp), atStart: true)
    window.sendEvent(try event(.leftMouseDown))
    window.discardEvents(matching: [.leftMouseUp], before: nil)
  }

  /// The panel is key while a dialog is up, so the shell window is not: the first click on a row must still be the
  /// click, not only a re-key (the real app: one click switched with an alert and with a confirm up). The window is
  /// not key in this runner either, so the event goes through `NSWindow.sendEvent` as a first click does.
  func testOneClickOnARowSwitchesTabsWithADialogUp() throws {
    let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController).outlineView
    let probe = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    XCTAssertTrue(outline.acceptsFirstMouse(for: probe), "a click on a row while another of our windows is key")

    for kind in [JavaScriptDialog.Kind.alert, .confirm] {
      controller.activate(node: first)
      let tab = try XCTUnwrap(controller.currentTab)
      let id = try XCTUnwrap(engine.raiseDialog(in: tab, kind: kind, message: "Now?"))
      XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab), "\(kind): the dialog is up")

      try clickRow(of: second)

      XCTAssertEqual(controller.currentTab, controller.engineTab(of: second), "\(kind): one click switches")
      XCTAssertNil(controller.javaScriptDialogs.panel(for: tab), "\(kind): the page is off screen: no panel")
      if kind == .alert {
        XCTAssertEqual(controller.javaScriptDialogs.pending[tab]?.id, id, "an alert stays attached")
        controller.activate(node: first)
        XCTAssertNotNil(controller.javaScriptDialogs.panel(for: tab), "and reappears on return")
        engine.respond(to: id, accepted: true, userInput: nil)
      } else {
        XCTAssertNil(controller.javaScriptDialogs.pending[tab], "a confirm ends on switch-away, as in Chromium")
        XCTAssertEqual(engine.dialogAnswers.count, 1, "only the alert was answered: the engine ended the confirm")
      }
    }
  }

  // MARK: The page dim in the window (#693)

  /// Whether `top` is drawn over `bottom`: under their nearest common ancestor, `top`'s branch comes later.
  private func isDrawn(_ top: NSView, over bottom: NSView) -> Bool {
    func chain(_ view: NSView) -> [NSView] {
      var views: [NSView] = []
      var current: NSView? = view
      while let next = current { views.insert(next, at: 0); current = next.superview }
      return views
    }
    let a = chain(top), b = chain(bottom)
    var depth = 0
    while depth < min(a.count, b.count), a[depth] === b[depth] { depth += 1 }
    guard depth > 0, depth < a.count, depth < b.count else { return false }
    let siblings = a[depth - 1].subviews
    guard let ia = siblings.firstIndex(where: { $0 === a[depth] }),
          let ib = siblings.firstIndex(where: { $0 === b[depth] }) else { return false }
    return ia > ib
  }

  private func dimmedPage() throws -> (tab: TabID, page: NSView, dim: PageDimView) {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Dimmed"))
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let dim = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab)?.pageDim)
    return (tab, page, dim)
  }

  /// The dim sits directly above the page in the card, so the card's own surfaces, the slid-out sidebar and the Peek
  /// stay over it.
  func testTheDimSitsUnderTheCardsSurfacesTheSidebarAndThePeek() throws {
    let (tab, page, dim) = try dimmedPage()
    let card = controller.rootView.card
    XCTAssertTrue(dim.superview === page.superview, "in the page's own superview")
    XCTAssertTrue(isDrawn(dim, over: page))
    XCTAssertTrue(isDrawn(card.toolbar, over: dim), "the Toolbar")
    XCTAssertTrue(isDrawn(controller.rootView.sidebarOverlay, over: dim), "the slid-out sidebar")

    controller.peek.open(try XCTUnwrap(URL(string: "https://example.com/peeked")), from: tab)
    let overlay = try XCTUnwrap(controller.peek.overlay, "the Peek opened")
    XCTAssertTrue(isDrawn(overlay, over: dim), "the Peek card")
  }

  /// Under the Toolbar the dim starts at the page's top, below the Toolbar, with square corners: the card's clip
  /// view rounds the card, not the dim.
  func testTheDimsTopEdgeIsSquareUnderTheToolbar() throws {
    let card = controller.rootView.card
    card.showsToolbar = true
    card.layoutSubtreeIfNeeded()
    let (_, page, dim) = try dimmedPage()
    controller.javaScriptDialogs.refresh()
    XCTAssertFalse(card.toolbar.isHidden)
    XCTAssertEqual(dim.frame, page.frame, "the page's frame in the same superview")
    XCTAssertLessThanOrEqual(dim.frame.maxY, card.toolbar.frame.minY + 0.5, "below the Toolbar")
    XCTAssertEqual(dim.layer?.cornerRadius, 0)
  }

  private func screenFrame(of view: NSView) throws -> NSRect {
    try XCTUnwrap(view.window).convertToScreen(view.convert(view.bounds, to: nil))
  }

  /// A row arriving while the dialog is up pushes the panel and the dim below it; the same dim stays.
  func testARowArrivingWhileADialogIsUpMovesThePanelAndTheDimBelowIt() throws {
    let (tab, page, dim) = try dimmedPage()
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    let pageTop = try screenFrame(of: page).maxY
    XCTAssertEqual(try screenFrame(of: dim).maxY, pageTop, accuracy: 0.5, "no row: the dim reaches the page's top")

    engine.raiseInfobar(in: tab, message: "One")
    let strip = try XCTUnwrap(controller.infobarStrips.strip(for: tab))
    let rowsBottom = pageTop - InfobarMetrics.rowHeight
    XCTAssertEqual(strip.panel.frame.minY, rowsBottom, accuracy: 0.5)
    XCTAssertEqual(panel.panel.frame.maxY, rowsBottom, accuracy: 0.5, "the panel hangs below the row")
    XCTAssertEqual(try screenFrame(of: dim).maxY, rowsBottom, accuracy: 0.5, "the dim leaves the row clear")
    XCTAssertTrue(panel.pageDim === dim, "the same dim, moved")
    XCTAssertFalse(dim.isLeaving)
  }

  /// HTML fullscreen hides the rows: the panel and the dim go up to the page's top, and back below the rows after.
  func testHTMLFullscreenWithADialogUpMovesThePanelAndTheDimToThePagesTop() throws {
    controller.activate(node: first)
    let tab = try XCTUnwrap(controller.currentTab)
    engine.raiseInfobar(in: tab, message: "One")
    engine.raiseInfobar(in: tab, message: "Two")
    _ = try XCTUnwrap(engine.raiseDialog(in: tab, kind: .alert, message: "Dimmed"))
    let panel = try XCTUnwrap(controller.javaScriptDialogs.panel(for: tab))
    let dim = try XCTUnwrap(panel.pageDim)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let pageTop = try screenFrame(of: page).maxY
    let rowsBottom = pageTop - 2 * InfobarMetrics.rowHeight
    XCTAssertEqual(try screenFrame(of: dim).maxY, rowsBottom, accuracy: 0.5)

    engine.setTabFullscreen(tab, true)
    XCTAssertNil(controller.infobarStrips.strip(for: tab), "no row in HTML fullscreen")
    XCTAssertEqual(panel.panel.frame.maxY, pageTop, accuracy: 0.5, "the panel at the page's top")
    XCTAssertEqual(try screenFrame(of: dim).maxY, pageTop, accuracy: 0.5, "the dim covers the whole page")

    engine.setTabFullscreen(tab, false)
    XCTAssertNotNil(controller.infobarStrips.strip(for: tab))
    XCTAssertEqual(panel.panel.frame.maxY, rowsBottom, accuracy: 0.5, "back below the rows")
    XCTAssertEqual(try screenFrame(of: dim).maxY, rowsBottom, accuracy: 0.5)
    XCTAssertTrue(panel.pageDim === dim)
  }
}
