import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// The sidebar column on its own (mounting into ShellRootView is a separate step), hosted in a plain window
/// at the default 190 pt sidebar width.
@MainActor
final class SidebarViewTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    windows.forEach { $0.close() }
    windows = []
  }

  private func makeSidebar(_ sidebar: StubSidebar = .sample()) -> SidebarController {
    let controller = SidebarController(source: sidebar)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    window.setContentSize(NSSize(width: 190, height: 800))
    controller.view.layoutSubtreeIfNeeded()
    windows.append(window)
    return controller
  }

  private func isTab(_ sidebar: StubSidebar, _ id: NodeID) -> Bool {
    if case .tab? = sidebar.node(id) { return true } else { return false }
  }

  private func rowView(_ controller: SidebarController, _ id: NodeID) throws -> SidebarRowView {
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let row = try XCTUnwrap(controller.currentPage?.outlineController.row(for: id))
    XCTAssertGreaterThanOrEqual(row, 0)
    return try XCTUnwrap(outline.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView)
  }

  private func cell(_ controller: SidebarController, _ id: NodeID) throws -> SidebarTabCellView {
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let row = try XCTUnwrap(controller.currentPage?.outlineController.row(for: id))
    return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView)
  }

  // C7: activating a tab repaints only the rows whose state changed.
  func testActivationRepaintsOnlyChangedRows() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let space = try XCTUnwrap(controller.currentSpace)
    let tabs = sidebar.children(of: .pinned(space)).filter { isTab(sidebar, $0) }
    XCTAssertGreaterThanOrEqual(tabs.count, 2)
    let untouched = sidebar.children(of: .today(space)).filter { isTab(sidebar, $0) }
    let outline = try XCTUnwrap(controller.view.currentPage?.outlineController)
    controller.activate(node: tabs[0])
    let before = outline.rowConfigureCount
    controller.activate(node: tabs[1])
    XCTAssertEqual(outline.rowConfigureCount - before, 2, "the old current row (now previous) and the new one")
    XCTAssertEqual(try rowView(controller, tabs[0]).state, .previous)
    XCTAssertEqual(try rowView(controller, tabs[1]).state, .current)
    for id in untouched { XCTAssertEqual(try rowView(controller, id).state, .normal) }
    let settled = outline.rowConfigureCount
    outline.setRowStates(controller.resolver)
    XCTAssertEqual(outline.rowConfigureCount, settled, "an unchanged resolver touches no row")
  }

  // C7: symbol and letter glyphs are cached bitmaps, never template symbols drawn per display.
  func testRowGlyphsAreCachedBitmaps() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let realized = (0..<outline.numberOfRows).compactMap { outline.view(atColumn: 0, row: $0, makeIfNecessary: false) }
    XCTAssertFalse(realized.isEmpty)
    for case let cell as SidebarTabCellView in realized {
      let image = try XCTUnwrap(cell.faviconView.image)
      XCTAssertFalse(image.isTemplate)
      XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep }, cell.titleField.stringValue)
    }
    for button in [controller.view.archiveButton, controller.view.newTabButton] {
      let image = try XCTUnwrap(button.image)
      XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
    }
  }

  // Pre-merge review: glyph bitmaps are per backing scale, so a backing change (the window moving between a
  // 1x and a 2x display) re-renders every realized row and favorite tile.
  func testBackingChangeRefreshesRealizedRowsAndTiles() throws {
    let controller = makeSidebar()
    let page = try XCTUnwrap(controller.currentPage)
    let outline = page.outlineView
    let cells = (0..<outline.numberOfRows).compactMap {
      outline.view(atColumn: 0, row: $0, makeIfNecessary: false) as? SidebarTabCellView
    }
    XCTAssertFalse(cells.isEmpty)
    cells.forEach { $0.faviconView.image = nil }
    var realizedRows = 0
    outline.enumerateAvailableRowViews { rowView, _ in if rowView is SidebarRowView { realizedRows += 1 } }
    let before = page.outlineController.rowConfigureCount
    page.viewDidChangeBackingProperties()
    XCTAssertEqual(page.outlineController.rowConfigureCount - before, realizedRows, "every realized row")
    for cell in cells { XCTAssertNotNil(cell.faviconView.image, cell.titleField.stringValue) }

    let favorites = controller.view.favorites
    let tiles = favorites.collectionView.visibleItems().compactMap { ($0 as? FavoriteTileItem)?.tileView }
    XCTAssertFalse(tiles.isEmpty)
    tiles.forEach { $0.faviconView.image = nil }
    favorites.viewDidChangeBackingProperties()
    for tile in tiles { XCTAssertNotNil(tile.faviconView.image) }
  }

  func testRowPitchAndFavoriteTiles() throws {
    let controller = makeSidebar()
    let outline = try XCTUnwrap(controller.view.currentOutline)
    XCTAssertEqual(outline.rect(ofRow: 0).height, 41)
    let grid = controller.view.favorites.collectionView
    grid.layoutSubtreeIfNeeded()
    let frames = (0..<6).compactMap { grid.item(at: IndexPath(item: $0, section: 0))?.view.frame }
    XCTAssertEqual(frames.count, 6)
    XCTAssertEqual(frames[0].size, CGSize(width: 52, height: 46))
    XCTAssertEqual(Set(frames.prefix(3).map(\.minY)).count, 1, "first three favorites share a row")
    XCTAssertEqual(frames[1].minX - frames[0].maxX, 9, accuracy: 0.01)
    XCTAssertEqual(frames[3].minY - frames[0].maxY, 9, accuracy: 0.01)
    XCTAssertEqual(controller.view.favorites.frame.height, 46 * 2 + 9)
  }

  /// An empty Favorites grid is 0 pt tall, so the first Favorites (an Arc import into an empty profile) arrive while
  /// its collection view has no size. A batch insert there left `item(at:)` nil after the grid was sized: no tiles,
  /// and accessibility clients saw none. Once the window lays out, every Favorite has a tile and the grid's
  /// accessibility children are those tiles, in order, with their titles.
  func testFavoritesAddedWhileTheGridHasNoSizeGetTiles() throws {
    let sidebar = StubSidebar()
    sidebar.addSpace(title: "Work")
    let controller = makeSidebar(sidebar)
    let grid = controller.view.favorites
    XCTAssertEqual(grid.frame.height, 0, "precondition: an empty grid has no height")
    XCTAssertTrue(grid.collectionView.bounds.isEmpty, "precondition: the collection view has no size")

    let location = SidebarLocation.favorites(profile: "default")
    let titles = ["Fixture Alpha", "Fixture Beta", "Fixture Gamma", "Fixture Delta"]
    let ids = titles.map { title in
      sidebar.addTab(url: URL(string: "https://\(title.split(separator: " ")[1].lowercased()).example/")!,
                     title: title, in: location)
    }
    controller.view.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()

    XCTAssertEqual(grid.frame.height, 46 * 2 + 9)
    XCTAssertFalse(grid.collectionView.bounds.isEmpty)
    XCTAssertEqual(grid.collectionView.numberOfSections, 1)
    XCTAssertEqual(grid.collectionView.numberOfItems(inSection: 0), titles.count)
    XCTAssertTrue(grid.collectionView.preparedContentRect.contains(grid.collectionView.bounds),
                  "prepared \(grid.collectionView.preparedContentRect) bounds \(grid.collectionView.bounds)")
    // DIAGNOSTIC (temporary, review follow-up): collection view state when the tiles are checked, then after a run
    // loop turn, then after an explicit reload and layout.
    func state(_ when: String) -> String {
      let cv = grid.collectionView
      let first = cv.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame
      return "\(when): frame \(cv.frame) visible \(cv.visibleRect) prepared \(cv.preparedContentRect) "
        + "visibleItems \(cv.visibleItems().count) paths \(cv.indexPathsForVisibleItems().count) "
        + "content \(cv.collectionViewLayout?.collectionViewContentSize ?? .zero) item0 \(String(describing: first)) "
        + "subviews \(cv.subviews.count) item(at:0) \(cv.item(at: IndexPath(item: 0, section: 0)) != nil) "
        + "needsLayout \(cv.needsLayout)"
    }
    var report = [state("checked")]
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    controller.view.layoutSubtreeIfNeeded()
    report.append(state("after run loop"))
    grid.collectionView.reloadData()
    grid.collectionView.layoutSubtreeIfNeeded()
    report.append(state("after reload"))
    print("FAVORITES-DIAG " + report.joined(separator: " || "))
    XCTAssertTrue(report.isEmpty, report.joined(separator: " || "))

    for (id, title) in zip(ids, titles) {
      let tile = try XCTUnwrap(grid.tile(for: id), "no tile for \(title)")
      XCTAssertEqual(tile.accessibilityLabel(), title)
      XCTAssertGreaterThan(tile.frame.width, 0)
    }
    let children = (grid.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
    XCTAssertEqual(children.map { $0.accessibilityLabel() }, titles)
    XCTAssertEqual(Set(children.map { $0.accessibilityIdentifier() }), [AXID.Favorites.tile])
    for child in children {
      XCTAssertTrue((child.accessibilityParent() as? NSView) === grid, "tile parent is the grid")
    }
  }

  func testContainerLayout() throws {
    let controller = makeSidebar()
    let view = controller.view
    XCTAssertEqual(view.topBar.frame, CGRect(x: 0, y: 0, width: 190, height: 36))
    XCTAssertEqual(view.favorites.frame.minX, 8)
    XCTAssertEqual(view.favorites.frame.width, 174)
    XCTAssertGreaterThanOrEqual(view.favorites.frame.minY, 36, "favorites sit below the traffic lights")
    XCTAssertEqual(view.favorites.frame.minY, view.urlBar.frame.maxY + 8, "URL bar shown: 8 pt to the tiles")
    XCTAssertEqual(view.bottomBar.frame.maxY, 800)
    XCTAssertEqual(view.bottomBar.frame.height, 50)
    // Arc's Space dock: 32 pt buttons, 8 pt from the sidebar edges, 9 pt above and below.
    XCTAssertEqual(view.archiveButton.frame, CGRect(x: 8, y: 9, width: 32, height: 32))
    XCTAssertEqual(view.newTabButton.frame, CGRect(x: 150, y: 9, width: 32, height: 32))
    let page = try XCTUnwrap(controller.currentPage)
    XCTAssertEqual(page.titleLabel.stringValue, "Personal")
    XCTAssertEqual(page.titleLabel.frame.minX, 16)
    XCTAssertEqual(page.titleLabel.font?.pointSize, 12)
    XCTAssertEqual(page.scrollView.frame.minX, 8)
    XCTAssertGreaterThan(view.pagesHost.frame.minY, view.favorites.frame.maxY)
    XCTAssertLessThanOrEqual(view.pagesHost.frame.maxY, view.bottomBar.frame.minY)
    XCTAssertEqual(view.spaceDots.count, 3)
  }

  func testOutlineOrderAndDivider() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let space = sidebar.spaceOrder[0]
    let pinned = sidebar.children(of: .pinned(space))
    let folder = try XCTUnwrap(pinned.first { !isTab(sidebar, $0) })
    let folderChildren = sidebar.children(of: .folder(folder))
    let today = sidebar.children(of: .today(space))
    let outlineController = try XCTUnwrap(controller.currentPage?.outlineController)
    // Pinned rows (folder expanded), divider, Today rows.
    XCTAssertEqual(outline.numberOfRows, pinned.count + folderChildren.count + 1 + today.count)
    let dividerRow = outlineController.dividerRow
    XCTAssertEqual(dividerRow, pinned.count + folderChildren.count)
    XCTAssertEqual(outline.rect(ofRow: dividerRow).height, 25)
    XCTAssertEqual(outlineController.row(for: today[0]), dividerRow + 1)
    // Children are indented one step; top-level rows are not.
    let childRow = outlineController.row(for: folderChildren[0])
    XCTAssertEqual(outline.frameOfCell(atColumn: 0, row: childRow).minX, 16)
    XCTAssertEqual(outline.frameOfCell(atColumn: 0, row: 0).minX, 0)
    XCTAssertEqual(outline.frameOfOutlineCell(atRow: outlineController.row(for: folder)), .zero)
    let titleCell = try cell(controller, today[0])
    XCTAssertEqual(titleCell.titleField.stringValue, "Weekend Recipes")
    XCTAssertEqual(titleCell.titleField.font?.pointSize, 14)
    XCTAssertEqual(titleCell.faviconView.frame, CGRect(x: 10, y: 13, width: 16, height: 16))
    XCTAssertEqual(titleCell.titleField.frame.minX, 34)
  }

  func testActivatingRowSetsCurrentAndPreviousStates() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    var activated: [NodeID] = []
    controller.onActivate = { activated.append($0) }
    let space = sidebar.spaceOrder[0]
    let first = sidebar.children(of: .today(space))[0]
    let second = sidebar.children(of: .today(space))[1]
    controller.activate(node: first)
    controller.activate(node: second)
    XCTAssertEqual(controller.rowState(for: second), .current)
    XCTAssertEqual(controller.rowState(for: first), .previous)
    XCTAssertEqual(activated, [first, second])
    XCTAssertEqual(try rowView(controller, second).displayedFill?.alpha, 0.85)
    XCTAssertEqual(try rowView(controller, first).displayedFill?.alpha, 0.32)
    // Re-activating the current tab keeps previous intact.
    controller.activate(node: second)
    XCTAssertEqual(controller.rowState(for: first), .previous)
  }

  func testHoverAndPressFeedback() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let space = sidebar.spaceOrder[0]
    let row = try rowView(controller, sidebar.children(of: .today(space))[0])
    XCTAssertNil(row.displayedFill)
    row.isHovered = true
    XCTAssertEqual(row.displayedFill, ShellTokens.sidebarItemHovered.resolve(.light))
    row.isPressed = true
    XCTAssertEqual(row.displayedFill, ShellTokens.tabPressed.resolve(.light))
    row.isHovered = false; row.isPressed = false
    row.layoutSubtreeIfNeeded()
    XCTAssertEqual(row.backgroundLayer.frame.height, 34)
    XCTAssertEqual(row.backgroundLayer.cornerCurve, .continuous)
  }

  func testFavoriteActivationMarksTileCurrent() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let favorites = sidebar.children(of: .favorites(profile: "default"))
    controller.activate(node: favorites[2])
    let grid = controller.view.favorites
    let tile = try XCTUnwrap(grid.tile(for: favorites[2]))
    XCTAssertTrue(tile.isCurrent)
    XCTAssertEqual(tile.displayedFill, ShellTokens.tabCurrent.resolve(.light))
    XCTAssertEqual(try XCTUnwrap(grid.tile(for: favorites[0])).displayedFill,
                   ShellTokens.sidebarItemBackground.resolve(.light))
    XCTAssertEqual(controller.currentSpace, sidebar.spaceOrder[0], "favorites do not switch Space")
  }

  func testAppendToTodayInsertsOneRowWithoutReloadingOthers() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let space = sidebar.spaceOrder[0]
    let firstToday = sidebar.children(of: .today(space))[0]
    let keptRowView = try rowView(controller, sidebar.children(of: .pinned(space))[0])
    let rowsBefore = outline.numberOfRows
    let id = sidebar.addTab(url: URL(string: "https://example.com/new")!, title: "New Page", in: .today(space))
    XCTAssertEqual(outline.numberOfRows, rowsBefore + 1)
    XCTAssertEqual(controller.currentPage?.outlineController.row(for: id), rowsBefore)
    XCTAssertTrue(try rowView(controller, sidebar.children(of: .pinned(space))[0]) === keptRowView,
                  "untouched rows keep their row views (no reloadData)")
    sidebar.updateTab(firstToday, url: nil, title: "Renamed")
    controller.view.layoutSubtreeIfNeeded()
    XCTAssertEqual(try cell(controller, firstToday).titleField.stringValue, "Renamed")
    XCTAssertTrue(try rowView(controller, sidebar.children(of: .pinned(space))[0]) === keptRowView)
  }

  func testAppendToPinnedAndFolder() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let outlineController = try XCTUnwrap(controller.currentPage?.outlineController)
    let space = sidebar.spaceOrder[0]
    let folder = try XCTUnwrap(sidebar.children(of: .pinned(space)).first { !isTab(sidebar, $0) })
    let rowsBefore = outline.numberOfRows
    let pinnedTab = sidebar.addTab(url: URL(string: "https://example.com/p")!, title: "Pinned New", in: .pinned(space))
    XCTAssertEqual(outline.numberOfRows, rowsBefore + 1)
    XCTAssertEqual(outlineController.row(for: pinnedTab), outlineController.dividerRow - 1)
    let inFolder = sidebar.addTab(url: URL(string: "https://example.com/f")!, title: "Folder New", in: .folder(folder))
    XCTAssertEqual(outline.numberOfRows, rowsBefore + 2)
    XCTAssertEqual(outline.level(forRow: outlineController.row(for: inFolder)), 1)
  }

  func testOtherSpaceChangesAreIgnoredByCurrentPage() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let rowsBefore = outline.numberOfRows
    sidebar.addTab(url: URL(string: "https://example.com/x")!, title: "Elsewhere", in: .today(sidebar.spaceOrder[2]))
    XCTAssertEqual(outline.numberOfRows, rowsBefore)
  }

  func testActivatingTabInDarkSpaceSwitchesPageAndFlavor() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let dev = sidebar.spaceOrder[2]
    let tab = sidebar.children(of: .today(dev))[0]
    controller.activate(node: tab)
    controller.view.layoutSubtreeIfNeeded()
    XCTAssertEqual(controller.currentSpace, dev)
    XCTAssertEqual(controller.currentPage?.titleLabel.stringValue, "Dev")
    XCTAssertEqual(controller.view.spaceDots.selectedIndex, 2)
    let row = try rowView(controller, tab)
    XCTAssertEqual(row.flavor, .dark)
    XCTAssertEqual(row.displayedFill, ShellTokens.tabCurrent.resolve(.dark))
  }

  func testSplitActivatesFirstPaneAndShowsCurrent() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let work = sidebar.spaceOrder[1]
    controller.showSpace(work)
    controller.view.layoutSubtreeIfNeeded()
    let split = try XCTUnwrap(sidebar.children(of: .today(work)).first { !isTab(sidebar, $0) })
    controller.activate(node: split)
    let firstPane = sidebar.children(of: .split(split))[0]
    XCTAssertEqual(controller.current, firstPane)
    XCTAssertEqual(controller.currentPage?.outlineController.state(for: split), .current)
    XCTAssertEqual(try cell(controller, split).titleField.stringValue, "Notes | Preview")
  }

  func testFolderActivationIsIgnored() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let folder = try XCTUnwrap(sidebar.children(of: .pinned(sidebar.spaceOrder[0])).first { !isTab(sidebar, $0) })
    let empty = sidebar.addFolder(title: "Empty", in: .pinned(sidebar.spaceOrder[0]))
    controller.activate(node: empty)
    XCTAssertNil(controller.current)
    controller.activate(node: folder)
    XCTAssertNil(controller.current, "folders toggle in place and never become current")
  }

  func testFaviconReplacesLetterPlaceholder() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let tab = sidebar.children(of: .today(sidebar.spaceOrder[0]))[0]
    let placeholder = try cell(controller, tab).faviconView.image
    let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
      NSColor.red.setFill(); rect.fill(); return true
    }
    let data = try XCTUnwrap(image.tiffRepresentation)
    controller.setFavicon(data, for: tab)
    let updated = try XCTUnwrap(try cell(controller, tab).faviconView.image)
    XCTAssertFalse(updated === placeholder)
    XCTAssertEqual(updated.size, NSSize(width: 4, height: 4))
    controller.setFavicon(nil, for: tab)
    XCTAssertTrue(try cell(controller, tab).faviconView.image === placeholder, "nil restores the cached placeholder")
  }

  func testDeactivateClearsStates() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    controller.activate(node: today[0])
    controller.activate(node: today[1])
    controller.deactivate(node: today[1])
    XCTAssertNil(controller.current)
    XCTAssertEqual(controller.rowState(for: today[0]), .previous)
    XCTAssertNil(try rowView(controller, today[1]).displayedFill)
  }

  /// #94: expanded folders show the open-folder icon (`folder.fill`) and collapsed folders show `folder`; outline
  /// removals and moves preserve folders' expanded/collapsed state; `isPressed` immediately updates
  /// `backgroundLayer.backgroundColor` to the 6.5% pressed fill; and the Favorites grid supports first-responder
  /// arrow-key navigation across rows and columns.
  func testFolderExpansionIconPreservedAcrossMovesPressedLayerFillAndFavoritesKeyboard() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let space = sidebar.spaceOrder[0]
    let outlineController = try XCTUnwrap(controller.currentPage?.outlineController)
    let outline = outlineController.outlineView
    let pinned = sidebar.children(of: .pinned(space))
    let folder = try XCTUnwrap(pinned.first { !isTab(sidebar, $0) })

    let expandedIcon = SidebarGlyphs.symbol("folder.fill", flavor: .light, scale: outline.shellBackingScale)
    let collapsedIcon = SidebarGlyphs.symbol("folder", flavor: .light, scale: outline.shellBackingScale)
    XCTAssertTrue(outline.isItemExpanded(outlineController.item(for: folder)))
    XCTAssertTrue(try cell(controller, folder).faviconView.image === expandedIcon,
                  "expanded folder uses open-folder icon")

    // Clicking the folder row collapses it and switches the icon to the closed folder glyph.
    outlineController.handleClick(row: outlineController.row(for: folder), modifiers: [])
    XCTAssertFalse(outline.isItemExpanded(outlineController.item(for: folder)))
    XCTAssertTrue(try cell(controller, folder).faviconView.image === collapsedIcon,
                  "collapsed folder uses closed-folder icon")

    // Moving the collapsed folder (and removing a sibling above it) keeps it collapsed.
    sidebar.moveNode(folder, to: .pinned(space), at: 0)
    XCTAssertFalse(outline.isItemExpanded(outlineController.item(for: folder)),
                   "moving a collapsed folder preserves its collapsed state")
    XCTAssertTrue(try cell(controller, folder).faviconView.image === collapsedIcon)
    sidebar.moveNode(folder, to: .today(space), at: 1)
    XCTAssertFalse(outline.isItemExpanded(outlineController.item(for: folder)),
                   "moving a collapsed folder across sections preserves its collapsed state")

    // Expanding it again and moving it back keeps it expanded.
    outlineController.handleClick(row: outlineController.row(for: folder), modifiers: [])
    XCTAssertTrue(outline.isItemExpanded(outlineController.item(for: folder)))
    XCTAssertTrue(try cell(controller, folder).faviconView.image === expandedIcon)
    sidebar.moveNode(folder, to: .pinned(space), at: 0)
    XCTAssertTrue(outline.isItemExpanded(outlineController.item(for: folder)))

    // Pressing a row immediately sets `backgroundLayer.backgroundColor` to the 6.5% pressed fill without waiting for
    // a later layout pass.
    let todayTab = sidebar.children(of: .today(space))[0]
    let todayRow = try rowView(controller, todayTab)
    todayRow.updateLayer()
    todayRow.isPressed = true
    let expectedPressed = ShellTokens.tabPressed.resolve(.light)
    XCTAssertEqual(todayRow.displayedFill, expectedPressed)
    XCTAssertEqual(todayRow.backgroundLayer.backgroundColor, expectedPressed.cgColor)
    todayRow.isPressed = false

    // Favorites grid first-responder and keyboard navigation across the 3-column grid.
    let favorites = sidebar.children(of: .favorites(profile: "default"))
    let grid = controller.view.favorites
    XCTAssertTrue(grid.collectionView.acceptsFirstResponder)
    var activated: [NodeID] = []
    controller.onActivate = { activated.append($0) }
    controller.activate(node: favorites[0])
    grid.collectionView.moveRight(nil)
    XCTAssertEqual(controller.current, favorites[1])
    grid.collectionView.moveDown(nil)
    XCTAssertEqual(controller.current, favorites[4], "moveDown advances by 3 columns to the next row")
    grid.collectionView.moveLeft(nil)
    XCTAssertEqual(controller.current, favorites[3])
    grid.collectionView.moveUp(nil)
    XCTAssertEqual(controller.current, favorites[0], "moveUp moves back up one 3-column row")
  }
}

