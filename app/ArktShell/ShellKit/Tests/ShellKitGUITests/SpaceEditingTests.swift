import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// New Space, rename and reorder (#106): New Space is named "Space N" (decision on #106), lands right after the
/// current Space (BH-037), becomes current with its title open for editing; the title renames in place (BH-038) and
/// the Spaces menu reorders (BH-039, the header drag is deferred). Every write goes through the source, so the app's
/// autosave (`onDidChange`) persists it.
@MainActor
final class SpaceEditingTests: XCTestCase {
  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let controller: ShellWindowController
    let ids: [SpaceID]
    var saves = 0

    init(_ titles: [String]) {
      var sidebar = SidebarModel.Sidebar()
      ids = titles.map { sidebar.addSpace(title: $0) }
      source = ModelSidebarSource(sidebar: sidebar)
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.orderFront(nil)
      source.onDidChange = { [unowned self] _ in self.saves += 1 }
    }

    var titles: [String] { source.spaceOrder.map { source.space($0)?.title ?? "" } }
    func page(_ id: SpaceID) -> SpacePageView? {
      controller.pager.pages.lazy.compactMap { $0 as? SpacePageView }.first { $0.spaceID == id }
    }
    var currentPage: SpacePageView? { controller.currentSpace.flatMap(page) }
    /// The field editor of the title being renamed.
    func editor(_ page: SpacePageView?) throws -> NSTextView {
      try XCTUnwrap(page?.titleLabel.currentEditor() as? NSTextView, "the title is being edited")
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func item(_ action: Selector) -> NSMenuItem {
    NSMenuItem(title: "", action: action, keyEquivalent: "")
  }

  // MARK: - New Space

  func testNewSpaceLandsAfterTheCurrentSpaceAsSpaceNAndBecomesCurrentWithItsTitleOpen() throws {
    let harness = Harness(["A", "B", "C"])
    harness.controller.sidebarController.showSpace(harness.ids[1])

    harness.controller.newSpace(nil)

    let new = try XCTUnwrap(harness.controller.currentSpace)
    XCTAssertEqual(harness.source.spaceOrder, [harness.ids[0], harness.ids[1], new, harness.ids[2]])
    XCTAssertEqual(harness.source.space(new)?.title, "Space 1")
    XCTAssertEqual(harness.controller.sidebarController.view.spaceDots.selectedIndex, 2)
    let page = try XCTUnwrap(harness.page(new))
    XCTAssertTrue(page.isRenaming, "the decision on #106: editable right after creation")
    let editor = try harness.editor(page)
    XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 7), "typing replaces the whole name")
    XCTAssertEqual(harness.saves, 1, "persisted through the autosave hook")
    harness.controller.close()
  }

  func testNewSpaceTakesTheSmallestFreeNumber() throws {
    let harness = Harness(["Space 1", "Space 3"])
    harness.controller.newSpace(nil)
    XCTAssertEqual(harness.titles, ["Space 1", "Space 2", "Space 3"])
    harness.controller.close()
  }

  func testEmptyStateNewSpaceCreatesSpace1WithItsTitleOpen() throws {
    let harness = Harness([])
    XCTAssertTrue(harness.controller.isShowingEmptyState)
    harness.controller.emptyState.newSpaceButton.performClick(nil)
    XCTAssertEqual(harness.titles, ["Space 1"])
    XCTAssertFalse(harness.controller.isShowingEmptyState)
    XCTAssertEqual(harness.currentPage?.isRenaming, true)
    harness.controller.close()
  }

  /// Cmd-T with no Space creates the Space silently: the new tab, not a rename field, gets the focus.
  func testCmdTWithNoSpaceCreatesSpace1WithoutOpeningItsTitle() throws {
    let harness = Harness([])
    harness.controller.open(URL(string: "https://example.com")!, inNewTab: true)
    XCTAssertEqual(harness.titles, ["Space 1"])
    XCTAssertEqual(harness.currentPage?.isRenaming, false)
    harness.controller.close()
  }

  /// The bottom bar's "+" keeps Cmd-T on a click and offers New Space in its context menu [I].
  func testNewTabButtonMenuOffersNewSpace() throws {
    let harness = Harness(["A"])
    let menu = try XCTUnwrap(harness.controller.sidebarController.view.newTabButton.menu)
    let item = try XCTUnwrap(menu.items.first { $0.action == #selector(ShellWindowController.newSpace(_:)) })
    XCTAssertEqual(item.title, "New Space")
    XCTAssertTrue(item.target === harness.controller)
    menu.performActionForItem(at: menu.index(of: item))
    XCTAssertEqual(harness.titles, ["A", "Space 1"])
    harness.controller.close()
  }

  // MARK: - Rename

  func testTypingAndReturnRenamesTheSpace() throws {
    let harness = Harness(["A"])
    harness.controller.renameSpace(nil)
    let page = harness.currentPage
    let editor = try harness.editor(page)
    editor.insertText("  Research ", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    editor.insertNewline(nil)

    XCTAssertEqual(harness.titles, ["Research"], "trimmed")
    XCTAssertEqual(page?.isRenaming, false)
    XCTAssertEqual(page?.titleLabel.stringValue, "Research")
    XCTAssertEqual(harness.controller.sidebarController.view.spaceDots.titles, ["Research"])
    XCTAssertEqual(harness.saves, 1)
    harness.controller.close()
  }

  func testEscapeKeepsTheOldTitle() throws {
    let harness = Harness(["A"])
    harness.controller.renameSpace(nil)
    let page = harness.currentPage
    let editor = try harness.editor(page)
    editor.insertText("Typo", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

    XCTAssertEqual(page?.isRenaming, false)
    XCTAssertEqual(page?.titleLabel.stringValue, "A")
    XCTAssertEqual(harness.titles, ["A"])
    XCTAssertEqual(harness.saves, 0)
    harness.controller.close()
  }

  /// An empty name is not taken [I]: the Space keeps its title (BH-043, an unnamed Space, is NEEDS-RUNTIME-CHECK).
  func testAnEmptyNameKeepsTheOldTitle() throws {
    let harness = Harness(["A"])
    harness.controller.renameSpace(nil)
    let page = harness.currentPage
    let editor = try harness.editor(page)
    editor.insertText("   ", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    editor.insertNewline(nil)

    XCTAssertEqual(harness.titles, ["A"])
    XCTAssertEqual(page?.titleLabel.stringValue, "A")
    XCTAssertEqual(harness.saves, 0)
    harness.controller.close()
  }

  func testLeavingTheFieldCommits() throws {
    let harness = Harness(["A"])
    harness.controller.renameSpace(nil)
    let editor = try harness.editor(harness.currentPage)
    editor.insertText("Moved on", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    harness.controller.window?.makeFirstResponder(nil)

    XCTAssertEqual(harness.titles, ["Moved on"])
    XCTAssertEqual(harness.currentPage?.isRenaming, false)
    harness.controller.close()
  }

  /// A Space change delivered while the field is open (another window, an import) does not replace what is typed.
  func testASpaceChangeWhileEditingKeepsTheTypedText() throws {
    let harness = Harness(["A", "B"])
    harness.controller.renameSpace(nil)
    let editor = try harness.editor(harness.currentPage)
    editor.insertText("Draft", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    harness.source.renameSpace(harness.ids[1], to: "B2")
    harness.source.renameSpace(harness.ids[0], to: "Elsewhere")

    XCTAssertEqual(editor.string, "Draft")
    editor.insertNewline(nil)
    XCTAssertEqual(harness.titles, ["Draft", "B2"])
    harness.controller.close()
  }

  func testAClickOnTheTitleOpensIt() throws {
    let harness = Harness(["A"])
    let page = try XCTUnwrap(harness.currentPage)
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let title = page.titleLabel.frame
    let point = NSPoint(x: title.midX, y: title.midY)
    XCTAssertTrue(page.hitTest(page.convert(point, to: page.superview)) === page, "the page takes the click")
    let event = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: page.convert(point, to: nil), modifierFlags: [], timestamp: 0,
      windowNumber: harness.controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1,
      pressure: 1))
    page.mouseDown(with: event)
    XCTAssertTrue(page.isRenaming)
    harness.controller.close()
  }

  /// BH-038: hovering the header shows an edit button, which opens the title too.
  func testHoverShowsTheEditButton() throws {
    let harness = Harness(["A"])
    let page = try XCTUnwrap(harness.currentPage)
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    XCTAssertTrue(page.editButton.isHidden)
    XCTAssertEqual(page.editButton.accessibilityLabel(), "Rename Space")

    page.setHeaderHovered(true)
    XCTAssertFalse(page.editButton.isHidden)
    XCTAssertGreaterThanOrEqual(page.editButton.frame.minX, page.titleLabel.frame.maxX, "after the title")
    page.editButton.performClick(nil)
    XCTAssertTrue(page.isRenaming)
    XCTAssertTrue(page.editButton.isHidden, "the open field needs no edit button")
    harness.controller.close()
  }

  // MARK: - Reorder

  func testMoveSpaceRightAndLeftReorderAndKeepTheSpaceCurrent() throws {
    let harness = Harness(["A", "B", "C"])
    let b = harness.ids[1]
    harness.controller.sidebarController.showSpace(b)

    harness.controller.moveSpaceRight(nil)
    XCTAssertEqual(harness.titles, ["A", "C", "B"])
    XCTAssertEqual(harness.controller.currentSpace, b)
    XCTAssertEqual(harness.controller.sidebarController.view.spaceDots.selectedIndex, 2)
    XCTAssertEqual(harness.controller.sidebarController.view.spaceDots.titles, ["A", "C", "B"])

    harness.controller.moveSpaceLeft(nil)
    harness.controller.moveSpaceLeft(nil)
    XCTAssertEqual(harness.titles, ["B", "A", "C"])
    XCTAssertEqual(harness.controller.currentSpace, b)
    XCTAssertEqual(harness.saves, 3)

    // Ctrl-N follows the new order (BH-039, BH-041).
    harness.controller.sidebarController.goToSpace(at: 1)
    waitUntil("the second Space current") { harness.controller.currentSpace == harness.ids[0] }
    harness.controller.close()
  }

  // MARK: - Menu

  func testSpaceMenuValidation() throws {
    let empty = Harness([])
    XCTAssertTrue(empty.controller.validateMenuItem(Self.item(#selector(ShellWindowController.newSpace(_:)))))
    for action in [#selector(ShellWindowController.renameSpace(_:)), #selector(ShellWindowController.moveSpaceLeft(_:)),
                   #selector(ShellWindowController.moveSpaceRight(_:))] {
      XCTAssertFalse(empty.controller.validateMenuItem(Self.item(action)), "\(action) without a Space")
    }
    empty.controller.close()

    let harness = Harness(["A", "B"])
    let left = Self.item(#selector(ShellWindowController.moveSpaceLeft(_:)))
    let right = Self.item(#selector(ShellWindowController.moveSpaceRight(_:)))
    XCTAssertTrue(harness.controller.validateMenuItem(Self.item(#selector(ShellWindowController.renameSpace(_:)))))
    XCTAssertFalse(harness.controller.validateMenuItem(left), "the first Space")
    XCTAssertTrue(harness.controller.validateMenuItem(right))
    harness.controller.sidebarController.showSpace(harness.ids[1])
    XCTAssertTrue(harness.controller.validateMenuItem(left))
    XCTAssertFalse(harness.controller.validateMenuItem(right), "the last Space")
    harness.controller.close()
  }

  /// The real Spaces menu: New Space is unbound (KB-043), the others too [I].
  func testTheSpacesMenuHasTheNewItems() throws {
    let windowsMenu = NSApp.windowsMenu
    defer { NSApp.windowsMenu = windowsMenu }
    let spaces = try XCTUnwrap(MainMenu.make().items.first { $0.title == "Spaces" }?.submenu)
    let expected: [(String, Selector)] = [
      ("New Space", #selector(ShellWindowController.newSpace(_:))),
      ("Rename Space", #selector(ShellWindowController.renameSpace(_:))),
      ("Move Space Left", #selector(ShellWindowController.moveSpaceLeft(_:))),
      ("Move Space Right", #selector(ShellWindowController.moveSpaceRight(_:))),
    ]
    for (title, action) in expected {
      let item = try XCTUnwrap(spaces.items.first { $0.action == action }, title)
      XCTAssertEqual(item.title, title)
      XCTAssertEqual(item.keyEquivalent, "", "\(title) is unbound")
    }
  }
}
