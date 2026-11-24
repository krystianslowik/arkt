import AppKit
import Carbon.HIToolbox
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Cmd-E cycles the pinned extensions (KB-047, #599) in a real shell window over an `InMemoryEngine`, driven by an
/// injected key sequence, with the real main menu installed. The first tap takes the window's route: while an extension
/// is pinned, the window takes Cmd-E before a focused page or field; with none pinned, the page keeps it and the menu
/// does not swallow it (maintainer decision on #599, 2026-11-24). While Command stays down, the next taps and the
/// release go through the app's event monitor, because the engine's popup is the key window by then.
@MainActor
final class PinnedExtensionCycleKeyTests: XCTestCase {
  private var harness: EngineHarnessWindow!
  private var savedMenu: NSMenu?
  private var extraWindows: [NSWindow] = []
  private var engine: InMemoryEngine { harness.engine }
  private var controller: ShellWindowController { harness.controller }
  private var panel: ExtensionsPanelController { controller.extensionsPanel! }
  private var shellWindow: NSWindow { controller.window! }
  private var window: EngineWindowID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedMenu = NSApp.mainMenu
    harness = EngineHarnessWindow(try EngineWorld.make().sidebar)
    harness.controller.showWindow(nil)
    window = try XCTUnwrap(harness.controller.engineWindow)
    NSApp.mainMenu = MainMenu.make(commands: AppCommands()).menu
  }

  override func tearDown() async throws {
    try releaseCommand()                       // ends any cycle a failed test left running
    if let sheet = harness.controller.window?.attachedSheet { harness.controller.window?.endSheet(sheet) }
    for extra in extraWindows { extra.close() }
    extraWindows = []
    NSApp.mainMenu = savedMenu
    harness.controller.close()
    harness = nil
  }

  // MARK: Events

  private func key(_ keyCode: Int, _ flags: CGEventFlags, repeating: Bool = false) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    event.flags = flags
    if repeating { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  /// Cmd-E as a key-down in `window`.
  private func commandE(in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "e",
                                   charactersIgnoringModifiers: "e", isARepeat: false, keyCode: UInt16(kVK_ANSI_E)))
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
    shellWindow.performKeyEquivalent(with: try key(kVK_ANSI_E, .maskCommand))
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
    try XCTUnwrap(shellWindow.contentView).addSubview(page)
    XCTAssertTrue(shellWindow.makeFirstResponder(page))
    return page
  }

  private func extraWindow() -> NSWindow {
    let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
                         backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    extraWindows.append(other)
    return other
  }

  private var menuItem: NSMenuItem {
    get throws {
      let items = try XCTUnwrap(NSApp.mainMenu).items.compactMap(\.submenu).flatMap(\.items)
      return try XCTUnwrap(items.first { $0.action == #selector(ShellWindowController.cyclePinnedExtensions(_:)) })
    }
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

  func testAHeldEDoesNotSpinThroughTheList() throws {
    pin(["a", "b", "c"])
    try firstTap()
    try nextTap(repeating: true)
    try nextTap(repeating: true)
    XCTAssertEqual(opened, ["a"])
    try nextTap()
    XCTAssertEqual(opened, ["a", "b"])
  }

  // MARK: None pinned: the page keeps Cmd-E

  func testWithNonePinnedAFocusedPageGetsCommandEAndNothingIsSwallowed() throws {
    pin([], unpinned: ["x", "y"])
    let page = try focusPage()
    XCTAssertTrue(try firstTap())
    XCTAssertEqual(page.keyEquivalents, 1, "the page has Cmd-E")
    XCTAssertEqual(opened, [])
    XCTAssertFalse(panel.isCyclingPinnedExtensions, "no cycle, so no monitor is left running")
    XCTAssertFalse(try XCTUnwrap(NSApp.mainMenu).performKeyEquivalent(with: try key(kVK_ANSI_E, .maskCommand)),
                   "a page that does not use Cmd-E hands it back to the menu, which must not swallow it")
    XCTAssertFalse(controller.validateMenuItem(try menuItem))
    page.removeFromSuperview()
  }

  func testWithNonePinnedAFocusedFieldIsNotSwallowed() throws {
    pin([])
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    shellWindow.contentView?.addSubview(field)
    XCTAssertTrue(shellWindow.makeFirstResponder(field))
    XCTAssertFalse(try firstTap(), "nothing in the window takes it")
    XCTAssertFalse(try XCTUnwrap(NSApp.mainMenu).performKeyEquivalent(with: try key(kVK_ANSI_E, .maskCommand)))
    field.removeFromSuperview()
  }

  // MARK: Pinned: Arkt takes Cmd-E before the page

  func testItWorksWithThePageFocused() throws {
    pin(["a", "b"])
    let page = try focusPage()
    XCTAssertTrue(try firstTap())
    try nextTap()
    XCTAssertEqual(opened, ["a", "b"])
    XCTAssertEqual(page.keyEquivalents, 0, "the page never saw Cmd-E")
    XCTAssertTrue(controller.validateMenuItem(try menuItem))
    page.removeFromSuperview()
  }

  func testItWorksWithATextFieldFocused() throws {
    pin(["a", "b"])
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    shellWindow.contentView?.addSubview(field)
    XCTAssertTrue(shellWindow.makeFirstResponder(field))
    XCTAssertTrue(try firstTap())
    XCTAssertEqual(opened, ["a"])
    XCTAssertEqual(field.stringValue, "", "no E typed into the field")
    field.removeFromSuperview()
  }

  func testASheetUpOpensNoPopup() throws {
    pin(["a", "b"])
    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                         backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    shellWindow.beginSheet(sheet)
    XCTAssertNotNil(shellWindow.attachedSheet)
    try firstTap()
    XCTAssertEqual(opened, [])
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
    XCTAssertFalse(controller.validateMenuItem(try menuItem))
    shellWindow.endSheet(sheet)
  }

  // MARK: The hold ends

  func testAnyKeyWithoutCommandEndsTheHold() throws {
    pin(["a", "b"])
    try firstTap()
    NSApp.sendEvent(try key(kVK_ANSI_E, []))
    XCTAssertFalse(panel.isCyclingPinnedExtensions, "Command went up unseen (menu tracking)")
    XCTAssertEqual(opened, ["a"])
  }

  func testTheAppResigningActiveEndsTheHold() throws {
    pin(["a", "b"])
    try firstTap()
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    XCTAssertFalse(panel.isCyclingPinnedExtensions, "Cmd-Tab away mid-hold: the release is never seen")
  }

  func testClosingTheWindowEndsTheHold() throws {
    pin(["a", "b"])
    try firstTap()
    let panel = self.panel
    controller.close()
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
  }

  // MARK: Other windows

  func testATapInAWindowOutsideThisOneEndsTheHoldAndPassesOn() throws {
    pin(["a", "b"])
    try firstTap()
    let little = extraWindow()                                 // a Little Arkt window or Settings
    let tap = try commandE(in: little)
    XCTAssertTrue(tap.window === little)
    XCTAssertFalse(panel.handleCycleEvent(tap), "the monitor passes the tap on to its window")
    XCTAssertEqual(opened, ["a"])
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
  }

  func testATapInAChildOfThisWindowContinuesTheHold() throws {
    pin(["a", "b"])
    try firstTap()
    let popup = extraWindow()                                  // the engine's popup hangs off the browser window
    shellWindow.addChildWindow(popup, ordered: .above)
    NSApp.sendEvent(try commandE(in: popup))
    XCTAssertEqual(opened, ["a", "b"])
    shellWindow.removeChildWindow(popup)
  }

  // MARK: The popup stays key after the hold

  /// After a hold the last popup stays open and is the key window (the engine makes it key), so the next Cmd-E never
  /// reaches the browser window. The app's router takes it there too, as the first tap of a new hold.
  func testANewHoldWhileThePopupIsKeyOpensTheFirstAgain() throws {
    pin(["a", "b", "c"])
    try firstTap()
    try nextTap()
    try releaseCommand()
    XCTAssertFalse(panel.isCyclingPinnedExtensions)
    let popup = extraWindow()                                  // the engine's popup hangs off the browser window
    shellWindow.addChildWindow(popup, ordered: .above)
    NSApp.sendEvent(try commandE(in: popup))
    XCTAssertEqual(opened, ["a", "b", "a"], "the new hold starts at the first pinned extension")
    XCTAssertTrue(panel.isCyclingPinnedExtensions)
    shellWindow.removeChildWindow(popup)
  }

  func testWithNonePinnedTheRouterTakesNothingFromAChildWindow() throws {
    pin([], unpinned: ["x"])
    let popup = extraWindow()
    shellWindow.addChildWindow(popup, ordered: .above)
    XCTAssertFalse(panel.handleCycleEvent(try commandE(in: popup)), "the key goes on to that window")
    XCTAssertEqual(opened, [])
    shellWindow.removeChildWindow(popup)
  }

  func testTheRouterTakesNothingFromAnUnrelatedWindow() throws {
    pin(["a"])
    XCTAssertFalse(panel.handleCycleEvent(try commandE(in: extraWindow())), "Little Arkt or Settings keeps its Cmd-E")
    XCTAssertEqual(opened, [])
  }

  func testOnboardingKeepsCommandE() throws {
    pin(["a"])
    let onboarding = controller.presentOnboarding(
      services: FakeOnboardingServices(sidebar: StubSidebar(), arcFound: false),
      options: .init(mode: .reentry, includesExtensions: false), stage: LateFoldStage())
    XCTAssertNotNil(onboarding)
    let page = try focusPage()
    try firstTap()
    XCTAssertEqual(opened, [], "the first run covers the browser")
    XCTAssertFalse(controller.validateMenuItem(try menuItem))
    controller.onboardingDidFinish()
    page.removeFromSuperview()
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
    try releaseCommand()
    controller.rootView.sidebarOverlay.reveal()
    try firstTap()
    XCTAssertTrue(engine.ranExtensionActions.last?.anchor === controller.extensionsButton,
                  "the overlay is out, so the button shows")
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