@MainActor
final class MountedSidebarTests: XCTestCase {
  override func setUp() async throws { _ = NSApplication.shared }

  func testRowPitchAndFavoriteTilesInWindow() throws {
    let sidebar = StubSidebar.sample()
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    root.layoutSubtreeIfNeeded()
    let outline = try XCTUnwrap(root.sidebarContainer.currentOutline)
    XCTAssertEqual(outline.rect(ofRow: 0).height, 41)
    let grid = root.sidebarContainer.favorites.collectionView
    grid.layoutSubtreeIfNeeded()
    let frames = (0..<3).compactMap { grid.item(at: IndexPath(item: $0, section: 0))?.view.frame }
    XCTAssertEqual(frames.count, 3)
    XCTAssertEqual(frames[0].size, CGSize(width: 52, height: 46))
    XCTAssertEqual(Set(frames.map(\.minY)).count, 1, "first three favorites share a row")
  }

  func testActivatingRowSetsCurrentAndPreviousStatesAndCard() throws {
    let sidebar = StubSidebar.sample()
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: sidebar)
    let space = sidebar.spaceOrder[0]
    let first = sidebar.children(of: .today(space))[0]
    let second = sidebar.children(of: .today(space))[1]
    controller.activate(node: first)
    controller.activate(node: second)
    XCTAssertEqual(controller.rowState(for: second), .current)
    XCTAssertEqual(controller.rowState(for: first), .previous)
    let tab = try XCTUnwrap(controller.currentTab)
    XCTAssertTrue(controller.rootView.card.clipView.subviews.contains { $0 === engine.contentView(for: tab) })
    engine.setDocumentTitle(tab, "Live Title")
    if case .tab(_, _, let title)? = sidebar.node(second) { XCTAssertEqual(title, "Live Title") } else { XCTFail() }
  }
}

