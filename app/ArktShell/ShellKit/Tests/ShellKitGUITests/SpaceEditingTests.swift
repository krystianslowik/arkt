import AppKit
import CoreBridge
import EngineAPITestSupport
import Motion
import SidebarModel
import XCTest
@testable import ShellUI

/// New Space, rename and reorder (#106, #279): New Space is named "Space N" (decision on #106), lands right after the
/// current Space (BH-037), becomes current with its title open for editing; the title renames in place (BH-038), the
/// header "..." menu sets the icon and the theme, and dragging the header reorders (BH-039). Every write goes through
/// the source, so the app's autosave (`onDidChange`) persists it.
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

  private static func mouse(_ type: NSEvent.EventType, at point: NSPoint, window: NSWindow?,
                             timestamp: TimeInterval = 0) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [], timestamp: timestamp, windowNumber: window?.windowNumber ?? 0,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  }

  /// Down on the page's title, drags through `steps` (x offsets in points from the press, 1/120 s apart), and returns
  /// the press point in window coordinates. Leaves the button down.
  private static func pressAndDrag(_ page: SpacePageView, window: NSWindow?, through steps: [CGFloat]) throws
    -> NSPoint {
    let start = page.convert(NSPoint(x: page.titleLabel.frame.midX, y: page.titleLabel.frame.midY), to: nil)
    page.mouseDown(with: try mouse(.leftMouseDown, at: start, window: window))
    for (index, dx) in steps.enumerated() {
      let point = NSPoint(x: start.x + dx, y: start.y)
      page.mouseDragged(with: try mouse(.leftMouseDragged, at: point, window: window,
                                        timestamp: Double(index + 1) / 120))
    }
    return start
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
    XCTAssertFalse(page.isRenaming, "the title opens on mouse up, once the press is too short to be a drag")
    let up = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseUp, location: event.locationInWindow, modifierFlags: [], timestamp: 0,
      windowNumber: event.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    page.mouseUp(with: up)
    XCTAssertTrue(page.isRenaming)
    XCTAssertNil(page.titleLabel.toolTip, "no reorder tip while typing")
    XCTAssertFalse(page.showsHeaderToolTipForTesting)
    page.layout()
    XCTAssertFalse(page.showsHeaderToolTipForTesting, "a layout while renaming does not bring it back")

    try harness.editor(page).insertNewline(nil)
    XCTAssertFalse(page.isRenaming)
    page.layout()
    XCTAssertEqual(page.titleLabel.toolTip, SpacePageView.reorderToolTip)
    XCTAssertTrue(page.showsHeaderToolTipForTesting)
    harness.controller.close()
  }

  func testAClickBesideTheTitleDoesNotOpenIt() throws {
    let harness = Harness(["A"])
    let page = try XCTUnwrap(harness.currentPage)
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let point = NSPoint(x: page.bounds.width - 8, y: SidebarMetrics.spaceTitleHeight / 2)
    XCTAssertFalse(page.titleLabel.frame.contains(point))
    XCTAssertFalse(page.editButton.frame.contains(point))
    XCTAssertFalse(page.optionsButton.frame.contains(point))
    let down = try Self.mouse(.leftMouseDown, at: page.convert(point, to: nil), window: harness.controller.window)
    page.mouseDown(with: down)
    let up = try Self.mouse(.leftMouseUp, at: down.locationInWindow, window: harness.controller.window)
    page.mouseUp(with: up)
    XCTAssertFalse(page.isRenaming)
    XCTAssertEqual(harness.saves, 0)
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
    XCTAssertFalse(page.optionsButton.isHidden)
    XCTAssertEqual(page.optionsButton.accessibilityLabel(), "Space Options")
    XCTAssertGreaterThanOrEqual(page.editButton.frame.minX, page.titleLabel.frame.maxX, "after the title")
    XCTAssertGreaterThanOrEqual(page.optionsButton.frame.minX, page.editButton.frame.maxX, "after the edit button")
    page.editButton.performClick(nil)
    XCTAssertTrue(page.isRenaming)
    XCTAssertTrue(page.editButton.isHidden, "the open field needs no edit button")
    harness.controller.close()
  }

  // MARK: - Icon, theme, header drag

  func testHeaderMenuSetsTheIconAndThemeAndLeavesProfileDisabled() throws {
    let harness = Harness(["A"])
    let background = harness.controller.themeBackground
    background.crossfadeDuration = 0
    background.reducesMotion = { false }
    let page = try XCTUnwrap(harness.currentPage)
    let menu = page.makeOptionsMenu()
    let profile = try XCTUnwrap(menu.item(withTitle: "Profile"))
    XCTAssertFalse(profile.isEnabled)
    XCTAssertNil(profile.action)
    XCTAssertEqual(menu.item(withTitle: "Theme")?.submenu?.items.map(\.title), ["Default", "Paper", "Dusk"])

    let dusk = try XCTUnwrap(menu.item(withTitle: "Theme")?.submenu?.item(withTitle: "Dusk"))
    page.pickTheme(dusk)
    XCTAssertEqual(harness.source.space(harness.ids[0])?.theme, SpaceThemeCatalog.dusk)
    XCTAssertEqual(harness.saves, 1)
    XCTAssertNil(background.crossfadeAnimationForTesting)
    let painted = background.baseColorsForTesting.flatMap { $0.components ?? [] }
    let expected = SpaceThemeCatalog.dusk.baseColors.flatMap { $0.cgColor.components ?? [] }
    XCTAssertEqual(painted.count, expected.count)
    for (got, want) in zip(painted, expected) {
      XCTAssertEqual(got, want, accuracy: 0.001)
    }

    let star = try XCTUnwrap(menu.item(withTitle: "Icon")?.submenu?.item(withTitle: "Star"))
    page.pickIcon(star)
    let dots = harness.controller.sidebarController.view.spaceDots
    XCTAssertEqual(dots.icons, [.symbol("star")])
    XCTAssertEqual(harness.source.sidebar.spaces[harness.ids[0]]?.icon, .symbol("star"))
    XCTAssertEqual(harness.saves, 2)
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    dots.updateLayer()
    let mark = try XCTUnwrap(dots.markForTesting(0))
    XCTAssertTrue(mark.showsImage)
    XCTAssertEqual(mark.width, SidebarMetrics.spaceIconSize)

    // D1: an emoji, built from scalars; anything but one emoji writes nothing.
    XCTAssertFalse(page.setEmojiIcon("1"))
    XCTAssertEqual(harness.saves, 2)
    XCTAssertTrue(page.setEmojiIcon("\u{1F680}"))
    XCTAssertEqual(harness.source.sidebar.spaces[harness.ids[0]]?.icon, .emoji("\u{1F680}"))
    XCTAssertEqual(dots.icons, [.emoji("\u{1F680}")])
    XCTAssertEqual(harness.saves, 3)
    XCTAssertEqual(dots.markForTesting(0)?.mark, .emoji("\u{1F680}"))

    // D2: Default clears the stored theme; the window draws the bridge default.
    let themes = try XCTUnwrap(page.makeOptionsMenu().item(withTitle: "Theme")?.submenu)
    page.pickTheme(try XCTUnwrap(themes.item(withTitle: "Default")))
    XCTAssertNil(harness.source.sidebar.spaces[harness.ids[0]]?.theme)
    XCTAssertEqual(harness.source.space(harness.ids[0])?.theme, .bridgeDefault)
    XCTAssertEqual(harness.saves, 4)
    harness.controller.close()
  }

  /// The "Emoji..." sheet enables Set Icon only for exactly one emoji.
  func testEmojiPromptEnablesSetOnlyForOneEmoji() {
    let prompt = SpaceEmojiPrompt(current: nil)
    XCTAssertFalse(prompt.canSet)
    let cases = [("\u{1F680}", true), ("7", false), ("\u{1F680}\u{1F680}", false), ("\u{2764}\u{FE0F}", true)]
    for (text, valid) in cases {
      prompt.field.stringValue = text
      prompt.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: prompt.field))
      XCTAssertEqual(prompt.canSet, valid, "\(text.unicodeScalars.map(\.value))")
    }
    XCTAssertTrue(SpaceEmojiPrompt(current: "\u{1F680}").canSet, "an emoji icon opens with it filled in")
  }

  func testHeaderDragReordersAndCtrlNFollowsTheNewOrder() throws {
    let harness = Harness(["A", "B", "C"])
    let page = try XCTUnwrap(harness.page(harness.ids[0]))
    page.headerSettle = SpringDriver(reduceMotion: { true })
    harness.controller.sidebarController.showSpace(harness.ids[0])
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let rest = page.titleLabel.frame.minX
    let pitch = SpaceHeaderDrag.pitch(headerWidth: page.bounds.width)
    XCTAssertGreaterThan(pitch, 100, "one slot is the header's width, not the dock's dot pitch")
    let dockPitch = SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing
    let start = try Self.pressAndDrag(page, window: harness.controller.window,
                                      through: [dockPitch, pitch / 4, pitch * 0.6])
    XCTAssertEqual(harness.titles, ["A", "B", "C"], "nothing moves until the release")
    XCTAssertEqual(page.titleLabel.frame.minX, rest + (pitch * 0.6).rounded(), accuracy: 1, "the title follows 1:1")
    let up = try Self.mouse(.leftMouseUp, at: NSPoint(x: start.x + pitch * 0.6, y: start.y),
                            window: harness.controller.window)
    page.mouseUp(with: up)

    XCTAssertEqual(harness.titles, ["B", "A", "C"])
    XCTAssertEqual(page.headerDragOffset, 0, "Reduce Motion: the title is home at once")
    XCTAssertEqual(page.titleLabel.frame.minX, rest)
    XCTAssertEqual(harness.controller.currentSpace, harness.ids[0])
    XCTAssertEqual(harness.saves, 1, "the new order is persisted through the autosave hook")
    harness.controller.sidebarController.goToSpace(at: 0)
    waitUntil("the first Space is the one the drag moved in front") {
      harness.controller.currentSpace == harness.ids[1]
    }
    harness.controller.close()
  }

  /// A drag short of half a header width moves nothing; the title springs home and a new press catches it mid-way,
  /// from where it is drawn (interruptible), then follows the pointer from there.
  func testHeaderDragBelowHalfAPageSpringsBackAndCanBeCaught() throws {
    let harness = Harness(["A", "B"])
    let page = try XCTUnwrap(harness.page(harness.ids[0]))
    page.headerSettle = SpringDriver(now: { 0 }, reduceMotion: { false })
    harness.controller.sidebarController.showSpace(harness.ids[0])
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let rest = page.titleLabel.frame.minX
    let window = harness.controller.window
    let start = try Self.pressAndDrag(page, window: window, through: [10, 20, 30])
    XCTAssertEqual(page.titleLabel.frame.minX, rest + 30)
    XCTAssertTrue(page.editButton.isHidden, "the hover buttons step aside during a drag")
    page.mouseUp(with: try Self.mouse(.leftMouseUp, at: NSPoint(x: start.x + 30, y: start.y), window: window))
    XCTAssertEqual(harness.titles, ["A", "B"])
    XCTAssertEqual(harness.saves, 0)
    XCTAssertTrue(page.headerSettle.isRunning, "springs home")

    page.mouseDown(with: try Self.mouse(.leftMouseDown, at: start, window: window))
    XCTAssertFalse(page.headerSettle.isRunning, "the press stops the spring")
    XCTAssertEqual(page.headerDragOffset, 30, accuracy: 0.001, "caught where it was drawn")
    page.mouseDragged(with: try Self.mouse(.leftMouseDragged, at: NSPoint(x: start.x + 2, y: start.y), window: window))
    XCTAssertEqual(page.headerDragOffset, 32, accuracy: 0.001, "and dragged on from there, past no threshold")
    page.mouseUp(with: try Self.mouse(.leftMouseUp, at: NSPoint(x: start.x + 2, y: start.y), window: window))
    XCTAssertFalse(page.isRenaming, "a caught title is a drag, not a click")
    page.headerSettle.stop()
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
    let spaces = try XCTUnwrap(MainMenu.make(commands: AppCommands()).menu.items.first { $0.title == "Spaces" }?.submenu)
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
