import AppKit
import Carbon.HIToolbox
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import FakeEngineKit
@testable import ShellUI

/// KB-031, KB-032 (#948): Cmd-Left and Cmd-Right go back and forward, as in Chrome and Safari, except while the
/// keyboard is in editable text, where they move the caret to the line start or end. Each key press runs in AppKit's
/// order (`NSApplication.sendEvent`): the event's window's key equivalents, then the real main menu, then `keyDown` on
/// the first responder.
@MainActor
final class HistoryArrowKeyTests: XCTestCase {
  private var savedMenu: NSMenu?
  private var windows: [NSWindow] = []
  private var executed: [EngineCommand] = []
  /// The window holds its command host weakly.
  private var hosts: [ShellEngineHost] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedMenu = NSApp.mainMenu
  }

  override func tearDown() async throws {
    NSApp.mainMenu = savedMenu
    windows.forEach { $0.close() }
    windows = []
    hosts = []
  }

  /// The app's main menu, its History items aimed at `window` (tests have no key window for nil-target actions to
  /// resolve through).
  private func installMenu(aimedAt window: NSWindow) throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let history = try XCTUnwrap(menu.items.first { $0.title == "History" }?.submenu)
    history.items.forEach { $0.target = window }
    NSApp.mainMenu = menu
  }

  /// A shell window whose engine runs every command (recorded in `executed`), and a page view that takes every key
  /// equivalent first, as `RenderWidgetHostViewCocoa` does.
  private func makeShellWindow() -> (ShellWindow, PageView) {
    let window = ShellWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600))
    windows.append(window)
    let host = ShellEngineHost(window: window, cardView: NSView())
    host.forward = EngineCommandForwarding(validate: { _ in true },
                                           execute: { [weak self] command, _ in self?.executed.append(command) })
    window.commandHost = host
    hosts.append(host)
    let page = PageView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    window.contentView?.addSubview(page)
    return (window, page)
  }

  /// A text field being edited in `window`, the caret after its last character.
  private func editingField(in window: NSWindow) throws -> NSTextView {
    let field = NSTextField(frame: NSRect(x: 10, y: 400, width: 300, height: 24))
    field.stringValue = "arkt.dev/history"
    window.contentView?.addSubview(field)
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = try XCTUnwrap(window.firstResponder as? NSTextView, "the field editor has the keyboard")
    editor.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
    return editor
  }

  /// A key-down for `keyCode` in `window`, built from a Quartz event as AppKit does.
  private func key(_ keyCode: Int, _ flags: CGEventFlags, in window: NSWindow) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let cg = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    cg.flags = flags
    let raw = try XCTUnwrap(NSEvent(cgEvent: cg))
    return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: raw.modifierFlags,
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          characters: raw.characters ?? "",
                                          charactersIgnoringModifiers: raw.charactersIgnoringModifiers ?? "",
                                          isARepeat: false, keyCode: raw.keyCode))
  }

  /// `NSApplication.sendEvent` for a key-down with Cmd: the window, then the main menu, then the first responder
  /// (`NSWindow.sendEvent` drops key events in a window that is not key, and test windows never are).
  private func press(_ keyCode: Int, _ flags: CGEventFlags = .maskCommand, in window: NSWindow) throws {
    let event = try key(keyCode, flags, in: window)
    if window.performKeyEquivalent(with: event) { return }
    if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
    window.firstResponder?.keyDown(with: event)
  }

  func testCommandLeftAndRightGoBackAndForwardFromAPageThatLeftThem() throws {
    let (window, page) = makeShellWindow()
    try installMenu(aimedAt: window)
    XCTAssertTrue(window.makeFirstResponder(page))

    try press(kVK_LeftArrow, in: window)
    try press(kVK_RightArrow, in: window)

    XCTAssertEqual(page.keyEquivalents, 2, "the page saw each key first")
    XCTAssertEqual(executed, [.back, .forward])
  }

  /// Not reserved: a page whose text field moves the caret on Cmd-Left keeps the key, and the menu never sees it.
  func testAPageThatUsesTheKeysKeepsThem() throws {
    let (window, page) = makeShellWindow()
    try installMenu(aimedAt: window)
    XCTAssertTrue(window.makeFirstResponder(page))
    page.usesKeys = true

    try press(kVK_LeftArrow, in: window)
    try press(kVK_RightArrow, in: window)

    XCTAssertEqual(page.keyEquivalents, 2)
    XCTAssertEqual(executed, [])
  }

  /// The address bar, a rename field: the field editor moves the caret, and nothing goes back.
  func testAShellTextFieldKeepsTheKeysForTheCaret() throws {
    let (window, _) = makeShellWindow()
    try installMenu(aimedAt: window)
    let editor = try editingField(in: window)

    try press(kVK_LeftArrow, in: window)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0), "Cmd-Left moved to the line start")
    try press(kVK_RightArrow, in: window)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 16, length: 0), "Cmd-Right moved to the line end")

    XCTAssertEqual(executed, [])
  }

  /// The command bar is its own panel: its field keeps the keys although the shell window behind it holds a page.
  func testTheCommandBarFieldKeepsTheKeysForTheCaret() throws {
    let (window, page) = makeShellWindow()
    try installMenu(aimedAt: window)
    XCTAssertTrue(window.makeFirstResponder(page))
    let panel = CommandBarPanel()
    windows.append(panel)
    let editor = try editingField(in: panel)

    try press(kVK_LeftArrow, in: panel)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
    try press(kVK_RightArrow, in: panel)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 16, length: 0))

    XCTAssertEqual(executed, [])
    XCTAssertEqual(page.keyEquivalents, 0)
  }

  /// Shift-Cmd-Left selects to the line start in a field and is not Back anywhere.
  func testShiftCommandLeftIsNotBack() throws {
    let (window, page) = makeShellWindow()
    try installMenu(aimedAt: window)
    XCTAssertTrue(window.makeFirstResponder(page))

    try press(kVK_LeftArrow, [.maskCommand, .maskShift], in: window)

    XCTAssertEqual(executed, [])
  }

  /// Through AppKit's own dispatch (`NSApplication.sendEvent`, which asks the main menu itself): Cmd-Left goes back
  /// while a view that is not text has the keyboard, and not while a field is being edited. (The caret move is not
  /// checked here: without a key window AppKit drops the `keyDown`, as the other tests show it lands.)
  func testAppKitsDispatchReachesTheHistoryMenuOnlyOutsideText() throws {
    let (window, page) = makeShellWindow()
    try installMenu(aimedAt: window)
    page.usesKeys = true
    XCTAssertTrue(window.makeFirstResponder(window.contentView))

    NSApp.sendEvent(try key(kVK_LeftArrow, .maskCommand, in: window))
    XCTAssertEqual(executed, [.back])

    _ = try editingField(in: window)
    NSApp.sendEvent(try key(kVK_LeftArrow, .maskCommand, in: window))
    XCTAssertEqual(executed, [.back], "the field keeps Cmd-Left")
  }

  /// The FakeEngine build: WKWebView counts as editing text only while a page field has the focus, so the History
  /// menu takes Cmd-Left from a page that only shows text and leaves it to a focused input.
  func testAWebKitPageEditsTextOnlyWithAFieldFocused() throws {
    let engine = FakeEngine()
    let host = StubWindowHost()
    let engineWindow = engine.createWindow(host: host)
    defer { engine.closeWindow(engineWindow) }
    let url = try XCTUnwrap(URL(string: "data:text/html,%3Ctitle%3Eh%3C/title%3E%3Cp%3Eh%3C/p%3E%3Cinput%20id=f%3E"))
    let tab = engine.createTab(url: url, in: engineWindow)
    engine.activateTab(tab)
    waitUntil("the page loaded") { engine.snapshot(of: tab).map { !$0.isLoading && $0.title == "h" } ?? false }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    page.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    window.contentView?.addSubview(page)
    XCTAssertTrue(window.makeFirstResponder(page))

    XCTAssertFalse(HistoryMenu.editsText(windowNumber: window.windowNumber), "no field has the focus")
    Task { await engine.runScript("document.getElementById('f').focus()", in: tab) }
    waitUntil("the page's field has the focus") { HistoryMenu.editsText(windowNumber: window.windowNumber) }
  }
}

/// Takes every key equivalent first while it has the keyboard, as a focused web page does
/// (`RenderWidgetHostViewCocoa` answers only as first responder). A page that does not use the key hands it to the
/// main menu, as the engine does (`ArktBrowserWindow::HandleKeyboardEvent`) and WKWebView does by sending it again.
@MainActor
private final class PageView: NSView {
  var keyEquivalents = 0
  var usesKeys = false
  override var acceptsFirstResponder: Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self else { return false }
    keyEquivalents += 1
    if !usesKeys { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
    return true
  }
}
