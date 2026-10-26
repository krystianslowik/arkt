import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Sidebar tab actions (#105): inline rename (BH-026), duplicate with history (BH-027), Cmd-click and Shift-click
/// multi-selection (BH-028) and its bulk actions (BH-072, BH-094, BH-117), Archive Below (BH-077), Clear Today Tabs
/// (BH-075), the empty-area gestures (BH-021, BH-023), the non-key dimming (BH-025) and the menus' window actions.
@MainActor
final class TabActionsTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// Work: Today `[t0, t1, t2, split(s0, s1), t3]`; Personal: empty.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var work: UUID
    var personal: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.arkt.tests.\(UUID().uuidString)"))
    var archived: [UUID] = []
    var archivedItems: [ArchivedItem] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { TabActionsTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.linkPasteboard = pasteboard
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        archived += ids
        archivedItems += source.archive(ids, reason: .manual, at: TabActionsTests.now)
      }
      // Reopen and Undo bring a row back from what this harness archived, as the app's coordinator does.
      controller.onReopenArchived = { [unowned self] id in
        guard let index = archivedItems.lastIndex(where: { $0.id == id }),
              let space = source.spaceOrder.first,
              let restored = try? source.restore(archivedItems.remove(at: index), fallbackSpace: space) else {
          return nil
        }
        return restored.nodeID
      }
      try? outline().clipboardURL = { [pasteboard] in
        pasteboard.string(forType: .string).flatMap { URL(string: $0) }
      }
    }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }

    func click(_ node: UUID, _ modifiers: NSEvent.ModifierFlags = []) throws {
      try outline().handleClick(row: row(node), modifiers: modifiers)
    }

    func menu(_ node: UUID?) throws -> NSMenu {
      let row = try node.map { try self.row($0) } ?? -1
      return try XCTUnwrap(try outline().menu(forRow: row), "no context menu")
    }

    func titles(_ node: UUID?) throws -> [String] {
      try menu(node).items.filter { !$0.isAlternate }.map(\.title)
    }

    /// Chooses `path` (a title, or a submenu title then an item title) in `node`'s menu (nil: the empty area).
    func choose(_ path: String..., on node: UUID?) throws {
      var menu = try self.menu(node)
      for title in path.dropLast() {
        menu = try XCTUnwrap(menu.item(withTitle: title)?.submenu, "no submenu \(title)")
      }
      let index = menu.indexOfItem(withTitle: path[path.count - 1])
      XCTAssertGreaterThanOrEqual(index, 0, "no menu item \(path)")
      XCTAssertTrue(menu.item(at: index)?.isEnabled ?? false, "\(path) is disabled")
      menu.performActionForItem(at: index)
    }

    func cell(_ node: UUID) throws -> SidebarTabCellView {
      try XCTUnwrap(try outline().outlineView.view(atColumn: 0, row: row(node), makeIfNecessary: false)
        as? SidebarTabCellView)
    }

    func rowState(_ node: UUID) throws -> TabRowState? {
      (try outline().outlineView.rowView(atRow: row(node), makeIfNecessary: false) as? SidebarRowView)?.state
    }

    func title(_ node: UUID) -> String? {
      switch source.node(node) {
      case .tab(_, _, let title)?, .folder(_, let title)?: title
      default: nil
      }
    }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }
    var current: UUID? { controller.sidebarController.current }
    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let personal = sidebar.addSpace(title: "Personal")
    var today = try (0..<3).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(work)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(work))
    let panes = try (0..<2).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    today.append(try sidebar.addTab(url: url("t3"), title: "T3", in: .today(work)))
    return World(sidebar: sidebar, work: work, personal: personal, today: today, split: split, panes: panes)
  }

  // MARK: Rename (BH-026)

  /// Rename from the menu: the field opens on the row with the title selected; Return keeps the typed name, and the
  /// next page title does not replace it.
  func testRenameFromTheMenuPersistsTheCustomTitle() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])

    try harness.choose("Rename", on: world.today[1])

    let cell = try harness.cell(world.today[1])
    let field = try XCTUnwrap(cell.renameField, "the rename field opens")
    XCTAssertEqual(field.focusRingType, .default, "the system focus ring")
    XCTAssertEqual(field.stringValue, "T1")
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2), "the whole title is selected")
    editor.insertText("Reading list", replacementRange: editor.selectedRange())
    editor.insertNewline(nil)

    XCTAssertNil(cell.renameField, "Return closes the field")
    XCTAssertEqual(harness.title(world.today[1]), "Reading list")
    guard case .tab(let item)? = harness.source.sidebar.nodes[world.today[1]]?.kind else {
      return XCTFail("not a tab")
    }
    XCTAssertEqual(item.customTitle, "Reading list", "the custom title is in the stored model")
    let tab = try XCTUnwrap(harness.tab(world.today[1]))
    harness.engine.setDocumentTitle(tab, "Page title")
    XCTAssertEqual(harness.title(world.today[1]), "Reading list", "a page title never replaces it")
    harness.controller.close()
  }

  func testEscapeKeepsTheOldTitle() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.outline().beginRename(world.today[0]))
    let field = try XCTUnwrap(try harness.cell(world.today[0]).renameField)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.insertText("Other", replacementRange: editor.selectedRange())
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

    XCTAssertNil(try harness.cell(world.today[0]).renameField)
    XCTAssertEqual(harness.title(world.today[0]), "T0")
    XCTAssertEqual(try harness.cell(world.today[0]).titleField.stringValue, "T0")
    harness.controller.close()
  }

  /// An accidental double-click followed by Return (or a click elsewhere) stores no custom title: the row keeps
  /// following the page title.
  func testCommittingAnUnchangedTitleStoresNoCustomTitle() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    XCTAssertTrue(try harness.outline().beginRename(world.today[0]))
    let field = try XCTUnwrap(try harness.cell(world.today[0]).renameField)
    try XCTUnwrap(field.currentEditor() as? NSTextView).insertNewline(nil)

    XCTAssertNil(try harness.cell(world.today[0]).renameField, "Return closes the field")
    guard case .tab(let item)? = harness.source.sidebar.nodes[world.today[0]]?.kind else {
      return XCTFail("not a tab")
    }
    XCTAssertNil(item.customTitle, "an unchanged name is not a rename")
    harness.engine.setDocumentTitle(try XCTUnwrap(harness.tab(world.today[0])), "Page title")
    XCTAssertEqual(harness.title(world.today[0]), "Page title", "the row still follows the page")
    harness.controller.close()
  }

  /// A page title arriving while the field is open leaves the field open (the row reload waits for it).
  func testAPageTitleDuringRenameDoesNotCloseTheField() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    XCTAssertTrue(try harness.outline().beginRename(world.today[0]))
    harness.engine.setDocumentTitle(try XCTUnwrap(harness.tab(world.today[0])), "Changed")
    XCTAssertNotNil(try harness.cell(world.today[0]).renameField)
    try harness.cell(world.today[0]).endRename(commit: false)
    XCTAssertEqual(try harness.cell(world.today[0]).titleField.stringValue, "Changed")
    harness.controller.close()
  }

  /// GS-004: a double-click on a tab row opens the field; on a folder it does not.
  func testDoubleClickOnATabRowOpensRename() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .pinned(world.work))
    let harness = Harness(world.sidebar)
    let outline = try harness.outline()
    outline.handleDoubleClick(row: try harness.row(folder), modifiers: [])
    XCTAssertNil(outline.renamingNode)
    outline.handleDoubleClick(row: try harness.row(world.today[2]), modifiers: [])
    XCTAssertEqual(outline.renamingNode, world.today[2])
    XCTAssertNotNil(try harness.cell(world.today[2]).renameField)
    harness.controller.close()
  }

  // MARK: Real mouse events through the table's own dispatch

  /// Shows the window with `current` focused and lays it out, as before a real click (`SplitSidebarTests`).
  private func shownOutline(_ harness: Harness, current: UUID) throws -> (NSWindow, SidebarOutlineView) {
    harness.controller.showWindow(nil)
    let window = try XCTUnwrap(harness.controller.window)
    harness.controller.activate(node: current)
    let view = try harness.outline().outlineView
    window.contentView?.layoutSubtreeIfNeeded()
    view.layoutSubtreeIfNeeded()
    return (window, view)
  }

  private func point(of node: UUID, in harness: Harness, _ view: SidebarOutlineView) throws -> NSPoint {
    let rect = view.rect(ofRow: try harness.row(node))
    let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    XCTAssertEqual(view.row(at: view.convert(point, from: nil)), try harness.row(node))
    return point
  }

  /// One click: the mouse-up is queued for the table's tracking loop, the mouse-down goes straight in.
  private func click(at point: NSPoint, _ flags: NSEvent.ModifierFlags = [], count: Int = 1,
                     in window: NSWindow, _ view: SidebarOutlineView) throws {
    func event(_ type: NSEvent.EventType) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count,
        pressure: type == .leftMouseUp ? 0 : 1))
    }
    window.postEvent(try event(.leftMouseUp), atStart: true)
    view.mouseDown(with: try event(.leftMouseDown))
    window.discardEvents(matching: [.leftMouseUp], before: nil)
  }

  /// A real Cmd-click selects (the table sends its action with selection off) and does not activate.
  func testARealCommandClickSelectsWithoutActivating() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let (window, view) = try shownOutline(harness, current: world.today[0])

    try click(at: try point(of: world.today[2], in: harness, view), [.command], in: window, view)

    XCTAssertEqual(try harness.outline().selectedNodes, [world.today[0], world.today[2]])
    XCTAssertEqual(harness.current, world.today[0])
  }

  /// A real double-click on a tab row: the first click activates, the second opens the rename field. On a folder the
  /// second click neither renames nor toggles the folder back.
  func testARealDoubleClickRenamesATabAndTogglesAFolderOnce() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .pinned(world.work))
    try world.sidebar.addTab(url: Self.url("f"), title: "F0", in: .folder(folder))
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let (window, view) = try shownOutline(harness, current: world.today[0])

    let tabPoint = try point(of: world.today[2], in: harness, view)
    try click(at: tabPoint, in: window, view)
    try click(at: tabPoint, count: 2, in: window, view)
    XCTAssertEqual(harness.current, world.today[2])
    XCTAssertEqual(try harness.outline().renamingNode, world.today[2])
    try harness.cell(world.today[2]).endRename(commit: false)

    let folderPoint = try point(of: folder, in: harness, view)
    try click(at: folderPoint, in: window, view)
    try click(at: folderPoint, count: 2, in: window, view)
    XCTAssertFalse(try harness.outline().isFolderOpen(folder),
                   "the first click closed it and the second did not reopen it")
    XCTAssertNil(try harness.outline().renamingNode)
  }

  /// A click on another row while the field is open keeps the typed name (design 4.1).
  func testAClickElsewhereCommitsTheRename() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    defer { harness.controller.close() }
    let (window, view) = try shownOutline(harness, current: world.today[0])
    XCTAssertTrue(try harness.outline().beginRename(world.today[1]))
    let editor = try XCTUnwrap(try harness.cell(world.today[1]).renameField?.currentEditor() as? NSTextView)
    editor.insertText("Typed", replacementRange: editor.selectedRange())

    try click(at: try point(of: world.today[3], in: harness, view), in: window, view)

    XCTAssertNil(try harness.outline().renamingNode)
    XCTAssertEqual(harness.title(world.today[1]), "Typed")
    XCTAssertEqual(harness.current, world.today[3])
  }

  // MARK: Duplicate (BH-027)

  func testDuplicateCopiesTheTabWithItsHistoryRightAfterIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.tab(world.today[0]))
    harness.engine.navigate(tab, to: Self.url("next"))
    XCTAssertEqual(harness.engine.history(of: tab)?.back.count, 1)

    try harness.choose("Duplicate", on: world.today[0])

    let today = harness.children(.today(world.work))
    XCTAssertEqual(today.count, world.today.count + 2)
    XCTAssertEqual(today[0], world.today[0])
    let copy = today[1]
    XCTAssertEqual(harness.current, copy, "the copy becomes current")
    let copyTab = try XCTUnwrap(harness.tab(copy))
    XCTAssertEqual(harness.engine.history(of: copyTab)?.back.count, 1, "history comes along")
    XCTAssertEqual(harness.engine.snapshot(of: copyTab)?.url, Self.url("next"))
    harness.controller.close()
  }

  // MARK: Multi-selection (BH-028)

  func testCommandClickSelectsTheCurrentRowAndTheClickedRow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.click(world.today[2], .command)

    XCTAssertEqual(try harness.outline().selectedNodes, [world.today[0], world.today[2]])
    XCTAssertEqual(harness.current, world.today[0], "Cmd-click does not activate")
    XCTAssertEqual(try harness.rowState(world.today[2]), .contentVisible, "the selected fill")
    XCTAssertEqual(try harness.rowState(world.today[0]), .current, "current wins over selected")
    XCTAssertEqual(try harness.rowState(world.today[1]), .normal)

    try harness.click(world.today[1])
    XCTAssertEqual(try harness.outline().selectedNodes, [], "a plain click ends the selection")
    XCTAssertEqual(try harness.rowState(world.today[2]), .normal)
    harness.controller.close()
  }

  /// Shift-click: the contiguous range; panes are skipped (their split row stands for them).
  func testShiftClickSelectsARangeWithTheSplitRowAndNoPanes() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])

    try harness.click(world.today[3], .shift)

    XCTAssertEqual(try harness.outline().selectedNodes, [world.today[1], world.today[2], world.split, world.today[3]])
    try harness.click(world.panes[0], .command)
    XCTAssertFalse(try harness.outline().selectedNodes.contains(world.panes[0]), "a pane is never selected")
    harness.controller.close()
  }

  /// The selection works with the keyboard focus ring (#103): a Cmd-click removes the ring like any click, and the
  /// ring's Up / Down keep working over a selection.
  func testSelectionAndTheKeyboardFocusRingCoexist() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let outline = try harness.outline()
    try harness.click(world.today[1], .command)
    outline.focusKeyboard(on: try harness.row(world.today[2]))
    XCTAssertFalse(outline.outlineView.keyboardFocusRing.isHidden)
    XCTAssertEqual(outline.selectedNodes, [world.today[0], world.today[1]], "focus does not change the selection")
    harness.controller.close()
  }

  /// Another tab coming forward (here a Favorite-style activation, not a row click) ends the selection, so Cmd-W then
  /// closes only the tab on screen.
  func testActivatingAnotherTabEndsTheSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    try harness.click(world.today[1], .command)
    XCTAssertEqual(try harness.outline().selectedNodes, [world.today[0], world.today[1]])

    harness.controller.activate(node: world.today[3])
    XCTAssertEqual(try harness.outline().selectedNodes, [], "the selection ends")
    XCTAssertEqual(try harness.rowState(world.today[1]), .normal)
    harness.controller.closeTab(nil)
    XCTAssertEqual(harness.archived, [world.today[3]], "only the tab on screen is archived")
    harness.controller.close()
  }

  /// A plain press on empty sidebar space ends the selection, as a plain click on a row does (design 6).
  func testAPlainClickOnEmptySpaceEndsTheSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    try harness.click(world.today[1], .command)
    let view = try harness.outline().outlineView
    view.performWindowDrag = { _, _ in }
    let below = view.convert(NSPoint(x: 40, y: view.rect(ofRow: view.numberOfRows - 1).maxY + 40), to: nil)
    let press = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: below, modifierFlags: [], timestamp: 0,
      windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

    view.mouseDown(with: press)

    XCTAssertEqual(try harness.outline().selectedNodes, [])
    harness.controller.close()
  }

  /// BH-072: Cmd-W archives every selected row at once; the split goes as one unit, nothing is torn out of it, and
  /// the toast counts the tabs.
  func testCommandWArchivesTheWholeSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    try harness.click(world.split, .shift)              // t1, t2, split

    harness.controller.closeTab(nil)

    XCTAssertEqual(Set(harness.archived), [world.today[1], world.today[2], world.split])
    XCTAssertEqual(harness.children(.today(world.work)), [world.today[0], world.today[3]])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Archived 4 tabs")
    XCTAssertNotNil(harness.current, "another tab becomes current")
    XCTAssertTrue([world.today[0], world.today[3]].contains(harness.current ?? UUID()))
    XCTAssertEqual(try harness.outline().selectedNodes, [], "the archived rows left the selection")
    harness.controller.close()
  }

  /// A selected row whose close waits on a leave-site prompt is leaving too: the current row's successor skips it,
  /// so the card never lands on a tab that is about to be archived.
  func testABulkCloseSkipsARowHeldByALeaveSitePrompt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[2])
    let held = try XCTUnwrap(harness.tab(world.today[2]))
    harness.engine.holdClose(held)
    harness.controller.activate(node: world.today[1])
    try harness.click(world.today[2], .command)          // t1 (current) and t2 (held)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.archived, [world.today[1]], "t2 waits on its prompt")
    XCTAssertEqual(harness.current, world.panes[0], "the next row that stays: the split's first pane")
    XCTAssertTrue(harness.engine.answerDialog(held, accept: true))
    XCTAssertEqual(harness.archived, [world.today[1], world.today[2]])
    XCTAssertEqual(harness.current, world.panes[0])
    harness.controller.close()
  }

  /// Decision 3: a bulk archive shows "Archived N tabs" with Undo (no key hint, 6 s); Undo brings every row back at
  /// its place, as one unit, and takes the toast down.
  func testUndoOnTheToastRestoresTheWholeSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let before = harness.children(.today(world.work))
    harness.controller.activate(node: world.today[1])
    try harness.click(world.split, .shift)              // t1, t2, split

    let rows = [world.today[1], world.today[2]] + world.panes          // the archived ones
    let loadedBefore = Set(rows.filter { harness.tab($0) != nil })
    harness.controller.closeTab(nil)
    let toast = try XCTUnwrap(harness.controller.toasts.current)
    XCTAssertEqual(toast.kind, .undo)
    XCTAssertEqual(toast.actionTitle, "Undo")
    XCTAssertNil(toast.shortcut)
    XCTAssertEqual(toast.glyph, "archivebox")
    XCTAssertEqual(toast.duration, .seconds(6))

    harness.controller.toasts.performActionForTesting()

    XCTAssertEqual(harness.children(.today(world.work)), before)
    XCTAssertEqual(harness.current, world.today[1], "the tab that was current comes back current")
    XCTAssertTrue(Set(rows.filter { harness.tab($0) != nil }).isSubset(of: loadedBefore),
                  "no page loads for rows that were not loaded")
    XCTAssertNil(harness.controller.toasts.current)
    XCTAssertFalse(harness.controller.reopenClosed(), "the batch left the stack with the Undo")
    harness.controller.close()
  }

  /// Cmd-Z after a bulk archive restores the same rows the Undo would, in one step, and dismisses the undo toast.
  func testCommandZRestoresTheSameRowsAsUndo() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let before = harness.children(.today(world.work))
    harness.controller.activate(node: world.today[1])
    try harness.click(world.split, .shift)

    harness.controller.closeTab(nil)
    XCTAssertTrue(harness.controller.reopenClosed())

    XCTAssertEqual(harness.children(.today(world.work)), before)
    XCTAssertNil(harness.controller.toasts.current, "the undo toast goes with its batch")
    harness.controller.close()
  }

  /// Clear Today Tabs comes back whole with one Undo, its rows in their order.
  func testUndoAfterClearTodayRestoresEveryRow() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .today(world.work))
    _ = try world.sidebar.addTab(url: Self.url("f"), title: "F0", in: .folder(folder))
    let harness = Harness(world.sidebar)
    let before = harness.children(.today(world.work))
    harness.controller.activate(node: world.today[0])
    try harness.choose("Clear Today Tabs", on: nil)
    XCTAssertEqual(harness.children(.today(world.work)), [])

    harness.controller.toasts.performActionForTesting()

    XCTAssertEqual(harness.children(.today(world.work)), before)
    harness.controller.close()
  }

  /// An auto-archive pass is its own undo unit: its toast's Undo brings back exactly the rows the pass took, not an
  /// earlier Cmd-W, which Cmd-Z then takes back on its own.
  func testUndoAfterAutoArchiveRestoresExactlyThatPass() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    harness.controller.closeTab(nil)                                   // a single Cmd-W first
    harness.controller.activate(node: world.today[0])
    let pass = [world.today[2], world.today[3]]
    harness.controller.onArchive?(pass)                                // what the auto-archive coordinator does
    harness.controller.rememberAutoArchived(pass, toast: ToastText.autoArchiveToast(count: pass.count))
    XCTAssertTrue(Set(harness.children(.today(world.work))).isDisjoint(with: pass + [world.today[1]]))
    XCTAssertEqual(harness.controller.toasts.current?.kind, .undo)

    harness.controller.toasts.performActionForTesting()

    let restored = Set(harness.children(.today(world.work)))
    XCTAssertTrue(restored.isSuperset(of: pass), "the pass comes back")
    XCTAssertFalse(restored.contains(world.today[1]), "the earlier Cmd-W stays undone")
    XCTAssertEqual(harness.current, world.today[0], "undoing a pass changes no current tab")
    XCTAssertTrue(harness.controller.reopenClosed())
    XCTAssertTrue(Set(harness.children(.today(world.work))).contains(world.today[1]), "Cmd-Z takes the Cmd-W back")
    XCTAssertFalse(harness.controller.reopenClosed(), "nothing is left to undo")
    harness.controller.close()
  }

  /// A single row's Cmd-W keeps its old behavior: no toast (alerts design, decision 3).
  func testSingleArchiveShowsNoToast() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.controller.closeTab(nil)
    XCTAssertEqual(harness.archived, [world.today[0]])
    XCTAssertNil(harness.controller.toasts.current)
    harness.controller.close()
  }

  func testRightClickOnASelectedRowShowsTheMultiSelectionMenu() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    try harness.click(world.today[1], .command)

    XCTAssertEqual(try harness.titles(world.today[1]),
                   ["Open in Split View", "New Folder", "", "Duplicate", "Pin Tabs", "Move To", "", "Copy Links", "",
                    "Archive"])
    XCTAssertEqual(try harness.titles(world.today[3]).first, "Rename", "an unselected row gets its own menu")
    XCTAssertEqual(try harness.outline().selectedNodes, [], "and the selection ends (OQ10)")
    harness.controller.close()
  }

  /// Pin Tabs on a selection holding a split: the split moves whole into Pinned, its panes stay in it.
  func testPinTabsMovesSplitsWhole() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[2])
    try harness.click(world.split, .command)

    try harness.choose("Pin Tabs", on: world.split)

    XCTAssertEqual(harness.children(.pinned(world.work)), [world.today[2], world.split])
    XCTAssertEqual(harness.children(.split(world.split)), world.panes, "the panes stay in their split")
    harness.controller.close()
  }

  /// BH-094: New Folder pins the selection into a new folder.
  func testNewFolderPinsTheSelectionIntoAFolder() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    try harness.click(world.today[1], .command)

    try harness.choose("New Folder", on: world.today[1])

    let pinned = harness.children(.pinned(world.work))
    XCTAssertEqual(pinned.count, 1)
    let folder = try XCTUnwrap(pinned.first)
    XCTAssertEqual(harness.children(.folder(folder)), [world.today[0], world.today[1]])
    XCTAssertEqual(try harness.outline().renamingNode, folder, "the new folder opens for naming [I]")
    harness.controller.close()
  }

  /// BH-117: Open in Split View joins 2 to 4 selected tabs into one split at the first one's place.
  func testOpenInSplitViewJoinsTheSelection() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    try harness.click(world.today[2], .command)

    try harness.choose("Open in Split View", on: world.today[2])

    let today = harness.children(.today(world.work))
    let split = try XCTUnwrap(today.first)
    XCTAssertEqual(harness.children(.split(split)), [world.today[0], world.today[2]])
    XCTAssertEqual(today, [split, world.today[1], world.split, world.today[3]])
    harness.controller.close()
  }

  func testMoveToSpaceMovesTheTabToThatSpacesToday() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.choose("Move To", "Personal", on: world.today[3])

    XCTAssertEqual(harness.children(.today(world.personal)), [world.today[3]])
    XCTAssertFalse(harness.children(.today(world.work)).contains(world.today[3]))
    harness.controller.close()
  }

  // MARK: Archive Below, Clear Today Tabs, Copy Link, Paste URL

  /// BH-077: every Today row below goes, the split as one unit, with the several-tabs toast.
  func testArchiveBelowArchivesEveryRowBelow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.choose("Archive Below", on: world.today[1])

    XCTAssertEqual(harness.children(.today(world.work)), [world.today[0], world.today[1]])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Archived 4 tabs")
    XCTAssertEqual(harness.current, world.today[0])
    harness.controller.close()
  }

  /// Archive Below on a pane archives only the panes below it; the split keeps the rest.
  func testArchiveBelowOnAPaneShrinksTheSplit() throws {
    var world = try Self.makeWorld()
    let third = try world.sidebar.addTab(url: Self.url("s2"), title: "S2", in: .split(world.split))
    let harness = Harness(world.sidebar)

    try harness.choose("Archive Below", on: world.panes[0])

    XCTAssertEqual(Set(harness.archived), [world.panes[1], third], "each pane below archives alone")
    XCTAssertNil(harness.source.node(world.panes[1]))
    XCTAssertNil(harness.source.node(third))
    XCTAssertNotNil(harness.source.node(world.panes[0]), "the clicked pane stays")
    XCTAssertEqual(harness.children(.today(world.work)).count, world.today.count + 1, "no other row is touched")
    harness.controller.close()
  }

  /// BH-075: Clear Today Tabs on the empty area archives every Today tab of the Space.
  func testClearTodayTabsFromTheEmptyAreaMenu() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.choose("Clear Today Tabs", on: nil)

    XCTAssertEqual(harness.children(.today(world.work)), [])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Archived 6 tabs")
    harness.controller.close()
  }

  func testCopyLinkAndItsMarkdownAlternate() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    try harness.choose("Copy Link", on: world.today[0])
    XCTAssertEqual(harness.pasteboard.string(forType: .string), "https://example.com/t0")
    try harness.choose("Copy Link as Markdown", on: world.today[0])
    XCTAssertEqual(harness.pasteboard.string(forType: .string), "[T0](https://example.com/t0)")
    harness.controller.close()
  }

  func testPasteURLAsNewTabIntoAFolder() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .pinned(world.work))
    let harness = Harness(world.sidebar)
    harness.pasteboard.clearContents()
    harness.pasteboard.setString("https://example.org/pasted", forType: .string)

    try harness.choose("Paste URL as New Tab", on: folder)

    let inside = harness.children(.folder(folder))
    XCTAssertEqual(inside.count, 1)
    guard case .tab(_, let url, _)? = harness.source.node(inside[0]) else { return XCTFail("not a tab") }
    XCTAssertEqual(url, URL(string: "https://example.org/pasted"))
    harness.controller.close()
  }

  /// BH-095: Delete sends the folder and its tabs to the Archive.
  func testDeleteFolderArchivesIt() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .pinned(world.work))
    try world.sidebar.addTab(url: Self.url("f"), title: "F0", in: .folder(folder))
    let harness = Harness(world.sidebar)

    try harness.choose("Delete", on: folder)

    XCTAssertEqual(harness.archived, [folder])
    XCTAssertNil(harness.source.node(folder))
    harness.controller.close()
  }

  /// BH-095 with the current tab inside: a Split View in the folder goes to the Archive whole, and the window shows
  /// the next tab instead of going blank, as Close Tab does (#109 review).
  func testDeleteFolderHoldingTheCurrentSplitShowsTheNextTab() throws {
    var world = try Self.makeWorld()
    let folder = try world.sidebar.addFolder(title: "F", in: .pinned(world.work))
    let split = try world.sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .folder(folder))
    let panes = try (0..<2).map { try world.sidebar.addTab(url: Self.url("fs\($0)"), title: "FS\($0)",
                                                           in: .split(split)) }
    let after = try world.sidebar.addTab(url: Self.url("p0"), title: "P0", in: .pinned(world.work))
    let harness = Harness(world.sidebar)
    harness.controller.showWindow(nil)
    defer { harness.controller.close() }
    harness.controller.activate(node: panes[1])
    try harness.outline().toggleFolder(folder, animated: false)     // the pane's split peeks out of the closed folder
    XCTAssertGreaterThanOrEqual(try harness.outline().row(for: split), 0)

    try harness.choose("Delete", on: folder)

    XCTAssertEqual(harness.archived, [folder], "the folder goes whole; its split is not split up")
    for node in [folder, split] + panes { XCTAssertNil(harness.source.node(node)) }
    XCTAssertEqual(harness.current, after, "the next tab becomes current")
    XCTAssertEqual(try harness.outline().row(for: split), -1, "no row of the folder is left")
    XCTAssertGreaterThanOrEqual(try harness.outline().row(for: after), 0)
  }

  // MARK: Favorite tile (design 3.3)

  /// A right-click on a tile opens the Favorite menu; Remove from Favorites puts it on top of the current Today.
  func testFavoriteTileMenuRemovesTheFavorite() throws {
    var world = try Self.makeWorld()
    let favorite = try world.sidebar.addTab(url: Self.url("fav"), title: "Fav", in: .favorites(profile: "default"))
    let harness = Harness(world.sidebar)
    let grid = harness.controller.sidebarController.view.favorites
    grid.layoutSubtreeIfNeeded()
    let tile = try XCTUnwrap(grid.tile(for: favorite))
    let center = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: center, modifierFlags: [],
                                                 timestamp: 0, windowNumber: grid.window?.windowNumber ?? 0,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    let menu = try XCTUnwrap(grid.collectionView.menu(for: event), "the tile has a menu")
    XCTAssertEqual(menu.items.filter { !$0.isAlternate }.map(\.title),
                   ["Rename", "Change Icon", "", "Back to Pinned URL", "Edit Pinned URL", "", "Copy Link", "",
                    "Remove from Favorites", "Close and Keep Favorite"])

    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Remove from Favorites"))

    XCTAssertEqual(harness.children(.favorites(profile: "default")), [])
    XCTAssertEqual(harness.children(.today(world.work)).first, favorite)
    harness.controller.close()
  }

  // MARK: Empty area (BH-021, BH-023) and dimming (BH-025)

  func testDoubleClickOnEmptySidebarSpaceOpensTheCommandBar() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let view = try harness.outline().outlineView
    var drags = 0
    view.performWindowDrag = { _, _ in drags += 1 }
    let below = NSPoint(x: 40, y: view.rect(ofRow: view.numberOfRows - 1).maxY + 40)
    XCTAssertLessThan(view.row(at: below), 0, "the point is below every row")
    let point = view.convert(below, to: nil)
    func mouseDown(_ clicks: Int) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                                       clickCount: clicks, pressure: 1))
    }

    view.mouseDown(with: try mouseDown(1))
    XCTAssertEqual(drags, 1, "a press on empty space drags the window (BH-023)")
    XCTAssertFalse(harness.controller.commandBar.isVisible)
    view.mouseDown(with: try mouseDown(2))
    XCTAssertTrue(harness.controller.commandBar.isVisible, "a double-click opens the command bar (BH-021)")
    harness.controller.close()
  }

  /// A sheet (Delete Space) or a child window taking key is the window's own, like the command bar panel.
  func testSheetsAndChildWindowsDoNotDimTheSidebar() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)
    let child = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.borderless],
                         backing: .buffered, defer: true)
    window.addChildWindow(child, ordered: .above)
    let own = harness.controller.ownKeyableWindows
    XCTAssertTrue(own.contains { $0 === harness.controller.commandBar.panel })
    XCTAssertTrue(own.contains { $0 === child })
    XCTAssertFalse(ShellWindowController.dimsSidebar(window: window, keyWindow: child, isKey: false, ownPanels: own))
    window.removeChildWindow(child)
    harness.controller.close()
  }

  func testTheSidebarDimsWhileTheWindowIsNotKey() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let sidebar = harness.controller.sidebarController.view
    XCTAssertFalse(sidebar.isDimmed)
    harness.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
    waitUntil("the sidebar to dim once no window of ours is key") { sidebar.isDimmed }
    XCTAssertEqual(sidebar.pager.alphaValue, SidebarContainerView.dimmedAlpha, accuracy: 0.001)
    XCTAssertEqual(harness.controller.rootView.card.alphaValue, 1, "the content card is untouched")
    harness.controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
    XCTAssertFalse(sidebar.isDimmed)
    XCTAssertEqual(sidebar.pager.alphaValue, 1)
    harness.controller.close()
  }
}
