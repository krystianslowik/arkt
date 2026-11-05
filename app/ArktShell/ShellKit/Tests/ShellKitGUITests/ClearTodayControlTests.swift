import AppKit
import Carbon.HIToolbox
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import Motion
import SidebarModel
import XCTest
@testable import ShellUI

/// The Clear control above Today and the rows' exit motion (#413, design/clear-today-tabs): "Clear" at the trailing
/// end of the divider while the pointer is over the sidebar, always in the accessibility tree; the archived rows
/// collapse upward together on one spring and leave the model when it settles; Reduce Motion fades them in place;
/// Undo brings them back on the reverse spring. Every frame is presented by hand on the test's clock.
@MainActor
final class ClearTodayControlTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let controller: ShellWindowController
    let space: UUID
    /// Today `[t0, t1, t2, t3]`; t3 is the current tab, so it stays (#429) below the rows that go. With `split`, a
    /// two-pane split comes first: `[split, t0, t1, t2, t3]`.
    let today: [UUID]
    var split: UUID?
    var panes: [UUID] = []
    var archived: [ArchivedItem] = []
    var archiveCalls = 0
    var clock: CFTimeInterval = 1000

    init(split withSplit: Bool = false) throws {
      var sidebar = SidebarModel.Sidebar()
      let space = sidebar.addSpace(title: "Work")
      _ = try sidebar.addTab(url: URL(string: "https://example.com/p")!, title: "Pinned", in: .pinned(space))
      if withSplit {
        let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
        panes = try ["l", "r"].map {
          try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: $0, in: .split(split))
        }
        self.split = split
      }
      today = try (0..<4).map {
        try sidebar.addTab(url: URL(string: "https://example.com/t\($0)")!, title: "T\($0)", in: .today(space))
      }
      self.space = space
      let source = ModelSidebarSource(sidebar: sidebar, now: { ClearTodayControlTests.now })
      self.source = source
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
      controller.onArchive = { [unowned self] ids in
        archiveCalls += 1
        archived += source.archive(ids, reason: .manual, at: ClearTodayControlTests.now)
      }
      controller.onReopenArchived = { [unowned self] id in
        guard let index = archived.lastIndex(where: { $0.id == id }),
              let restored = try? source.restore(archived.remove(at: index), fallbackSpace: space) else {
          return nil
        }
        return restored.nodeID
      }
    }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    /// Shows the window with t3 current and puts the Clear motion on this harness's clock.
    func show(reduceMotion: Bool = false) throws {
      controller.showWindow(nil)
      controller.activate(node: today[3])
      let motion = try outline().todayClear
      motion.now = { [unowned self] in self.clock }
      motion.drivesFramesItself = false
      motion.reduceMotion = { reduceMotion }
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func advance(by seconds: CFTimeInterval) throws {
      clock += seconds
      try outline().todayClear.presentFrame()
    }

    func divider() throws -> SidebarDividerView {
      let outline = try outline()
      return try XCTUnwrap(outline.outlineView.view(atColumn: 0, row: outline.dividerRow, makeIfNecessary: false)
                             as? SidebarDividerView)
    }

    func style(_ node: UUID) throws -> FolderMotionLayout.RowStyle { try outline().rowStyle(for: node) }

    var todayNow: [UUID] { source.children(of: .today(space)) }

    /// A Clear from the control, then frames until it is `seconds` in.
    func clearAndAdvance(by seconds: CFTimeInterval) throws {
      try divider().clearButton.performClick(nil)
      try advance(by: seconds)
    }
  }

  private func key(_ keyCode: Int) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: The control

  func testTheControlShowsWhileThePointerIsOverTheSidebarAndStaysInTheAccessibilityTree() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let outline = try harness.outline()
    let button = try harness.divider().clearButton

    XCTAssertEqual(button.alphaValue, 0, "hidden until the pointer is over the sidebar")
    XCTAssertFalse(button.isHidden, "never hidden from VoiceOver")
    XCTAssertTrue(button.isEnabled)
    outline.setSidebarHovered(true)
    XCTAssertEqual(button.alphaValue, 1)
    outline.setSidebarHovered(false)
    XCTAssertEqual(button.alphaValue, 0)

    XCTAssertEqual(button.title, "Clear")
    XCTAssertEqual(button.accessibilityLabel(), "Clear Today tabs")
    XCTAssertEqual(button.accessibilityHelp(), "Moves the tabs under Today to the Archive")
    XCTAssertEqual(button.accessibilityIdentifier(), AXID.Sidebar.clearToday)
    let proxy = try XCTUnwrap(outline.outlineView.axProxyRows.element.accessibilityChildren()?
      .compactMap { $0 as? AXProxyRow }.first { $0.accessibilityIdentifier() == AXID.Sidebar.divider })
    XCTAssertTrue((proxy.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === button },
                  "the divider row lists the control while it is not drawn")
  }

  func testTheControlSitsAtTheTrailingEndOfTheDividerAndTheLineEndsBeforeIt() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let divider = try harness.divider()
    try harness.outline().setSidebarHovered(true)
    divider.layoutSubtreeIfNeeded()
    let chip = divider.clearButton.frame
    XCTAssertEqual(chip.maxX, divider.bounds.width - SidebarMetrics.faviconLeading + 2, accuracy: 0.5)
    XCTAssertEqual(chip.midY, divider.bounds.midY, accuracy: 1)
    XCTAssertLessThanOrEqual(divider.lineFrame.maxX, chip.minX - 8 + 0.5)
  }

  func testWithoutTodayTabsTheControlIsNotDrawnAndDisabled() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    for node in harness.today { harness.controller.close(node: node) }
    XCTAssertTrue(harness.todayNow.isEmpty)
    let outline = try harness.outline()
    outline.setSidebarHovered(true)
    let button = try harness.divider().clearButton
    XCTAssertFalse(button.isEnabled)
    XCTAssertEqual(button.alphaValue, 0)
  }

  // MARK: Exit motion

  func testClearCollapsesTheRowsTogetherAndArchivesThemWhenTheSpringSettles() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let leaving = Array(harness.today[0..<3])

    try harness.divider().clearButton.performClick(nil)
    XCTAssertEqual(harness.todayNow, harness.today, "the rows stay in the model while they leave")
    XCTAssertEqual(harness.archiveCalls, 0)

    try harness.advance(by: 0.06)
    let first = try harness.style(leaving[0])
    XCTAssertGreaterThan(first.alpha, 0)
    XCTAssertLessThan(first.alpha, 1)
    XCTAssertLessThan(first.scaleY, 1)
    XCTAssertLessThan(first.offsetY, 0)
    for node in leaving.dropFirst() {
      XCTAssertEqual(try harness.style(node).alpha, first.alpha, accuracy: 1e-9, "one spring, no stagger")
    }
    let kept = try harness.style(harness.today[3])
    XCTAssertEqual(kept.alpha, 1)
    XCTAssertLessThan(kept.offsetY, 0, "the kept row slides up with the same spring")

    try harness.advance(by: 2)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
    XCTAssertEqual(try harness.style(harness.today[3]), .rest)
    XCTAssertEqual(harness.archived.count, 3)
    XCTAssertFalse(try harness.outline().todayClear.isRunning)
  }

  func testAClearDuringTheExitIsIgnored() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let button = try harness.divider().clearButton
    button.performClick(nil)
    try harness.advance(by: 0.06)
    let mid = try harness.style(harness.today[0])

    button.performClick(nil)
    try harness.outline().todayClear.presentFrame()
    XCTAssertEqual(try harness.style(harness.today[0]), mid, "the running exit goes on from where it is")

    try harness.advance(by: 2)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
    XCTAssertEqual(harness.archived.count, 3, "each row archived once")
  }

  func testReduceMotionFadesTheRowsInPlaceThenTheGapCloses() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show(reduceMotion: true)

    try harness.divider().clearButton.performClick(nil)
    try harness.advance(by: FadeDuration.standard / 2)
    let fading = try harness.style(harness.today[0])
    XCTAssertGreaterThan(fading.alpha, 0)
    XCTAssertLessThan(fading.alpha, 1)
    XCTAssertEqual(fading.offsetY, 0)
    XCTAssertEqual(fading.scaleY, 1)
    XCTAssertEqual(try harness.style(harness.today[3]), .rest, "nothing moves")
    XCTAssertEqual(harness.todayNow, harness.today)

    try harness.advance(by: FadeDuration.standard)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
    XCTAssertEqual(try harness.style(harness.today[3]), .rest)
  }

  func testUndoBringsTheRowsBackOnTheReverseSpring() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    try harness.divider().clearButton.performClick(nil)
    try harness.advance(by: 2)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])

    harness.controller.toasts.performActionForTesting()
    XCTAssertEqual(harness.todayNow, harness.today, "the rows come back in their old order")
    let start = try harness.style(harness.today[0])
    XCTAssertEqual(start.alpha, 0, "they start collapsed")
    XCTAssertEqual(start.scaleY, TodayClearLayout.endScaleY)

    try harness.advance(by: 0.06)
    let opening = try harness.style(harness.today[0])
    XCTAssertGreaterThan(opening.alpha, 0)
    XCTAssertLessThan(opening.alpha, 1)

    try harness.advance(by: 2)
    for node in harness.today { XCTAssertEqual(try harness.style(node), .rest) }
  }

  func testUnderReduceMotionUndoFadesTheRowsInWithoutMoving() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show(reduceMotion: true)
    try harness.divider().clearButton.performClick(nil)
    try harness.advance(by: 1)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])

    harness.controller.toasts.performActionForTesting()
    try harness.advance(by: FadeDuration.standard / 2)
    let fading = try harness.style(harness.today[0])
    XCTAssertGreaterThan(fading.alpha, 0)
    XCTAssertLessThan(fading.alpha, 1)
    XCTAssertEqual(fading.offsetY, 0)
    XCTAssertEqual(fading.scaleY, 1)
    XCTAssertEqual(try harness.style(harness.today[3]), .rest)

    try harness.advance(by: FadeDuration.standard)
    for node in harness.today { XCTAssertEqual(try harness.style(node), .rest) }
  }

  func testAPageLeavingTheScreenMidExitArchivesAtOnce() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    try harness.divider().clearButton.performClick(nil)
    try harness.advance(by: 0.06)
    XCTAssertEqual(harness.todayNow, harness.today)

    try XCTUnwrap(harness.controller.sidebarController.currentPage).isHidden = true
    XCTAssertEqual(harness.todayNow, [harness.today[3]], "no frame needed")
    XCTAssertFalse(try harness.outline().todayClear.isRunning)
  }

  func testAWindowNotOnScreenClearsAtOnce() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    harness.controller.activate(node: harness.today[3])
    let outline = try harness.outline()
    outline.todayClear.reduceMotion = { false }
    outline.perform(.clearToday(harness.space))
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
  }

  // MARK: Every entry point (orchestrator decision on #413)

  func testTheMenuItemAndShortcutRunTheSameExitWhileTheSidebarIsOnScreen() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    harness.controller.clearTodayTabs(nil)
    XCTAssertTrue(try harness.outline().todayClear.isRunning)
    XCTAssertEqual(harness.todayNow, harness.today)
    try harness.advance(by: 2)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
  }

  // MARK: Ending early

  func testClosingTheWindowMidExitLeavesTheRowsArchived() throws {
    let harness = try Harness()
    try harness.show()
    try harness.clearAndAdvance(by: 0.06)
    harness.controller.window?.performClose(nil)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
    XCTAssertEqual(harness.archived.count, 3)
  }

  func testQuittingMidExitLeavesTheRowsArchived() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let today = try (0..<3).map {
      try sidebar.addTab(url: URL(string: "https://example.com/q\($0)")!, title: "Q\($0)", in: .today(space))
    }
    let source = ModelSidebarSource(sidebar: sidebar, now: { ClearTodayControlTests.now })
    let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: source)
    set.configure = { controller in
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: ClearTodayControlTests.now) }
    }
    let controller = set.openWindow(opensFirstTab: false)
    defer { controller.window?.orderOut(nil) }
    controller.showWindow(nil)
    controller.activate(node: today[2])
    let motion = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController.todayClear)
    var clock: CFTimeInterval = 1000
    motion.now = { clock }
    motion.drivesFramesItself = false
    motion.reduceMotion = { false }
    controller.clearTodayTabs(nil)
    clock += 0.06
    motion.presentFrame()
    XCTAssertTrue(motion.isRunning)

    set.saveSessionsForTermination()
    XCTAssertEqual(source.children(of: .today(space)), [today[2]])
  }

  func testMinimizingMidExitLeavesTheRowsArchived() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    try harness.clearAndAdvance(by: 0.06)
    harness.controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
  }

  func testCmdZMidExitUndoesTheClearOnTheReturnSpring() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    try harness.clearAndAdvance(by: 0.06)

    XCTAssertTrue(harness.controller.reopenClosed())
    XCTAssertEqual(harness.todayNow, harness.today)
    let motion = try harness.outline().todayClear
    XCTAssertEqual(motion.direction, .returning)
    XCTAssertEqual(try harness.style(harness.today[0]).alpha, 0, "they come back from collapsed")
    try harness.advance(by: 2)
    for node in harness.today { XCTAssertEqual(try harness.style(node), .rest) }
  }

  // MARK: The Clear rules at settle

  func testARowActivatedMidExitStaysAndStaysCurrent() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    try harness.clearAndAdvance(by: 0.06)

    let outline = try harness.outline()
    outline.handleClick(row: outline.row(for: harness.today[0]), modifiers: [])
    XCTAssertEqual(harness.controller.currentNode, harness.today[3], "clicks on the rows are ignored mid-exit")
    XCTAssertNil(outline.outlineView(outline.outlineView, pasteboardWriterForItem:
                                       try XCTUnwrap(outline.outlineView.item(atRow: outline.row(for: harness.today[1])))),
                 "no drag starts mid-exit")

    harness.controller.activate(node: harness.today[1])
    try harness.advance(by: 2)
    XCTAssertTrue(harness.todayNow.contains(harness.today[1]), "a row shown meanwhile stays")
    XCTAssertEqual(harness.controller.currentNode, harness.today[1])
    XCTAssertFalse(harness.todayNow.contains(harness.today[0]))
  }

  // MARK: Containers

  func testAnExpandedSplitLeavesWithItsPaneRows() throws {
    let harness = try Harness(split: true)
    defer { harness.controller.close() }
    try harness.show()
    let outline = try harness.outline()
    let split = try XCTUnwrap(harness.split)
    let paneRows = harness.panes.map(outline.row(for:))
    XCTAssertTrue(paneRows.allSatisfy { $0 >= 0 }, "the split shows its panes")
    let leavingRows = [outline.row(for: split)] + paneRows + harness.today[0..<3].map(outline.row(for:))
    let gap = leavingRows.reduce(CGFloat(0)) { $0 + outline.outlineView.rect(ofRow: $1).height }

    try harness.clearAndAdvance(by: 0.06)
    let gone = 1 - (try harness.style(split)).alpha
    XCTAssertGreaterThan(gone, 0)
    for pane in harness.panes {
      XCTAssertEqual(try harness.style(pane).alpha, 1 - gone, accuracy: 1e-9, "the panes fade with their split")
    }
    XCTAssertEqual(try harness.style(harness.today[3]).offsetY, -gone * gap, accuracy: 0.01,
                   "the panes' height counts toward the gap")

    try harness.advance(by: 2)
    XCTAssertEqual(harness.todayNow, [harness.today[3]])
  }

  // MARK: Keyboard

  func testTabFromAFocusedRowReachesTheControlAndReturnPressesIt() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let outline = try harness.outline()
    let view = outline.outlineView
    harness.controller.revealCurrentTab(nil)
    XCTAssertTrue(harness.controller.window?.firstResponder === view)

    view.keyDown(with: try key(kVK_Tab))
    let button = try harness.divider().clearButton
    XCTAssertTrue(harness.controller.window?.firstResponder === button, "Tab reached the control")
    XCTAssertEqual(button.alphaValue, 1, "drawn while it has the keyboard focus")

    button.keyDown(with: try key(kVK_Tab))
    XCTAssertTrue(harness.controller.window?.firstResponder === view, "Tab goes back to the rows")
    XCTAssertEqual(view.keyboardFocusRow, outline.dividerRow + 1)
    XCTAssertEqual(button.alphaValue, 0)

    view.keyDown(with: try key(kVK_Tab))
    button.keyDown(with: try key(kVK_Return))
    XCTAssertTrue(outline.todayClear.isRunning, "Return pressed it")
  }

  // MARK: Hover

  func testAHiddenPageForgetsTheHover() throws {
    let harness = try Harness()
    defer { harness.controller.close() }
    try harness.show()
    let page = try XCTUnwrap(harness.controller.sidebarController.currentPage)
    page.outlineController.setSidebarHovered(true)
    page.isHidden = true
    XCTAssertFalse(page.outlineController.isSidebarHovered)
  }
}
