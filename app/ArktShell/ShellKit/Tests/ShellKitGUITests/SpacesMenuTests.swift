import AppKit
import Carbon.HIToolbox
@testable import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The Spaces menu (#387) lists the main window's Spaces, in sidebar order, and nothing else: Ctrl-1 ... Ctrl-9
/// (KB-035, BH-041) on the first nine, the zero-based index as tag. It follows adds, renames, moves and removals the
/// next time AppKit updates it (opening it, or matching a key equivalent).
@MainActor
final class SpacesMenuTests: XCTestCase {
  private var source: ModelSidebarSource!
  private var controller: ShellWindowController!
  private var ids: [SpaceID] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    controller?.window?.orderOut(nil)
    controller = nil
    source = nil
  }

  private func makeWindow(_ titles: [String]) {
    var sidebar = SidebarModel.Sidebar()
    ids = titles.map { sidebar.addSpace(title: $0) }
    source = ModelSidebarSource(sidebar: sidebar)
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
  }

  /// The real main menu's Spaces menu, reading this test's window (the test runner never has a main window).
  private func spacesMenu() throws -> SpacesMenu {
    let main = MainMenu.make(commands: AppCommands()).menu
    let menu = try XCTUnwrap(main.items.first { $0.title == "Spaces" }?.submenu as? SpacesMenu)
    // Optional: a menu still alive after tearDown (a window becoming main) must not read the released controller.
    menu.entries = { [weak self] in self?.controller?.spaceMenuEntries ?? [] }
    return menu
  }

  private func spaceItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.delegate?.menuNeedsUpdate?(menu)
    return menu.items.filter { $0.action == #selector(ShellWindowController.goToSpace(_:)) }
  }

  private func assertItems(_ menu: NSMenu, _ titles: [String], file: StaticString = #filePath, line: UInt = #line) {
    let items = spaceItems(menu)
    XCTAssertEqual(items.map(\.title), titles, file: file, line: line)
    XCTAssertEqual(items.map(\.tag), Array(titles.indices), file: file, line: line)
    XCTAssertEqual(items.map(\.keyEquivalent), titles.indices.map { $0 < 9 ? "\($0 + 1)" : "" }, file: file, line: line)
    for item in items.prefix(9) {
      XCTAssertEqual(item.keyEquivalentModifierMask, [.control], item.title, file: file, line: line)
    }
    XCTAssertTrue(items.allSatisfy { $0.target == nil }, "reaches the main window's controller", file: file, line: line)
  }

  // MARK: - Tests

  func testOneSpaceListsOneItem() throws {
    makeWindow(["Home"])
    assertItems(try spacesMenu(), ["Home"])
  }

  func testNoSpaceListsNoItemAndKeepsTheOtherItems() throws {
    makeWindow([])
    let menu = try spacesMenu()
    assertItems(menu, [])
    let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    XCTAssertEqual(titles, ["New Space", "Rename Space", "Move Space Left", "Move Space Right", "Reset Space",
                            "Next Space", "Previous Space", "Delete Space..."])
    XCTAssertFalse(zip(menu.items, menu.items.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem },
                   "no doubled separator")
  }

  func testOnlyTheFirstNineSpacesHaveKeys() throws {
    let titles = (1...11).map { "S\($0)" }
    makeWindow(titles)
    assertItems(try spacesMenu(), titles)
  }

  func testTheListFollowsAddRenameMoveAndRemove() throws {
    makeWindow(["Home"])
    let menu = try spacesMenu()
    assertItems(menu, ["Home"])

    let work = try source.addSpace(title: "Work")
    assertItems(menu, ["Home", "Work"])

    source.renameSpace(ids[0], to: "Personal")
    assertItems(menu, ["Personal", "Work"])

    source.moveSpace(work, to: 0)
    assertItems(menu, ["Work", "Personal"])

    _ = source.removeSpace(work, at: Date())
    assertItems(menu, ["Personal"])
  }

  /// An empty title still names the item, by its place.
  func testAnUntitledSpaceIsNamedByItsPlace() throws {
    makeWindow(["Home", ""])
    assertItems(try spacesMenu(), ["Home", "Space 2"])
  }

  /// AppKit does not ask the menu's delegate before it matches a key equivalent, so the window's Space changes reach
  /// the menu as they happen: Ctrl-2 finds a Space added while the menu was closed.
  func testASpaceAddedWhileTheMenuIsClosedGetsItsKeyAtOnce() throws {
    makeWindow(["Home"])
    let menu = try spacesMenu()
    menu.refreshList()

    _ = try source.addSpace(title: "Work")

    let items = menu.items.filter { $0.action == #selector(ShellWindowController.goToSpace(_:)) }
    XCTAssertEqual(items.map(\.title), ["Home", "Work"])
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.control], timestamp: 0, windowNumber: 0, context: nil,
      characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: UInt16(kVK_ANSI_2)))
    XCTAssertEqual(items.filter { MainMenuKeyEquivalentTests.matches($0, event) }.map(\.title), ["Work"])
  }

  /// A rename reaches the closed menu too.
  func testARenameReachesTheClosedMenu() throws {
    makeWindow(["Home"])
    let menu = try spacesMenu()
    menu.refreshList()

    source.renameSpace(ids[0], to: "Personal")

    XCTAssertEqual(menu.items.filter { $0.action == #selector(ShellWindowController.goToSpace(_:)) }.map(\.title),
                   ["Personal"])
  }

  /// The window's own list, which the menu reads from the main window: its profile's Spaces in sidebar order.
  func testTheWindowListsItsSpacesInSidebarOrder() throws {
    makeWindow(["A", "B", "C"])
    source.moveSpace(ids[2], to: 0)
    XCTAssertEqual(controller.spaceMenuEntries, [
      SpacesMenu.Entry(id: ids[2], title: "C"), SpacesMenu.Entry(id: ids[0], title: "A"),
      SpacesMenu.Entry(id: ids[1], title: "B"),
    ])
  }

  /// The tag picks the Space, as before (KB-035).
  func testAnItemGoesToItsSpace() throws {
    makeWindow(["A", "B", "C"])
    let items = spaceItems(try spacesMenu())
    controller.goToSpace(items[2])
    XCTAssertEqual(controller.pager.targetIndex, 2)
  }
}
