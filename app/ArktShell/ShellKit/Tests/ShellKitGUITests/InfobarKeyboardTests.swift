import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// F6 into a tab's infobar strip (#478, maintainer decision 2026-11-13): F6 from the page puts the keyboard on the
/// strip's first control; Tab and Shift-Tab go through every control of every row, Left and Right along the row, Up and
/// Down between rows; Return, Enter and Space press; Esc and F6 give the keyboard back to the page. The strip never
/// takes the keyboard on its own, and its keys go to the strip, not to a focused field. Keys are delivered to the
/// strip's stack view in the process; nothing is posted to the system.
/// A browser window stand-in that records the window commands instead of closing, minimizing, zooming or going full
/// screen, and enables them for the menu.
@MainActor
private final class RecordingWindow: NSWindow {
  var actions: [Selector] = []
  var validated: [Selector] = []
  override func performClose(_ sender: Any?) { actions.append(#selector(performClose(_:))) }
  override func performMiniaturize(_ sender: Any?) { actions.append(#selector(performMiniaturize(_:))) }
  override func performZoom(_ sender: Any?) { actions.append(#selector(performZoom(_:))) }
  override func toggleFullScreen(_ sender: Any?) { actions.append(#selector(toggleFullScreen(_:))) }
  override func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if let action = item.action { validated.append(action) }
    return true
  }
}

@MainActor
final class InfobarKeyboardTests: XCTestCase {
  private var window: RecordingWindow!
  private var page: NSView!
  private var field: NSTextField!
  private var engine: InMemoryEngine!
  private var tab: TabID!
  private var presenter: InfobarPresenter!
  private var observation: EngineObservation?
  /// The tabs whose page the presenter gave the keyboard back to, in order.
  private var pageFocused: [TabID] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = RecordingWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500), styleMask: [.titled],
                      backing: .buffered, defer: false)
    page = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
    page.addSubview(field)
    window.contentView = page
    window.orderFront(nil)
    engine = InMemoryEngine()
    let engineWindow = engine.createWindow(host: StubWindowHost())
    tab = engine.createTab(url: URL(string: "arkt-test://example.com/Keyboard")!, in: engineWindow)
    engine.activateTab(tab)
    presenter = InfobarPresenter(engine: engine, anchor: { [unowned self] _ in page }, windowIsVisible: { _ in true })
    presenter.reduceMotion = { true }
    presenter.announce = { _, _ in }
    presenter.focusPage = { [unowned self] tab in pageFocused.append(tab) }
    observation = engine.observe { [unowned self] in presenter.handle($0) }
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    observation?.cancel()
    presenter.closeAll()
    window.isReleasedWhenClosed = false
    window.close()
    presenter = nil
    field = nil
    page = nil
    window = nil
    engine = nil
  }

  private func strip() throws -> InfobarPanel { try XCTUnwrap(presenter.strip(for: tab)) }

  /// A key down for the strip, delivered the way the strip's window delivers it to its first responder.
  private func press(_ keyCode: UInt16, _ characters: String = "", shift: Bool = false) throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0,
      windowNumber: try strip().panel.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    try strip().stack.keyDown(with: event)
  }

  private enum Key {
    static let tab: UInt16 = 48, returnKey: UInt16 = 36, enter: UInt16 = 76, space: UInt16 = 49
    static let escape: UInt16 = 53, f6: UInt16 = 97
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
  }

  /// The title or label of the control the keyboard is on.
  private func focused() throws -> String? {
    guard let control = try strip().keyboardFocusedControl else { return nil }
    return control.accessibilityLabel()
  }

  /// The controls whose focus ring is on, by label, across the strip.
  private func rings() throws -> [String] {
    try strip().rows.flatMap { row in
      [row.linkButton, row.okButton, row.cancelButton, row.closeButton].compactMap { $0 }
        .filter { InfobarRowView.ring(of: $0)?.isFocused == true }
        .compactMap { $0.accessibilityLabel() }
    }
  }

  // MARK: In and out

  func testTheStripTakesNoKeyboardUntilF6() throws {
    engine.raiseInfobar(in: tab, message: "One")
    XCTAssertNil(try strip().keyboardFocus)
    XCTAssertFalse(try strip().stack.acceptsFirstResponder, "the stack refuses the keyboard on its own")
    XCTAssertEqual(try rings(), [])
  }

  func testF6PutsTheKeyboardOnTheFirstControlAndOnlyThereIsARing() throws {
    engine.raiseInfobar(in: tab, message: "One")
    XCTAssertTrue(presenter.focusStrip(of: tab, holding: nil))
    XCTAssertEqual(try focused(), "OK")
    XCTAssertEqual(try rings(), ["OK"])
    XCTAssertTrue(try strip().panel.firstResponder === (try strip().stack), "keys go to the strip's controller")
  }

  func testEscGivesTheKeyboardBackToThePage() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.escape, "\u{1b}")
    XCTAssertNil(try strip().keyboardFocus)
    XCTAssertEqual(try rings(), [])
    XCTAssertEqual(pageFocused, [tab])
    XCTAssertFalse(try strip().stack.acceptsFirstResponder)
  }

  func testF6AgainGivesTheKeyboardBackToThePage() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.f6)
    XCTAssertNil(try strip().keyboardFocus)
    XCTAssertEqual(pageFocused, [tab])
  }

  func testWithoutANamedTabTheTabWhosePageHoldsTheKeyboardIsFound() throws {
    engine.raiseInfobar(in: tab, message: "One")
    XCTAssertFalse(presenter.focusStrip(of: nil, holding: window), "the keyboard is not in a page: nothing")
    XCTAssertNil(try strip().keyboardFocus)
    XCTAssertTrue(presenter.focusStrip(of: nil, holding: field), "a field inside the page counts as the page")
    XCTAssertEqual(try focused(), "OK")
  }

  func testATabWithoutAStripOrWithNothingToReachKeepsTheKeyboard() throws {
    XCTAssertFalse(presenter.focusStrip(of: tab, holding: nil), "no infobar")
    engine.raiseInfobar(in: tab, message: "Note", okTitle: nil, cancelTitle: nil, isCloseable: false)
    XCTAssertFalse(presenter.focusStrip(of: tab, holding: nil), "an infobar with no control")
    XCTAssertNil(try strip().keyboardFocus)
  }

  // MARK: Moving

  func testTabAndShiftTabGoThroughEveryControlOfEveryRowAndAround() throws {
    engine.raiseInfobar(in: tab, message: "One")
    engine.raiseInfobar(in: tab, message: "Two", cancelTitle: nil)
    presenter.focusStrip(of: tab, holding: nil)
    var order: [String?] = [try focused()]
    for _ in 0..<5 {
      try press(Key.tab, "\t")
      order.append(try focused())
    }
    XCTAssertEqual(order, ["OK", "Cancel", "Close", "OK", "Close", "OK"], "row one, row two, then around")
    XCTAssertEqual(try strip().keyboardFocus?.id, try strip().rows[0].infobar.id)
    try press(Key.tab, "\t", shift: true)
    XCTAssertEqual(try focused(), "Close")
    XCTAssertEqual(try strip().keyboardFocus?.id, try strip().rows[1].infobar.id, "Shift-Tab goes back around")
    XCTAssertEqual(try rings(), ["Close"])
  }

  func testLeftAndRightGoAlongTheRowAndUpAndDownBetweenRows() throws {
    engine.raiseInfobar(in: tab, message: "One")
    engine.raiseInfobar(in: tab, message: "Two")
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.right)
    XCTAssertEqual(try focused(), "Cancel")
    try press(Key.down)
    XCTAssertEqual(try strip().keyboardFocus?.id, try strip().rows[1].infobar.id)
    XCTAssertEqual(try focused(), "Cancel", "the same place in the next row")
    try press(Key.down)
    XCTAssertEqual(try strip().keyboardFocus?.id, try strip().rows[1].infobar.id, "the last row stays")
    try press(Key.left)
    try press(Key.left)
    XCTAssertEqual(try focused(), "Close", "Left goes around within the row")
    try press(Key.up)
    XCTAssertEqual(try strip().keyboardFocus?.id, try strip().rows[0].infobar.id)
    XCTAssertEqual(try focused(), "Close")
  }

  func testRightToLeftMirrorsLeftAndRight() throws {
    engine.raiseInfobar(in: tab, message: "One")
    try strip().stack.userInterfaceLayoutDirection = .rightToLeft
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.left)
    XCTAssertEqual(try focused(), "Cancel", "Left moves on, as reading goes right to left")
    try press(Key.right)
    XCTAssertEqual(try focused(), "OK")
  }

  func testADisabledControlIsSkipped() throws {
    let infobar = Infobar(id: InfobarID(), tab: tab, message: "One", ok: InfobarButton(title: "OK", isEnabled: false),
                          cancel: InfobarButton(title: "Cancel"), closeLabel: "Close")
    presenter.handle(.infobarsChanged(tab, [infobar]))
    presenter.focusStrip(of: tab, holding: nil)
    XCTAssertEqual(try focused(), "Cancel")
    try press(Key.tab, "\t")
    XCTAssertEqual(try focused(), "Close")
    try press(Key.tab, "\t")
    XCTAssertEqual(try focused(), "Cancel")
  }

  func testTheTrailingLinkIsReachedInReadingOrder() throws {
    let after = Infobar(id: InfobarID(), tab: tab, message: "One", linkTitle: "Learn more",
                        ok: InfobarButton(title: "OK"), closeLabel: "Close")
    let before = Infobar(id: InfobarID(), tab: tab, message: "Two", linkTitle: "Details", linkBeforeButtons: true,
                         ok: InfobarButton(title: "Allow"))
    presenter.handle(.infobarsChanged(tab, [after, before]))
    presenter.focusStrip(of: tab, holding: nil)
    var order: [String?] = [try focused()]
    for _ in 0..<4 {
      try press(Key.tab, "\t")
      order.append(try focused())
    }
    XCTAssertEqual(order, ["OK", "Learn more", "Close", "Details", "Allow"])
  }

  func testOtherKeysAndShortcutsAreNotTheStrips() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    let strip = try strip()
    let letter = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: strip.panel.windowNumber,
      context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
    XCTAssertEqual(strip.stack.keyHandler?(letter), false)
    let commandTab = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: strip.panel.windowNumber,
      context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: Key.tab))
    XCTAssertEqual(strip.stack.keyHandler?(commandTab), false, "a shortcut with Command goes on to the menu")
    XCTAssertEqual(try focused(), "OK")
  }

  // MARK: Pressing

  func testReturnEnterAndSpacePressTheControl() throws {
    for (key, characters, expected) in [(Key.returnKey, "\r", InfobarAction.ok), (Key.enter, "\u{3}", .cancel),
                                        (Key.space, " ", .close)] {
      let id = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Row"))
      presenter.focusStrip(of: tab, holding: nil)
      if expected == .cancel { try press(Key.right) }
      if expected == .close { try press(Key.left) }
      try press(key, characters)
      XCTAssertEqual(engine.infobarActions.last?.id, id)
      XCTAssertEqual(engine.infobarActions.last?.action, expected)
    }
    XCTAssertEqual(engine.infobarActions.count, 3)
  }

  // MARK: The list changes under the keyboard

  func testWhenTheFocusedRowGoesTheKeyboardMovesToTheRowThatIsLeft() throws {
    engine.raiseInfobar(in: tab, message: "One")
    let second = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Two"))
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.returnKey, "\r")                               // OK on row one: the engine removes it
    XCTAssertEqual(try strip().rows.map(\.infobar.message), ["Two"])
    XCTAssertEqual(try strip().keyboardFocus?.id, second)
    XCTAssertEqual(try focused(), "OK")
    XCTAssertEqual(try rings(), ["OK"])
    XCTAssertEqual(pageFocused, [], "the strip still holds the keyboard")
  }

  func testWhenTheLastRowGoesThePageGetsTheKeyboardBack() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    try press(Key.returnKey, "\r")
    XCTAssertNil(presenter.strip(for: tab))
    XCTAssertEqual(pageFocused, [tab])
  }

  func testATabThatLeavesTheScreenDoesNotTakeTheKeyboardBack() throws {
    var shown = true
    presenter = InfobarPresenter(engine: engine, anchor: { [unowned self] _ in shown ? page : nil },
                                 windowIsVisible: { _ in true })
    presenter.reduceMotion = { true }
    presenter.announce = { _, _ in }
    presenter.focusPage = { [unowned self] tab in pageFocused.append(tab) }
    observation?.cancel()
    observation = engine.observe { [unowned self] in presenter.handle($0) }
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    shown = false
    presenter.refresh()
    XCTAssertNil(presenter.strip(for: tab))
    XCTAssertEqual(pageFocused, [], "the tab is off screen: its page does not take the keyboard")
  }

  // MARK: The browser window's commands while the strip holds the keyboard (#478 review)

  private static let windowCommands: [Selector] = [
    #selector(NSWindow.performClose(_:)), #selector(NSWindow.performMiniaturize(_:)),
    #selector(NSWindow.performZoom(_:)), #selector(NSWindow.toggleFullScreen(_:)),
  ]

  func testCloseMinimizeZoomAndFullScreenReachTheBrowserWindowNotTheStrip() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    let panel = try strip().panel
    XCTAssertTrue(panel.parent === window)
    for action in Self.windowCommands {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      XCTAssertTrue(panel.validateMenuItem(item), "\(action) is enabled as the browser window says")
      XCTAssertTrue(NSApp.sendAction(action, to: panel, from: item), "\(action) is taken")
    }
    XCTAssertEqual(window.validated, Self.windowCommands, "the browser window validated each item")
    XCTAssertEqual(window.actions, Self.windowCommands, "and ran each command")
    XCTAssertTrue(panel.isVisible, "the strip itself did not close")
  }

  func testOtherMenuItemsAreStillValidatedByTheStripItself() throws {
    engine.raiseInfobar(in: tab, message: "One")
    let panel = try strip().panel
    let item = NSMenuItem(title: "", action: #selector(NSWindow.makeKeyAndOrderFront(_:)), keyEquivalent: "")
    _ = panel.validateMenuItem(item)
    XCTAssertEqual(window.validated, [], "only the window commands go to the browser window")
  }

  // MARK: Losing the keyboard to another window

  func testAnotherWindowTakingTheKeyboardDropsTheRingAndLeavesThePageAlone() throws {
    engine.raiseInfobar(in: tab, message: "One")
    presenter.focusStrip(of: tab, holding: nil)
    try strip().panel.resignKey()
    XCTAssertNil(try strip().keyboardFocus)
    XCTAssertEqual(try rings(), [])
    XCTAssertFalse(try strip().stack.acceptsFirstResponder)
    XCTAssertEqual(pageFocused, [], "the window that took the keyboard keeps it")
  }

  // MARK: The shortcut

  func testOnlyAPlainF6IsTheStripShortcut() throws {
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
      try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                     isARepeat: false, keyCode: code))
    }
    XCTAssertTrue(InfobarPanel.isStripShortcut(try key(Key.f6, [])))
    XCTAssertTrue(InfobarPanel.isStripShortcut(try key(Key.f6, [.function])), "Fn-F6 on a Mac keyboard")
    for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
      XCTAssertFalse(InfobarPanel.isStripShortcut(try key(Key.f6, flags)), "\(flags)")
    }
    XCTAssertFalse(InfobarPanel.isStripShortcut(try key(Key.escape, [])))
  }
}
