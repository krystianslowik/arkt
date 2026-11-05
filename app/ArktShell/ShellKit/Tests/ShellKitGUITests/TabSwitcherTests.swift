import AppKit
import Carbon.HIToolbox
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import Motion
@testable import ShellUI

/// The Ctrl-Tab switcher on a real shell window (#103; design/tab-switcher): raw key events go through
/// `ShellWindow.sendEvent`, the panel is shown in the same turn as the key-down, and Ctrl's release commits.
@MainActor
final class TabSwitcherTests: XCTestCase {
  private var source: StubSidebar!
  private var controller: ShellWindowController!
  private var space: SpaceID!
  private var tabs: [NodeID] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    source = StubSidebar()
    space = source.addSpace(title: "Work", theme: SpaceThemeInfo(baseColors: [.white(1)], isDark: false))
    tabs = (0..<7).map {
      source.addTab(url: URL(string: "https://example.com/\($0)")!, title: "Tab \($0)", in: .today(space))
    }
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    controller.window?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: false)
    controller.tabSwitcher.reduceMotion = { true }
    controller.onArchive = { [unowned self] ids in ids.forEach { self.source.removeNode($0) } }
  }

  override func tearDown() async throws {
    controller.window?.orderOut(nil)
    controller = nil
  }

  // MARK: Events

  private func key(_ keyCode: Int, _ flags: CGEventFlags, down: Bool = true) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down))
    event.flags = flags
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  /// A Ctrl press or release as AppKit reports it: a flags-changed event carrying the modifiers still held.
  private func flags(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                   windowNumber: controller.window?.windowNumber ?? 0, context: nil,
                                   characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                   keyCode: UInt16(kVK_Control)))
  }

  private func send(_ event: NSEvent) { controller.window?.sendEvent(event) }
  private func ctrlTab(shift: Bool = false) throws {
    send(try key(kVK_Tab, shift ? [.maskControl, .maskShift] : .maskControl))
  }
  private func releaseCtrl() throws { send(try flags([])) }

  private var switcher: TabSwitcherController { controller.tabSwitcher }
  private var panel: TabSwitcherView { controller.tabSwitcher.view }

  /// Views `nodes` in order, as clicks would.
  private func view(_ nodes: [NodeID]) {
    for node in nodes { controller.activate(node: node) }
  }

  private func shownTitles() -> [String] {
    panel.rowViews.prefix(panel.rowCount).map(\.titleField.stringValue)
  }

  // MARK: Opening

  func testOneViewedTabOpensNothing() throws {
    try ctrlTab()
    XCTAssertFalse(switcher.isOpen)
    XCTAssertTrue(panel.isHidden)
  }

  /// The one-frame bar: the panel is on screen, filled, at full opacity, when `sendEvent` returns.
  func testHoldingCtrlShowsTheRecentTabsInTheSameTurn() throws {
    view([tabs[0], tabs[1], tabs[2], tabs[3]])

    try ctrlTab()

    XCTAssertTrue(switcher.isOpen)
    XCTAssertFalse(panel.isHidden)
    XCTAssertEqual(panel.layer?.opacity, 1)
    XCTAssertEqual(shownTitles(), ["Tab 2", "Tab 1", "Tab 0"], "newest first, the current tab left out")
    XCTAssertEqual(switcher.session?.highlight, 0)
    XCTAssertNil(panel.layer?.animationKeys(), "no entrance animation")
  }

  func testTheListStopsAtFiveRowsAndTheHeightFollowsTheRows() throws {
    view(tabs)
    try ctrlTab()
    XCTAssertEqual(panel.rowCount, 5)
    XCTAssertEqual(panel.frame.height, TabSwitcherView.height(rows: 5))
    XCTAssertEqual(panel.frame.width, TabSwitcherView.width)
  }

  func testThePanelIsCenteredWithItsTopAtThirtyEightPercent() throws {
    view([tabs[0], tabs[1]])
    try ctrlTab()
    let bounds = controller.rootView.bounds
    XCTAssertEqual(panel.frame.midX, bounds.midX, accuracy: 0.5)
    XCTAssertEqual(panel.frame.minY, (bounds.height * 0.38).rounded(), accuracy: 0.5)
  }

  // MARK: Flick and commit

  /// BH-007: a tap and release before the panel was presented switches with no fade (no UI was drawn).
  func testTheFlickSwitchesToThePreviousTabWithoutAFade() throws {
    view([tabs[0], tabs[1]])

    try ctrlTab()
    try releaseCtrl()

    XCTAssertEqual(controller.sidebarController.current, tabs[0])
    XCTAssertFalse(switcher.isOpen)
    XCTAssertTrue(panel.isHidden)
    XCTAssertNil(panel.layer?.animationKeys())

    try ctrlTab()
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[1], "tapping again returns to the original tab")
  }

  func testTabAdvancesAndReleasingCtrlLandsOnTheHighlightedTab() throws {
    view([tabs[0], tabs[1], tabs[2], tabs[3]])

    try ctrlTab()
    send(try key(kVK_Tab, .maskControl))
    send(try key(kVK_Tab, .maskControl))
    XCTAssertEqual(switcher.session?.highlighted, tabs[0])
    try releaseCtrl()

    XCTAssertEqual(controller.sidebarController.current, tabs[0])
  }

  func testShiftTabAndBacktickMoveBackwardsAndWrap() throws {
    view([tabs[0], tabs[1], tabs[2], tabs[3]])
    try ctrlTab()
    send(try key(kVK_Tab, [.maskControl, .maskShift]))
    XCTAssertEqual(switcher.session?.highlighted, tabs[0], "wraps from the first row to the last")
    send(try key(kVK_ANSI_Grave, .maskControl))
    XCTAssertEqual(switcher.session?.highlighted, tabs[1])
  }

  func testCtrlShiftTabOpensOnTheLastRow() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab(shift: true)
    XCTAssertEqual(switcher.session?.highlighted, tabs[0])
  }

  /// A commit after the panel was presented fades it out (0.10 s); a new Ctrl-Tab during the fade shows it at once.
  func testACommitAfterPresentationFadesAndAReopenInterruptsTheFade() throws {
    controller.showWindow(nil)
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    waitUntil("the panel was presented") { self.switcher.hasPresented }

    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[1])
    XCTAssertNotNil(panel.layer?.animation(forKey: TabSwitcherView.fadeKey))
    XCTAssertFalse(panel.isHidden, "still fading")

    try ctrlTab()
    XCTAssertNil(panel.layer?.animation(forKey: TabSwitcherView.fadeKey))
    XCTAssertEqual(panel.layer?.opacity, 1)
    XCTAssertFalse(panel.isHidden)
    try releaseCtrl()
    waitUntil("the fade ended") { self.panel.isHidden }
  }

  // MARK: Cancel and dismiss

  func testEscapeCancelsAndStaysOnTheCurrentTab() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    send(try key(kVK_Escape, .maskControl))
    XCTAssertFalse(switcher.isOpen)
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[2])
  }

  /// Any other key dismisses as a cancel and is then handled as usual.
  func testAnotherKeyDismissesWithoutSwitching() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    send(try key(kVK_ANSI_A, .maskControl))
    XCTAssertFalse(switcher.isOpen)
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[2])
  }

  func testAClickOutsideThePanelCancels() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5),
                                                 modifierFlags: .control, timestamp: 0,
                                                 windowNumber: controller.window?.windowNumber ?? 0, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1))
    send(click)
    XCTAssertFalse(switcher.isOpen)
    XCTAssertEqual(controller.sidebarController.current, tabs[2])
  }

  /// The window losing key (another app, another window) ends the session as a cancel, so a Ctrl release that
  /// arrives later switches nothing.
  func testResigningKeyCancelsAndALaterCtrlReleaseSwitchesNothing() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    XCTAssertTrue(switcher.isOpen)

    controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))

    XCTAssertFalse(switcher.isOpen)
    XCTAssertTrue(panel.isHidden, "never presented, so hidden at once")
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[2])
  }

  // MARK: Spaces

  /// RT-12 as assumed: the list spans this window's Spaces in viewing order, and landing on a tab of another Space
  /// shows that Space.
  func testTheListSpansSpacesAndLandingOnAnotherSpaceShowsIt() throws {
    let other = source.addSpace(title: "Home", theme: SpaceThemeInfo(baseColors: [.white(1)], isDark: false))
    let away = source.addTab(url: URL(string: "https://example.com/away")!, title: "Away", in: .today(other))
    view([tabs[0], away, tabs[1]])
    XCTAssertEqual(controller.currentSpace, space)

    try ctrlTab()
    XCTAssertEqual(shownTitles(), ["Away", "Tab 0"])
    XCTAssertEqual(panel.rowViews[0].spaceField.stringValue, "Home")
    try releaseCtrl()

    XCTAssertEqual(controller.sidebarController.current, away)
    XCTAssertEqual(controller.currentSpace, other)
    try ctrlTab()
    XCTAssertEqual(shownTitles(), ["Tab 1", "Tab 0"], "the Space switch kept the viewing order")
    try releaseCtrl()
    XCTAssertEqual(controller.currentSpace, space)
  }

  // MARK: W

  /// BH-010: W closes the highlighted tab, the row that took its place is highlighted, and the switcher stays open.
  func testWClosesTheHighlightedTabAndKeepsTheSwitcherOpen() throws {
    view([tabs[0], tabs[1], tabs[2], tabs[3]])
    try ctrlTab()
    send(try key(kVK_Tab, .maskControl))                       // tabs[1]

    send(try key(kVK_ANSI_W, .maskControl))

    XCTAssertTrue(switcher.isOpen)
    XCTAssertNil(source.node(tabs[1]), "the Today tab was archived")
    XCTAssertEqual(shownTitles(), ["Tab 2", "Tab 0"])
    XCTAssertEqual(switcher.session?.highlighted, tabs[0])
    XCTAssertEqual(panel.frame.height, TabSwitcherView.height(rows: 2))
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[0])
  }

  /// Closing the last row dismisses the switcher; the tab current at open stays current.
  func testClosingEveryRowDismissesAndKeepsTheCurrentTab() throws {
    view([tabs[0], tabs[1]])
    try ctrlTab()
    send(try key(kVK_ANSI_W, .maskControl))
    XCTAssertFalse(switcher.isOpen)
    XCTAssertTrue(panel.isHidden)
    try releaseCtrl()
    XCTAssertEqual(controller.sidebarController.current, tabs[1])
  }

  /// A row's tab removed by another path collapses as if closed with W.
  func testARowRemovedElsewhereCollapses() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    source.removeNode(tabs[0])
    XCTAssertEqual(shownTitles(), ["Tab 1"])
  }

  // MARK: Rows

  /// Each row carries its Space's chip; a pane is marked as split.
  func testRowsShowTheSpaceChipAndTheSplitMarker() throws {
    let split = source.addSplit(in: .today(space))
    let pane = source.addTab(url: URL(string: "https://example.com/pane")!, title: "Pane", in: .split(split))
    view([pane, tabs[0]])
    try ctrlTab()
    let row = panel.rowViews[0]
    XCTAssertEqual(row.titleField.stringValue, "Pane")
    XCTAssertEqual(row.spaceField.stringValue, "Work")
    row.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(row.spaceField.frame.width, ceil(row.spaceField.cell?.cellSize.width ?? 0),
                                "the Space name is not truncated")
    XCTAssertFalse(row.splitView.isHidden)
    XCTAssertEqual(row.accessibilityLabel(), "Pane, Work, 1 of 1, split")
  }

  func testThePanelIsARecentTabsDialogAndTheHighlightedRowIsSelected() throws {
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    XCTAssertEqual(panel.accessibilityLabel(), "Recent tabs")
    XCTAssertEqual(panel.accessibilitySubrole(), .dialog)
    XCTAssertEqual(panel.accessibilityIdentifier(), AXID.TabSwitcher.panel)
    XCTAssertEqual(panel.rowViews[0].accessibilityLabel(), "Tab 1, Work, 1 of 2")
    XCTAssertTrue(panel.rowViews[0].isAccessibilitySelected())
    send(try key(kVK_Tab, .maskControl))
    XCTAssertTrue(panel.rowViews[1].isAccessibilitySelected())
    XCTAssertFalse(panel.rowViews[0].isAccessibilitySelected())
  }

  // MARK: Motion

  /// Reduce Motion: the highlight jumps.
  func testReduceMotionMovesTheHighlightAtOnce() throws {
    controller.showWindow(nil)
    view([tabs[0], tabs[1], tabs[2]])
    try ctrlTab()
    send(try key(kVK_Tab, .maskControl))
    XCTAssertFalse(panel.isHighlightMoving)
    XCTAssertEqual(panel.highlightOffset, TabSwitcherView.rowHeight)
    panel.layout()                                       // a layout pass must not undo the translation
    XCTAssertEqual(panel.highlightLayer.frame.minY, TabSwitcherView.rowHeight, accuracy: 0.01,
                   "the fill sits under the second row")
  }

  /// With motion, the highlight springs and a second Tab mid-flight retargets the same run.
  func testTheHighlightSpringsAndRetargetsMidFlight() throws {
    switcher.reduceMotion = { false }
    controller.showWindow(nil)
    view([tabs[0], tabs[1], tabs[2], tabs[3]])
    try ctrlTab()
    send(try key(kVK_Tab, .maskControl))
    XCTAssertTrue(panel.isHighlightMoving)
    send(try key(kVK_Tab, .maskControl))
    XCTAssertTrue(panel.isHighlightMoving)
    waitUntil("the highlight settled") { !self.panel.isHighlightMoving }
    XCTAssertEqual(panel.highlightOffset, 2 * TabSwitcherView.rowHeight, accuracy: 0.01)
  }

  /// With motion, W slides the rows below up with a transform; the panel is already at its new height.
  func testWSlidesTheRowsBelowWithATransform() throws {
    switcher.reduceMotion = { false }
    controller.showWindow(nil)
    view([tabs[0], tabs[1], tabs[2], tabs[3]])
    try ctrlTab()
    send(try key(kVK_ANSI_W, .maskControl))                    // closes tabs[2], the first row
    XCTAssertEqual(panel.frame.height, TabSwitcherView.height(rows: 2))
    XCTAssertTrue(panel.isCollapsing)
    XCTAssertGreaterThan(panel.rowViews[0].layer?.transform.m42 ?? 0, 0, "the row that took the place starts below")
    waitUntil("the rows settled") { !self.panel.isCollapsing }
    XCTAssertEqual(panel.rowViews[0].layer?.transform.m42 ?? -1, 0, accuracy: 0.01)
  }

  /// Where `title`'s row is on screen now: its slot plus the slide translation it presents.
  private func presentedY(_ title: String) throws -> CGFloat {
    let row = try XCTUnwrap(panel.rowViews.prefix(panel.rowCount).first { $0.titleField.stringValue == title })
    return row.frame.minY + (row.layer?.transform.m42 ?? 0)
  }

  /// Ticks every running row slide to `time`.
  private func stepCollapse(to time: CFTimeInterval) {
    for driver in panel.collapseDrivers where driver.isRunning { driver.tick(at: time) }
  }

  /// A second W mid-collapse (#609): every row left continues from where it is on screen, with its velocity,
  /// instead of jumping back a row and sliding again. The row above the closed one keeps its slot; the rows below it
  /// take a slot up from where they are. The clock is frozen and the display links are off, so only `tick(at:)`
  /// moves the rows, whatever the machine's speed.
  func testASecondWMidCollapseContinuesFromWhereTheRowsAre() throws {
    switcher.reduceMotion = { false }
    controller.showWindow(nil)
    var clock: CFTimeInterval = 100
    panel.collapseClock = { clock }
    panel.collapseDrivers.forEach { $0.drivesDisplayLink = false }
    view(Array(tabs[0...5]))
    try ctrlTab()
    XCTAssertEqual(shownTitles(), ["Tab 4", "Tab 3", "Tab 2", "Tab 1", "Tab 0"])

    send(try key(kVK_ANSI_W, .maskControl))                   // closes Tab 4; the four rows below slide up
    XCTAssertEqual(shownTitles(), ["Tab 3", "Tab 2", "Tab 1", "Tab 0"])
    clock = 100.03
    stepCollapse(to: clock)
    XCTAssertTrue(panel.isCollapsing)
    send(try key(kVK_Tab, .maskControl))                      // the highlight onto Tab 2, itself mid-slide
    XCTAssertEqual(switcher.session?.highlight, 1)
    let titles = ["Tab 3", "Tab 1", "Tab 0"]
    let before = try titles.map(presentedY)
    let closedAt = try presentedY("Tab 2")
    for (title, y) in zip(titles, before) {
      let slot = try XCTUnwrap(shownTitles().firstIndex(of: title))
      XCTAssertGreaterThan(y, CGFloat(slot) * TabSwitcherView.rowHeight, "\(title) is still below its slot")
    }

    send(try key(kVK_ANSI_W, .maskControl))                   // closes Tab 2 mid-collapse

    XCTAssertEqual(shownTitles(), titles)
    XCTAssertTrue(panel.isCollapsing)
    for (title, y) in zip(titles, before) {
      XCTAssertEqual(try presentedY(title), y, accuracy: 0.01, "\(title) starts from where it was on screen")
    }
    XCTAssertFalse(panel.ghost.isHidden)
    XCTAssertEqual(panel.ghost.titleField.stringValue, "Tab 2")
    XCTAssertEqual(panel.ghost.frame.minY, closedAt, accuracy: 0.01, "the closed row fades where it was on screen")

    var last = before
    for frame in 1...3 {
      stepCollapse(to: clock + Double(frame) / 120)
      let now = try titles.map(presentedY)
      for (index, title) in titles.enumerated() {
        XCTAssertLessThan(now[index], last[index], "\(title) keeps moving up on frame \(frame)")
      }
      last = now
    }
    stepCollapse(to: clock + 5)
    XCTAssertFalse(panel.isCollapsing)
    for (slot, title) in titles.enumerated() {
      XCTAssertEqual(try presentedY(title), CGFloat(slot) * TabSwitcherView.rowHeight, accuracy: 0.01)
    }
  }

  /// Reduce Motion: a second W mid-fade slides nothing; the rows sit in their slots and the moved ones fade in.
  func testReduceMotionWTwiceSlidesNothing() throws {
    controller.showWindow(nil)
    view(Array(tabs[0...5]))
    try ctrlTab()
    send(try key(kVK_ANSI_W, .maskControl))
    send(try key(kVK_ANSI_W, .maskControl))
    XCTAssertEqual(shownTitles(), ["Tab 2", "Tab 1", "Tab 0"])
    XCTAssertFalse(panel.isCollapsing)
    for row in panel.rowViews.prefix(panel.rowCount) {
      XCTAssertEqual(row.layer?.transform.m42 ?? -1, 0, "no slide")
    }
    XCTAssertNotNil(panel.rowViews[0].layer?.animation(forKey: "tabSwitcher.closeFade"), "the moved rows fade in")
  }
}

