import AppKit
import EngineAPI
import ShellUI

/// Arkt's main menu, the same in both builds (week-3 plan, W3-7 part D; week-3 results, W3-8 step 3). Only the
/// install point differs: the FakeEngine build installs it at launch (`AppDelegate`), the Engine build one turn after
/// `NSApplicationDidFinishLaunchingNotification`, after Chromium's `AppController` handled it.
///
/// Rules from W3-8, which Chromium's menu code depends on:
/// - App-level items have explicit targets: About, Hide, Hide Others, Show All, Bring All to Front and Quit target
///   `NSApp`; New Window, Settings, Import from Arc and Show Archive target the composition root's `AppCommands`.
///   A nil-target app item would reach `AppController` (the engine build's `NSApp.delegate`) and run Chromium's
///   behaviour.
/// - Quit is `terminate:` to `NSApp` with tag `IDC_EXIT`, in the first top-level menu (the confirm-to-quit panel looks
///   for it there).
/// - No top-level `IDC_FILE_MENU`, `IDC_TAB_MENU` or `IDC_HISTORY_MENU` tag (AppController would rewrite Cmd-W and
///   Shift-Cmd-W or fill Arkt's menus with Chromium's rows), and a hidden `IDC_BOOKMARKS_MENU` placeholder with an
///   empty submenu (without it the first window that becomes main crashes the engine).
/// - Page commands are `commandDispatch:` items with a nil target and the `EngineCommand` id as tag: the key
///   `ShellWindow` forwards them to its host, which runs the ones the shell claims and passes the rest to the engine.
@MainActor
enum MainMenu {
  /// The menu and the submenus `NSApp` must point at.
  struct Built {
    let menu: NSMenu
    let services: NSMenu
    let windows: NSMenu
    let help: NSMenu
  }

  /// Chromium's tags (`chrome/app/chrome_command_ids.h`; week-3 results, W3-0 step 5 and W3-8).
  enum Tag {
    static let exit = EngineCommand.exit.rawValue          // IDC_EXIT, 34031
    static let bookmarksMenu = 57333                       // IDC_BOOKMARKS_MENU
  }

  /// Sets the main menu and points `servicesMenu`, `windowsMenu` and `helpMenu` into it. Chromium's values point into
  /// its own menu after the swap, so all three are set on every install. AppKit keeps the first Services menu it was
  /// given (a later `servicesMenu` assignment is ignored), so a Services menu that exists already is moved into
  /// Arkt's App menu instead of replaced.
  static func install(commands: AppCommands) {
    let built = make(commands: commands)
    if let current = NSApp.servicesMenu, current !== built.services,
       let holder = built.menu.items.first?.submenu?.items.first(where: { $0.submenu === built.services }) {
      current.supermenu?.items.first { $0.submenu === current }?.submenu = nil
      holder.submenu = current
    }
    NSApp.mainMenu = built.menu
    NSApp.servicesMenu = built.menu.items.first?.submenu?.items.first { $0.title == "Services" }?.submenu
    NSApp.windowsMenu = built.windows
    NSApp.helpMenu = built.help
  }

