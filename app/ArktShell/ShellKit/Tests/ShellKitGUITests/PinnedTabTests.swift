import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Pinned tabs (BH-055 to BH-061, BH-065): Cmd-D pin/unpin with its toasts (KB-012), reset to the pinned URL
/// (KB-041, favicon click GS-005, Cmd-click BH-058), Reset Space (BH-059), Replace Pin (BH-060), Separate From
/// Pinned Tab (BH-061), the stored pinned URL surviving navigation (BH-057, BH-062), and the per-window collapsed
/// Pinned section (BH-065). Favicon clicks are driven through `handleClick(row:modifiers:)` with the outline's
/// recorded click point; the menu paths are the items' own `performActionForItem`.
@MainActor
final class PinnedTabTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// One Space "Work": pinned tabs `p0`, `p1`, a folder with `foldered`, Today tabs `today`, and a split with two
  /// panes.
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var p0: UUID
    var p1: UUID
    var folder: UUID
    var foldered: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
    var favorite: UUID
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var errors: [(SidebarMutation, String)] = []

    init(_ sidebar: SidebarModel.Sidebar, opensFirstTab: Bool = false) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { PinnedTabTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source, opensFirstTab: opensFirstTab)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onError = { [unowned self] mutation, error in
        errors.append((mutation, String(describing: error)))
      }
    }

    var sidebarController: SidebarController { controller.sidebarController }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }

    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }
    func tabURL(_ node: UUID) -> URL? {
      guard case .tab(_, let url, _)? = source.node(node) else { return nil }
      return url
    }
    func tabTitle(_ node: UUID) -> String? {
      guard case .tab(_, _, let title)? = source.node(node) else { return nil }
      return title
    }

    /// Activates `node` and navigates its engine tab away from the pinned URL.
    func navigate(_ node: UUID, to path: String, title: String) throws {
      controller.activate(node: node)
      let tab = try XCTUnwrap(controller.tabsByNode[node], "the node is not loaded")
      engine.navigate(tab, to: PinnedTabTests.url(path))
      engine.finishLoad(tab, title: title)
    }

    /// The point of `node`'s favicon in outline coordinates (the recorded click location of a favicon click).
    func faviconPoint(_ node: UUID) throws -> NSPoint {
      let outlineView = try outline().outlineView
      let cellFrame = outlineView.frameOfCell(atColumn: 0, row: try row(node))
      return NSPoint(x: cellFrame.minX + SidebarMetrics.faviconLeading + SidebarMetrics.faviconSize / 2,
                     y: cellFrame.midY)
    }

    /// A click on the middle of `node`'s row title in outline coordinates.
    func titlePoint(_ node: UUID) throws -> NSPoint {
      let outlineView = try outline().outlineView
      let cellFrame = outlineView.frameOfCell(atColumn: 0, row: try row(node))
      return NSPoint(x: cellFrame.minX + SidebarMetrics.titleLeading + 20, y: cellFrame.midY)
    }

    /// A click on `node`'s row at `point` with `modifiers`, the way the outline records and dispatches clicks.
    func click(_ node: UUID, at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) throws {
      let outline = try outline()
      outline.outlineView.lastClickPoint = point
      outline.handleClick(row: try row(node), modifiers: modifiers)
    }

    func menuTitles(_ node: UUID) throws -> [String] {
      let menu = try XCTUnwrap(try outline().menu(forRow: row(node)), "the row has no context menu")
      return menu.items.map(\.title)
    }

    /// Chooses the context menu item `title` on `node`'s row and returns whether it was enabled.
    @discardableResult
    func choose(_ title: String, on node: UUID) throws -> Bool {
      let menu = try XCTUnwrap(try outline().menu(forRow: row(node)), "the row has no context menu")
      let index = menu.indexOfItem(withTitle: title)
      XCTAssertGreaterThanOrEqual(index, 0, "no \(title) item")
      let item = try XCTUnwrap(menu.item(at: index))
      guard item.isEnabled else { return false }
      menu.performActionForItem(at: index)
      return true
    }

    func menuItem(_ action: Selector) -> NSMenuItem {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      item.target = controller
      return item
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let p0 = try sidebar.addTab(url: url("p0"), title: "P0", in: .pinned(space))
    let p1 = try sidebar.addTab(url: url("p1"), title: "P1", in: .pinned(space))
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    let foldered = try sidebar.addTab(url: url("g0"), title: "G0", in: .folder(folder))
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try (0..<2).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let favorite = try sidebar.addTab(url: url("f0"), title: "F0", in: .favorites(profile: "default"))
    return World(sidebar: sidebar, space: space, p0: p0, p1: p1, folder: folder, foldered: foldered,
                 today: today, split: split, panes: panes, favorite: favorite)
  }

  // MARK: Pin and unpin (BH-055, KB-012)

  /// The File menu item's title and enabled state follow the current tab (KB-012).
  func testPinMenuItemTitleAndEnabledStateFollowTheCurrentTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let item = harness.menuItem(#selector(ShellWindowController.pinCurrentTab(_:)))
    XCTAssertFalse(harness.controller.validateMenuItem(item), "no current tab")

    for node in [world.today[0], world.p0, world.panes[0]] {
      harness.controller.activate(node: node)
      XCTAssertTrue(harness.controller.validateMenuItem(item))
    }
    harness.controller.activate(node: world.today[0])
    XCTAssertTrue(harness.controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Pin Tab")
    harness.controller.activate(node: world.p0)
    XCTAssertTrue(harness.controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Unpin Tab")
    harness.controller.activate(node: world.panes[0])
    XCTAssertTrue(harness.controller.validateMenuItem(item))
    XCTAssertEqual(item.title, "Pin Tab", "a focused pane pins its split (BH-115)")

    harness.controller.activate(node: world.favorite)
    XCTAssertFalse(harness.controller.validateMenuItem(item), "a Favorite is not pinnable")
    harness.controller.activate(node: world.foldered)
    XCTAssertFalse(harness.controller.validateMenuItem(item), "a foldered tab is pinned through its folder")
    harness.controller.close()
  }

  func testCmdDPinsTheCurrentTodayTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.today[0]])

    harness.controller.pinCurrentTab(nil)

    XCTAssertEqual(harness.children(.pinned(world.space)), [world.p0, world.p1, world.folder, world.today[0]])
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[1], world.split])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Pinned Tab to Work")
    // The current tab never closes or archives on a pin (BH-055; the pin keeps the page).
    XCTAssertEqual(harness.controller.currentNode, world.today[0])
    XCTAssertNotNil(harness.engine.snapshot(of: tab))
    XCTAssertTrue(harness.controller.visibleNodes.contains(world.today[0]))
    XCTAssertTrue(harness.errors.isEmpty)
    harness.controller.close()
  }

  func testCmdDUnpinsTheCurrentPinnedTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.p0)
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])

    harness.controller.pinCurrentTab(nil)

    XCTAssertEqual(harness.children(.pinned(world.space)), [world.p1, world.folder])
    XCTAssertEqual(harness.children(.today(world.space)), [world.p0, world.today[0], world.today[1], world.split],
                   "an unpinned tab lands on top of Today [I]")
    XCTAssertEqual(harness.controller.toasts.current?.text, "Un-Pinned Tab from Work")
    XCTAssertEqual(harness.controller.currentNode, world.p0)
    XCTAssertNotNil(harness.engine.snapshot(of: tab))
    harness.controller.close()
  }

  /// A focused pane pins its whole split; both panes and the layout survive (BH-115; panes are never split apart).
  func testCmdDOnAFocusedPanePinsTheWholeSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    harness.controller.pinCurrentTab(nil)

    XCTAssertEqual(harness.children(.pinned(world.space)), [world.p0, world.p1, world.folder, world.split])
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    XCTAssertEqual(harness.controller.currentNode, world.panes[0])
    XCTAssertNotNil(harness.controller.tabsByNode[world.panes[0]])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Pinned Tab to Work")

    harness.controller.pinCurrentTab(nil)
    XCTAssertEqual(harness.children(.today(world.space)), [world.split, world.today[0], world.today[1]])
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    harness.controller.close()
  }

  // MARK: Context menu (BH-055, BH-057, BH-060, BH-061)

  func testATodayRowOffersPinTabAndAPinnedRowThePinnedItems() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertEqual(try harness.menuTitles(world.today[0]), SplitSidebarTests.todayMenu)
    XCTAssertEqual(try harness.menuTitles(world.p0),
                   ["Rename", "Duplicate", "Unpin Tab", "", "Back to Pinned URL", "Replace Pin with Current Page",
                    "Separate From Pinned Tab", "Edit Pinned URL", "", "Move To", "", "Copy Link",
                    "Copy Link as Markdown", "", "Close and Keep Pinned"])
    XCTAssertEqual(try harness.menuTitles(world.panes[0]), SplitSidebarTests.paneMenu,
                   "a pane row never offers pin items")
    harness.controller.close()
  }

  func testTheContextMenuPinsAndUnpins() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    XCTAssertTrue(try harness.choose("Pin Tab", on: world.today[0]))
    XCTAssertEqual(harness.children(.pinned(world.space)), [world.p0, world.p1, world.folder, world.today[0]])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Pinned Tab to Work")
    XCTAssertTrue(try harness.choose("Unpin Tab", on: world.today[0]))
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[0], world.today[1], world.split])
    XCTAssertEqual(harness.controller.toasts.current?.text, "Un-Pinned Tab from Work")
    harness.controller.close()
  }

  // MARK: Unpin and auto-archive

  /// Stamps hidden tabs the way `AppSession` wires `onTabHidden` (decision 10), at the fixed test clock.
  private func wireStamping(_ harness: Harness) {
    harness.controller.onTabHidden = { [unowned harness] id in harness.source.markInactive([id], at: Self.now) }
  }

  /// The Today items the idle timer would archive right now, with what the window shows exempt.
  private func autoArchived(_ harness: Harness) -> [UUID] {
    AutoArchivePolicy.itemsToArchive(
      in: harness.source.sidebar,
      AutoArchiveInput(now: Self.now, startedAt: .distantPast, exempt: harness.controller.visibleNodes,
                       threshold: { _ in .twelveHours }))
  }

  private static let longIdle = now.addingTimeInterval(-2 * 86_400)

  /// An idle pinned tab that is not current, unpinned from its row, restarts its idle clock: it lands in Today
  /// without being archived on the next timer pass.
  func testUnpinningAnIdleBackgroundTabDoesNotAutoArchiveIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    wireStamping(harness)
    harness.source.markInactive([world.p0], at: Self.longIdle)

    XCTAssertTrue(try harness.choose("Unpin Tab", on: world.p0))

    XCTAssertEqual(harness.children(.today(world.space)).first, world.p0)
    XCTAssertFalse(autoArchived(harness).contains(world.p0))
    harness.controller.close()
  }

  /// The same for an unpinned split: every pane restarts its clock, so the split stays.
  func testUnpinningAnIdleBackgroundSplitDoesNotAutoArchiveIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    wireStamping(harness)
    try harness.source.moveNode(world.split, to: .pinned(world.space), at: 3)
    harness.source.markInactive(world.panes, at: Self.longIdle)

    harness.controller.togglePin(of: world.split)

    XCTAssertEqual(harness.children(.today(world.space)).first, world.split)
    XCTAssertFalse(autoArchived(harness).contains(world.split))
    harness.controller.close()
  }

  /// A Favorite dragged to Today restarts its idle clock the same way.
  func testMovingAnIdleFavoriteToTodayDoesNotAutoArchiveIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    wireStamping(harness)
    harness.source.markInactive([world.favorite], at: Self.longIdle)

    XCTAssertTrue(harness.controller.move(world.favorite, to: .today(world.space)))

    XCTAssertFalse(autoArchived(harness).contains(world.favorite))
    harness.controller.close()
  }

  /// Reordering inside Today is not activity: the idle clock keeps running.
  func testReorderingWithinTodayKeepsTheIdleClock() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    wireStamping(harness)
    harness.source.markInactive([world.today[1]], at: Self.longIdle)

    XCTAssertTrue(harness.controller.move(world.today[1], to: .today(world.space), at: 0))

    XCTAssertTrue(autoArchived(harness).contains(world.today[1]))
    harness.controller.close()
  }

  // MARK: Unpin and the live URL

  /// A pinned tab that navigated away and is unpinned keeps the page it shows: the Today node takes the live URL.
  func testUnpinningANavigatedPinnedTabWritesTheLiveURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")

    harness.controller.pinCurrentTab(nil)

    XCTAssertEqual(harness.children(.today(world.space)).first, world.p0)
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0/other"))
    harness.controller.close()
  }

  /// An unpinned split writes each pane's live URL.
  func testUnpinningASplitWritesEachPanesLiveURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.source.moveNode(world.split, to: .pinned(world.space), at: 3)
    try harness.navigate(world.panes[1], to: "s1/other", title: "Other")

    harness.controller.togglePin(of: world.split)

    XCTAssertEqual(harness.tabURL(world.panes[0]), Self.url("s0"))
    XCTAssertEqual(harness.tabURL(world.panes[1]), Self.url("s1/other"))
    harness.controller.close()
  }

  /// A navigated Favorite moved to Today takes the live URL the same way.
  func testMovingANavigatedFavoriteToTodayWritesTheLiveURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.favorite, to: "f0/other", title: "Elsewhere")

    XCTAssertTrue(harness.controller.move(world.favorite, to: .today(world.space)))

    XCTAssertEqual(harness.tabURL(world.favorite), Self.url("f0/other"))
    harness.controller.close()
  }

  /// The reset-family items stay disabled while the pinned tab shows its pinned URL.
  func testTheResetItemsAreDisabledUntilTheTabNavigates() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    for title in ["Back to Pinned URL", "Replace Pin with Current Page", "Separate From Pinned Tab"] {
      XCTAssertFalse(try harness.choose(title, on: world.p0), title)
    }
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    for title in ["Back to Pinned URL", "Replace Pin with Current Page", "Separate From Pinned Tab"] {
      let menu = try XCTUnwrap(try harness.outline().menu(forRow: harness.row(world.p0)))
      XCTAssertTrue(menu.item(withTitle: title)?.isEnabled ?? false, title)
    }
    harness.controller.close()
  }

  // MARK: The stored pinned URL (BH-057, BH-062, BH-048)

  /// A pinned tab's node keeps the pinned URL on navigation; the title still follows the page (BH-062).
  func testAPinnedTabsNodeKeepsThePinnedURLOnNavigation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0"))
    XCTAssertEqual(harness.tabTitle(world.p0), "Other")
    harness.controller.close()
  }

  /// Favorites keep their pinned URL the same way (BH-048).
  func testAFavoritesNodeKeepsThePinnedURLOnNavigation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.favorite, to: "f0/other", title: "Elsewhere")
    XCTAssertEqual(harness.tabURL(world.favorite), Self.url("f0"))
    XCTAssertEqual(harness.tabTitle(world.favorite), "Elsewhere")
    harness.controller.close()
  }

  /// A foldered tab is pinned through its folder: same rule.
  func testAFolderedTabsNodeKeepsThePinnedURLOnNavigation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.foldered, to: "g0/other", title: "Other")
    XCTAssertEqual(harness.tabURL(world.foldered), Self.url("g0"))
    harness.controller.close()
  }

  /// Today tabs track the live URL (unchanged).
  func testATodayTabsNodeTracksTheLiveURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.today[0], to: "t0/other", title: "Other")
    XCTAssertEqual(harness.tabURL(world.today[0]), Self.url("t0/other"))
    harness.controller.close()
  }

  // MARK: Reset (BH-057, KB-041)

  func testResetTabReturnsTheCurrentPinnedTabToItsPinnedURL() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])

    harness.controller.resetTab(nil)

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"))
    XCTAssertEqual(harness.controller.currentNode, world.p0)
    harness.controller.close()
  }

  func testResetTabIsEnabledOnlyForANavigatedPinnedTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let item = harness.menuItem(#selector(ShellWindowController.resetTab(_:)))
    harness.controller.activate(node: world.today[0])
    XCTAssertFalse(harness.controller.validateMenuItem(item), "a Today tab has no pinned URL")
    harness.controller.activate(node: world.p0)
    XCTAssertFalse(harness.controller.validateMenuItem(item), "still at the pinned URL")
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    XCTAssertTrue(harness.controller.validateMenuItem(item))
    harness.controller.resetTab(nil)
    XCTAssertFalse(harness.controller.validateMenuItem(item), "reset again: back at the pinned URL")
    harness.controller.close()
  }

  /// GS-005: a favicon click on a navigated pinned tab resets it; on an untouched one it activates it.
  /// A click's recorded point lasts for that click only: a later activation with no mouse-down (an AX press) is
  /// never hit-tested against an old favicon point, so it activates the navigated pin instead of resetting it.
  func testAClickWithoutAMouseDownIgnoresTheLastClickPoint() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])
    harness.controller.activate(node: world.today[0])
    try harness.click(world.p0, at: harness.faviconPoint(world.p0))
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"), "the favicon click resets")
    try harness.navigate(world.p0, to: "p0/again", title: "Again")
    harness.controller.activate(node: world.today[0])

    try harness.outline().handleClick(row: try harness.row(world.p0), modifiers: [])

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0/again"))
    XCTAssertEqual(harness.controller.currentNode, world.p0)
    harness.controller.close()
  }

  func testAFaviconClickResetsANavigatedPinnedTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])
    harness.controller.activate(node: world.today[0])   // the reset must not come from activating the row

    try harness.click(world.p0, at: harness.faviconPoint(world.p0))

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"))

    // An untouched pinned tab's favicon click activates it like any other click.
    try harness.click(world.p0, at: harness.faviconPoint(world.p0))
    XCTAssertEqual(harness.controller.currentNode, world.p0)
    harness.controller.close()
  }

  /// A click on the row's title still activates, even on a navigated pinned tab.
  func testATitleClickOnANavigatedPinnedTabActivatesWithoutResetting() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])
    harness.controller.activate(node: world.today[0])

    try harness.click(world.p0, at: harness.titlePoint(world.p0))

    XCTAssertEqual(harness.controller.currentNode, world.p0)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0/other"), "no reset from the title")
    harness.controller.close()
  }

  /// BH-058: Cmd-click resets the pin and opens the page it was on in a new (background [I]) Today tab.
  func testCmdClickOnTheFaviconResetsAndOpensThePageInANewTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])

    try harness.click(world.p0, at: harness.faviconPoint(world.p0), modifiers: .command)

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"), "the pin reset")
    let today = harness.children(.today(world.space))
    XCTAssertEqual(today.count, 4, "the page's tab plus the two Today tabs and the split")
    XCTAssertEqual(harness.tabURL(try XCTUnwrap(today.first)), Self.url("p0/other"))
    XCTAssertEqual(harness.controller.currentNode, world.p0, "the new tab stays in the background [I]")
    harness.controller.close()
  }

  // MARK: Reset Space (BH-059)

  func testResetSpaceResetsEveryNavigatedPinnedTabOfTheCurrentSpace() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    try harness.navigate(world.foldered, to: "g0/other", title: "Guide")
    let item = harness.menuItem(#selector(ShellWindowController.resetSpace(_:)))
    XCTAssertTrue(harness.controller.validateMenuItem(item))

    harness.controller.resetSpace(nil)

    XCTAssertEqual(harness.engine.snapshot(of: try XCTUnwrap(harness.controller.tabsByNode[world.p0]))?.url,
                   Self.url("p0"))
    XCTAssertEqual(harness.engine.snapshot(of: try XCTUnwrap(harness.controller.tabsByNode[world.foldered]))?.url,
                   Self.url("g0"))
    XCTAssertFalse(harness.controller.validateMenuItem(item), "nothing left to reset")
    harness.controller.close()
  }

  func testResetSpaceIsDisabledWithNothingNavigated() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let item = harness.menuItem(#selector(ShellWindowController.resetSpace(_:)))
    harness.controller.activate(node: world.p0)          // loaded, but at the pinned URL
    XCTAssertFalse(harness.controller.validateMenuItem(item))
    harness.controller.close()
  }

  // MARK: Replace Pin (BH-060)

  func testReplacePinWritesTheCurrentPageIntoThePin() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")

    XCTAssertTrue(try harness.choose("Replace Pin with Current Page", on: world.p0))

    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0/other"))
    XCTAssertEqual(harness.tabTitle(world.p0), "Other")
    if case .atPinnedURL = harness.controller.pinnedState(of: world.p0) {} else {
      XCTFail("the tab shows its new pinned URL")
    }
    harness.controller.close()
  }

  // MARK: Separate From Pinned Tab (BH-061)

  func testSeparateFromPinnedTabMovesThePageOutAndResetsThePin() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.navigate(world.p0, to: "p0/other", title: "Other")
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])

    XCTAssertTrue(try harness.choose("Separate From Pinned Tab", on: world.p0))

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"), "the pin reset")
    let today = harness.children(.today(world.space))
    let detached = try XCTUnwrap(today.first)
    XCTAssertEqual(harness.tabURL(detached), Self.url("p0/other"))
    XCTAssertEqual(harness.tabTitle(detached), "Other")
    XCTAssertEqual(harness.controller.currentNode, detached, "the page keeps the focus [I]")
    XCTAssertEqual(harness.children(.pinned(world.space)), [world.p0, world.p1, world.folder])
    harness.controller.close()
  }

  // MARK: Collapse Pinned (BH-065)

  private func rowCount(_ harness: Harness) throws -> Int { try harness.outline().outlineView.numberOfRows }

  func testCollapsePinnedHidesThePinnedRowsAndExpandBringsThemBack() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    let expanded = try rowCount(harness)
    // p0, p1, the folder and its tab: 4 rows hidden; the divider and Today stay.
    let hidden = 4

    page.setPinnedCollapsed(true)
    XCTAssertEqual(try rowCount(harness), expanded - hidden)
    XCTAssertGreaterThanOrEqual(try harness.row(world.today[0]), 0, "Today rows stay")

    page.setPinnedCollapsed(false)
    XCTAssertEqual(try rowCount(harness), expanded)
    XCTAssertGreaterThanOrEqual(try harness.row(world.p0), 0)
    harness.controller.close()
  }

  /// DM 3.1: the collapsed state is per window; a second window on the same source keeps its own.
  func testTheCollapsedStateIsPerWindow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    // A second window on the same source (two windows showing the same Space, BH-066's premise).
    let other = ShellWindowController(engine: InMemoryEngine(), sidebar: harness.source, opensFirstTab: false)
    other.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    other.window?.contentView?.layoutSubtreeIfNeeded()
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    let otherPage = try XCTUnwrap(other.sidebarController.currentPage)

    page.setPinnedCollapsed(true)

    XCTAssertTrue(page.isPinnedCollapsed)
    XCTAssertFalse(otherPage.isPinnedCollapsed)
    XCTAssertEqual(otherPage.outlineController.outlineView.numberOfRows,
                   page.outlineController.outlineView.numberOfRows + 4)

    otherPage.setPinnedCollapsed(true)
    otherPage.setPinnedCollapsed(false)
    XCTAssertTrue(page.isPinnedCollapsed, "the other window's toggle does not touch this one")
    harness.controller.close()
    other.close()
  }

  /// While collapsed the Space title draws bold when the window shows one of its pinned tabs [I]
  /// (PARITY: "the last pinned tab is in view", BH-065).
  func testTheCollapsedSpaceTitleBoldsAroundAPinnedTab() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    func isBold() -> Bool { page.titleLabel.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false }

    page.setPinnedCollapsed(true)
    harness.controller.activate(node: world.p0)
    XCTAssertTrue(isBold())
    harness.controller.activate(node: world.today[0])
    XCTAssertFalse(isBold())
    page.setPinnedCollapsed(false)
    harness.controller.activate(node: world.p0)
    XCTAssertFalse(isBold(), "expanded: the regular weight")
    harness.controller.close()
  }

  /// The caret appears with the first pinned tab and goes with the last (the header of an unpinned Space has none).
  func testTheCollapseCaretFollowsThePinnedSection() throws {
    var sidebar = SidebarModel.Sidebar()
    sidebar.addSpace(title: "Bare")
    let harness = Harness(sidebar)
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    XCTAssertTrue(page.collapsePinnedButton.isHidden, "no pinned tabs, no caret")

    let pinned = try harness.source.addTab(url: Self.url("p"), title: "P", in: .pinned(harness.source.spaceOrder[0]))
    XCTAssertFalse(page.collapsePinnedButton.isHidden)
    harness.source.mutate { $0.remove(pinned) }
    XCTAssertTrue(page.collapsePinnedButton.isHidden)
    harness.controller.close()
  }

  /// The collapse ends with the last pin: the next pin lands in a visible section, with its caret.
  func testLosingTheLastPinExpandsTheSection() throws {
    var sidebar = SidebarModel.Sidebar()
    sidebar.addSpace(title: "Bare")
    let harness = Harness(sidebar)
    let space = harness.source.spaceOrder[0]
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    let pinned = try harness.source.addTab(url: Self.url("p"), title: "P", in: .pinned(space))
    page.setPinnedCollapsed(true)

    harness.source.mutate { $0.remove(pinned) }

    XCTAssertFalse(page.isPinnedCollapsed)
    let next = try harness.source.addTab(url: Self.url("q"), title: "Q", in: .pinned(space))
    XCTAssertFalse(page.collapsePinnedButton.isHidden)
    XCTAssertGreaterThanOrEqual(try harness.row(next), 0, "the new pin shows")
    harness.controller.close()
  }

  /// The caret and the Space options menu toggle the collapse; the chevron and the item's title follow.
  func testTheCaretAndTheOptionsMenuToggleTheCollapse() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let page = try XCTUnwrap(harness.sidebarController.currentPage)
    let expanded = try rowCount(harness)

    page.collapsePinnedButton.performClick(nil)
    XCTAssertTrue(page.isPinnedCollapsed)
    XCTAssertEqual(try rowCount(harness), expanded - 4)

    let menu = page.makeOptionsMenu()
    let expand = try XCTUnwrap(menu.items.first { $0.title == "Expand Pinned" })
    _ = expand.target?.perform(expand.action, with: expand)
    XCTAssertFalse(page.isPinnedCollapsed)
    XCTAssertEqual(try rowCount(harness), expanded)
    XCTAssertNotNil(page.makeOptionsMenu().items.first { $0.title == "Collapse Pinned" })
    harness.controller.close()
  }
}
