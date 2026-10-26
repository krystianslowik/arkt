import AppKit
import Carbon.HIToolbox
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Keyboard tab navigation without the overlay (#103): Cmd-1 ... Cmd-9, next / previous tab in sidebar order,
/// Ctrl-Cmd-Right / Left through recent tabs, the reveal scroll and overflow pill (BH-018), and Ctrl-Space's focus
/// hand-off to the sidebar (BH-019, BH-020).
@MainActor
final class TabKeyboardNavigationTests: XCTestCase {
  private var source: StubSidebar!
  private var controller: ShellWindowController!
  private var space: SpaceID!
  private var favorites: [NodeID] = []
  private var pinned: NodeID!
  private var folder: NodeID!
  private var folderTabs: [NodeID] = []
  private var today: [NodeID] = []

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    source = StubSidebar()
    space = source.addSpace(title: "Work", theme: SpaceThemeInfo(baseColors: [.white(1)], isDark: false))
    favorites = (0..<2).map {
      source.addTab(url: Self.url("f\($0)"), title: "F\($0)", in: .favorites(profile: "default"))
    }
    pinned = source.addTab(url: Self.url("p"), title: "P", in: .pinned(space))
    folder = source.addFolder(title: "Folder", in: .pinned(space))
    folderTabs = (0..<2).map { source.addTab(url: Self.url("d\($0)"), title: "D\($0)", in: .folder(folder)) }
    today = (0..<30).map { source.addTab(url: Self.url("t\($0)"), title: "T\($0)", in: .today(space)) }
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    controller.window?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: false)
    controller.sidebarReveal.reduceMotion = { true }
    controller.tabSwitcher.reduceMotion = { true }
    controller.window?.layoutIfNeeded()
  }

  override func tearDown() async throws {
    controller.window?.orderOut(nil)
    controller = nil
  }

  private func menuItem(tag: Int) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: #selector(ShellWindowController.goToSidebarItem(_:)), keyEquivalent: "")
    item.tag = tag
    return item
  }

  private var current: NodeID? { controller.sidebarController.current }
  private var page: SpacePageView { controller.sidebarController.currentPage! }
  private var outline: SidebarOutlineView { page.outlineView }

  // MARK: Cmd-1 ... Cmd-9

  func testCommandNumberCountsFavoritesFirst() {
    controller.goToSidebarItem(menuItem(tag: 1))
    XCTAssertEqual(current, favorites[0])
    controller.goToSidebarItem(menuItem(tag: 3))
    XCTAssertEqual(current, pinned)
    controller.goToSidebarItem(menuItem(tag: 4))
    XCTAssertEqual(current, folderTabs[0], "an open folder's tabs count in place")
  }

  func testWithoutFavoritesCountingStartsAtPinned() {
    controller.tabNavigationSettings.countsFavorites = false
    controller.goToSidebarItem(menuItem(tag: 1))
    XCTAssertEqual(current, pinned)
  }

  func testCommandNineOpensTheLastItemUnlessTheNinthSettingIsOn() {
    controller.goToSidebarItem(menuItem(tag: 9))
    XCTAssertEqual(current, today.last)
    controller.tabNavigationSettings.ninthOpensNinth = true
    controller.goToSidebarItem(menuItem(tag: 9))
    XCTAssertEqual(current, today[3], "F0 F1 P D0 D1 T0 T1 T2 T3")
  }

  // MARK: Next / previous

  func testNextAndPreviousFollowTheSidebarOrderAndStopAtTheEnds() {
    controller.activate(node: pinned)
    controller.nextSidebarTab(nil)
    XCTAssertEqual(current, folderTabs[0])
    controller.previousSidebarTab(nil)
    controller.previousSidebarTab(nil)
    XCTAssertEqual(current, favorites[1])
    controller.activate(node: favorites[0])
    controller.previousSidebarTab(nil)
    XCTAssertEqual(current, favorites[0], "no wrap at the top")
  }

  // MARK: Ctrl-Cmd-Right / Left

  func testCyclingWalksBackThroughRecentTabsAndWraps() {
    controller.activate(node: today[0])
    controller.activate(node: today[1])
    controller.activate(node: today[2])
    controller.cycleRecentTabForward(nil)
    XCTAssertEqual(current, today[1])
    controller.cycleRecentTabForward(nil)
    XCTAssertEqual(current, today[0])
    controller.cycleRecentTabBackward(nil)
    XCTAssertEqual(current, today[1])
    XCTAssertFalse(controller.tabSwitcher.isOpen, "no overlay")
  }

  // MARK: Reveal (BH-018)

  func testAKeyboardJumpScrollsTheRowIntoViewAndShowsTheOverflowPill() throws {
    let clip = page.scrollView.contentView
    XCTAssertEqual(clip.bounds.minY, 0)
    controller.goToSidebarItem(menuItem(tag: 9))

    let row = page.outlineController.row(for: try XCTUnwrap(today.last))
    XCTAssertTrue(clip.bounds.contains(outline.rect(ofRow: row)), "the row is in view")
    let pill = controller.sidebarReveal.pill
    XCTAssertTrue(pill.isShowing)
    XCTAssertFalse(pill.isHidden)
    let hiddenAbove = (0..<outline.numberOfRows).filter {
      $0 != page.outlineController.dividerRow && outline.rect(ofRow: $0).maxY <= clip.bounds.minY
    }.count
    XCTAssertGreaterThan(hiddenAbove, 0)
    XCTAssertEqual(pill.label.stringValue, "\(hiddenAbove) more above")
    XCTAssertTrue(pill.superview === page)
    XCTAssertEqual(pill.accessibilityIdentifier(), AXID.TabSwitcher.overflowPill)
  }

  func testARowAlreadyInViewNeitherScrollsNorShowsThePill() {
    controller.goToSidebarItem(menuItem(tag: 3))
    XCTAssertEqual(page.scrollView.contentView.bounds.minY, 0)
    XCTAssertFalse(controller.sidebarReveal.pill.isShowing)
  }

  /// The pill leaves after its time, driven by an injected sleep (no real wait), and on the user's next scroll.
  func testThePillLeavesAfterItsTimeAndOnTheNextScroll() async throws {
    let sleeper = PillSleeper()
    let revealer = SidebarRevealer(sleep: { duration in await sleeper.sleep(duration) })
    revealer.reduceMotion = { true }
    let clip = page.scrollView.contentView
    revealer.reveal(row: outline.numberOfRows - 1, in: page, flavor: .light)
    XCTAssertTrue(revealer.pill.isShowing)
    await sleeper.waitForSleepers(1)
    let requested = await sleeper.requested
    XCTAssertEqual(requested, [SidebarRevealer.pillDuration])
    await sleeper.wakeOldest()
    while revealer.pill.isShowing { await Task.yield() }

    revealer.reveal(row: 0, in: page, flavor: .light)
    let hiddenBelow = (0..<outline.numberOfRows).filter {
      $0 != page.outlineController.dividerRow && outline.rect(ofRow: $0).minY >= clip.bounds.maxY
    }.count
    XCTAssertTrue(revealer.pill.isShowing)
    XCTAssertEqual(revealer.pill.label.stringValue, SidebarRevealer.pillText(count: hiddenBelow, above: false))
    page.scrollView.onUserScroll?()
    XCTAssertFalse(revealer.pill.isShowing)
    await sleeper.waitForSleepers(2)
    await sleeper.wakeOldest()
  }

  /// With motion the reveal springs, and Reduce Motion jumps (the other tests).
  func testWithMotionTheRevealScrollSprings() {
    controller.sidebarReveal.reduceMotion = { false }
    // Taller than most screens: `showWindow` constrains it, as on CI, and the reveal must measure after that.
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 1100), display: false)
    controller.showWindow(nil)
    controller.goToSidebarItem(menuItem(tag: 9))
    XCTAssertTrue(controller.sidebarReveal.isScrolling)
    waitUntil("the reveal settled") { !self.controller.sidebarReveal.isScrolling }
    let row = page.outlineController.row(for: today.last!)
    XCTAssertTrue(page.scrollView.contentView.bounds.contains(outline.rect(ofRow: row)))
  }

  // MARK: Ctrl-Space (BH-019, BH-020)

  private func key(_ keyCode: Int) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  func testCtrlSpaceOpensTheFolderAndFocusesTheCurrentRowWithTheSystemRing() throws {
    controller.activate(node: folderTabs[1])
    page.outlineController.handleClick(row: page.outlineController.row(for: folder), modifiers: [])   // collapse
    XCTAssertFalse(page.outlineController.isFolderOpen(folder))
    XCTAssertEqual(page.outlineController.row(for: folderTabs[1]), page.outlineController.row(for: folder) + 1,
                   "the current tab peeks out of its closed folder (#109)")

    controller.revealCurrentTab(nil)

    let row = page.outlineController.row(for: folderTabs[1])
    XCTAssertGreaterThanOrEqual(row, 0, "the folder opened")
    XCTAssertTrue(page.outlineController.isFolderOpen(folder))
    XCTAssertTrue(controller.window?.firstResponder === outline)
    XCTAssertEqual(outline.keyboardFocusRow, row)
    let ring = outline.keyboardFocusRing
    XCTAssertFalse(ring.isHidden)
    XCTAssertTrue(ring.superview === outline)
    XCTAssertEqual(ring.frame, outline.keyboardFocusRect(row))
    ring.updateLayer()
    XCTAssertEqual(ring.ring.strokeColor, ring.strokeColor, "the system focus ring color")
    XCTAssertEqual(ring.ring.lineWidth, KeyboardFocusRingView.lineWidth)
  }

  func testArrowsMoveTheFocusPastTheDividerAndReturnOpensTheRow() throws {
    controller.activate(node: folderTabs[1])
    controller.revealCurrentTab(nil)
    let start = try XCTUnwrap(outline.keyboardFocusRow)

    outline.keyDown(with: try key(kVK_DownArrow))
    XCTAssertEqual(outline.keyboardFocusRow, page.outlineController.row(for: today[0]), "the divider is skipped")
    outline.keyDown(with: try key(kVK_UpArrow))
    XCTAssertEqual(outline.keyboardFocusRow, start)
    outline.keyDown(with: try key(kVK_DownArrow))

    outline.keyDown(with: try key(kVK_Return))

    XCTAssertEqual(current, today[0])
    XCTAssertFalse(controller.window?.firstResponder === outline, "focus went back to the page")
    XCTAssertNil(outline.keyboardFocusRow)
    XCTAssertTrue(outline.keyboardFocusRing.isHidden)
  }

  func testEscapeGivesFocusBackWithoutOpeningAnything() throws {
    controller.activate(node: pinned)
    controller.revealCurrentTab(nil)
    outline.keyDown(with: try key(kVK_DownArrow))

    outline.keyDown(with: try key(kVK_Escape))

    XCTAssertEqual(current, pinned)
    XCTAssertNil(outline.keyboardFocusRow)
    XCTAssertFalse(controller.window?.firstResponder === outline)
  }

  /// With motion, Ctrl-Space on an off-screen row scrolls once, by the reveal spring: no jump before it.
  func testCtrlSpaceWithMotionScrollsOnlyThroughTheRevealSpring() throws {
    controller.sidebarReveal.reduceMotion = { false }
    controller.showWindow(nil)
    controller.activate(node: try XCTUnwrap(today.last))
    page.scrollView.contentView.scroll(to: .zero)
    page.scrollView.reflectScrolledClipView(page.scrollView.contentView)

    controller.revealCurrentTab(nil)

    XCTAssertTrue(controller.sidebarReveal.isScrolling)
    XCTAssertEqual(page.scrollView.contentView.bounds.minY, 0, "nothing jumped ahead of the spring")
    waitUntil("the reveal settled") { !self.controller.sidebarReveal.isScrolling }
    let row = try XCTUnwrap(outline.keyboardFocusRow)
    XCTAssertTrue(page.scrollView.contentView.bounds.contains(outline.keyboardFocusRect(row)))
  }

  /// Arrow keys past the visible rows scroll the focus row into view.
  func testArrowKeysScrollTheFocusRowIntoView() throws {
    controller.activate(node: today[0])
    controller.revealCurrentTab(nil)
    for _ in 0..<25 { outline.keyDown(with: try key(kVK_DownArrow)) }
    let row = try XCTUnwrap(outline.keyboardFocusRow)
    XCTAssertEqual(row, page.outlineController.row(for: today[25]))
    XCTAssertTrue(page.scrollView.contentView.bounds.contains(outline.keyboardFocusRect(row)))
  }

  func testCtrlSpaceShowsAHiddenSidebar() {
    controller.activate(node: pinned)
    controller.rootView.sidebarVisible = false
    controller.revealCurrentTab(nil)
    XCTAssertTrue(controller.rootView.sidebarVisible)
    XCTAssertNotNil(outline.keyboardFocusRow)
  }

  /// #343: a Favorite current puts the system keyboard-focus ring on its tile, not on an unrelated outline row.
  func testCtrlSpaceFocusesTheCurrentFavoriteTileWithTheSystemRing() throws {
    controller.activate(node: favorites[0])
    controller.revealCurrentTab(nil)

    let grid = controller.sidebarController.view.favorites
    let tile = try XCTUnwrap(grid.tile(for: favorites[0]))
    XCTAssertTrue(controller.window?.firstResponder === grid.collectionView)
    XCTAssertEqual(grid.keyboardFocusID, favorites[0])
    XCTAssertFalse(tile.keyboardFocusRing.isHidden)
    XCTAssertEqual(tile.keyboardFocusRing.frame, tile.bounds)
    tile.keyboardFocusRing.updateLayer()
    XCTAssertEqual(tile.keyboardFocusRing.ring.strokeColor, tile.keyboardFocusRing.strokeColor)
    XCTAssertEqual(tile.keyboardFocusRing.ring.lineWidth, KeyboardFocusRingView.lineWidth)
    XCTAssertNil(outline.keyboardFocusRow)
  }

  /// #343: arrows move only the tile cursor; Return activates that tile and gives focus back to the page.
  func testFavoriteArrowsMoveFocusAndReturnOpensTheTile() throws {
    controller.activate(node: favorites[0])
    controller.revealCurrentTab(nil)
    let grid = controller.sidebarController.view.favorites

    grid.collectionView.keyDown(with: try key(kVK_RightArrow))
    XCTAssertEqual(grid.keyboardFocusID, favorites[1])
    XCTAssertEqual(current, favorites[0], "moving focus does not activate the destination")
    grid.collectionView.keyDown(with: try key(kVK_LeftArrow))
    XCTAssertEqual(grid.keyboardFocusID, favorites[0])
    grid.collectionView.keyDown(with: try key(kVK_RightArrow))
    grid.collectionView.keyDown(with: try key(kVK_Return))

    XCTAssertEqual(current, favorites[1])
    XCTAssertNil(grid.keyboardFocusID)
    XCTAssertFalse(controller.window?.firstResponder === grid.collectionView)
    XCTAssertEqual(grid.tile(for: favorites[1])?.keyboardFocusRing.isHidden, true)
  }

  /// #343: Down leaves the grid for the first outline row; Up returns to the tile that had focus.
  func testUpAndDownMoveBetweenTheFavoritesGridAndOutline() throws {
    controller.activate(node: favorites[0])
    controller.revealCurrentTab(nil)
    let grid = controller.sidebarController.view.favorites

    grid.collectionView.keyDown(with: try key(kVK_DownArrow))
    let firstRow = try XCTUnwrap(outline.keyboardFocusRow)
    XCTAssertTrue(controller.window?.firstResponder === outline)
    XCTAssertTrue(page.outlineController.isKeyboardFocusable(row: firstRow))
    XCTAssertNil(grid.keyboardFocusID)

    outline.keyDown(with: try key(kVK_UpArrow))
    XCTAssertTrue(controller.window?.firstResponder === grid.collectionView)
    XCTAssertEqual(grid.keyboardFocusID, favorites[0])
    XCTAssertNil(outline.keyboardFocusRow)
  }

  /// #343: with no Favorites, Up at the first outline row keeps the outline cursor and its ring.
  func testUpAtTheFirstOutlineRowWithoutFavoritesKeepsOutlineFocus() throws {
    for favorite in favorites { source.removeNode(favorite) }
    controller.activate(node: pinned)
    controller.revealCurrentTab(nil)
    let row = try XCTUnwrap(outline.keyboardFocusRow)

    outline.keyDown(with: try key(kVK_UpArrow))

    XCTAssertTrue(controller.window?.firstResponder === outline)
    XCTAssertEqual(outline.keyboardFocusRow, row)
    XCTAssertFalse(outline.keyboardFocusRing.isHidden)
  }

  /// #343 / design VoiceOver: a moved tile cursor reports its destination, and announcement text uses that
  /// destination's title rather than the still-current tab's title.
  func testFavoriteCursorMovementReportsItsDestinationForVoiceOver() throws {
    controller.activate(node: favorites[0])
    controller.revealCurrentTab(nil)
    let grid = controller.sidebarController.view.favorites
    var destinations: [NodeID] = []
    grid.onKeyboardFocusMoved = { destinations.append($0) }

    grid.collectionView.keyDown(with: try key(kVK_RightArrow))

    XCTAssertEqual(destinations, [favorites[1]])
    XCTAssertEqual(controller.sidebarAnnouncementText(for: favorites[1]), "Sidebar, F1")
    XCTAssertEqual(controller.sidebarAnnouncementText(for: pinned), "Sidebar, P")
  }

  /// #343: Esc leaves a moved tile cursor without opening it.
  func testEscapeFromAFavoriteGivesFocusBackWithoutOpeningAnything() throws {
    controller.activate(node: favorites[0])
    controller.revealCurrentTab(nil)
    let grid = controller.sidebarController.view.favorites
    grid.collectionView.keyDown(with: try key(kVK_RightArrow))

    grid.collectionView.keyDown(with: try key(kVK_Escape))

    XCTAssertEqual(current, favorites[0])
    XCTAssertNil(grid.keyboardFocusID)
    XCTAssertFalse(controller.window?.firstResponder === grid.collectionView)
  }

  /// The next pointer click removes the ring.
  func testAClickInTheSidebarRemovesTheFocusRing() throws {
    controller.activate(node: pinned)
    controller.revealCurrentTab(nil)
    XCTAssertNotNil(outline.keyboardFocusRow)
    outline.presentContextMenu = { _, _, _ in }
    let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .control,
                                                 timestamp: 0, windowNumber: controller.window?.windowNumber ?? 0,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    outline.mouseDown(with: click)                    // a Ctrl-click: shows the (stubbed) menu, no tracking loop
    XCTAssertNil(outline.keyboardFocusRow)
  }
}

/// A sleeper whose sleeps end only when the test wakes them, oldest first.
private actor PillSleeper {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requested: [Duration] = []

  func sleep(_ duration: Duration) async {
    requested.append(duration)
    await withCheckedContinuation { waiters.append($0) }
  }

  /// Returns once `count` sleeps in total have started.
  func waitForSleepers(_ count: Int) async {
    while requested.count < count { await Task.yield() }
  }

  func wakeOldest() {
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().resume()
  }
}