  static func make(commands: AppCommands) -> Built {
    let main = NSMenu()
    let services = NSMenu(title: "Services")
    let windows = NSMenu(title: "Window")
    let help = NSMenu(title: "Help")
    main.addItem(submenu(title: "Arkt Shell", items: appItems(commands: commands, services: services)))
    main.addItem(submenu(title: "File", items: fileItems(commands: commands)))
    main.addItem(submenu(title: "Edit", items: editItems(commands: commands)))
    main.addItem(submenu(title: "View", items: viewItems()))
    main.addItem(submenu(title: "History", items: historyItems()))
    main.addItem(holder(for: spacesMenu()))                                            // #387, built in ShellUI
    main.addItem(submenu(title: TabsMenu.title, items: TabsMenu.items()))               // #103, built in ShellUI
    windowItems(commands: commands).forEach { windows.addItem($0) }
    // Onboarding spec, section 12: the first Help item, no shortcut.
    help.addItem(item("Welcome to Arkt", #selector(AppCommands.showWelcome(_:)), "", [], target: commands))
    main.addItem(holder(for: windows))
    main.addItem(holder(for: help))
    main.addItem(bookmarksPlaceholder())
    return Built(menu: main, services: services, windows: windows, help: help)
  }

  // MARK: - Menus

  private static func appItems(commands: AppCommands, services: NSMenu) -> [NSMenuItem] {
    let quit = item("Quit Arkt Shell", #selector(NSApplication.terminate(_:)), "q", target: NSApp)   // KB-069
    quit.tag = Tag.exit
    return [
      item("About Arkt Shell", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", [], target: NSApp),
      .separator(),
      // KB-066: Arkt's Settings window (#307); it keeps Cmd-, from Chromium's settings page (decision 9).
      item("Settings...", #selector(AppCommands.showSettings(_:)), ",", target: commands),
      .separator(),
      holder(for: services),
      .separator(),
      item("Hide Arkt Shell", #selector(NSApplication.hide(_:)), "h", target: NSApp),                // KB-069
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option],
           target: NSApp),
      item("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", [], target: NSApp),
      .separator(),
      quit,
    ]
  }

  /// Target nil for the window items: with the bar key, AppKit still walks the main window's chain to
  /// `ShellWindowController` and `ShellWindow`.
  private static func fileItems(commands: AppCommands) -> [NSMenuItem] {
    [
      item("New Tab", #selector(ShellWindowController.newTab(_:)), "t"),                  // KB-001
      item("New Window", #selector(AppCommands.newWindow(_:)), "n", target: commands),   // KB-005
      item("Open Command Bar", #selector(ShellWindowController.openLocation(_:)), "l"),    // KB-002
      .separator(),
      item("Archive Tab", #selector(ShellWindowController.closeTab(_:)), "w"),             // KB-008
      // KB-010, BH-074 (#346): also reopens a closed Peek. PARITY(NEEDS-RUNTIME-CHECK): Arc's title and place.
      item("Reopen Closed Tab", #selector(ShellWindowController.reopenClosedTab(_:)), "t", [.command, .shift]),
      // KB-019, BH-075 (#110): the current Space's Today tabs go to the Archive; no row plays media (BH-076).
      item("Clear Today Tabs", #selector(ShellWindowController.clearTodayTabs(_:)), "k", [.command, .shift]),
      item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]), // KB-009
      .separator(),
      item("Pin Tab", #selector(ShellWindowController.pinCurrentTab(_:)), "d"),             // KB-012, BH-055
      // KB-041 (unbound in Arc), BH-057; enabled for a navigated pinned tab.
      item("Back to Pinned URL", #selector(ShellWindowController.resetTab(_:)), ""),
      .separator(),
      page("Save Page As...", .savePage, "s", [.command, .shift]),                         // KB-060 (Arc's key)
      page("Print...", .print, "p"),                                                       // KB-060
      .separator(),
      item("Import Browser Data...", #selector(AppCommands.importFromArc(_:)), "", [], target: commands),   // E4c
    ]
  }

  /// Undo targets the router (KB-011): it reopens a closed tab or Peek when no text is being edited, and otherwise
  /// sends `undo:` down the responder chain as a nil-target item would.
  private static func editItems(commands: AppCommands) -> [NSMenuItem] {
    let find = submenu(title: "Find", items: [
      page("Find...", .find, "f"),                                                         // KB-058
      page("Find Next", .findNext, "g"),                                                   // KB-059
      page("Find Previous", .findPrevious, "g", [.command, .shift]),                       // KB-059
      .separator(),
      item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"),   // KB-058
    ])
    return [
      item("Undo", #selector(ReopenUndoRouter.undo(_:)), "z", target: commands.undoRouter),
      item("Redo", Selector(("redo:")), "Z"),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
      .separator(),
      // #118: the copy-link actions (KB-013 to KB-016). The keys are reserved (ReservedKeys) so a page cannot
      // swallow them.
      item("Copy URL", #selector(ShellWindowController.copyCurrentURL(_:)), "c", [.command, .shift]),
      item("Copy URL as Markdown", #selector(ShellWindowController.copyCurrentURLAsMarkdown(_:)), "c",
           [.command, .shift, .option]),
      item("Copy URL as Quote", #selector(ShellWindowController.copyCurrentURLAsQuote(_:)), "c",
           [.command, .shift, .control]),
      item("Paste URL as New Tab", #selector(ShellWindowController.pasteURLAsNewTab(_:)), "v", [.command, .option]),
      .separator(),
      find,
    ]
  }

  /// KB-017, BH-001: Cmd-S and KB-018, BH-032: Cmd-Shift-D (`ShellWindowController.validateMenuItem` titles them
  /// Show / Hide Sidebar and Show / Hide Toolbar). Split View
  /// (S5): Arc's four View menu items plus a Split View submenu, built by ShellUI's SplitMenu.
  private static func viewItems() -> [NSMenuItem] {
    let developer = submenu(title: "Developer", items: [                                   // KB-049, KB-050
      page("View Source", .viewSource, "u", [.command, .option]),
      page("Developer Tools", .devTools, "i", [.command, .option]),
      page("Inspect Elements", .inspect, "c", [.command, .option]),
      page("JavaScript Console", .console, "j", [.command, .option]),
    ])
    return [
      item("Hide Sidebar", #selector(ShellWindowController.toggleSidebarVisibility(_:)), "s"),
      item("Show Toolbar", #selector(ShellWindowController.toggleToolbar(_:)), "D"),
      .separator(),
    ] + SplitMenu.items() + [
      .separator(),
      page("Stop", .stop, "."),                                                            // KB-054
      page("Reload This Page", .reload, "r"),                                              // KB-056
      page("Force Reload This Page", .reloadBypassingCache, "r", [.command, .shift]),
      .separator(),
      page("Actual Size", .zoomReset, "0"),                                                // KB-057
      page("Zoom In", .zoomIn, "+"),
      page("Zoom Out", .zoomOut, "-"),
      .separator(),
      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),   // KB-051
      .separator(),
      developer,
    ]
  }

  /// No `IDC_HISTORY_MENU` tag: Chromium's HistoryMenuBridge would fill it with its own rows. Cmd-Left and Cmd-Right
  /// are not menu keys (a menu item would take them from text fields).
  private static func historyItems() -> [NSMenuItem] {
    [
      page("Back", .back, "["),                                                            // KB-031
      page("Forward", .forward, "]"),                                                      // KB-032
      .separator(),
      page("Show All History", .history, "y"),                                             // KB-065
    ]
  }

  /// KB-033, KB-034 (Cmd-Opt-Right / Left). The Spaces themselves, with KB-035, BH-041 (Ctrl-1 ... Ctrl-9), are
  /// listed by `SpacesMenu` between these items (#387).
  private static func spacesMenu() -> SpacesMenu {
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    // #106: New Space is unbound (KB-043); Rename and Move are [I], PARITY(NEEDS-RUNTIME-CHECK): Arc's titles and place.
    let leading: [NSMenuItem] = [
      item("New Space", #selector(ShellWindowController.newSpace(_:)), "", []),
      item("Rename Space", #selector(ShellWindowController.renameSpace(_:)), "", []),
      item("Move Space Left", #selector(ShellWindowController.moveSpaceLeft(_:)), "", []),
      item("Move Space Right", #selector(ShellWindowController.moveSpaceRight(_:)), "", []),
      // BH-059: every navigated pinned tab of the current Space returns to its pinned URL.
      item("Reset Space", #selector(ShellWindowController.resetSpace(_:)), "", []),
      .separator(),
      item("Next Space", #selector(ShellWindowController.nextSpace(_:)), right, [.command, .option]),
      item("Previous Space", #selector(ShellWindowController.previousSpace(_:)), left, [.command, .option]),
    ]
    // #206, decision on #86: asks, then archives the Space's items. PARITY(NEEDS-RUNTIME-CHECK): Arc's title and place.
    let trailing = [.separator(), item("Delete Space...", #selector(ShellWindowController.deleteSpace(_:)), "", [])]
    return SpacesMenu(leading: leading, trailing: trailing)
  }

  /// AppKit lists the open windows (the Archive window among them) below these (`NSApp.windowsMenu`).
  private static func windowItems(commands: AppCommands) -> [NSMenuItem] {
    [
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),                   // KB-069
      item("Zoom", #selector(NSWindow.performZoom(_:)), "", []),
      .separator(),
      page("Downloads", .downloads, "j", [.command, .shift]),                              // KB-065
      // KB-043: Show Archive is unbound by default; Cmd-Shift-L stays reserved for the Library (KB-065).
      item("Show Archive", #selector(AppCommands.showArchive(_:)), "", [], target: commands),
      // BH-087, KB-043: unbound; opens the Archive window and asks there (#111).
      item("Clear Archive...", #selector(AppCommands.clearArchive(_:)), "", [], target: commands),
      .separator(),
      item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "", [], target: NSApp),
    ]
  }

  /// Hidden, with an empty submenu: Chromium's BookmarkMenuBridge takes it over (W3-8, condition 1).
  private static func bookmarksPlaceholder() -> NSMenuItem {
    let placeholder = holder(for: NSMenu(title: "Bookmarks"))
    placeholder.tag = Tag.bookmarksMenu
    placeholder.isHidden = true
    return placeholder
  }

  // MARK: - Items

  static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    return holder(for: menu)
  }

  /// The item that opens `menu`, titled like it.
  static func holder(for menu: NSMenu) -> NSMenuItem {
    let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    holder.submenu = menu
    return holder
  }

  static func item(_ title: String, _ action: Selector, _ key: String,
                   _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = target
    return item
  }

  /// A page command: `commandDispatch:`, nil target, the command's id as tag.
  static func page(_ title: String, _ command: EngineCommand, _ key: String,
                   _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = item(title, #selector(ShellWindow.commandDispatch(_:)), key, modifiers)
    item.tag = command.rawValue
    return item
  }
}
