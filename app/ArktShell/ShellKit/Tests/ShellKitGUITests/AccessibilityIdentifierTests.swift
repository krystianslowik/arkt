import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The UI test suite drives the shell only through accessibility identifiers (`AXID`). These tests walk the window's
/// accessibility tree the way an accessibility client sees it (unignored children only) and check each identifier
/// with its role, label and value or enabled state. Group U4a: window, content card, empty state, Toolbar, toasts.
@MainActor
final class AccessibilityIdentifierTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeController(_ sidebar: StubSidebar = .sample()) -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar, toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  // MARK: Tree walking

  /// Every unignored accessibility element below `root`, depth first.
  private func descendants(of root: Any) -> [Any] {
    guard let element = root as? NSAccessibilityProtocol else { return [] }
    let children = NSAccessibility.unignoredChildren(from: element.accessibilityChildren() ?? [])
    return children.flatMap { [$0] + descendants(of: $0) }
  }

  /// The identifier an accessibility client reads from the element itself. For a control that element is its cell,
  /// so the identifier must be set on the cell too (`setAccessibilityIdentifierWithCell`).
  private func identifier(of element: Any) -> String? {
    guard let id = (element as? NSAccessibilityProtocol)?.accessibilityIdentifier(), !id.isEmpty else { return nil }
    return id
  }

  /// The label set on a control is kept on the control, not on the cell the tree lists.
  private func label(of element: NSAccessibilityProtocol) -> String? {
    if let control = (element as? NSCell)?.controlView { return control.accessibilityLabel() }
    return element.accessibilityLabel()
  }

  private func elements(_ id: String, in controller: ShellWindowController) throws -> [NSAccessibilityProtocol] {
    let window = try XCTUnwrap(controller.window)
    return descendants(of: window).filter { identifier(of: $0) == id }.compactMap { $0 as? NSAccessibilityProtocol }
  }

  private func element(_ id: String, in controller: ShellWindowController,
                       file: StaticString = #filePath, line: UInt = #line) throws -> NSAccessibilityProtocol {
    let found = try elements(id, in: controller)
    XCTAssertEqual(found.count, 1, "exactly one element with identifier \(id)", file: file, line: line)
    return try XCTUnwrap(found.first, "no element with identifier \(id)", file: file, line: line)
  }

  // MARK: Window and content card

  func testWindowAndContentCardHaveIdentifiers() throws {
    let controller = makeController()
    let window = try XCTUnwrap(controller.window)
    XCTAssertEqual(window.accessibilityIdentifier(), AXID.Shell.window)
    XCTAssertEqual(window.accessibilityRole(), .window)
    let card = try element(AXID.Content.card, in: controller)
    XCTAssertEqual(card.accessibilityRole(), .group)
    XCTAssertTrue(card as AnyObject === controller.rootView.card)
    controller.close()
  }

  // MARK: Empty state

  func testEmptyStateHasIdentifiersAndImportIsAbsentWhileHidden() throws {
    let controller = makeController(StubSidebar())
    let group = try element(AXID.EmptyState.root, in: controller)
    XCTAssertEqual(group.accessibilityRole(), .group)
    XCTAssertTrue(group as AnyObject === controller.emptyState)
    let newSpace = try element(AXID.EmptyState.newSpace, in: controller)
    XCTAssertEqual(newSpace.accessibilityRole(), .button)
    XCTAssertEqual(newSpace.accessibilityTitle(), "New Space")
    XCTAssertEqual(try elements(AXID.EmptyState.importFromArc, in: controller).count, 0,
                   "Import from Arc is absent from the tree while hidden")

    controller.isArcImportAvailable = true
    controller.rootView.layoutSubtreeIfNeeded()
    let importButton = try element(AXID.EmptyState.importFromArc, in: controller)
    XCTAssertEqual(importButton.accessibilityRole(), .button)
    XCTAssertEqual(importButton.accessibilityTitle(), "Import from Arc")
    controller.close()
  }

  func testEmptyStateIsAbsentWhenASpaceExists() throws {
    let controller = makeController()
    XCTAssertEqual(try elements(AXID.EmptyState.root, in: controller).count, 0)
    controller.close()
  }

  // MARK: Toolbar

  func testToolbarIsAbsentWhileHidden() throws {
    let controller = makeController()
    XCTAssertFalse(controller.isToolbarVisible)
    for id in [AXID.Toolbar.root, AXID.Toolbar.back, AXID.Toolbar.forward, AXID.Toolbar.reload, AXID.Toolbar.urlBar] {
      XCTAssertEqual(try elements(id, in: controller).count, 0, "\(id) is absent while the Toolbar is hidden")
    }
    controller.close()
  }

  func testToolbarButtonsAndURLBarHaveIdentifiersLabelsAndState() throws {
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample(), toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.toggleToolbar(nil)
    controller.rootView.layoutSubtreeIfNeeded()

    let toolbar = try element(AXID.Toolbar.root, in: controller)
    XCTAssertEqual(toolbar.accessibilityRole(), .toolbar)
    XCTAssertEqual(toolbar.accessibilityLabel(), "Toolbar")
    let back = try element(AXID.Toolbar.back, in: controller)
    let forward = try element(AXID.Toolbar.forward, in: controller)
    let reload = try element(AXID.Toolbar.reload, in: controller)
    for (button, label) in [(back, "Back"), (forward, "Forward"), (reload, "Reload")] {
      XCTAssertEqual(button.accessibilityRole(), .button, label)
      XCTAssertEqual(self.label(of: button), label)
    }
    XCTAssertFalse(back.isAccessibilityEnabled(), "no history yet")
    XCTAssertFalse(forward.isAccessibilityEnabled(), "no history yet")
    XCTAssertTrue(reload.isAccessibilityEnabled())

    let tab = try XCTUnwrap(controller.currentTab)
    let next = try XCTUnwrap(URL(string: "https://second.example/page"))
    engine.navigate(tab, to: next)
    XCTAssertTrue(back.isAccessibilityEnabled(), "Back follows setHistory")
    XCTAssertFalse(forward.isAccessibilityEnabled())

    let urlBar = try element(AXID.Toolbar.urlBar, in: controller)
    XCTAssertEqual(urlBar.accessibilityRole(), .button)
    XCTAssertEqual(urlBar.accessibilityValue() as? String, controller.rootView.card.toolbar.urlBar.displayedText)
    XCTAssertTrue((urlBar.accessibilityValue() as? String)?.contains("second.example/page") == true, "the full address")
    controller.close()
  }

  // MARK: Toasts

  func testToastIsAbsentWhileIdle() throws {
    let controller = makeController()
    XCTAssertEqual(try elements(AXID.Toast.root, in: controller).count, 0)
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0)
    controller.close()
  }

  func testTimedToastHasIdentifierLabelAndValueAndNoActionWithoutTitle() throws {
    let controller = makeController()
    controller.toasts.show(Toast(text: "Saved"))
    controller.rootView.layoutSubtreeIfNeeded()
    let toast = try element(AXID.Toast.root, in: controller)
    XCTAssertEqual(toast.accessibilityRole(), .group)
    XCTAssertEqual(toast.accessibilityLabel(), "Saved")
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.timed)
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0, "no action button without a title")
    controller.close()
  }

  func testPersistentToastWithActionHasActionButton() throws {
    let controller = makeController()
    controller.toasts.show(Toast(text: "Could not save", actionTitle: "Retry", isPersistent: true))
    controller.rootView.layoutSubtreeIfNeeded()
    let toast = try element(AXID.Toast.root, in: controller)
    XCTAssertEqual(toast.accessibilityLabel(), "Could not save")
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.persistent)
    let action = try element(AXID.Toast.action, in: controller)
    XCTAssertEqual(action.accessibilityRole(), .button)
    XCTAssertEqual(action.accessibilityTitle(), "Retry")

    controller.toasts.show(Toast(text: "Opened"))
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.timed, "a timed toast over it updates the value")
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0)
    controller.close()
  }

  // MARK: Sidebar chrome, Space dots and Space pages (U4b)

  func testSidebarURLBarNewTabAndSpaceDotsHaveIdentifiersLabelsAndSelection() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeController(sidebar)
    let urlBar = try element(AXID.Sidebar.urlBar, in: controller)
    XCTAssertEqual(urlBar.accessibilityRole(), .button)
    XCTAssertEqual(urlBar.accessibilityValue() as? String,
                   controller.rootView.sidebarContainer.urlBar.displayedText)

    let newTab = try element(AXID.Sidebar.newTab, in: controller)
    XCTAssertEqual(newTab.accessibilityRole(), .button)
    XCTAssertEqual(label(of: newTab), "New Tab")

    let dotsGroup = try element(AXID.Sidebar.spaceDots, in: controller)
    XCTAssertEqual(dotsGroup.accessibilityRole(), .group)
    XCTAssertEqual(dotsGroup.accessibilityLabel(), "Spaces")

    let dots = try elements(AXID.Sidebar.spaceDot, in: controller)
    XCTAssertEqual(dots.count, 3)
    XCTAssertEqual(dots.map { $0.accessibilityLabel() }, ["Personal", "Work", "Dev"])
    XCTAssertEqual(dots.map { $0.isAccessibilitySelected() }, [true, false, false])

    controller.sidebarController.showSpace(sidebar.spaceOrder[1])
    controller.rootView.layoutSubtreeIfNeeded()
    let updatedDots = try elements(AXID.Sidebar.spaceDot, in: controller)
    XCTAssertEqual(updatedDots.map { $0.isAccessibilitySelected() }, [false, true, false])
    controller.close()
  }

  func testSpacePagesAndTitlesHaveIdentifiersLabelsAndSelection() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeController(sidebar)
    // At rest, SpacePagerView hides offscreen pages so only the current Space's page is in the accessibility tree.
    let page = try element(AXID.Sidebar.page, in: controller)
    XCTAssertEqual(page.accessibilityRole(), .group)
    XCTAssertEqual(page.accessibilityLabel(), "Personal")
    XCTAssertTrue(page.isAccessibilitySelected())

    let title = try element(AXID.Sidebar.spaceTitle, in: controller)
    XCTAssertEqual(title.accessibilityValue() as? String, "Personal")

    let pager = controller.rootView.sidebarContainer.pager
    XCTAssertEqual(pager.pages.map { $0.accessibilityIdentifier() }, Array(repeating: AXID.Sidebar.page, count: 3))
    XCTAssertEqual(pager.pages.map { $0.accessibilityLabel() }, ["Personal", "Work", "Dev"])
    XCTAssertEqual(pager.pages.map { $0.isAccessibilitySelected() }, [true, false, false])

    controller.sidebarController.showSpace(sidebar.spaceOrder[2])
    controller.rootView.layoutSubtreeIfNeeded()
    let updatedPage = try element(AXID.Sidebar.page, in: controller)
    XCTAssertEqual(updatedPage.accessibilityLabel(), "Dev")
    XCTAssertTrue(updatedPage.isAccessibilitySelected())
    XCTAssertEqual(pager.pages.map { $0.isAccessibilitySelected() }, [false, false, true])
    let updatedTitle = try element(AXID.Sidebar.spaceTitle, in: controller)
    XCTAssertEqual(updatedTitle.accessibilityValue() as? String, "Dev")
    controller.close()
  }

  // MARK: Sidebar outline rows, divider and close button (U4b)

  func testSidebarOutlineRowsDividerAndHoverCloseButton() throws {
    let sidebar = StubSidebar.sample()
    let space = sidebar.spaceOrder[0]
    let split = sidebar.addSplit(in: .today(space))
    let pane0 = sidebar.addTab(url: URL(string: "https://example.com/p0")!, title: "Left Pane", in: .split(split))
    _ = sidebar.addTab(url: URL(string: "https://example.com/p1")!, title: "Right Pane", in: .split(split))
    let controller = makeController(sidebar)
    let page = try XCTUnwrap(controller.sidebarController.currentPage)
    page.outlineView.layoutSubtreeIfNeeded()

    func inCurrentPage(_ id: String) -> [NSAccessibilityProtocol] {
      descendants(of: page).filter { identifier(of: $0) == id }.compactMap { $0 as? NSAccessibilityProtocol }
    }

    let dividers = inCurrentPage(AXID.Sidebar.divider)
    XCTAssertEqual(dividers.count, 1)
    XCTAssertEqual(dividers.first?.accessibilityRole(), .splitter)

    let folders = inCurrentPage(AXID.Sidebar.rowFolder)
    XCTAssertEqual(folders.count, 1)
    XCTAssertEqual(folders.first?.accessibilityRole(), .row)
    XCTAssertEqual(folders.first?.accessibilityLabel(), "Trips")
    XCTAssertEqual(folders.first?.isAccessibilitySelected(), false)

    let pinnedRows = inCurrentPage(AXID.Sidebar.rowPinned)
    XCTAssertEqual(pinnedRows.count, 4)
    XCTAssertEqual(pinnedRows.map { $0.accessibilityLabel() },
                   ["Family Calendar", "Inbox", "Lisbon Itinerary", "Flight Options"])
    // The initial current tab is the first Pinned tab ("Family Calendar").
    XCTAssertEqual(pinnedRows.map { $0.isAccessibilitySelected() }, [true, false, false, false],
                   "the initial current tab's row is selected without enabling outline selection")
    XCTAssertTrue(page.outlineView.selectedRowIndexes.isEmpty)

    let todayRows = inCurrentPage(AXID.Sidebar.rowToday)
    XCTAssertEqual(todayRows.count, 5)
    XCTAssertEqual(todayRows.map { $0.accessibilityLabel() },
                   ["Weekend Recipes", "Reading List", "Swift Blog", "Left Pane", "Right Pane"])
    XCTAssertEqual(todayRows.map { $0.isAccessibilitySelected() }, [false, false, false, false, false])

    let splitRows = inCurrentPage(AXID.Sidebar.rowSplit)
    XCTAssertEqual(splitRows.count, 1)
    XCTAssertEqual(splitRows.first?.accessibilityLabel(), "Left Pane | Right Pane")
    XCTAssertEqual(splitRows.first?.isAccessibilitySelected(), false)

    controller.activate(node: pane0)
    page.outlineView.layoutSubtreeIfNeeded()
    XCTAssertEqual(inCurrentPage(AXID.Sidebar.rowSplit).first?.isAccessibilitySelected(), true,
                   "a split row is selected while one of its panes is current")
    XCTAssertEqual(inCurrentPage(AXID.Sidebar.rowPinned).map { $0.isAccessibilitySelected() },
                   [false, false, false, false])
    XCTAssertEqual(inCurrentPage(AXID.Sidebar.rowToday).map { $0.isAccessibilitySelected() },
                   [false, false, false, true, false])

    XCTAssertEqual(inCurrentPage(AXID.Sidebar.rowClose).count, 0, "close button absent while no row is hovered")
    let todayNode = sidebar.children(of: .today(space))[0]
    let todayRowIndex = page.outlineController.row(for: todayNode)
    let todayRowView = try XCTUnwrap(page.outlineView.rowView(atRow: todayRowIndex, makeIfNecessary: false)
                                       as? SidebarRowView)
    todayRowView.isHovered = true
    let closeButtons = inCurrentPage(AXID.Sidebar.rowClose)
    XCTAssertEqual(closeButtons.count, 1)
    XCTAssertEqual(closeButtons.first?.accessibilityRole(), .button)
    if let firstClose = closeButtons.first {
      XCTAssertEqual(label(of: firstClose), "Archive this tab")
    }
    let todayCell = try XCTUnwrap(page.outlineView.view(atColumn: 0, row: todayRowIndex, makeIfNecessary: false)
                                    as? SidebarTabCellView)
    todayRowView.isHovered = false
    todayCell.setCloseButtonShown(false, animated: false)
    XCTAssertEqual(inCurrentPage(AXID.Sidebar.rowClose).count, 0)
    controller.close()
  }

  // MARK: Favorites grid and tiles (U4b)

  func testFavoritesGridTilesAndCloseButton() throws {
    let sidebar = StubSidebar.sample()
    let favorites = sidebar.children(of: .favorites(profile: "default"))
    let controller = makeController(sidebar)
    controller.rootView.sidebarContainer.favorites.collectionView.layoutSubtreeIfNeeded()

    let grid = try element(AXID.Favorites.grid, in: controller)
    XCTAssertEqual(grid.accessibilityRole(), .group)

    let tiles = try elements(AXID.Favorites.tile, in: controller)
    XCTAssertEqual(tiles.count, 6)
    for tile in tiles { XCTAssertEqual(tile.accessibilityRole(), .button) }
    XCTAssertEqual(tiles.map { $0.accessibilityLabel() },
                   ["Example", "Wikipedia", "Hacker News", "GitHub", "Apple Developer", "Swift"])
    // The initial current tab is in Pinned, so all six Favorites start unloaded.
    XCTAssertEqual(tiles.compactMap { $0.accessibilityValue() as? String },
                   Array(repeating: AXID.Favorites.unloaded, count: 6))
    XCTAssertEqual(try elements(AXID.Favorites.tileClose, in: controller).count, 0)

    controller.activate(node: favorites[1])
    controller.rootView.sidebarContainer.favorites.collectionView.layoutSubtreeIfNeeded()
    let loadedTiles = try elements(AXID.Favorites.tile, in: controller)
    XCTAssertEqual(loadedTiles.compactMap { $0.accessibilityValue() as? String },
                   [AXID.Favorites.unloaded, AXID.Favorites.loaded, AXID.Favorites.unloaded,
                    AXID.Favorites.unloaded, AXID.Favorites.unloaded, AXID.Favorites.unloaded])
    XCTAssertEqual(try elements(AXID.Favorites.tileClose, in: controller).count, 0,
                   "close button absent until the loaded tile is hovered")

    let tileView = try XCTUnwrap(controller.rootView.sidebarContainer.favorites.tile(for: favorites[1]))
    tileView.isHovered = true
    let close = try element(AXID.Favorites.tileClose, in: controller)
    XCTAssertEqual(close.accessibilityRole(), .button)
    XCTAssertEqual(label(of: close), "Close this tab")
    tileView.isHovered = false
    tileView.setCloseButtonShown(false, animated: false)
    XCTAssertEqual(try elements(AXID.Favorites.tileClose, in: controller).count, 0)
    controller.close()
  }
}
