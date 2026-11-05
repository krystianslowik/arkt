import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Little Arkt's ways in and out besides Open in (#356, docs/design/little-arkt.md): the Dock menu's rows, the Window
/// menu's own heading, Opt-Cmd-click on a link or a sidebar tab, and the chooser's Open in New Window.
@MainActor
final class LittleArktMenusTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let pageURL = URL(string: "https://example.com/start")!
  private let linkURL = URL(string: "https://example.org/linked")!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
  }

  private func makeSet() throws -> (set: ShellWindowSet, engine: InMemoryEngine, source: ModelSidebarSource) {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { true }
    set.configure = { controller in
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: EngineWorld.now) }
    }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine, source)
  }

  /// A main window showing a new Today tab on `pageURL`.
  private func mainWindowWithPage(_ set: ShellWindowSet) throws -> (ShellWindowController, NodeID, TabID) {
    let main = set.openWindow()
    main.open(pageURL, inNewTab: true)
    let node = try XCTUnwrap(main.currentNode)
    let tab = try XCTUnwrap(main.currentTab)
    return (main, node, tab)
  }

  private func openLittle(_ set: ShellWindowSet, _ engine: InMemoryEngine, title: String) throws
    -> LittleArktWindowController {
    let little = set.openLittleArkt(url: URL(string: "https://example.net/\(title)")!)
    let tab = try XCTUnwrap(little.shownTab)
    engine.setDocumentTitle(tab, title)
    little.finishMotion()
    return little
  }

  // MARK: Opt-Cmd-click a link (BH-132, GS-028)

  func testOptionCommandClickOpensTheLinkInALittleArktWindow() throws {
    let (set, engine, _) = try makeSet()
    let (main, _, tab) = try mainWindowWithPage(set)

    let decision = engine.simulateLinkActivation(in: tab, url: linkURL, modifiers: [.command, .option],
                                                 disposition: .newBackgroundTab)

    XCTAssertEqual(decision, .cancel, "the engine does not open the link itself")
    waitUntil("a Little Arkt window opened") { set.littleArkts.count == 1 }
    let little = try XCTUnwrap(set.littleArkts.first)
    let shown = try XCTUnwrap(little.shownTab)
    XCTAssertEqual(engine.snapshot(of: shown)?.url, linkURL)
    XCTAssertEqual(main.currentTab, tab, "the source tab stays where it was")
    XCTAssertEqual(engine.snapshot(of: tab)?.url, pageURL, "the source page did not navigate")
    XCTAssertEqual(set.controllers.count, 1, "no new browser window")
  }

  func testOptionCommandClickFollowsTheSetting() throws {
    let (set, engine, _) = try makeSet()
    let (main, _, tab) = try mainWindowWithPage(set)
    main.opensLittleArktOnOptionCommandClick = { false }

    let decision = engine.simulateLinkActivation(in: tab, url: linkURL, modifiers: [.command, .option],
                                                 disposition: .newBackgroundTab)

    XCTAssertEqual(decision, .navigate, "off: the engine's own Opt-Cmd-click")
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertTrue(set.littleArkts.isEmpty)
  }

  func testOtherModifiedClicksDoNotOpenLittleArkt() throws {
    let (set, engine, _) = try makeSet()
    let (_, _, tab) = try mainWindowWithPage(set)

    _ = engine.simulateLinkActivation(in: tab, url: linkURL, modifiers: [.command], disposition: .newBackgroundTab)
    _ = engine.simulateLinkActivation(in: tab, url: linkURL, modifiers: [.command, .option, .shift],
                                      disposition: .newForegroundTab)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertTrue(set.littleArkts.isEmpty)
  }

  // MARK: Opt-Cmd-click a sidebar tab (BH-132)

  func testOptionCommandClickOnATodayTabMovesItsPageIntoALittleArktWindow() throws {
    let (set, engine, source) = try makeSet()
    let (main, node, tab) = try mainWindowWithPage(set)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let outline = try XCTUnwrap(main.sidebarController.outline(containing: node))

    outline.handleClick(row: outline.row(for: node), modifiers: [.command, .option])

    let little = try XCTUnwrap(set.littleArkts.first)
    waitUntil("the page is in the Little Arkt window") { little.shownTab == tab }
    XCTAssertEqual(engine.snapshot(of: tab)?.window, little.engineWindow, "the same tab moved, nothing reloaded")
    XCTAssertTrue(engine.contentView(for: tab) === page)
    XCTAssertTrue(page.isDescendant(of: little.card))
    XCTAssertNil(source.node(node), "the row left the sidebar")
    XCTAssertNil(main.tabsByNode[node])
  }

  func testOptionCommandClickOnAnUnloadedTodayTabOpensItsURL() throws {
    let (set, engine, source) = try makeSet()
    let main = set.openWindow()
    let space = try XCTUnwrap(main.currentSpace)
    let node = try source.addTab(url: linkURL, title: "Linked", in: .today(space), at: nil)
    let outline = try XCTUnwrap(main.sidebarController.outline(containing: node))
    XCTAssertNil(main.tabsByNode[node], "never loaded")

    outline.handleClick(row: outline.row(for: node), modifiers: [.command, .option])

    let little = try XCTUnwrap(set.littleArkts.first)
    let shown = try XCTUnwrap(little.shownTab)
    XCTAssertEqual(engine.snapshot(of: shown)?.url, linkURL)
    XCTAssertNil(source.node(node), "the row left the sidebar")
  }

  func testOptionCommandClickOnATabFollowsTheSetting() throws {
    let (set, _, source) = try makeSet()
    let (main, node, _) = try mainWindowWithPage(set)
    main.opensLittleArktOnOptionCommandClick = { false }
    let outline = try XCTUnwrap(main.sidebarController.outline(containing: node))

    outline.handleClick(row: outline.row(for: node), modifiers: [.command, .option])

    XCTAssertTrue(set.littleArkts.isEmpty)
    XCTAssertNotNil(source.node(node))
  }

  // MARK: Open in New Window (chooser)

  func testOpenInNewWindowMovesThePageToANewMainWindow() throws {
    let (set, engine, _) = try makeSet()
    let (main, _, _) = try mainWindowWithPage(set)
    let little = try openLittle(set, engine, title: "Atlas")
    let tab = try XCTUnwrap(little.shownTab)
    let page = try XCTUnwrap(engine.contentView(for: tab))

    little.openInNewWindow()

    waitUntil("a second main window opened") { set.controllers.count == 2 }
    let opened = try XCTUnwrap(set.controllers.last)
    XCTAssertFalse(opened === main)
    waitUntil("the page is in the new window") { opened.currentTab == tab }
    XCTAssertEqual(engine.snapshot(of: tab)?.window, opened.engineWindow)
    XCTAssertTrue(engine.contentView(for: tab) === page, "the same page, not a reload")
    XCTAssertEqual(opened.currentSpace, main.currentSpace, "on the Space Open in names")
    waitUntil("the Little Arkt window closed") { set.littleArkts.isEmpty }
  }

  func testTheChooserListsOpenInNewWindow() throws {
    let (set, engine, _) = try makeSet()
    _ = try mainWindowWithPage(set)
    let little = try openLittle(set, engine, title: "Atlas")

    let titles = little.chooserMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }

    XCTAssertEqual(titles.first, LittleArktCopy.chooserHeading)
    XCTAssertEqual(Array(titles.suffix(4)), ["-", LittleArktCopy.openInNewWindow, "-", LittleArktCopy.copyLink])
  }

  // MARK: Dock menu (BH-139, GS-041)

  func testTheDockMenuListsTheWindowsByPageTitleThenHideAndClose() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    _ = try openLittle(set, engine, title: "Three days in Lisbon")
    _ = try openLittle(set, engine, title: "Custard tarts")

    let titles = set.littleArktMenus.dockItems().map { $0.isSeparatorItem ? "-" : $0.title }

    XCTAssertEqual(titles, ["Three days in Lisbon", "Custard tarts", "-", LittleArktCopy.hideAll,
                            LittleArktCopy.closeAll])
  }

  func testTheDockMenuHasNoLittleArktRowsWithoutWindows() throws {
    let (set, _, _) = try makeSet()
    _ = set.openWindow()
    XCTAssertTrue(set.littleArktMenus.dockItems().isEmpty)
  }

  func testHideAllThenShowAll() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let first = try openLittle(set, engine, title: "One")
    let second = try openLittle(set, engine, title: "Two")
    let menus = set.littleArktMenus

    try perform(menus, LittleArktCopy.hideAll)

    XCTAssertFalse(first.window.isVisible)
    XCTAssertFalse(second.window.isVisible)
    XCTAssertEqual(set.littleArkts.count, 2, "hidden, not closed")
    XCTAssertTrue(menus.dockItems().contains { $0.title == LittleArktCopy.showAll })
    XCTAssertFalse(menus.dockItems().contains { $0.title == LittleArktCopy.hideAll })

    try perform(menus, LittleArktCopy.showAll)

    XCTAssertTrue(first.window.isVisible)
    XCTAssertTrue(second.window.isVisible)
    XCTAssertTrue(menus.dockItems().contains { $0.title == LittleArktCopy.hideAll })
  }

  func testAPageTitleRowBringsThatWindowBackFromHidden() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let first = try openLittle(set, engine, title: "One")
    let second = try openLittle(set, engine, title: "Two")
    try perform(set.littleArktMenus, LittleArktCopy.hideAll)

    try perform(set.littleArktMenus, "One")

    XCTAssertTrue(first.window.isVisible)
    XCTAssertFalse(second.window.isVisible)
  }

  func testCloseAllClosesEveryWindowHiddenOrNot() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let hidden = try openLittle(set, engine, title: "One")
    _ = try openLittle(set, engine, title: "Two")
    hidden.window.orderOut(nil)
    let ids = set.littleArkts.compactMap(\.engineWindow)

    try perform(set.littleArktMenus, LittleArktCopy.closeAll)

    waitUntil("every Little Arkt window closed") { set.littleArkts.isEmpty }
    for id in ids { XCTAssertFalse(engine.windowIDs.contains(id)) }
    XCTAssertEqual(set.controllers.count, 1, "the main window stays")
  }

  private func perform(_ menus: LittleArktMenus, _ title: String) throws {
    let item = try XCTUnwrap(menus.dockItems().first { $0.title == title }, "no \(title) row")
    let action = try XCTUnwrap(item.action)
    XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
  }

  // MARK: Window menu

  func testTheWindowMenuListsThemUnderTheirOwnHeading() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let first = try openLittle(set, engine, title: "One")
    _ = try openLittle(set, engine, title: "Two")
    let menu = windowMenu()

    set.littleArktMenus.updateWindowMenu(menu)
    set.littleArktMenus.updateWindowMenu(menu)                // twice: the section is replaced, never doubled

    let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    XCTAssertEqual(titles, ["Minimize", "Zoom", "-", LittleArktCopy.windowMenuHeading, "One", "Two", "-",
                            "Bring All to Front"])
    let heading = try XCTUnwrap(menu.items.first { $0.title == LittleArktCopy.windowMenuHeading })
    XCTAssertFalse(heading.isEnabled, "a heading, not an action")
    XCTAssertTrue(first.window.isExcludedFromWindowsMenu, "AppKit's own list does not show them a second time")

    let row = try XCTUnwrap(menu.items.first { $0.title == "One" })
    first.window.orderOut(nil)
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(row.action), to: row.target, from: row))
    XCTAssertTrue(first.window.isVisible, "the row brings its window forward")
  }

  func testTheWindowMenuSectionGoesWithTheLastWindow() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    _ = try openLittle(set, engine, title: "One")
    let menu = windowMenu()
    set.littleArktMenus.updateWindowMenu(menu)

    try perform(set.littleArktMenus, LittleArktCopy.closeAll)
    waitUntil("closed") { set.littleArkts.isEmpty }
    set.littleArktMenus.updateWindowMenu(menu)

    XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title },
                   ["Minimize", "Zoom", "-", "Bring All to Front"])
  }

  private func windowMenu() -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
                 keyEquivalent: "")
    return menu
  }
}