/// A focused view that takes every key, as a web page does.
@MainActor
private final class KeyEatingView: NSView {
  private(set) var keyDowns = 0
  override var acceptsFirstResponder: Bool { true }
  override func keyDown(with event: NSEvent) { keyDowns += 1 }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyDowns += 1
    return true
  }
}

extension TabSwitcherTests {
  /// A page that takes every key never sees Ctrl-Tab, Tab, W or Esc while the switcher handles them.
  func testAFocusedPageNeverSeesTheSwitcherKeys() throws {
    let page = KeyEatingView(frame: NSRect(x: 400, y: 100, width: 100, height: 100))
    controller.rootView.addSubview(page)
    XCTAssertTrue(controller.window?.makeFirstResponder(page) == true)
    controller.activate(node: tabs[0])
    controller.activate(node: tabs[1])
    controller.activate(node: tabs[2])
    XCTAssertTrue(controller.window?.makeFirstResponder(page) == true)
    let source = CGEventSource(stateID: .privateState)
    for (code, flags) in [(kVK_Tab, CGEventFlags.maskControl), (kVK_Tab, .maskControl), (kVK_ANSI_W, .maskControl),
                          (kVK_Escape, .maskControl)] {
      let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true))
      event.flags = flags
      controller.window?.sendEvent(try XCTUnwrap(NSEvent(cgEvent: event)))
    }
    XCTAssertEqual(page.keyDowns, 0)
    XCTAssertFalse(controller.tabSwitcher.isOpen)
  }
}

extension TabSwitcherTests {
  /// While the first run covers the window, Ctrl-Tab opens nothing (its menu items are disabled the same way).
  func testCtrlTabDoesNothingWhileTheFirstRunCoversTheWindow() throws {
    view([tabs[0], tabs[1]])
    _ = controller.presentOnboarding(services: FakeOnboardingServices(sidebar: source, arcFound: false),
                                     options: .init(mode: .firstRun, includesExtensions: false, resume: nil))
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Tab), keyDown: true))
    event.flags = .maskControl
    controller.window?.sendEvent(try XCTUnwrap(NSEvent(cgEvent: event)))
    XCTAssertFalse(controller.tabSwitcher.isOpen)
    XCTAssertTrue(controller.tabSwitcher.view.isHidden)
  }
}
