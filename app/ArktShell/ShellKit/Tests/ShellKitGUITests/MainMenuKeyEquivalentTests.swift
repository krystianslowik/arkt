import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ShellUI

/// Stands in for the app target's `AppCommands` (the app-level menu target) so the real `App/MainMenu.swift` (linked
/// into this target as `MainMenu.swift`) compiles here; only its action selectors are needed.
@MainActor
final class AppCommands: NSObject {
  @objc func newWindow(_ sender: Any?) {}
  @objc func newBlankWindow(_ sender: Any?) {}
  @objc func newIncognitoWindow(_ sender: Any?) {}
  @objc func newLittleArktWindow(_ sender: Any?) {}
  @objc func showSettings(_ sender: Any?) {}
  @objc func importFromArc(_ sender: Any?) {}
  @objc func showArchive(_ sender: Any?) {}
  @objc func showLibrary(_ sender: Any?) {}
  @objc func clearArchive(_ sender: Any?) {}
  @objc func showWelcome(_ sender: Any?) {}
  let undoRouter = ReopenUndoRouter()
}

/// `CommandBarPanel.sendEvent` takes Cmd-Return and Opt-Return before anything else in the panel (KB-085). That
/// hides no menu action only while no menu item binds those keys, so the real main menu is built and checked.
@MainActor
final class MainMenuKeyEquivalentTests: XCTestCase {
  /// Every item of the real main menu, submenus included.
  private func allItems() -> [NSMenuItem] {
    _ = NSApplication.shared
    var items: [NSMenuItem] = []
    func collect(_ menu: NSMenu) {
      for item in menu.items {
        items.append(item)
        if let submenu = item.submenu { collect(submenu) }
      }
    }
    let menu = MainMenu.make(commands: AppCommands()).menu
    // Nine Spaces, so Ctrl-1 ... Ctrl-9 are in the menu (#387: it lists the main window's Spaces).
    if let spaces = menu.items.first(where: { $0.title == SpacesMenu.menuTitle })?.submenu as? SpacesMenu {
      let entries = (1...9).map { SpacesMenu.Entry(id: SpaceID(), title: "Space \($0)") }
      spaces.entries = { entries }
      spaces.refreshList()
    }
    collect(menu)
    return items
  }

