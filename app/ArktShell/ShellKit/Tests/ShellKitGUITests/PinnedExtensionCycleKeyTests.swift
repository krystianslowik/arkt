import AppKit
import Carbon.HIToolbox
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Cmd-E cycles the pinned extensions (KB-047, #599) in a real shell window over an `InMemoryEngine`, driven by an
/// injected key sequence. The first tap takes the window's route: Cmd-E is reserved, so it reaches the main menu
/// before a focused page or field, and the item runs the controller's action. While Command stays down, the next taps
/// and the release go through the app's event monitor, because the engine's popup is the key window by then.
@MainActor
final class PinnedExtensionCycleKeyTests: XCTestCase {
  private var harness: EngineHarnessWindow!
  private var savedMenu: NSMenu?
  private var engine: InMemoryEngine { harness.engine }
  private var controller: ShellWindowController { harness.controller }
  private var panel: ExtensionsPanelController { controller.extensionsPanel! }
  private var window: EngineWindowID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedMenu = NSApp.mainMenu
    harness = EngineHarnessWindow(try EngineWorld.make().sidebar)
    harness.controller.showWindow(nil)
    window = try XCTUnwrap(harness.controller.engineWindow)
    installMenu()
  }

  override func tearDown() async throws {
    try releaseCommand()                       // ends any cycle a failed test left running
    NSApp.mainMenu = savedMenu
    harness.controller.close()
    harness = nil
  }

  /// The main menu's Cmd-E item, aimed at this test's controller: in the app it has a nil target and reaches the main
  /// window's controller through the responder chain (`MainMenuKeyEquivalentTests`), which a test process that is not
  /// active has no key window for.
  private func installMenu() {
    let menu = NSMenu()
    let holder = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    let view = NSMenu(title: "View")
    let item = NSMenuItem(title: "Cycle through pinned extensions",
                          action: #selector(ShellWindowController.cyclePinnedExtensions(_:)), keyEquivalent: "e")
    item.keyEquivalentModifierMask = .command
    item.target = controller
    item.isHidden = true
    item.allowsKeyEquivalentWhenHidden = true
    view.addItem(item)
    holder.submenu = view
    menu.addItem(holder)
    NSApp.mainMenu = menu
  }

  // MARK: Events

  private func key(_ keyCode: Int, _ flags: CGEventFlags, repeating: Bool = false) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    event.flags = flags
    if repeating { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  /// A Command press or release as AppKit reports it: a flags-changed event carrying the modifiers still held.
  private func flags(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                   windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                   isARepeat: false, keyCode: UInt16(kVK_Command)))
  }

  /// The first tap of a hold: through the shell window, as AppKit hands it a key equivalent.
  @discardableResult
  private func firstTap() throws -> Bool {
    try XCTUnwrap(controller.window).performKeyEquivalent(with: try key(kVK_ANSI_E, .maskCommand))
  }

  /// A later tap while Command is held: through the application, wherever the key window is.
  private func nextTap(repeating: Bool = false) throws {
    NSApp.sendEvent(try key(kVK_ANSI_E, .maskCommand, repeating: repeating))
  }

  private func releaseCommand() throws { NSApp.sendEvent(try flags([])) }

  private var opened: [String] { engine.ranExtensionActions.map(\.id) }

  private func pin(_ ids: [String], unpinned: [String] = []) {
    engine.setExtensionActions(ids.map { ExtensionAction(id: $0, name: $0.uppercased(), isPinned: true) }
                               + unpinned.map { ExtensionAction(id: $0, name: $0.uppercased()) }, in: window)
  }

  /// A focused web page: it takes every key equivalent it is offered, as `RenderWidgetHostViewCocoa` does.
  private func focusPage() throws -> SwallowingPageView {
    let page = SwallowingPageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let content = try XCTUnwrap(controller.window?.contentView)
    content.addSubview(page)
    XCTAssertTrue(controller.window?.makeFirstResponder(page) == true)
    return page
  }

  // MARK: Cycling

  func testEachTapOpensTheNextPinnedExtensionInPinOrderAndWraps() throws {
    pin(["a", "b", "c"], unpinned: ["x"])
    engine.movePinnedExtension("c", to: 0)                                  // pin order: c, a, b
    XCTAssertTrue(try firstTap())
    try nextTap()
    try nextTap()
    try nextTap()
    XCTAssertEqual(opened, ["c", "a", "b", "c"], "pin order, wrapping, never the unpinned one")
    XCTAssertTrue(engine.ranExtensionActions.allSatisfy { $0.window == window })
  }

  func testReleasingCommandLeavesThePopupAndTheNextHoldStartsAtTheFirst() throws {
    pin(["a", "b", "c"])
    try firstTap()
    try nextTap()
    try releaseCommand()
    XCTAssertEqual(opened, ["a", "b"], "the release opens and closes nothing")
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
    try firstTap()
    XCTAssertEqual(opened, ["a", "b", "a"])
  }

  func testWithNonePinnedNothingHappens() throws {
    pin([], unpinned: ["x", "y"])
    try firstTap()
    try nextTap()
    XCTAssertEqual(opened, [])
    XCTAssertFalse(panel.isCyclingPinnedExtensions, "no cycle, so no monitor is left running")
  }

  func testAHeldEDoesNotSpinThroughTheList() throws {
    pin(["a", "b", "c"])
    try firstTap()
    try nextTap(repeating: true)
    try nextTap(repeating: true)
    XCTAssertEqual(opened, ["a"])
    try nextTap()
    XCTAssertEqual(opened, ["a", "b"])
  }

  func testATapInAnotherBrowserWindowEndsThisWindowsHold() throws {
    pin(["a", "b"])
    try firstTap()
    let other = ShellWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    other.orderBack(nil)
    defer { other.close() }
    NSApp.mainMenu = NSMenu()                  // the tap goes on to the other window's menu route, not this test's
    let tap = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                             windowNumber: other.windowNumber, context: nil, characters: "e",
                                             charactersIgnoringModifiers: "e", isARepeat: false,
                                             keyCode: UInt16(kVK_ANSI_E)))
    XCTAssertTrue(tap.window === other)
    NSApp.sendEvent(tap)
    XCTAssertEqual(opened, ["a"], "Cmd-` moved to another window while Command was held: that window cycles its own")
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
  }

  // MARK: Focus

  func testItWorksWithThePageFocused() throws {
    pin(["a", "b"])
    let page = try focusPage()
    XCTAssertTrue(try firstTap())
    try nextTap()
    XCTAssertEqual(opened, ["a", "b"])
    XCTAssertEqual(page.keyEquivalents, 0, "the page never saw Cmd-E")
    page.removeFromSuperview()
  }

  func testItWorksWithATextFieldFocused() throws {
    pin(["a", "b"])
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    controller.window?.contentView?.addSubview(field)
    XCTAssertTrue(controller.window?.makeFirstResponder(field) == true)
    XCTAssertTrue(try firstTap())
    XCTAssertEqual(opened, ["a"])
    XCTAssertEqual(field.stringValue, "", "no E typed into the field")
    field.removeFromSuperview()
  }

  // MARK: Anchor

  func testThePopupAnchorsToTheExtensionsButtonOrWithTheSidebarHiddenToThePage() throws {
    pin(["a", "b"])
    try firstTap()
    XCTAssertTrue(engine.ranExtensionActions.last?.anchor === controller.extensionsButton)
    try releaseCommand()
    controller.rootView.sidebarVisible = false
    try firstTap()
    XCTAssertTrue(engine.ranExtensionActions.last?.anchor === controller.rootView.card,
                  "the button is off screen with the sidebar hidden")
    XCTAssertNotNil(controller.rootView.card.window)
    controller.rootView.sidebarVisible = true
  }
}

/// Takes every key equivalent, as a focused web page does.
@MainActor
final class SwallowingPageView: NSView {
  var keyEquivalents = 0
  override var acceptsFirstResponder: Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyEquivalents += 1
    return true
  }
}