/// Engine that finishes the load (title, favicon, redirected URL) synchronously inside `createTab`,
/// before the caller can record the returned TabID.
@MainActor
private final class EagerEngine: EngineClient {
  let inner = InMemoryEngine()
  var tabIDs: [TabID] { inner.tabIDs }
  func createTab(url: URL?) -> TabID { finishEarly(inner.createTab(url: url), url: url) }
  func createTab(url: URL?, in window: EngineWindowID) -> TabID {
    finishEarly(inner.createTab(url: url, in: window), url: url)
  }
  private func finishEarly(_ id: TabID, url: URL?) -> TabID {
    if let url { inner.navigate(id, to: url.appendingPathComponent("redirected")) }
    inner.finishLoad(id, title: "Loaded Early", favicon: Data([0x89, 0x50]))
    return id
  }
  func closeTab(_ id: TabID) { inner.closeTab(id) }
  func closeTab(_ id: TabID, mode: CloseMode) { inner.closeTab(id, mode: mode) }
  func navigate(_ id: TabID, to url: URL) { inner.navigate(id, to: url) }
  func reload(_ id: TabID) { inner.reload(id) }
  func goBack(_ id: TabID) { inner.goBack(id) }
  func goForward(_ id: TabID) { inner.goForward(id) }
  func goToHistory(_ id: TabID, offset: Int) { inner.goToHistory(id, offset: offset) }
  func history(of id: TabID) -> TabHistory? { inner.history(of: id) }
  func duplicateTab(_ id: TabID) -> TabID? { inner.duplicateTab(id) }
  func snapshot(of id: TabID) -> TabSnapshot? { inner.snapshot(of: id) }
  func contentView(for id: TabID) -> NSView? { inner.contentView(for: id) }
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { inner.observe(handler) }
  var windowIDs: [EngineWindowID] { inner.windowIDs }
  func createWindow(host: any EngineWindowHosting) -> EngineWindowID { inner.createWindow(host: host) }
  func closeWindow(_ id: EngineWindowID) { inner.closeWindow(id) }
  func activateTab(_ id: TabID) { inner.activateTab(id) }
  func activeTab(in window: EngineWindowID) -> TabID? { inner.activeTab(in: window) }
  func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    inner.observeWindows(handler)
  }
  func observe(window: EngineWindowID, _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    inner.observe(window: window, handler)
  }
}

