import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The Extensions panel (#595, design/extensions direction C) over an `InMemoryEngine`: anchored to the bottom-bar
/// button, Pinned and Not pinned groups, the pin toggle, ordering by keyboard, accessibility and drag, the empty and
/// none-pinned states and the smallest window.
@MainActor
final class ExtensionsPanelTests: XCTestCase {
  private var harness: EngineHarnessWindow!
  private var engine: InMemoryEngine { harness.engine }
  private var window: EngineWindowID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    harness = EngineHarnessWindow(try EngineWorld.make().sidebar)
    harness.controller.showWindow(nil)
    window = try XCTUnwrap(harness.controller.engineWindow)
    panel.reduceMotion = { false }
  }

  override func tearDown() async throws {
    panel.hide(keyboard: true)
    harness.controller.window?.orderOut(nil)
    harness = nil
  }

  private var panel: ExtensionsPanelController { harness.controller.extensionsPanel! }
  private var button: ExtensionsButton { harness.controller.extensionsButton! }
  private var view: ExtensionsPanelView { panel.contentView! }

  private func action(_ id: String, name: String? = nil, pinned: Bool = false, icon: Bool = false,
                      access: ExtensionSiteAccess = .onThisSite) -> ExtensionAction {
    ExtensionAction(id: id, name: name ?? id.uppercased(), iconPNG: icon ? Self.png : nil, isPinned: pinned,
                    siteAccess: access)
  }

  private static let png: Data = {
    let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
      NSColor.gray.setFill(); rect.fill(); return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
  }()

  private func open(_ actions: [ExtensionAction]) {
    engine.setExtensionActions(actions, in: window)
    button.performClick(nil)
    XCTAssertTrue(panel.isShown)
  }

  private func row(_ id: String) throws -> ExtensionsPanelRow { try XCTUnwrap(view.row(for: id)) }

  // MARK: Opening

  func testTheButtonOpensADialogAnchoredAboveIt() throws {
    open([action("a", pinned: true), action("b")])
    let window = try XCTUnwrap(panel.panel)
    XCTAssertEqual(window.accessibilitySubrole(), .dialog)
    XCTAssertEqual(window.accessibilityLabel(), "Extensions")
    XCTAssertEqual(window.frame.width, 316)
    let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
    XCTAssertEqual(window.frame.minY, anchor.maxY + ExtensionsPanelMetrics.gap, accuracy: 0.5)
    let bar = try XCTUnwrap(button.superview)
    let barRect = button.window!.convertToScreen(bar.convert(bar.bounds, to: nil))
    XCTAssertEqual(window.frame.minX, barRect.minX + ExtensionsPanelMetrics.sidebarInset, accuracy: 0.5)
    XCTAssertTrue(window.isKeyWindow || !NSApp.isActive, "the panel takes the keyboard")
    XCTAssertTrue(window.parent === button.window)
    XCTAssertTrue(button.isOpen, "the button keeps its fill while the panel is up")

    button.performClick(nil)
    XCTAssertFalse(panel.isShown, "a second click closes it")
    XCTAssertFalse(button.isOpen)
  }

  func testTheButtonIsEnabledWithoutExtensions() {
    XCTAssertTrue(button.isEnabled, "the empty state is the panel's, so the button always opens it")
    XCTAssertEqual(button.accessibilityLabel(), "Extensions")
  }

  func testEscapeClosesAndGivesTheKeyboardBack() throws {
    open([action("a")])
    let window = try XCTUnwrap(panel.panel)
    window.cancelOperation(nil)
    XCTAssertFalse(panel.isShown)
    XCTAssertTrue(button.window?.firstResponder === button)
  }

  func testAMouseDismissalLeavesTheFirstResponderAlone() throws {
    open([action("a")])
    let parent = try XCTUnwrap(button.window)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    parent.contentView?.addSubview(field)
    parent.makeFirstResponder(field)
    let responder = parent.firstResponder
    panel.handleMouseDown(in: parent, at: NSPoint(x: 600, y: 400))
    XCTAssertFalse(panel.isShown)
    XCTAssertTrue(parent.firstResponder === responder, "the click elsewhere decides the focus, not the panel")
    field.removeFromSuperview()
  }

  func testOpenedFromTheKeyboardTheFirstRowTakesTheFocus() throws {
    engine.setExtensionActions([action("a", pinned: true), action("b")], in: window)
    panel.show(fromKeyboard: true)
    XCTAssertTrue(panel.panel?.firstResponder === (try row("a")).runButton)
    panel.hide(keyboard: true)
    engine.setExtensionActions([], in: window)
    panel.show(fromKeyboard: true)
    XCTAssertTrue(panel.panel?.firstResponder === view.browseButton)
  }

  func testTheEngineWindowGoingAwayClosesThePanel() throws {
    open([action("a")])
    engine.closeWindow(window)
    XCTAssertFalse(panel.isShown, "no empty state for a window that has no engine window")
  }

  func testTheSidebarHidingAndFullScreenCloseThePanel() throws {
    open([action("a")])
    harness.controller.toggleSidebarVisibility(nil)
    XCTAssertFalse(panel.isShown)
    harness.controller.toggleSidebarVisibility(nil)
    button.performClick(nil)
    XCTAssertTrue(panel.isShown)
    harness.controller.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification))
    XCTAssertFalse(panel.isShown)
  }

  func testShrinkingTheWindowKeepsThePanelAboveTheBarAndInside() throws {
    open((0..<8).map { action("x\($0)", pinned: $0 < 4) })
    let parent = try XCTUnwrap(button.window)
    let tall = try XCTUnwrap(panel.panel).frame
    XCTAssertFalse(view.scrolls)
    parent.setFrame(NSRect(x: parent.frame.minX, y: parent.frame.minY, width: 640, height: 420), display: true)
    harness.controller.windowDidResize(Notification(name: NSWindow.didResizeNotification))
    let frame = try XCTUnwrap(panel.panel).frame
    let anchor = parent.convertToScreen(button.convert(button.bounds, to: nil))
    XCTAssertLessThan(frame.height, tall.height)
    XCTAssertEqual(frame.minY, anchor.maxY + ExtensionsPanelMetrics.gap, accuracy: 0.5)
    XCTAssertLessThanOrEqual(frame.maxY, parent.frame.maxY - ExtensionsPanelMetrics.topMargin + 0.5)
    XCTAssertTrue(view.scrolls)
  }

  func testIncreaseContrastEdgesTheRows() throws {
    panel.increaseContrast = { true }
    open([action("a")])
    XCTAssertTrue(try row("a").showsContrastEdge)
    panel.hide(keyboard: true)
    panel.increaseContrast = { false }
    button.performClick(nil)
    XCTAssertFalse(try row("a").showsContrastEdge)
  }

  func testAClickElsewhereInTheWindowClosesButNotOneInAnotherWindow() throws {
    open([action("a")])
    let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: .borderless,
                         backing: .buffered, defer: true)
    panel.handleMouseDown(in: popup, at: .zero)
    XCTAssertTrue(panel.isShown, "an extension's popup is its own window; clicking it keeps the row it points at")
    panel.handleMouseDown(in: panel.panel, at: NSPoint(x: 10, y: 10))
    XCTAssertTrue(panel.isShown)
    panel.handleMouseDown(in: button.window, at: NSPoint(x: 600, y: 400))
    XCTAssertFalse(panel.isShown)
  }

  func testTheEntranceScalesAndFadesAndOnlyFadesUnderReduceMotion() throws {
    open([action("a")])
    XCTAssertNotNil(panel.entranceAnimations["appear.transform"])
    XCTAssertNotNil(panel.entranceAnimations["appear.opacity"])
    panel.hide(keyboard: true)
    panel.reduceMotion = { true }
    button.performClick(nil)
    XCTAssertNil(panel.entranceAnimations["appear.transform"])
    XCTAssertEqual(panel.entranceAnimations["appear.opacity"]?.duration ?? 0, 0.15, accuracy: 1e-9)
  }

  // MARK: States

  func testNoExtensionsShowsTheEmptyStateWithTheWebStore() throws {
    var browsed = 0
    panel.onBrowseWebStore = { browsed += 1 }
    open([])
    XCTAssertEqual(view.state, .empty)
    XCTAssertFalse(view.emptyView.isHidden)
    XCTAssertEqual(view.browseButton.title, "Browse the Web Store")
    view.browseButton.performClick(nil)
    XCTAssertEqual(browsed, 1)
    XCTAssertFalse(panel.isShown)
  }

  func testBrowseTheWebStoreOpensItInANewTab() throws {
    open([])
    view.browseButton.performClick(nil)
    let tab = try XCTUnwrap(harness.controller.currentTab)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, OnboardingController.Options.chromeWebStore)
  }

  func testNonePinnedShowsTheHintAboveEveryExtension() throws {
    open([action("a"), action("b")])
    XCTAssertEqual(view.state, .nonePinned)
    XCTAssertFalse(view.hintView.isHidden)
    XCTAssertEqual(view.displayedRowIDs, ["a", "b"])
    XCTAssertEqual(view.headerTitles, ["Pinned", "Not pinned"])
    XCTAssertFalse(view.hintText.contains("\u{2318}"), "Cmd-E is not bound yet (#599)")
  }

  func testAllPinnedShowsNoNotPinnedGroup() throws {
    open([action("a", pinned: true)])
    XCTAssertEqual(view.headerTitles, ["Pinned"])
    XCTAssertTrue(view.hintView.isHidden)
  }

  func testManageExtensionsGoesToSettings() throws {
    var managed = 0
    harness.controller.onManageExtensions = { managed += 1 }
    open([action("a")])
    XCTAssertEqual(view.manageButton.title, "Manage Extensions...")
    view.manageButton.performClick(nil)
    XCTAssertEqual(managed, 1)
    XCTAssertFalse(panel.isShown)
  }

  // MARK: Rows

  func testARowShowsNameAndStatusAndRunsTheActionAnchoredToItself() throws {
    open([action("a", access: .onClick), action("b", icon: true)])
    let a = try row("a")
    XCTAssertEqual(a.nameLabel.stringValue, "A")
    XCTAssertEqual(a.statusLabel.stringValue, "Needs access to this site")
    XCTAssertTrue(a.showsAttentionDot)
    XCTAssertEqual(a.runButton.accessibilityLabel(), "A, Needs access to this site")
    XCTAssertFalse(a.showsIconImage, "no icon: the neutral tile")
    XCTAssertTrue(try row("b").showsIconImage)

    a.runButton.performClick(nil)
    XCTAssertEqual(engine.ranExtensionActions.map(\.id), ["a"])
    XCTAssertTrue(engine.ranExtensionActions.first?.anchor === a)
    XCTAssertTrue(panel.isShown, "the popup points at the row, so the panel stays")
  }

  func testThePinToggleIsPressedWhenPinnedAndPinsAndUnpins() throws {
    open([action("a", pinned: true), action("b")])
    let b = try row("b")
    XCTAssertEqual(b.pinToggle.accessibilityLabel(), "Pin B")
    XCTAssertEqual(b.pinToggle.accessibilitySubrole(), .toggle)
    XCTAssertEqual(b.pinToggle.accessibilityValue() as? Bool, false)
    XCTAssertEqual(try row("a").pinToggle.accessibilityValue() as? Bool, true)

    b.pinToggle.performClick(nil)
    XCTAssertEqual(engine.pinnedExtensionIDs, ["a", "b"])
    XCTAssertEqual(view.displayedRowIDs, ["a", "b"])
    XCTAssertTrue(try row("b").isPinned)
    XCTAssertEqual(try row("b").pinToggle.accessibilityValue() as? Bool, true)
    XCTAssertEqual(view.headerTitles, ["Pinned"])

    try row("a").pinToggle.performClick(nil)
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b"])
    XCTAssertEqual(view.displayedRowIDs, ["b", "a"])
  }

  func testOnlyPinnedRowsHaveAGrip() throws {
    open([action("a", pinned: true), action("b")])
    XCTAssertFalse(try row("a").grip.isHidden)
    XCTAssertTrue(try row("b").grip.isHidden)
  }

  func testTheMoreButtonAndRightClickShowTheEnginesContextMenu() async throws {
    open([action("a", pinned: true)])
    let a = try row("a")
    var shown: [String] = []
    a.presentMenu = { menu, _ in shown.append(menu.items.first?.title ?? "") }
    XCTAssertEqual(a.moreButton.accessibilityLabel(), "More for A")
    a.moreButton.performClick(nil)
    XCTAssertTrue(a.accessibilityPerformShowMenu())
    await a.pendingPresentation?.value                 // the show-menu action pops the menu up on the next turn
    XCTAssertEqual(shown, ["A", "A"], "the engine's menu, its name as the header")
    let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                      clickCount: 1, pressure: 1))
    XCTAssertEqual(a.menu(for: rightClick)?.items.map(\.title).contains("Unpin"), true)
    XCTAssertEqual(a.runButton.menu(for: rightClick)?.items.first?.title, "A", "right-click on the main area")
    XCTAssertEqual(a.pinToggle.menu(for: rightClick)?.items.first?.title, "A")

    let ctrlClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .control,
                                                     timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                     clickCount: 1, pressure: 1))
    a.runButton.mouseDown(with: ctrlClick)
    XCTAssertEqual(shown.count, 3, "Ctrl-click shows the menu")
    XCTAssertTrue(engine.ranExtensionActions.isEmpty, "and does not run the action")
  }

  func testRemoveIsDisabledWithoutTheRemoveSheet() throws {
    open([action("a")])
    XCTAssertNotNil(panel.onRemove, "the window wires the remove sheet (#720)")
    panel.onRemove = nil
    let a = try row("a")
    let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                      clickCount: 1, pressure: 1))
    let remove = { (menu: NSMenu?) in menu?.items.first { $0.tag == ExtensionContextCommand.remove.rawValue } }
    XCTAssertEqual(remove(a.menu(for: rightClick))?.isEnabled, false)
    panel.onRemove = { _ in }
    XCTAssertEqual(remove(a.menu(for: rightClick))?.isEnabled, true)
  }

  func testAControlClickOnTheGripIsNotADrag() throws {
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    var began = false
    a.grip.onBegin = { _ in began = true }
    a.menuProvider = nil                    // AppKit would run the real context menu's modal tracking loop
    let ctrlClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .control,
                                                     timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                     clickCount: 1, pressure: 1))
    a.grip.mouseDown(with: ctrlClick)
    XCTAssertFalse(began)
    XCTAssertFalse(a.grip.holdsCursor)
  }

  // MARK: Order without a drag

  func testMoveUpAndDownAreAccessibilityActionsOfPinnedRows() throws {
    open([action("a", pinned: true), action("b", pinned: true), action("c", pinned: true), action("d")])
    XCTAssertEqual(try row("a").accessibilityCustomActions()?.map(\.name), ["Move Down"])
    XCTAssertEqual(try row("b").accessibilityCustomActions()?.map(\.name), ["Move Up", "Move Down"])
    XCTAssertEqual(try row("c").accessibilityCustomActions()?.map(\.name), ["Move Up"])
    XCTAssertEqual(try row("d").accessibilityCustomActions()?.map(\.name) ?? [], [])

    let moveDown = try XCTUnwrap(try row("a").accessibilityCustomActions()?.first)
    XCTAssertTrue(moveDown.handler?() ?? false)
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b", "a", "c"])
    XCTAssertEqual(view.displayedRowIDs, ["b", "a", "c", "d"])
  }

  func testCommandOptionArrowsMoveTheFocusedRow() throws {
    open([action("a", pinned: true), action("b", pinned: true), action("c", pinned: true)])
    let window = try XCTUnwrap(panel.panel)
    let b = try row("b")
    XCTAssertTrue(window.makeFirstResponder(b.runButton))
    XCTAssertTrue(view.performKeyEquivalent(with: key(0x7E)))                 // Up: Move Up
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b", "a", "c"])
    XCTAssertTrue(window.firstResponder === b.runButton, "focus stays on the moved row")
    XCTAssertFalse(view.performKeyEquivalent(with: key(0x7B)), "already first")  // Left: nothing to do
    XCTAssertTrue(view.performKeyEquivalent(with: key(0x7C)))                 // Right: Move Down
    XCTAssertTrue(view.performKeyEquivalent(with: key(0x7D)))                 // Down: Move Down
    XCTAssertEqual(engine.pinnedExtensionIDs, ["a", "c", "b"])
  }

  private func key(_ code: UInt16) -> NSEvent {
    let characters = String(Character(UnicodeScalar(0xF700 + Int([0x7E: 0, 0x7D: 1, 0x7B: 2, 0x7C: 3][code]!))!))
    return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .numericPad,
                                                                             .function],
                            timestamp: 0, windowNumber: panel.panel?.windowNumber ?? 0, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                            keyCode: code)!
  }

  // MARK: Drag by the grip

  func testDraggingByTheGripShowsTheInsertionLineAndReorders() throws {
    open([action("a", pinned: true), action("b", pinned: true), action("c", pinned: true), action("d")])
    let a = try row("a")
    let start = NSPoint(x: 8, y: a.frame.midY)
    view.beginDrag(a, at: start)
    XCTAssertEqual(a.layer?.transform.m11 ?? 0, ExtensionsPanelMotion.liftScale, accuracy: 1e-6)
    let c = try row("c")
    view.continueDrag(to: NSPoint(x: 8, y: c.frame.maxY + 4))
    XCTAssertFalse(view.insertionLine.isHidden)
    XCTAssertEqual(view.insertionLine.frame.height, 2)
    XCTAssertEqual(view.insertionLine.frame.midY, c.frame.maxY, accuracy: 1.5)
    XCTAssertEqual(view.dragGap, 3)
    // The lifted row follows the pointer by its transform alone.
    XCTAssertEqual(a.layer?.transform.m42 ?? 0, abs(c.frame.maxY + 4 - start.y), accuracy: 1)

    view.endDrag()
    XCTAssertTrue(view.insertionLine.isHidden)
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b", "c", "a"])
    XCTAssertEqual(view.displayedRowIDs, ["b", "c", "a", "d"])
  }

  func testTheDragStaysInThePinnedGroup() throws {
    open([action("a", pinned: true), action("b", pinned: true), action("d")])
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    view.continueDrag(to: NSPoint(x: 8, y: try row("d").frame.maxY + 200))
    XCTAssertEqual(view.dragGap, 2, "past the last pinned row it drops at the end of Pinned")
    view.endDrag()
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b", "a"])
  }

  func testADropBackInPlaceMovesNothing() throws {
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    view.continueDrag(to: NSPoint(x: 8, y: a.frame.midY + 3))
    XCTAssertTrue(view.insertionLine.isHidden, "no line where the row already is")
    view.endDrag()
    XCTAssertEqual(engine.pinnedExtensionIDs, ["a", "b"])
  }

  func testReduceMotionLiftsWithoutScale() throws {
    panel.reduceMotion = { true }
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    XCTAssertEqual(a.layer?.transform.m11 ?? 0, 1, accuracy: 1e-6)
    view.continueDrag(to: NSPoint(x: 8, y: try row("b").frame.maxY + 2))
    view.endDrag()
    XCTAssertEqual(engine.pinnedExtensionIDs, ["b", "a"])
    XCTAssertNil(try row("a").layer?.animation(forKey: "settle"), "the row jumps to its place")
  }

  func testTheDropSettlesIntoPlace() throws {
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    view.continueDrag(to: NSPoint(x: 8, y: try row("b").frame.maxY + 2))
    view.endDrag()
    let settle = try XCTUnwrap(try row("a").layer?.animation(forKey: "settle") as? CABasicAnimation)
    XCTAssertEqual(settle.duration, ExtensionsPanelMotion.settleDuration, accuracy: 1e-9)
    XCTAssertEqual(try row("a").layer?.transform.m42 ?? 1, 0, accuracy: 1e-6, "the model value is the slot")
  }

  func testADropWaitsForAnEngineThatAnswersLater() throws {
    var pendingTimeouts: [@MainActor () -> Void] = []
    panel.schedule = { _, action in pendingTimeouts.append(action) }
    open([action("a", pinned: true), action("b", pinned: true)])
    var moves: [(String, Int)] = []
    view.onMove = { id, index in moves.append((id, index)) }    // a batching engine: the order arrives later
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    view.continueDrag(to: NSPoint(x: 8, y: try row("b").frame.maxY + 2))
    let dropped = a.layer?.transform.m42 ?? 0
    view.endDrag()
    XCTAssertEqual(moves.map(\.0), ["a"])
    XCTAssertTrue(view.isAwaitingDrop)
    XCTAssertEqual(a.layer?.transform.m42 ?? 0, dropped, accuracy: 0.5, "the row stays where it was dropped")
    XCTAssertEqual(pendingTimeouts.count, 1)

    engine.movePinnedExtension("a", to: 1)                     // the engine's batch arrives
    XCTAssertFalse(view.isAwaitingDrop)
    XCTAssertEqual(view.displayedRowIDs, ["b", "a"])
    XCTAssertEqual(a.layer?.transform.m42 ?? 1, 0, accuracy: 1e-6)
    XCTAssertNotNil(a.layer?.animation(forKey: "settle"))
    pendingTimeouts.forEach { $0() }                            // a late timeout changes nothing
    XCTAssertNotNil(a.layer?.animation(forKey: "settle"))
  }

  func testADropTheEngineIgnoresSettlesBackAfterTheTimeout() throws {
    var pendingTimeouts: [@MainActor () -> Void] = []
    panel.schedule = { _, action in pendingTimeouts.append(action) }
    open([action("a", pinned: true), action("b", pinned: true)])
    view.onMove = { _, _ in }
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    view.continueDrag(to: NSPoint(x: 8, y: try row("b").frame.maxY + 2))
    view.endDrag()
    XCTAssertTrue(view.isAwaitingDrop)
    pendingTimeouts.forEach { $0() }
    XCTAssertFalse(view.isAwaitingDrop)
    XCTAssertEqual(view.displayedRowIDs, ["a", "b"])
    XCTAssertEqual(a.layer?.transform.m42 ?? 1, 0, accuracy: 1e-6)
    XCTAssertNotNil(a.layer?.animation(forKey: "settle"), "it eases back to its slot")
  }

  func testReduceMotionIsReadOnceForTheWholeDrag() throws {
    var reduced = false
    panel.reduceMotion = { reduced }
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    view.beginDrag(a, at: NSPoint(x: 8, y: a.frame.midY))
    reduced = true
    view.continueDrag(to: NSPoint(x: 8, y: a.frame.midY + 3))
    XCTAssertEqual(a.layer?.transform.m11 ?? 0, ExtensionsPanelMotion.liftScale, accuracy: 1e-6)
    view.endDrag()
  }

  func testARowRemovedMidDragReleasesTheCursor() throws {
    open([action("a", pinned: true), action("b", pinned: true)])
    let a = try row("a")
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                clickCount: 1, pressure: 1))
    a.grip.mouseDown(with: down)
    XCTAssertTrue(a.grip.holdsCursor)
    engine.setExtensionActions([action("b", pinned: true)], in: window)
    XCTAssertFalse(a.grip.holdsCursor)
    XCTAssertNil(view.dragGap)
  }

  // MARK: Worst cases

  func testThirtyExtensionsWithLongNamesAndNoIconsScrollInsideTheWindow() throws {
    let long = String(repeating: "Super Ultra Productivity Toolkit ", count: 3).prefix(85)
    let actions = (0..<30).map { action("x\($0)", name: "\(long)", pinned: $0 < 10) }
    open(actions)
    XCTAssertEqual(view.displayedRowIDs.count, 30)
    let window = try XCTUnwrap(panel.panel)
    let parent = try XCTUnwrap(button.window)
    XCTAssertLessThanOrEqual(window.frame.maxY, parent.frame.maxY - ExtensionsPanelMetrics.topMargin + 0.5)
    XCTAssertTrue(view.scrolls)
    XCTAssertFalse(view.manageButton.isHidden, "the footer stays")
    let first = try row("x0")
    first.layoutSubtreeIfNeeded()
    XCTAssertEqual(first.nameLabel.lineBreakMode, .byTruncatingTail)
    XCTAssertLessThanOrEqual(first.nameLabel.frame.maxX, first.pinToggle.frame.minX)
    XCTAssertLessThanOrEqual(first.statusLabel.frame.maxX, first.pinToggle.frame.minX)
  }

  func testTheSmallestWindowCapsAndNarrowsThePanel() throws {
    let parent = try XCTUnwrap(button.window)
    parent.setFrame(NSRect(x: 0, y: 0, width: 640, height: 420), display: true)
    parent.contentView?.layoutSubtreeIfNeeded()
    open((0..<6).map { action("x\($0)", pinned: $0 < 4) })
    let window = try XCTUnwrap(panel.panel)
    XCTAssertLessThanOrEqual(window.frame.maxY, parent.frame.maxY - ExtensionsPanelMetrics.topMargin + 0.5)
    XCTAssertGreaterThanOrEqual(window.frame.minX, parent.frame.minX)
    XCTAssertLessThanOrEqual(window.frame.width, 316)
    XCTAssertTrue(view.scrolls)
  }

  func testTheOpenPanelFollowsTheEngine() throws {
    open([action("a")])
    engine.setExtensionActions([action("a"), action("b", pinned: true)], in: window)
    XCTAssertEqual(view.displayedRowIDs, ["b", "a"])
    engine.setExtensionActions([], in: window)
    XCTAssertEqual(view.state, .empty)
  }
}
