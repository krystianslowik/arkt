import AppKit
import Testing
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// The extension context menu (#596, design/extensions "The context menu"): the native menu of an extension action
/// built from the engine's item tree, each item enabled per the design table, Manage and Remove handed to the shell,
/// everything else back to the engine, and the same menu from right-click, Ctrl-click and the accessibility
/// show-menu action.
@MainActor
struct ExtensionContextMenuTests {
  init() {
    _ = NSApplication.shared             // `performActionForItem(at:)` sends through `NSApp`
  }

  private typealias C = ExtensionContextCommand

  private static func action(_ id: String, _ name: String, siteAccess: ExtensionSiteAccess = .noSiteAccess,
                             options: Bool = false) -> ExtensionAction {
    ExtensionAction(id: id, name: name, hasOptionsPage: options, siteAccess: siteAccess)
  }

  private static func engine(_ actions: [ExtensionAction],
                             url: String? = nil) -> (InMemoryEngine, EngineWindowID) {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    if let url { engine.createTab(url: URL(string: url), in: window) }
    engine.setExtensionActions(actions, in: window)
    return (engine, window)
  }

  private static func menu(_ engine: InMemoryEngine, _ window: EngineWindowID, _ id: String,
                           manage: @escaping @MainActor (ExtensionAction) -> Void = { _ in },
                           remove: @escaping @MainActor (ExtensionAction) -> Void = { _ in }) -> NSMenu? {
    ExtensionContextMenu.menu(forAction: id, in: window, engine: engine, onManage: manage, onRemove: remove)
  }

  private func titles(_ menu: NSMenu) -> [String] {
    menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  private func item(_ menu: NSMenu, _ title: String) -> NSMenuItem? {
    menu.items.first { $0.title == title }
  }

  // MARK: Items per the design table

  @Test func unpinnedActionWithOptionsAndSiteAccess() throws {
    let (engine, window) = Self.engine([Self.action("a", "Alpha", siteAccess: .onThisSite, options: true)],
                                       url: "https://news.example.com/a")
    let menu = try #require(Self.menu(engine, window, "a"))

    #expect(titles(menu) == ["Alpha", "Options...", "Pin to Sidebar", "This Can Read and Change Site Data", "-",
                             "Manage Extension...", "Remove from Arkt..."])
    #expect(menu.autoenablesItems == false)
    #expect(item(menu, "Alpha")?.isEnabled == false)                  // the name is a disabled header
    #expect(item(menu, "Options...")?.isEnabled == true)
    #expect(item(menu, "Pin to Sidebar")?.isEnabled == true)
    #expect(item(menu, "Manage Extension...")?.isEnabled == true)
    #expect(item(menu, "Remove from Arkt...")?.isEnabled == true)
    #expect(!menu.items.contains { $0.title == "Move Left" || $0.title == "Move Right" })