  func testNoMenuItemBindsCommandOrOptionReturn() {
    let items = allItems()
    XCTAssertTrue(items.contains { $0.keyEquivalent == "t" && $0.action == #selector(ShellWindowController.newTab(_:)) },
                  "the app's menu was built")
    let returnKeys: Set<String> = ["\r", "\n", "\u{3}"]                  // Return, newline, keypad Enter
    for item in items where returnKeys.contains(item.keyEquivalent) {
      XCTAssertTrue(item.keyEquivalentModifierMask.isDisjoint(with: [.command, .option]),
                    "\(item.title) binds Cmd- or Opt-Return, which the command bar takes first")
    }
  }

  /// KB-017, BH-001 (#102): View > Hide Sidebar on Cmd-S, first in the View menu; `validateMenuItem` flips the title.
  func testHideSidebarSitsFirstInTheViewMenuOnCommandS() throws {
    _ = NSApplication.shared
    let view = try XCTUnwrap(MainMenu.make(commands: AppCommands()).menu.items.first { $0.title == "View" }?.submenu)
    let item = try XCTUnwrap(view.items.first)
    XCTAssertEqual(item.title, "Hide Sidebar")
    XCTAssertEqual(item.action, #selector(ShellWindowController.toggleSidebarVisibility(_:)))
    XCTAssertEqual(item.keyEquivalent, "s")
    XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
    XCTAssertNil(item.target, "reaches the main window's controller through the responder chain")
    let commandS = allItems().filter { $0.keyEquivalent == "s" && $0.keyEquivalentModifierMask == [.command] }
    XCTAssertEqual(commandS.count, 1, "no other item binds Cmd-S")
  }

  /// #118 (KB-013 to KB-016): the copy-link items sit in the Edit menu with Arc's keys.
  func testCopyLinkItemsSitInTheEditMenuWithArcsKeys() throws {
    _ = NSApplication.shared
    let edit = try XCTUnwrap(MainMenu.make(commands: AppCommands()).menu.items.first { $0.title == "Edit" }?.submenu)
    let expected: [(String, Selector, String, NSEvent.ModifierFlags)] = [
      ("Copy URL", #selector(ShellWindowController.copyCurrentURL(_:)), "c", [.command, .shift]),
      ("Copy URL as Markdown", #selector(ShellWindowController.copyCurrentURLAsMarkdown(_:)), "c",
       [.command, .shift, .option]),
      ("Copy URL as Quote", #selector(ShellWindowController.copyCurrentURLAsQuote(_:)), "c",
       [.command, .shift, .control]),
      ("Paste URL as New Tab", #selector(ShellWindowController.pasteURLAsNewTab(_:)), "v", [.command, .option]),
    ]
    for (title, action, key, modifiers) in expected {
      let item = try XCTUnwrap(edit.items.first { $0.title == title }, title)
      XCTAssertEqual(item.action, action, title)
      XCTAssertEqual(item.keyEquivalent, key, title)
      XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title)
      XCTAssertNil(item.target, "reaches the main window's controller through the responder chain")
    }
  }

  // MARK: Split View (S5)

  /// RT-38 (passive read, #78): Arc's View menu holds these four directly, with these titles and keys.
  func testSplitViewItemsSitInTheViewMenuWithArcsKeys() throws {
    _ = NSApplication.shared
    let view = try XCTUnwrap(MainMenu.make(commands: AppCommands()).menu.items.first { $0.title == "View" }?.submenu)
    let expected: [(String, Selector, String)] = [
      ("Add Split View", #selector(ShellWindowController.addSplitPane(_:)), "="),                 // KB-070
      ("Close this Split Pane", #selector(ShellWindowController.closeSplitPane(_:)), "-"),        // KB-071
      ("Separate Page from Split View", #selector(ShellWindowController.separatePageFromSplit(_:)), ""),  // KB-075
      ("Expand Current Split", #selector(ShellWindowController.expandCurrentSplit(_:)), ""),      // KB-075
    ]
    for (title, action, key) in expected {
      let item = try XCTUnwrap(view.items.first { $0.title == title }, title)
      XCTAssertEqual(item.action, action, title)
      XCTAssertEqual(item.keyEquivalent, key, title)
      if !key.isEmpty { XCTAssertEqual(item.keyEquivalentModifierMask, [.control, .shift], title) }
    }
  }

  /// #206: the Spaces menu ends with Delete Space, without a key (PARITY(NEEDS-RUNTIME-CHECK): Arc's title and place).
  func testSpacesMenuEndsWithDeleteSpace() throws {
    _ = NSApplication.shared
    let spaces = try XCTUnwrap(MainMenu.make(commands: AppCommands()).menu.items.first { $0.title == "Spaces" }?.submenu)
    let item = try XCTUnwrap(spaces.items.last)
    XCTAssertEqual(item.title, "Delete Space...")
    XCTAssertEqual(item.action, #selector(ShellWindowController.deleteSpace(_:)))
    XCTAssertEqual(item.keyEquivalent, "")
    XCTAssertTrue(spaces.items.dropLast().last?.isSeparatorItem ?? false)
  }

  /// No two items share a key equivalent.
  func testKeyEquivalentsAreUnique() {
    var seen: [String: String] = [:]
    for item in allItems() where !item.keyEquivalent.isEmpty {
      let key = "\(item.keyEquivalent) \(item.keyEquivalentModifierMask.rawValue)"
      XCTAssertNil(seen[key], "\(item.title) and \(seen[key] ?? "") share a key equivalent")
      seen[key] = item.title
    }
  }

  /// Each split shortcut, as the US layout delivers it, matches exactly its own item and no other; plain Ctrl-1 ...
  /// Ctrl-4 still reach only the Space items (KB-035), not the pane items. Each item is probed alone, so an earlier
  /// item cannot hide a conflict.
  func testSplitShortcutsReachOnlyTheirOwnItem() throws {
    let items = allItems().filter { !$0.keyEquivalent.isEmpty }
    let cases: [(Int, NSEvent.ModifierFlags, String)] = [
      (kVK_ANSI_Equal, [.control, .shift], "Add Split View"),
      (kVK_ANSI_Minus, [.control, .shift], "Close this Split Pane"),
      (kVK_ANSI_RightBracket, [.control, .shift], "Next Split View Pane"),
      (kVK_ANSI_LeftBracket, [.control, .shift], "Previous Split View Pane"),
      (kVK_ANSI_1, [.control, .shift], "Switch to Split View 1"),
      (kVK_ANSI_2, [.control, .shift], "Switch to Split View 2"),
      (kVK_ANSI_3, [.control, .shift], "Switch to Split View 3"),
      (kVK_ANSI_4, [.control, .shift], "Switch to Split View 4"),
      (kVK_ANSI_1, [.control], "Space 1"),
      (kVK_ANSI_4, [.control], "Space 4"),
    ]
    for (keyCode, flags, title) in cases {
      let event = try SplitShortcutTests.key(keyCode, flags: flags)
      let matches = items.filter { Self.matches($0, event) }.map(\.title)
      XCTAssertEqual(matches, [title], "key \(keyCode) with \(flags.rawValue)")
    }
  }

  /// #497: whatever the active keyboard layout, a key press that a menu item without Cmd takes (Space 1 ... 9, the
  /// Split View items) is reserved. Every key code is tried with Ctrl and Ctrl-Shift, so the digit row and the
  /// punctuation keys are covered on the layout the test runs under (US, AZERTY, QWERTZ ...): ReservedKeys must be
  /// a superset of what the menu matches, or a focused page swallows the key.
  func testEveryMenuKeyWithoutCommandIsReservedOnTheActiveLayout() throws {
    // Ctrl-Space (Reveal Current Tab, KB-036) is not a Space or Split View item and is outside this check.
    let items = allItems().filter {
      !$0.keyEquivalent.isEmpty && $0.keyEquivalent != " " && !$0.keyEquivalentModifierMask.contains(.command)
    }
    XCTAssertGreaterThanOrEqual(items.count, 9 + 8, "the Space and Split View items carry keys")
    let source = CGEventSource(stateID: .privateState)
    var matched = 0
    for keyCode in 0..<128 {
      for flags in [CGEventFlags.maskControl, [.maskControl, .maskShift]] {
        guard let cg = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true) else { continue }
        cg.flags = flags
        guard let event = NSEvent(cgEvent: cg) else { continue }
        for item in items where Self.matches(item, event) {
          matched += 1
          XCTAssertTrue(ReservedKeys.arkt.matches(event),
                        "\(item.title): key \(keyCode) types \(event.charactersIgnoringModifiers ?? "")")
        }
      }
    }
    XCTAssertGreaterThan(matched, 0, "some key on this layout reaches a Space or Split View item")
  }

  /// Whether `item`'s key equivalent alone takes `event`: a one-item menu with the same key, aimed at a probe.
  static func matches(_ item: NSMenuItem, _ event: NSEvent) -> Bool {
    let probe = KeyProbe()
    let menu = NSMenu()
    let copy = NSMenuItem(title: item.title, action: #selector(KeyProbe.hit(_:)), keyEquivalent: item.keyEquivalent)
    copy.keyEquivalentModifierMask = item.keyEquivalentModifierMask
    copy.target = probe
    menu.addItem(copy)
    return menu.performKeyEquivalent(with: event) && probe.hits == 1
  }
}

@MainActor
private final class KeyProbe: NSObject {
  var hits = 0
  @objc func hit(_ sender: Any?) { hits += 1 }
}

/// W3-7 part D: the menu inventory and the conditions Chromium's menu code puts on it (week-3 results, W3-8). The same
/// menu is installed in both builds, so these checks cover the FakeEngine app and the Engine app alike.
@MainActor
final class MainMenuInventoryTests: XCTestCase {
  /// Chromium's menu tags (`chrome_command_ids.h`; week-3 results, W3-0 step 5 and W3-8).
  private enum IDC {
    static let exit = 34031
    static let fileMenu = 57326
    static let tabMenu = 57323
    static let historyMenu = 57324
    static let bookmarksMenu = 57333
  }

  private let commands = AppCommands()
  private var built: MainMenu.Built!

  override func setUp() async throws {
    _ = NSApplication.shared
    built = MainMenu.make(commands: commands)
  }

  private func allItems(_ menu: NSMenu? = nil) -> [NSMenuItem] {
    var items: [NSMenuItem] = []
    func collect(_ menu: NSMenu) {
      for item in menu.items {
        items.append(item)
        if let submenu = item.submenu { collect(submenu) }
      }
    }
    collect(menu ?? built.menu)
    return items
  }

  private func item(_ title: String) throws -> NSMenuItem {
    try XCTUnwrap(allItems().first { $0.title == title }, title)
  }

  // MARK: Tags (step 2)

  func testTheBookmarksPlaceholderIsHiddenAndEmptyAndNoChromiumMenuTagIsUsed() throws {
    let topLevel = built.menu.items
    let placeholder = try XCTUnwrap(topLevel.first { $0.tag == IDC.bookmarksMenu })
    XCTAssertTrue(placeholder.isHidden)
    XCTAssertEqual(placeholder.submenu?.items.count, 0)
    for tag in [IDC.fileMenu, IDC.tabMenu, IDC.historyMenu] {
      XCTAssertFalse(allItems().contains { $0.tag == tag }, "tag \(tag) must not be in Arkt's menu")
    }
  }

  // MARK: Targets (step 1)

  func testQuitIsTerminateToNSAppTaggedExitInTheFirstMenu() throws {
    let first = try XCTUnwrap(built.menu.items.first?.submenu)
    let quit = try XCTUnwrap(first.items.first { $0.tag == IDC.exit })
    XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
    XCTAssertTrue(quit.target === NSApp)
    XCTAssertEqual(quit.keyEquivalent, "q")
    XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
  }

  func testAppLevelItemsHaveExplicitTargets() throws {
    let toApp: [(String, Selector)] = [
      ("About Arkt", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
      ("Hide Arkt", #selector(NSApplication.hide(_:))),
      ("Hide Others", #selector(NSApplication.hideOtherApplications(_:))),
      ("Show All", #selector(NSApplication.unhideAllApplications(_:))),
      ("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
    ]
    for (title, action) in toApp {
      let item = try item(title)
      XCTAssertEqual(item.action, action, title)
      XCTAssertTrue(item.target === NSApp, title)
    }
    let toCommands: [(String, Selector)] = [
      ("New Window", #selector(AppCommands.newWindow(_:))),
      ("New Incognito Window", #selector(AppCommands.newIncognitoWindow(_:))),
      ("New Blank Window", #selector(AppCommands.newBlankWindow(_:))),
      ("Settings...", #selector(AppCommands.showSettings(_:))),
      ("Import Browser Data...", #selector(AppCommands.importFromArc(_:))),
      ("Show Archive", #selector(AppCommands.showArchive(_:))),
      ("Show Library", #selector(AppCommands.showLibrary(_:))),            // KB-065, #132
      ("Clear Archive...", #selector(AppCommands.clearArchive(_:))),   // KB-043, unbound
    ]
    for (title, action) in toCommands {
      let item = try item(title)
      XCTAssertEqual(item.action, action, title)
      XCTAssertTrue(item.target === commands, title)
    }
  }

  /// Edit > Undo (Cmd-Z, KB-011) goes to the reopen router, which passes `undo:` on unless it reopens (#346).
  func testUndoTargetsTheReopenRouter() throws {
    let undo = try item("Undo")
    XCTAssertTrue(undo.target === commands.undoRouter)
    XCTAssertEqual(undo.action, #selector(ReopenUndoRouter.undo(_:)))
    XCTAssertEqual(undo.keyEquivalent, "z")
    XCTAssertEqual(undo.keyEquivalentModifierMask, .command)
  }

  /// AppController answers these at the end of the responder chain with Chromium's behaviour.
  func testNoNilTargetItemReachesChromiumsAppController() {
    let chromiumOnly: Set<String> = ["showPreferences:", "orderFrontStandardAboutPanel:", "toggleConfirmToQuit:",
                                     "terminate:"]
    for item in allItems() where item.target == nil {
      guard let action = item.action else { continue }
      XCTAssertFalse(chromiumOnly.contains(NSStringFromSelector(action)), "\(item.title) has a nil target")
    }
  }

  // MARK: Page commands (step 3)

  func testPageCommandsDispatchTheirEngineCommandWithANilTarget() throws {
    let expected: [(String, Int, String, NSEvent.ModifierFlags)] = [
      ("Reload This Page", 33002, "r", .command),
      ("Force Reload This Page", 33007, "r", [.command, .shift]),
      ("Stop", 33006, ".", .command),
      ("Back", 33000, "[", .command),
      ("Forward", 33001, "]", .command),
      ("Find...", 37000, "f", .command),
      ("Find Next", 37001, "g", .command),
      ("Find Previous", 37002, "g", [.command, .shift]),
      ("Actual Size", 38002, "0", .command),
      ("Zoom In", 38001, "+", .command),
      ("Zoom Out", 38003, "-", .command),
      ("Save Page As...", 35004, "s", [.command, .shift]),
      ("Print...", 35003, "p", .command),
      ("View Source", 35002, "u", [.command, .option]),
      ("Developer Tools", 40004, "i", [.command, .option]),
      ("Inspect Elements", 40023, "c", [.command, .option]),
      ("JavaScript Console", 40005, "j", [.command, .option]),
      ("Show All History", 40010, "y", .command),
      ("Downloads", 40012, "j", [.command, .shift]),
    ]
    // A user's own shortcut for a title (System Settings, Keyboard Shortcuts, App Shortcuts) replaces ours.
    let userKeys = UserDefaults.standard.dictionary(forKey: "NSUserKeyEquivalents") ?? [:]
    for (title, tag, key, modifiers) in expected {
      let item = try item(title)
      XCTAssertEqual(item.action, #selector(ShellWindow.commandDispatch(_:)), title)
      XCTAssertNil(item.target, title)
      XCTAssertEqual(item.tag, tag, title)
      guard userKeys[title] == nil else { continue }
      XCTAssertEqual(item.keyEquivalent, key, title)
      XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title)
    }
    let dispatching = allItems().filter { $0.action == #selector(ShellWindow.commandDispatch(_:)) }
    XCTAssertEqual(dispatching.count, expected.count, "no other commandDispatch: item")
  }

  /// `IDC_NEW_WINDOW`, the one id the menu and host use that has no `EngineCommand` constant, matches
  /// `chrome_command_ids.h`.
  func testPendingCommandIdsMatchChromium() {
    XCTAssertEqual(PendingEngineCommands.all.map(\.rawValue), [34000])
  }

  // MARK: Shell items (step 4)

  func testShellItemsAndTheirKeys() throws {
    let expected: [(String, Selector, String, NSEvent.ModifierFlags)] = [
      ("New Tab", #selector(ShellWindowController.newTab(_:)), "t", .command),
      ("New Window", #selector(AppCommands.newWindow(_:)), "n", .command),
      ("New Incognito Window", #selector(AppCommands.newIncognitoWindow(_:)), "n", [.command, .shift]),
      ("New Blank Window", #selector(AppCommands.newBlankWindow(_:)), "n", [.command, .control]),
      ("Open Command Bar", #selector(ShellWindowController.openLocation(_:)), "l", .command),
      ("Archive Tab", #selector(ShellWindowController.closeTab(_:)), "w", .command),
      ("Reopen Closed Tab", #selector(ShellWindowController.reopenClosedTab(_:)), "t", [.command, .shift]),   // KB-010
      ("Clear Today Tabs", #selector(ShellWindowController.clearTodayTabs(_:)), "k", [.command, .shift]),     // KB-019
      ("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
      ("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
      ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", .command),
      ("Zoom", #selector(NSWindow.performZoom(_:)), "", []),
      ("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j", .command),
      ("Settings...", #selector(AppCommands.showSettings(_:)), ",", .command),
      ("Show Archive", #selector(AppCommands.showArchive(_:)), "", []),
      ("Show Library", #selector(AppCommands.showLibrary(_:)), "l", [.command, .shift]),             // KB-065, #132
    ]
    for (title, action, key, modifiers) in expected {
      let item = try item(title)
      XCTAssertEqual(item.action, action, title)
      XCTAssertEqual(item.keyEquivalent, key, title)
      if !key.isEmpty { XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title) }
    }
  }

  /// Each reserved key, as the US layout delivers it, is the key of exactly the Arkt item it is reserved for.
  func testEveryReservedKeyBelongsToItsArktItem() throws {
    let items = allItems().filter { !$0.keyEquivalent.isEmpty }
    let cases: [(Int, CGEventFlags, String)] = [
      (kVK_ANSI_T, .maskCommand, "New Tab"),
      (kVK_ANSI_L, .maskCommand, "Open Command Bar"),
      (kVK_ANSI_W, .maskCommand, "Archive Tab"),
      (kVK_ANSI_W, [.maskCommand, .maskShift], "Close Window"),
      (kVK_ANSI_N, .maskCommand, "New Window"),
      (kVK_ANSI_N, [.maskCommand, .maskShift], "New Incognito Window"),
      (kVK_ANSI_N, [.maskCommand, .maskControl], "New Blank Window"),
      (kVK_ANSI_Q, .maskCommand, "Quit Arkt"),
      (kVK_RightArrow, [.maskCommand, .maskAlternate], "Next Space"),
      (kVK_LeftArrow, [.maskCommand, .maskAlternate], "Previous Space"),
      (kVK_ANSI_D, .maskCommand, "Pin Tab"),                                    // KB-012 (#108)
      (kVK_ANSI_T, [.maskCommand, .maskShift], "Reopen Closed Tab"),            // KB-010 (#346)
      (kVK_ANSI_K, [.maskCommand, .maskShift], "Clear Today Tabs"),             // KB-019 (#110)
    ]
    let source = CGEventSource(stateID: .privateState)
    for (keyCode, flags, title) in cases {
      let cg = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
      cg.flags = flags
      let event = try XCTUnwrap(NSEvent(cgEvent: cg))
      XCTAssertTrue(ReservedKeys.arkt.matches(event), title)
      if keyCode != kVK_RightArrow, keyCode != kVK_LeftArrow {
        try XCTSkipUnless(event.characters(byApplyingModifiers: []) == event.charactersIgnoringModifiers?.lowercased(),
                          "keyboard layout is not US-compatible")
      }
      let matches = items.filter { MainMenuKeyEquivalentTests.matches($0, event) }.map(\.title)
      XCTAssertEqual(matches, [title], "key \(keyCode)")
    }
  }

  // MARK: Install (step 5)

  func testInstallPointsServicesWindowsAndHelpIntoTheMenu() throws {
    let saved = (NSApp.mainMenu, NSApp.servicesMenu, NSApp.windowsMenu, NSApp.helpMenu)
    defer {
      NSApp.mainMenu = saved.0
      NSApp.servicesMenu = saved.1
      NSApp.windowsMenu = saved.2
      NSApp.helpMenu = saved.3
    }
    // Chromium's menu, as `chrome::BuildMainMenu` leaves it: Services and Help point into it.
    let chromium = MainMenu.make(commands: AppCommands())
    NSApp.mainMenu = chromium.menu
    NSApp.servicesMenu = chromium.services
    NSApp.helpMenu = chromium.help

    MainMenu.install(commands: commands)

    let menu = try XCTUnwrap(NSApp.mainMenu)
    XCTAssertFalse(menu === chromium.menu)
    let submenus = allItems(menu).compactMap(\.submenu)
    for (name, target) in [("services", NSApp.servicesMenu), ("windows", NSApp.windowsMenu), ("help", NSApp.helpMenu)] {
      let target = try XCTUnwrap(target, name)
      XCTAssertTrue(submenus.contains { $0 === target }, "\(name) menu is inside Arkt's menu")
    }
  }

  /// Onboarding spec, section 12: "Welcome to Arkt" is the first Help item, with no shortcut and an explicit target.
  func testHelpMenuStartsWithWelcomeToArkt() throws {
    let commands = AppCommands()
    let built = MainMenu.make(commands: commands)
    let first = try XCTUnwrap(built.help.items.first)
    XCTAssertEqual(first.title, "Welcome to Arkt")
    XCTAssertEqual(first.action, #selector(AppCommands.showWelcome(_:)))
    XCTAssertTrue(first.target === commands)
    XCTAssertEqual(first.keyEquivalent, "")
  }

  /// KB-019 (#110): Clear Today Tabs sits in the File menu on Shift-Cmd-K, with the close actions.
  func testClearTodayTabsSitsInTheFileMenuOnShiftCommandK() throws {
    let file = try XCTUnwrap(built.menu.items.first { $0.title == "File" }?.submenu)
    let clear = try XCTUnwrap(file.items.first { $0.title == "Clear Today Tabs" })
    XCTAssertEqual(clear.action, #selector(ShellWindowController.clearTodayTabs(_:)))
    XCTAssertEqual(clear.keyEquivalent, "k")
    XCTAssertEqual(clear.keyEquivalentModifierMask, [.command, .shift])
    XCTAssertNil(clear.target, "reaches the main window's controller through the responder chain")
    let shiftCommandK = allItems().filter {
      $0.keyEquivalent == "k" && $0.keyEquivalentModifierMask == [.command, .shift]
    }
    XCTAssertEqual(shiftCommandK.count, 1, "no other item binds Shift-Cmd-K")
  }

  /// KB-012 and KB-041 (#108): Pin Tab sits in the File menu on Cmd-D; Back to Pinned URL is unbound, as in Arc.
  /// Reset Space joins the Spaces menu's Space actions, without a key.
  func testPinnedTabItemsSitInTheFileAndSpacesMenus() throws {
    let menu = built.menu
    let file = try XCTUnwrap(menu.items.first { $0.title == "File" }?.submenu)
    let pin = try XCTUnwrap(file.items.first { $0.title == "Pin Tab" })
    XCTAssertEqual(pin.action, #selector(ShellWindowController.pinCurrentTab(_:)))
    XCTAssertEqual(pin.keyEquivalent, "d")
    XCTAssertEqual(pin.keyEquivalentModifierMask, [.command])
    XCTAssertNil(pin.target, "reaches the main window's controller through the responder chain")
    let reset = try XCTUnwrap(file.items.first { $0.title == "Back to Pinned URL" })
    XCTAssertEqual(reset.action, #selector(ShellWindowController.resetTab(_:)))
    XCTAssertEqual(reset.keyEquivalent, "")
    let spaces = try XCTUnwrap(menu.items.first { $0.title == "Spaces" }?.submenu)
    let resetSpace = try XCTUnwrap(spaces.items.first { $0.title == "Reset Space" })
    XCTAssertEqual(resetSpace.action, #selector(ShellWindowController.resetSpace(_:)))
    XCTAssertEqual(resetSpace.keyEquivalent, "")
    let commandD = allItems().filter { $0.keyEquivalent == "d" && $0.keyEquivalentModifierMask == [.command] }
    XCTAssertEqual(commandD.count, 1, "no other item binds Cmd-D")
  }

  /// #373: a nil-target action whose selector `NSWindow` implements is dead: the window comes before its controller in
  /// the responder chain, so the menu resolves the target to the window and the action goes nowhere. Found with
  /// Cmd-D: `NSWindow` has a private `pinTab:` (window tabbing), which swallowed File > Pin Tab while a text field
  /// held focus and (through the same chain) elsewhere. `toggleSidebarVisibility(_:)` exists for the same reason.
  func testNilTargetWindowItemsDoNotUseSelectorsTheWindowImplements() throws {
    let file = try XCTUnwrap(built.menu.items.first { $0.title == "File" }?.submenu)
    let pin = try XCTUnwrap(file.items.first { $0.title == "Pin Tab" })
    let pinAction = try XCTUnwrap(pin.action)
    XCTAssertFalse(NSWindow.instancesRespond(to: pinAction),
                   "NSWindow implements \(pinAction); Pin Tab would reach the window, not the controller")
    // Every nil-target item meant for the controller: none may be claimed by the window first.
    let controllerItems = allItems().filter {
      $0.target == nil && $0.action.map { ShellWindowController.instancesRespond(to: $0) } == true
    }
    XCTAssertFalse(controllerItems.isEmpty)
    for item in controllerItems {
      let action = try XCTUnwrap(item.action)
      XCTAssertFalse(NSWindow.instancesRespond(to: action),
                     "\(item.title): NSWindow implements \(action), so the controller never receives it")
    }
  }

  /// Decision 9: no menu item names Arc.
  func testNoMenuItemNamesArc() throws {
    let word = try Regex("\\bArc\\b")
    let built = MainMenu.make(commands: AppCommands())
    func walk(_ menu: NSMenu) -> [String] {
      menu.items.flatMap { [$0.title] + ($0.submenu.map(walk) ?? []) }
    }
    for title in walk(built.menu) { XCTAssertNil(title.firstMatch(of: word), title) }
  }
}