extension MountedSidebarTests {
  // E4b: every favicon the window learns from the engine reaches `onFaviconChanged` (the app persists it), both the
  // one caught up from the snapshot inside createTab and later `.faviconChanged` events.
  func testFaviconChangesReachTheHook() throws {
    let sidebar = StubSidebar.sample()
    let engine = EagerEngine()
    let controller = ShellWindowController(engine: engine, sidebar: sidebar)
    var seen: [(NodeID, Data?)] = []
    controller.onFaviconChanged = { seen.append(($0, $1)) }
    let node = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    controller.activate(node: node)
    XCTAssertEqual(seen.map(\.0), [node])
    XCTAssertEqual(seen.last?.1, Data([0x89, 0x50]))
    let tab = try XCTUnwrap(controller.currentTab)
    engine.inner.finishLoad(tab, title: "Loaded Early", favicon: Data([0x89, 0x51]))
    XCTAssertEqual(seen.map(\.0), [node, node])
    XCTAssertEqual(seen.last?.1, Data([0x89, 0x51]))
  }

  func testStateEmittedInsideCreateTabReachesTheSidebar() throws {
    let sidebar = StubSidebar.sample()
    let controller = ShellWindowController(engine: EagerEngine(), sidebar: sidebar)
    let space = sidebar.spaceOrder[0]
    let second = sidebar.children(of: .today(space))[1]
    guard case .tab(_, let originalURL, _)? = sidebar.node(second) else { return XCTFail() }
    controller.activate(node: second)
    guard case .tab(_, let url, let title)? = sidebar.node(second) else { return XCTFail() }
    XCTAssertEqual(title, "Loaded Early")
    XCTAssertEqual(url, originalURL.appendingPathComponent("redirected"))
  }
}

