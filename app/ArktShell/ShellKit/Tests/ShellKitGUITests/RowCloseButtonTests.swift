import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// GS-043: the hover close (X) button on sidebar rows. Visibility follows the row's hover state; a click or the
/// VoiceOver action runs the same close as Cmd-W (BH-071 Today archives, BH-067 pinned closes and keeps the pin).
/// Events are delivered in-process (posted to the app queue or sent to the view); nothing goes through the OS.
@MainActor
final class RowCloseButtonTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// One pinned tab, a pinned folder with one tab, Today tabs, then a two-pane split in Today.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var pinned: UUID
    var folder: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [[UUID]] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { RowCloseButtonTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        archived.append(ids)
        _ = source.archive(ids, reason: .manual, at: RowCloseButtonTests.now)
      }
    }

    var outlineController: SidebarOutlineController? { controller.sidebarController.currentPage?.outlineController }

    func rowView(_ id: UUID) throws -> SidebarRowView {
      let outline = try XCTUnwrap(controller.sidebarController.view.currentOutline)
      outline.layoutSubtreeIfNeeded()
      let row = try XCTUnwrap(outlineController?.row(for: id))
      XCTAssertGreaterThanOrEqual(row, 0)
      return try XCTUnwrap(outline.rowView(atRow: row, makeIfNecessary: true) as? SidebarRowView)
    }

    func cell(_ id: UUID) throws -> SidebarTabCellView {
      let outline = try XCTUnwrap(controller.sidebarController.view.currentOutline)
      outline.layoutSubtreeIfNeeded()
      let row = try XCTUnwrap(outlineController?.row(for: id))
      return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarTabCellView)
    }

    /// Hovers the row, checks that a click at the X's center lands on the X (not on the row, which would activate
    /// it), then clicks it in-process.
    func clickClose(_ id: UUID) throws {
      try rowView(id).isHovered = true
      let button = try cell(id).closeButton
      XCTAssertFalse(button.isHidden, "the X is clickable while the row is hovered")
      let content = try XCTUnwrap(button.window?.contentView)
      let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
      let hit = content.hitTest(content.superview?.convert(center, from: nil) ?? center)
      XCTAssertTrue(hit === button, "a click on the X goes to the X")
      button.performClick(nil)
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: url("p"), title: "Pinned", in: .pinned(space))
    let folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    _ = try sidebar.addTab(url: url("pf"), title: "In folder", in: .folder(folder))
    let today = try (0..<3).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    return World(sidebar: sidebar, space: space, pinned: pinned, folder: folder, today: today, split: split,
                 panes: panes)
  }

  // MARK: Visibility

  func testCloseButtonShowsOnlyWhileTheRowIsHovered() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.today[0])
    let cell = try harness.cell(world.today[0])
    XCTAssertFalse(cell.isCloseButtonShown)
    XCTAssertTrue(cell.closeButton.isHidden)
    let content = try XCTUnwrap(row.window?.contentView)
    let center = cell.closeButton.convert(NSPoint(x: cell.closeButton.bounds.midX,
                                                  y: cell.closeButton.bounds.midY), to: nil)
    XCTAssertFalse(content.hitTest(content.superview?.convert(center, from: nil) ?? center) === cell.closeButton,
                   "a hidden X takes no clicks")

    row.isHovered = true
    XCTAssertTrue(cell.isCloseButtonShown)
    XCTAssertFalse(cell.closeButton.isHidden)

    row.isHovered = false
    XCTAssertFalse(cell.isCloseButtonShown)
    harness.controller.close()
  }

  /// The X sits at the trailing edge, and the title stops before it while it is shown; frames are set directly.
  func testCloseButtonSitsAtTheTrailingEdgeAndTheTitleMakesRoom() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.today[0])
    let cell = try harness.cell(world.today[0])
    let restingTitleWidth = cell.titleField.frame.width

    row.isHovered = true

    let button = cell.closeButton.frame
    XCTAssertEqual(button.width, SidebarMetrics.closeButtonSize)
    XCTAssertEqual(button.maxX, cell.bounds.width - SidebarMetrics.closeButtonTrailing, accuracy: 0.5)
    XCTAssertEqual(button.midY, cell.bounds.midY, accuracy: 1)
    XCTAssertLessThanOrEqual(cell.titleField.frame.maxX, button.minX)
    XCTAssertLessThan(cell.titleField.frame.width, restingTitleWidth)

    row.isHovered = false
    XCTAssertEqual(cell.titleField.frame.width, restingTitleWidth)
    harness.controller.close()
  }

  func testFolderRowsHaveNoCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.folder)
    let cell = try harness.cell(world.folder)
    row.isHovered = true
    XCTAssertFalse(cell.isCloseButtonShown)
    XCTAssertTrue(cell.closeButton.isHidden)
    XCTAssertEqual(row.accessibilityCustomActions() ?? [], [])
    harness.controller.close()
  }

  /// A reused row or cell starts without the X.
  func testReuseHidesTheCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.today[0])
    let cell = try harness.cell(world.today[0])
    row.isHovered = true
    XCTAssertTrue(cell.isCloseButtonShown)

    row.prepareForReuse()
    XCTAssertFalse(cell.isCloseButtonShown)

    row.isHovered = true
    cell.prepareForReuse()
    XCTAssertFalse(cell.isCloseButtonShown)
    XCTAssertTrue(cell.closeButton.isHidden)
    harness.controller.close()
  }

  /// A row reloaded under the pointer (title change) keeps its X: the new cell picks up the row's hover state.
  func testReloadedCellUnderTheHoveredRowShowsTheCloseButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.today[0])
    row.isHovered = true

    harness.source.updateTab(world.today[0], url: nil, title: "Renamed")

    let cell = try harness.cell(world.today[0])
    XCTAssertEqual(cell.titleField.stringValue, "Renamed")
    XCTAssertTrue(cell.isCloseButtonShown)
    harness.controller.close()
  }

  /// Rows scrolled or reused under a still pointer resync their hover state when tracking areas update.
  func testHoverResyncsFromThePointerLocation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let row = try harness.rowView(world.today[0])
    let cell = try harness.cell(world.today[0])
    let inside = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)

    row.syncHover(pointerInWindow: inside)
    XCTAssertTrue(row.isHovered)
    XCTAssertTrue(cell.isCloseButtonShown)

    row.syncHover(pointerInWindow: NSPoint(x: inside.x, y: inside.y + 10 * SidebarMetrics.rowPitch))
    XCTAssertFalse(row.isHovered)
    XCTAssertFalse(cell.isCloseButtonShown)

    row.isHovered = true
    row.syncHover(pointerInWindow: nil)
    XCTAssertFalse(row.isHovered, "no pointer in the window means no hover")
    harness.controller.close()
  }

  // MARK: Tooltips

  /// GS-043 [S]: "Archive this tab" on Today, "Close and Keep Pinned" on pinned; panes read like tabs (decision 4).
  func testTooltipsPerKind() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertEqual(try harness.cell(world.today[0]).closeButton.toolTip, "Archive this tab")
    XCTAssertEqual(try harness.cell(world.pinned).closeButton.toolTip, "Close and Keep Pinned")
    XCTAssertEqual(try harness.cell(world.split).closeButton.toolTip, "Archive this split")
    XCTAssertEqual(try harness.cell(world.panes[0]).closeButton.toolTip, "Archive this tab")
    XCTAssertEqual(try harness.cell(world.today[0]).closeButton.accessibilityLabel(), "Archive this tab")
    harness.controller.close()
  }

  // MARK: Click

  /// BH-071: the X on a Today tab that is not current archives it; the current tab stays and the row is never
  /// activated by the click.
  func testClosingANonCurrentTodayTabArchivesItAndKeepsTheCurrentTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let current = try XCTUnwrap(harness.controller.currentTab)

    try harness.clickClose(world.today[2])

    XCTAssertEqual(harness.archived, [[world.today[2]]])
    XCTAssertNil(harness.source.node(world.today[2]))
    XCTAssertEqual(harness.controller.currentTab, current)
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0])
    harness.controller.close()
  }

  /// Same as Cmd-W on the current Today tab: archived, the next sibling below becomes current.
  func testClosingTheCurrentTodayTabActivatesTheNextSibling() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])

    try harness.clickClose(world.today[1])

    XCTAssertEqual(harness.archived, [[world.today[1]]])
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[2])
    XCTAssertEqual(harness.controller.visibleNodes, [world.today[2]])
    harness.controller.close()
  }

  /// BH-067: the X on the current pinned tab closes its page and keeps the pin; nothing is archived.
  func testClosingThePinnedTabClosesItsPageAndKeepsThePin() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let tab = try XCTUnwrap(harness.controller.currentTab)

    try harness.clickClose(world.pinned)

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(tab))
    XCTAssertNotNil(harness.source.node(world.pinned))
    XCTAssertNil(harness.controller.currentTab)
    harness.controller.close()
  }

  /// A pinned tab whose page is loaded in the background closes that page; the current tab is untouched.
  func testClosingABackgroundPinnedTabClosesOnlyItsPage() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.pinned)
    let pinnedTab = try XCTUnwrap(harness.controller.currentTab)
    harness.controller.activate(node: world.today[0])
    let current = try XCTUnwrap(harness.controller.currentTab)

    try harness.clickClose(world.pinned)

    XCTAssertEqual(harness.archived, [])
    XCTAssertFalse(harness.engine.tabIDs.contains(pinnedTab))
    XCTAssertEqual(harness.controller.currentTab, current)
    XCTAssertNotNil(harness.source.node(world.pinned))
    harness.controller.close()
  }

  /// The X on a Today split row archives the whole split; its current pane hands over to the next sibling.
  func testClosingATodaySplitRowArchivesTheWholeSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.clickClose(world.split)

    XCTAssertEqual(harness.archived, [[world.split]])
    XCTAssertNil(harness.source.node(world.split))
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[2], "nearest sibling above")
    harness.controller.close()
  }

  /// User decision 4: the X on a pane archives only that pane.
  func testClosingAPaneArchivesOnlyThatPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.clickClose(world.panes[0])

    XCTAssertEqual(harness.archived, [[world.panes[0]]])
    XCTAssertNotNil(harness.source.node(world.panes[1]))
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0])
    harness.controller.close()
  }

  // MARK: Accessibility

  /// VoiceOver: each closable row carries one custom action named for what it does, running the same close.
  func testRowsCarryACloseOrArchiveAccessibilityAction() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let pinnedActions = try XCTUnwrap(harness.rowView(world.pinned).accessibilityCustomActions())
    XCTAssertEqual(pinnedActions.map(\.name), ["Close"])
    let todayActions = try XCTUnwrap(harness.rowView(world.today[1]).accessibilityCustomActions())
    XCTAssertEqual(todayActions.map(\.name), ["Archive"])

    XCTAssertTrue(todayActions[0].handler?() ?? false)

    XCTAssertEqual(harness.archived, [[world.today[1]]])
    XCTAssertEqual(harness.controller.sidebarController.current, world.today[0])
    harness.controller.close()
  }
}