    let access = try #require(item(menu, "This Can Read and Change Site Data")?.submenu)
    #expect(titles(access) == ["When You Click the Extension", "On news.example.com", "On All Sites"])
    #expect(access.items.map(\.state) == [.off, .on, .off])            // exactly one checked
    #expect(access.items.map(\.isEnabled) == [true, true, true])
  }

  @Test func pinnedActionsDisableMovesAtTheEnds() throws {
    let (engine, window) = Self.engine(["a", "b", "c"].map { Self.action($0, $0.uppercased()) })
    for id in ["a", "b", "c"] { engine.setExtensionPinned(id, pinned: true) }

    func moves(_ id: String) throws -> [Bool] {
      let menu = try #require(Self.menu(engine, window, id))
      return try ["Move Left", "Move Right"].map { try #require(item(menu, $0)).isEnabled }
    }
    #expect(try moves("a") == [false, true])
    #expect(try moves("b") == [true, true])
    #expect(try moves("c") == [true, false])

    let menu = try #require(Self.menu(engine, window, "b"))
    #expect(titles(menu) == ["B", "Options...", "Unpin from Sidebar", "Move Left", "Move Right", "-",
                             "Manage Extension...", "Remove from Arkt..."])
    #expect(item(menu, "Options...")?.isEnabled == false)             // no options page
    #expect(item(menu, "This Can Read and Change Site Data") == nil)  // no host permissions
  }

  @Test func singlePinnedActionCannotMoveEitherWay() throws {
    let (engine, window) = Self.engine([Self.action("a", "A"), Self.action("b", "B")])
    engine.setExtensionPinned("a", pinned: true)
    let menu = try #require(Self.menu(engine, window, "a"))
    #expect(item(menu, "Move Left")?.isEnabled == false)
    #expect(item(menu, "Move Right")?.isEnabled == false)
  }

  @Test func unknownActionHasNoMenu() {
    let (engine, window) = Self.engine([Self.action("a", "A")])
    #expect(Self.menu(engine, window, "missing") == nil)
    #expect(Self.menu(engine, EngineWindowID(), "a") == nil)
  }

  @Test func longNameIsKeptVerbatimAsTheHeader() throws {
    let long = String(repeating: "Very Long Extension Name ", count: 4).trimmingCharacters(in: .whitespaces)
    let (engine, window) = Self.engine([Self.action("a", long)])
    let menu = try #require(Self.menu(engine, window, "a"))
    #expect(menu.items.first?.title == long)
    #expect(menu.items.first?.isEnabled == false)
  }

  // MARK: Commands

  @Test func pinAndMoveGoToTheEngine() throws {
    let (engine, window) = Self.engine([Self.action("a", "A"), Self.action("b", "B")])
    let first = try #require(Self.menu(engine, window, "a"))
    first.performActionForItem(at: first.indexOfItem(withTitle: "Pin to Sidebar"))
    #expect(engine.pinnedExtensionIDs == ["a"])
    #expect(try #require(Self.menu(engine, window, "a")).indexOfItem(withTitle: "Unpin from Sidebar") >= 0)

    engine.setExtensionPinned("b", pinned: true)
    let second = try #require(Self.menu(engine, window, "b"))
    second.performActionForItem(at: second.indexOfItem(withTitle: "Move Left"))
    #expect(engine.pinnedExtensionIDs == ["b", "a"])
    #expect(engine.performedExtensionContextCommands.map(\.command) == [C.togglePin, C.moveLeft])
    #expect(engine.performedExtensionContextCommands.allSatisfy { $0.window == window })
  }

  @Test func disabledMoveDoesNothing() throws {
    let (engine, window) = Self.engine([Self.action("a", "A"), Self.action("b", "B")])
    engine.setExtensionPinned("a", pinned: true)
    engine.setExtensionPinned("b", pinned: true)
    let menu = try #require(Self.menu(engine, window, "a"))
    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Move Left"))
    #expect(engine.pinnedExtensionIDs == ["a", "b"])
    #expect(engine.performedExtensionContextCommands.isEmpty)
  }

  @Test func siteAccessChoiceGoesToTheEngine() throws {
    let (engine, window) = Self.engine([Self.action("a", "A", siteAccess: .onClick)], url: "https://example.com")
    let menu = try #require(Self.menu(engine, window, "a"))
    let access = try #require(item(menu, "This Can Read and Change Site Data")?.submenu)
    access.performActionForItem(at: access.indexOfItem(withTitle: "On All Sites"))
    #expect(engine.extensionActions(in: window).first?.siteAccess == .onAllSites)
    let rebuilt = try #require(Self.menu(engine, window, "a"))
    let rebuiltAccess = try #require(item(rebuilt, "This Can Read and Change Site Data")?.submenu)
    #expect(rebuiltAccess.items.map(\.state) == [.off, .off, .on])
  }

  @Test func optionsGoesToTheEngine() throws {
    let (engine, window) = Self.engine([Self.action("a", "A", options: true)])
    let menu = try #require(Self.menu(engine, window, "a"))
    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Options..."))
    #expect(engine.performedExtensionContextCommands.map(\.command) == [C.options])
    #expect(engine.performedExtensionContextCommands.first?.actionID == "a")
  }

  @Test func manageAndRemoveGoToTheShellNotTheEngine() throws {
    let (engine, window) = Self.engine([Self.action("a", "Alpha")])
    var managed: [ExtensionAction] = []
    var removed: [ExtensionAction] = []
    let built = Self.menu(engine, window, "a", manage: { managed.append($0) }, remove: { removed.append($0) })
    let menu = try #require(built)
    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Manage Extension..."))
    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Remove from Arkt..."))
    #expect(managed.map(\.id) == ["a"])
    #expect(managed.first?.extensionID == "a")
    #expect(removed.map(\.name) == ["Alpha"])
    #expect(engine.performedExtensionContextCommands.isEmpty)
  }

  @Test func headerDoesNothing() throws {
    let (engine, window) = Self.engine([Self.action("a", "A")])
    let menu = try #require(Self.menu(engine, window, "a"))
    menu.performActionForItem(at: 0)
    #expect(engine.performedExtensionContextCommands.isEmpty)
    #expect(engine.pinnedExtensionIDs.isEmpty)
  }

  // MARK: Ownership

  @Test func menuDoesNotKeepTheEngineAlive() {
    weak var weakEngine: InMemoryEngine?
    var kept: NSMenu?
    autoreleasepool {
      let (engine, window) = Self.engine([Self.action("a", "A")])
      kept = Self.menu(engine, window, "a")
      weakEngine = engine
    }
    #expect(kept != nil)
    #expect(weakEngine == nil)
    kept?.performActionForItem(at: kept?.indexOfItem(withTitle: "Pin to Sidebar") ?? -1)   // quietly nothing
  }

  // MARK: The row's menu: right-click, Ctrl-click and the accessibility show-menu action

  @Test func rowGivesTheSameMenuToTheMouseAndToAccessibility() throws {
    let (engine, window) = Self.engine([Self.action("a", "Alpha", siteAccess: .onClick, options: true)])
    let row = ExtensionContextMenuView(frame: NSRect(x: 0, y: 0, width: 300, height: 44))
    row.menuProvider = { Self.menu(engine, window, "a") }
    var shown: [(NSMenu, NSView)] = []
    row.presentMenu = { shown.append(($0, $1)) }

    let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                clickCount: 1, pressure: 1))
    let mouseMenu = try #require(row.menu(for: event))
    #expect(row.accessibilityPerformShowMenu())
    #expect(shown.count == 1)
    let axMenu = try #require(shown.first?.0)
    #expect(shown.first?.1 === row)
    #expect(titles(axMenu) == titles(mouseMenu))
    #expect(axMenu.items.map(\.isEnabled) == mouseMenu.items.map(\.isEnabled))
  }

  @Test func rowWithoutAMenuDeclinesTheShowMenuAction() {
    let (engine, window) = Self.engine([Self.action("a", "A")])
    let row = ExtensionContextMenuView(frame: .zero)
    var shown = 0
    row.presentMenu = { _, _ in shown += 1 }
    #expect(row.accessibilityPerformShowMenu() == false)              // no provider
    row.menuProvider = { Self.menu(engine, window, "gone") }
    #expect(row.accessibilityPerformShowMenu() == false)              // the action went away
    #expect(shown == 0)
  }
}
