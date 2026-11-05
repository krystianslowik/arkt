import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The Edit Pin popover (#363, design/edit-pin, direction B): Edit Pinned URL on a pinned row and Rename or Edit
/// Pinned URL on a Favorite tile open one popover anchored to the row or tile. Save stores the name as the custom
/// title and the address as the pinned URL; Back to Pinned URL then returns to it. Text goes in through the field
/// editor, Return and Escape through the field's commands, as the keyboard sends them.
@MainActor
final class EditPinTests: XCTestCase {
  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var p0: UUID
    var p1: UUID
    var favorite: UUID
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var announcements: [String] = []

    init(_ sidebar: SidebarModel.Sidebar, size: NSSize = NSSize(width: 1200, height: 800),
         reducesMotion: Bool = true) {
      let source = ModelSidebarSource(sidebar: sidebar)
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(origin: .zero, size: size), display: false)
      controller.window?.orderFront(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.sidebarController.editPinReducesMotion = { reducesMotion }
      controller.sidebarController.editPinAnnounce = { [unowned self] text, _ in announcements.append(text) }
    }

    var sidebarController: SidebarController { controller.sidebarController }
    var editPin: EditPinController? { sidebarController.editPin }
    var root: NSView { controller.window!.contentView! }

    func popover() throws -> EditPinView {
      let view = try XCTUnwrap(editPin?.view, "the Edit Pin popover is open")
      view.layoutSubtreeIfNeeded()
      return view
    }

    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(sidebarController.currentPage?.outlineController)
    }

    func tabURL(_ node: UUID) -> URL? {
      guard case .tab(_, let url, _)? = source.node(node) else { return nil }
      return url
    }

    func tabTitle(_ node: UUID) -> String? {
      guard case .tab(_, _, let title)? = source.node(node) else { return nil }
      return title
    }

    /// Chooses `title` on `node`'s row menu.
    func choose(_ title: String, on node: UUID) throws {
      let outline = try outline()
      let menu = try XCTUnwrap(outline.menu(forRow: outline.row(for: node)), "the row has a menu")
      let index = menu.indexOfItem(withTitle: title)
      XCTAssertGreaterThanOrEqual(index, 0, "no \(title) item")
      XCTAssertTrue(try XCTUnwrap(menu.item(at: index)).isEnabled, "\(title) is enabled")
      menu.performActionForItem(at: index)
    }

    /// Chooses `title` on the Favorite tile's right-click menu.
    func chooseOnTile(_ title: String, _ favorite: UUID) throws {
      let grid = sidebarController.view.favorites
      grid.layoutSubtreeIfNeeded()
      let tile = try XCTUnwrap(grid.tile(for: favorite))
      let center = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
      let event = try XCTUnwrap(NSEvent.mouseEvent(
        with: .rightMouseDown, location: center, modifierFlags: [], timestamp: 0,
        windowNumber: grid.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      let menu = try XCTUnwrap(grid.collectionView.menu(for: event), "the tile has a menu")
      let index = menu.indexOfItem(withTitle: title)
      XCTAssertGreaterThanOrEqual(index, 0, "no \(title) item")
      menu.performActionForItem(at: index)
    }

    /// Replaces `field`'s text through the field editor, as typing does.
    func type(_ text: String, into field: NSTextField) throws {
      let window = try XCTUnwrap(field.window)
      if field.currentEditor() == nil { window.makeFirstResponder(field) }
      let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "the field is being edited")
      editor.selectAll(nil)
      editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Sends `command` (insertNewline:, cancelOperation:) from the field editor of `field`.
    func send(_ command: Selector, from field: NSTextField) throws {
      let window = try XCTUnwrap(field.window)
      if field.currentEditor() == nil { window.makeFirstResponder(field) }
      let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
      editor.doCommand(by: command)
    }

    /// Whether `field` holds the keyboard with its whole text selected.
    func isFocusedWithAllSelected(_ field: NSTextField) -> Bool {
      guard let editor = field.currentEditor() as? NSTextView,
            controller.window?.firstResponder === editor else { return false }
      return editor.selectedRange() == NSRange(location: 0, length: (editor.string as NSString).length)
    }

    func key(_ code: UInt16, _ characters: String) throws -> NSEvent {
      try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: controller.window?.windowNumber ?? 0, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    func click(at point: NSPoint, in view: NSView) throws {
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
          with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
          windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1,
          pressure: 1)))
      }
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
    let p0 = try sidebar.addTab(url: url("p0"), title: "Q4 planning", in: .pinned(space))
    let p1 = try sidebar.addTab(url: url("p1"), title: "P1", in: .pinned(space))
    _ = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let favorite = try sidebar.addTab(url: url("cal"), title: "Calendar", in: .favorites(profile: "default"))
    return World(sidebar: sidebar, space: space, p0: p0, p1: p1, favorite: favorite)
  }

  // MARK: Pinned tab: Edit Pinned URL

  /// The popover anchors to the row (arrow on its leading edge at the row's middle), focuses Pinned URL with the
  /// text selected, and reads as a dialog named for the kind.
  func testEditPinnedURLOpensOnTheRowWithTheAddressSelected() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)

    let popover = try harness.popover()
    XCTAssertEqual(popover.titleLabel.stringValue, "Edit Pinned Tab")
    XCTAssertEqual(popover.nameField.stringValue, "Q4 planning")
    XCTAssertEqual(popover.urlField.stringValue, "example.com/p0")
    XCTAssertTrue(harness.isFocusedWithAllSelected(popover.urlField))
    XCTAssertEqual(popover.frame.width, EditPinMetrics.width)
    XCTAssertEqual(popover.accessibilityRole(), .group)
    XCTAssertEqual(popover.accessibilitySubrole(), .dialog)
    XCTAssertEqual(popover.accessibilityLabel(), "Edit Pinned Tab")
    XCTAssertEqual(popover.accessibilityIdentifier(), AXID.EditPin.popover)
    XCTAssertEqual(popover.nameField.accessibilityLabel(), "Name")
    XCTAssertEqual(popover.urlField.accessibilityLabel(), "Pinned URL")
    XCTAssertEqual(popover.useCurrentPageButton.accessibilityHelp(), "Sets the pinned URL to this tab's address")
    XCTAssertEqual(popover.saveButton.keyEquivalent, "\r")

    let outline = try harness.outline()
    let row = outline.outlineView.convert(outline.outlineView.rect(ofRow: outline.row(for: world.p0)), to: harness.root)
    let arrowY = harness.root.isFlipped ? popover.frame.minY + EditPinMetrics.arrowCenter
      : popover.frame.maxY - EditPinMetrics.arrowCenter
    XCTAssertEqual(arrowY, row.midY, accuracy: 0.5, "the arrow points at the row")
    XCTAssertEqual(popover.frame.minX - EditPinMetrics.arrowDepth, row.maxX, accuracy: 0.5,
                   "the arrow's tip touches the row's trailing edge")
    harness.controller.close()
  }

  /// Save stores the new pinned URL without navigating the tab; Back to Pinned URL then goes there.
  func testSavingANewPinnedURLAndBackToPinnedURLReturnsToIt() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.p0)
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()

    try harness.type("example.com/p0/board", into: popover.urlField)
    popover.saveButton.performClick(nil)

    XCTAssertNil(harness.editPin, "Save closes the popover")
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0/board"))
    XCTAssertEqual(harness.tabTitle(world.p0), "Q4 planning", "the name did not change")
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0"), "the page stays where it is")
    try harness.choose("Back to Pinned URL", on: world.p0)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("p0/board"))
    harness.controller.close()
  }

  /// Return in a field saves, as Save does; a new name is stored as the custom title.
  func testReturnSavesTheNameAsTheCustomTitle() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()

    try harness.type("Roadmap", into: popover.nameField)
    try harness.send(#selector(NSResponder.insertNewline(_:)), from: popover.nameField)

    XCTAssertNil(harness.editPin)
    XCTAssertEqual(harness.tabTitle(world.p0), "Roadmap")
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0"))
    if case .tab(let stored)? = harness.source.sidebar.nodes[world.p0]?.kind {
      XCTAssertEqual(stored.customTitle, "Roadmap")
    } else {
      XCTFail("the pin is a tab")
    }
    harness.controller.close()
  }

  /// Real Return and Escape key events through the window, with a field holding the keyboard: Return saves,
  /// Escape closes without storing.
  func testReturnAndEscapeThroughTheWindow() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    let window = try XCTUnwrap(harness.controller.window)

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    var popover = try harness.popover()
    try harness.type("example.com/escaped", into: popover.urlField)
    window.sendEvent(try harness.key(53, "\u{1b}"))
    XCTAssertNil(harness.editPin, "Escape closes")
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0"))

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    popover = try harness.popover()
    try harness.type("example.com/returned", into: popover.urlField)
    window.sendEvent(try harness.key(36, "\r"))
    XCTAssertNil(harness.editPin, "Return saves")
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("returned"))
    harness.controller.close()
  }

  /// Use Current Page fills Pinned URL with the page the tab shows now.
  func testUseCurrentPageFillsTheAddressOfTheLivePage() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.p0)
    let tab = try XCTUnwrap(harness.controller.tabsByNode[world.p0])
    harness.engine.navigate(tab, to: Self.url("p0/other"))
    harness.engine.finishLoad(tab, title: "Other")
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()

    popover.useCurrentPageButton.performClick(nil)
    XCTAssertEqual(popover.urlField.stringValue, "example.com/p0/other")
    popover.saveButton.performClick(nil)

    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0/other"))
    if case .atPinnedURL = harness.controller.pinnedState(of: world.p0) {} else {
      XCTFail("the tab now shows its pinned URL")
    }
    harness.controller.close()
  }

  /// Save stays enabled; something that is not a web address keeps the popover open with the reason under the field,
  /// announced and set as the field's help. Nothing is stored, and the next edit clears the line.
  func testAnInvalidAddressKeepsThePopoverOpenWithTheReason() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()
    XCTAssertTrue(popover.errorLine.isHidden)

    try harness.type("planning example com/roadmap", into: popover.urlField)
    XCTAssertTrue(popover.saveButton.isEnabled)
    try harness.send(#selector(NSResponder.insertNewline(_:)), from: popover.urlField)

    XCTAssertNotNil(harness.editPin, "the popover stays open")
    XCTAssertFalse(popover.errorLine.isHidden)
    XCTAssertEqual(popover.errorLabel.stringValue, "Enter a web address, like example.com")
    XCTAssertEqual(popover.urlField.accessibilityHelp(), "Enter a web address, like example.com")
    XCTAssertTrue(popover.urlFieldShowsError)
    XCTAssertEqual(harness.announcements, ["Enter a web address, like example.com"])
    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0"))

    try harness.type("example.com/p0/fixed", into: popover.urlField)
    XCTAssertTrue(popover.errorLine.isHidden)
    XCTAssertFalse(popover.urlFieldShowsError)
    XCTAssertNil(popover.urlField.accessibilityHelp())
    harness.controller.close()
  }

  /// Escape and Cancel close without storing anything; so does a click outside the popover, and the window
  /// resigning key. A click inside keeps it open.
  func testEscapeCancelAndAClickOutsideCloseWithoutStoring() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    var popover = try harness.popover()
    try harness.type("example.com/changed", into: popover.urlField)
    try harness.send(#selector(NSResponder.cancelOperation(_:)), from: popover.urlField)
    XCTAssertNil(harness.editPin)

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    popover = try harness.popover()
    try harness.type("example.com/changed", into: popover.urlField)
    popover.cancelButton.performClick(nil)
    XCTAssertNil(harness.editPin)

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    popover = try harness.popover()
    try harness.click(at: NSPoint(x: popover.bounds.midX, y: popover.bounds.midY), in: popover)
    XCTAssertNotNil(harness.editPin, "a click inside keeps it")
    try harness.click(at: NSPoint(x: harness.root.bounds.maxX - 40, y: harness.root.bounds.midY), in: harness.root)
    XCTAssertNil(harness.editPin)

    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: harness.controller.window)
    XCTAssertNil(harness.editPin)

    XCTAssertEqual(harness.tabURL(world.p0), Self.url("p0"))
    harness.controller.close()
  }

  /// Opening it on another row replaces the open one; the node going away closes it.
  func testOneAtATimeAndItClosesWhenTheNodeGoes() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let first = try harness.popover()
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p1)
    XCTAssertNil(first.superview, "the first popover left")
    XCTAssertEqual(try harness.popover().nodeID, world.p1)
    XCTAssertEqual(harness.root.subviews.filter { $0 is EditPinView }.count, 1)

    harness.source.removeNode(world.p1)
    XCTAssertNil(harness.editPin)
    harness.controller.close()
  }

  // MARK: Favorite

  /// Rename on a tile opens the popover under the tile (arrow on its top edge, centered on the tile) with Name
  /// focused; the saved name is the custom title, the tile's tooltip and its VoiceOver label.
  func testFavoriteRenameOpensUnderTheTileAndTheNameBecomesTheTooltip() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.chooseOnTile("Rename\u{2026}", world.favorite)

    let popover = try harness.popover()
    XCTAssertEqual(popover.titleLabel.stringValue, "Edit Favorite")
    XCTAssertEqual(popover.accessibilityLabel(), "Edit Favorite")
    XCTAssertTrue(harness.isFocusedWithAllSelected(popover.nameField))
    let tile = try XCTUnwrap(harness.sidebarController.view.favorites.tile(for: world.favorite))
    let tileFrame = tile.convert(tile.bounds, to: harness.root)
    XCTAssertEqual(popover.frame.minX + popover.arrowX, tileFrame.midX, accuracy: 0.5, "the arrow is on the tile")
    let below = harness.root.isFlipped ? popover.frame.minY - tileFrame.maxY : tileFrame.minY - popover.frame.maxY
    XCTAssertEqual(below, EditPinMetrics.arrowDepth + EditPinMetrics.anchorGap, accuracy: 0.5)

    try harness.type("Team calendar", into: popover.nameField)
    popover.saveButton.performClick(nil)

    XCTAssertEqual(harness.tabTitle(world.favorite), "Team calendar")
    let renamed = try XCTUnwrap(harness.sidebarController.view.favorites.tile(for: world.favorite))
    XCTAssertEqual(renamed.toolTip, "Team calendar")
    XCTAssertEqual(renamed.accessibilityLabel(), "Team calendar")
    harness.controller.close()
  }

  /// Edit Pinned URL on a tile focuses Pinned URL and stores the Favorite's address.
  func testFavoriteEditPinnedURLStoresTheAddress() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    try harness.chooseOnTile("Edit Pinned URL\u{2026}", world.favorite)
    let popover = try harness.popover()
    XCTAssertTrue(harness.isFocusedWithAllSelected(popover.urlField))

    try harness.type("calendar.example.com/team/week", into: popover.urlField)
    popover.saveButton.performClick(nil)

    XCTAssertEqual(harness.tabURL(world.favorite), URL(string: "https://calendar.example.com/team/week"))
    XCTAssertEqual(harness.tabTitle(world.favorite), "Calendar")
    harness.controller.close()
  }

  // MARK: Layout and motion

  /// The longest address stays on one line and scrolls inside its field.
  func testALongAddressScrollsInsideItsField() throws {
    var world = try Self.makeWorld()
    let long = URL(string: "https://planning.example.com/workspaces/q4-2026/boards/roadmap?view=timeline"
                   + "&filter=owner%3Ame&sort=due&group=status&columns=title,owner,due,status,estimate")!
    world.sidebar = try {
      var sidebar = world.sidebar
      try sidebar.updateTab(world.p0, url: long, title: nil)
      return sidebar
    }()
    let harness = Harness(world.sidebar)
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()
    let cell = try XCTUnwrap(popover.urlField.cell)
    XCTAssertTrue(cell.isScrollable)
    XCTAssertFalse(cell.wraps)
    XCTAssertEqual(popover.urlField.frame.height, popover.nameField.frame.height)
    XCTAssertEqual(popover.frame.width, EditPinMetrics.width)
    harness.controller.close()
  }

  /// The smallest window (640 x 420): the popover keeps its width, anchors to the row and stays inside the window.
  func testTheSmallestWindowKeepsTheWidthAndTheAnchor() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar, size: NSSize(width: 640, height: 420))
    try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let popover = try harness.popover()
    XCTAssertEqual(popover.frame.width, EditPinMetrics.width)
    XCTAssertTrue(harness.root.bounds.contains(popover.frame), "inside the window")
    let outline = try harness.outline()
    let row = outline.outlineView.convert(outline.outlineView.rect(ofRow: outline.row(for: world.p0)), to: harness.root)
    XCTAssertGreaterThanOrEqual(popover.frame.minX, row.maxX, "it overlaps the page, not the sidebar")
    harness.controller.close()
  }

  /// Opening scales up from the arrow and fades in; with Reduce Motion it only fades.
  func testOpeningMotionAndItsReduceMotionVariant() throws {
    let world = try Self.makeWorld()
    let moving = Harness(world.sidebar, reducesMotion: false)
    try moving.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let layer = try XCTUnwrap(try moving.popover().layer)
    XCTAssertNotNil(layer.animation(forKey: EditPinMotion.openScaleKey))
    XCTAssertNotNil(layer.animation(forKey: EditPinMotion.openFadeKey))
    moving.controller.close()

    let still = Harness(world.sidebar, reducesMotion: true)
    try still.choose("Edit Pinned URL\u{2026}", on: world.p0)
    let stillLayer = try XCTUnwrap(try still.popover().layer)
    XCTAssertNil(stillLayer.animation(forKey: EditPinMotion.openScaleKey), "Reduce Motion: no scale")
    let fade = try XCTUnwrap(stillLayer.animation(forKey: EditPinMotion.openFadeKey) as? CABasicAnimation)
    XCTAssertEqual(fade.duration, EditPinMotion.reducedOpenDuration, accuracy: 0.001)
    still.controller.close()
  }

  /// The invalid address line fades in over 0.15 s with and without Reduce Motion; only the growth of the popover
  /// is dropped with Reduce Motion (`EditPinMotion.errorResizeDuration`).
  func testTheErrorLineFadesInWithAndWithoutReduceMotion() throws {
    let world = try Self.makeWorld()
    for reduces in [false, true] {
      let harness = Harness(world.sidebar, reducesMotion: reduces)
      try harness.choose("Edit Pinned URL\u{2026}", on: world.p0)
      let popover = try harness.popover()
      let top = harness.root.isFlipped ? popover.frame.minY : popover.frame.maxY
      try harness.type("not an address", into: popover.urlField)
      popover.saveButton.performClick(nil)
      let fade = try XCTUnwrap(popover.errorLine.layer?.animation(forKey: EditPinMotion.errorFadeKey)
                                 as? CABasicAnimation, "the line fades in (Reduce Motion \(reduces))")
      XCTAssertEqual(fade.duration, EditPinMotion.errorDuration, accuracy: 0.001)
      if reduces {
        XCTAssertEqual(popover.frame.height, EditPinMetrics.height(showingError: true), "at once")
        XCTAssertEqual(harness.root.isFlipped ? popover.frame.minY : popover.frame.maxY, top, accuracy: 0.5,
                       "the popover grows downward; its top and arrow stay")
      }
      harness.controller.close()
    }
  }
}