/// Review follow-ups: node-level reloads, shadow paths, accessibility, favicon pruning.
@MainActor
final class SidebarReviewTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws { _ = NSApplication.shared }
  override func tearDown() async throws { windows.forEach { $0.close() }; windows = [] }

  private func makeSidebar(_ sidebar: StubSidebar) -> SidebarController {
    let controller = SidebarController(source: sidebar)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    controller.view.layoutSubtreeIfNeeded()
    windows.append(window)
    return controller
  }

  private func cells(_ outline: NSOutlineView) -> [Int: NSView] {
    var map: [Int: NSView] = [:]
    for row in 0..<outline.numberOfRows {
      if let view = outline.view(atColumn: 0, row: row, makeIfNecessary: false) { map[row] = view }
    }
    return map
  }

  func testTitleChangeReloadsExactlyOneRow() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    let target = try XCTUnwrap(controller.currentPage?.outlineController.row(for: today[1]))
    let before = cells(outline)
    XCTAssertEqual(before.count, outline.numberOfRows)
    sidebar.updateTab(today[1], url: nil, title: "Renamed")
    let after = cells(outline)
    for (row, view) in before where row != target {
      XCTAssertTrue(after[row] === view, "row \(row) must not reload")
    }
    XCTAssertEqual((after[target] as? SidebarTabCellView)?.titleField.stringValue, "Renamed")
  }

  func testAppendDoesNotReloadOtherTodayRows() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let before = cells(outline)
    sidebar.addTab(url: URL(string: "https://example.com/n")!, title: "New", in: .today(sidebar.spaceOrder[0]))
    let after = cells(outline)
    for (row, view) in before { XCTAssertTrue(after[row] === view, "row \(row) must not reload") }
    XCTAssertEqual(outline.numberOfRows, before.count + 1)
  }

  func testFavoriteTitleChangeUpdatesTile() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let favorite = sidebar.children(of: .favorites(profile: "default"))[1]
    controller.view.favorites.collectionView.layoutSubtreeIfNeeded()
    sidebar.updateTab(favorite, url: nil, title: "Encyclopedia")
    XCTAssertEqual(controller.view.favorites.tile(for: favorite)?.accessibilityLabel(), "Encyclopedia")
  }

  func testRowShadowPathAndDarkOpacity() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    controller.activate(node: today[0])
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let row = try XCTUnwrap(controller.currentPage?.outlineController.row(for: today[0]))
    let rowView = try XCTUnwrap(outline.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView)
    rowView.layoutSubtreeIfNeeded()
    rowView.displayIfNeeded()
    let layer = rowView.backgroundLayer
    XCTAssertEqual(layer.shadowOpacity, 1)
    let path = try XCTUnwrap(layer.shadowPath)
    XCTAssertEqual(path.boundingBox, layer.bounds)
    rowView.flavor = .dark
    rowView.displayIfNeeded()
    XCTAssertEqual(layer.shadowOpacity, 0, "dark shadow token is fully transparent")
  }

  func testTileShadowPathAndDarkOpacity() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let favorite = sidebar.children(of: .favorites(profile: "default"))[0]
    controller.activate(node: favorite)
    controller.view.favorites.collectionView.layoutSubtreeIfNeeded()
    let tile = try XCTUnwrap(controller.view.favorites.tile(for: favorite))
    tile.layoutSubtreeIfNeeded()
    tile.displayIfNeeded()
    let layer = try XCTUnwrap(tile.layer)
    XCTAssertEqual(layer.shadowOpacity, 1)
    XCTAssertEqual(try XCTUnwrap(layer.shadowPath).boundingBox, layer.bounds)
    tile.flavor = .dark
    tile.displayIfNeeded()
    XCTAssertEqual(layer.shadowOpacity, 0)
  }

  func testAccessibility() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let favorites = sidebar.children(of: .favorites(profile: "default"))
    controller.view.favorites.collectionView.layoutSubtreeIfNeeded()
    let tile = try XCTUnwrap(controller.view.favorites.tile(for: favorites[0]))
    XCTAssertEqual(tile.accessibilityLabel(), "Example")
    XCTAssertEqual(tile.accessibilityRole(), .button)
    XCTAssertTrue(tile.isAccessibilityElement())
    XCTAssertFalse(tile.faviconView.isAccessibilityElement())
    let outlineController = try XCTUnwrap(controller.currentPage?.outlineController)
    let divider = try XCTUnwrap(controller.view.currentOutline?.view(
      atColumn: 0, row: outlineController.dividerRow, makeIfNecessary: false) as? SidebarDividerView)
    XCTAssertTrue(divider.isAccessibilityElement(), "the divider is exposed as a splitter (U4b, #226)")
    XCTAssertEqual(divider.accessibilityRole(), .splitter)
    XCTAssertEqual(divider.accessibilityIdentifier(), AXID.Sidebar.divider)
  }

  private func faviconData() throws -> Data {
    let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
      NSColor.red.setFill(); rect.fill(); return true
    }
    return try XCTUnwrap(image.tiffRepresentation)
  }

  // E4b: the favicon stays while the node exists (engine tab closed or not); it goes with the node.
  func testFaviconIsKeptWhileTheNodeExistsAndDroppedWithIt() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    let data = try faviconData()
    controller.setFavicon(data, for: today[0])
    controller.setFavicon(data, for: today[2])
    controller.activate(node: today[0])
    controller.deactivate(node: today[0])
    controller.deactivate(node: today[2])                 // never current
    XCTAssertNotNil(controller.favicons[today[0]], "engine tab closed, node still in the sidebar")
    XCTAssertNotNil(controller.favicons[today[2]])
    sidebar.removeNode(today[0])
    XCTAssertNil(controller.favicons[today[0]], "node removed from the source")
    XCTAssertNotNil(controller.favicons[today[2]])
  }

  func testFaviconsOfARemovedSpaceAreDropped() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let removed = sidebar.spaceOrder[1]
    let tab = sidebar.children(of: .today(removed))[0]
    let favorite = sidebar.children(of: .favorites(profile: "default"))[0]
    let data = try faviconData()
    controller.setFavicons([tab: data, favorite: data])
    sidebar.removeSpace(removed)                          // emits `.spaceRemoved` only
    XCTAssertNil(controller.favicons[tab])
    XCTAssertNotNil(controller.favicons[favorite])
  }

  func testSetFaviconsDecodesABatchAndShowsIt() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let row = try XCTUnwrap(controller.currentPage?.outlineController.row(for: today[0]))
    func cell() throws -> SidebarTabCellView {
      try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView)
    }
    let placeholder = try cell().faviconView.image
    let data = try faviconData()
    controller.setFavicons([today[0]: data, today[1]: data, NodeID(): data])
    XCTAssertNotNil(controller.favicons[today[0]])
    XCTAssertNotNil(controller.favicons[today[1]])
    XCTAssertEqual(controller.favicons.count, 2, "ids that are not in the source are ignored")
    let shown = try XCTUnwrap(try cell().faviconView.image)
    XCTAssertFalse(shown === placeholder)
  }

  func testControllerAndAnotherObserverBothReceiveChanges() throws {
    let sidebar = StubSidebar.sample()
    let controller = makeSidebar(sidebar)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    var seen: [SidebarChange] = []
    let observation = sidebar.observe { seen.append($0) }
    let rows = outline.numberOfRows
    sidebar.addTab(url: URL(string: "https://example.com/m")!, title: "M", in: .today(sidebar.spaceOrder[0]))
    XCTAssertEqual(outline.numberOfRows, rows + 1)
    XCTAssertEqual(seen, [.structure(.today(sidebar.spaceOrder[0]))])
    observation.cancel()
  }
}
