import AppKit
import ShellUI

@MainActor
enum MainMenu {
  static func make() -> NSMenu {
    let main = NSMenu()
    main.addItem(submenu(title: "Arkt Shell", items: [
      item("Quit Arkt Shell", #selector(NSApplication.terminate(_:)), "q"),
    ]))
    // Target nil: with the bar key, AppKit still walks the main window's chain to ShellWindowController.
    main.addItem(submenu(title: "File", items: [
      item("New Tab", #selector(ShellWindowController.newTab(_:)), "t"),                  // KB-001
      item("Open Command Bar", #selector(ShellWindowController.openLocation(_:)), "l"),    // KB-002
      item("Archive Tab", #selector(ShellWindowController.closeTab(_:)), "w"),             // KB-008
      .separator(),
      item("Import from Arc...", #selector(AppDelegate.importFromArc(_:)), "", []),       // E4c, no shortcut
    ]))
    main.addItem(submenu(title: "Edit", items: [
      item("Undo", Selector(("undo:")), "z"),
      item("Redo", Selector(("redo:")), "Z"),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ]))
    // KB-018, BH-032: Cmd-Shift-D. ShellWindowController.validateMenuItem titles it Show / Hide Toolbar.
    // Split View (S5): Arc's four View menu items plus a Split View submenu, built by ShellUI's SplitMenu.
    main.addItem(submenu(title: "View", items: [
      item("Show Toolbar", #selector(ShellWindowController.toggleToolbar(_:)), "D"),
      .separator(),
    ] + SplitMenu.items()))
    // KB-033, KB-034 (Cmd-Opt-Right / Left) and KB-035, BH-041 (Ctrl-1 ... Ctrl-9).
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    // #106: New Space is unbound (KB-043); Rename and Move are [I], PARITY(NEEDS-RUNTIME-CHECK): Arc's titles and place.
    var spaces: [NSMenuItem] = [
      item("New Space", #selector(ShellWindowController.newSpace(_:)), "", []),
      item("Rename Space", #selector(ShellWindowController.renameSpace(_:)), "", []),
      item("Move Space Left", #selector(ShellWindowController.moveSpaceLeft(_:)), "", []),
      item("Move Space Right", #selector(ShellWindowController.moveSpaceRight(_:)), "", []),
      .separator(),
      item("Next Space", #selector(ShellWindowController.nextSpace(_:)), right, [.command, .option]),
      item("Previous Space", #selector(ShellWindowController.previousSpace(_:)), left, [.command, .option]),
      .separator(),
    ]
    for n in 1...9 {
      let space = item("Space \(n)", #selector(ShellWindowController.goToSpace(_:)), "\(n)", [.control])
      space.tag = n - 1
      spaces.append(space)
    }
    // #206, decision on #86: asks, then archives the Space's items. PARITY(NEEDS-RUNTIME-CHECK): Arc's title and place.
    spaces += [.separator(), item("Delete Space...", #selector(ShellWindowController.deleteSpace(_:)), "", [])]
    main.addItem(submenu(title: "Spaces", items: spaces))
    // KB-043: Show Archive is unbound by default; Cmd-Shift-L stays reserved for the Library (KB-065).
    let window = submenu(title: "Window", items: [
      item("Show Archive", #selector(AppDelegate.showArchive(_:)), "", []),
    ])
    main.addItem(window)
    // AppKit lists the open windows (the Archive window among them) in the Window menu.
    NSApp.windowsMenu = window.submenu
    return main
  }

  static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
    let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    holder.submenu = menu
    return holder
  }

  static func item(_ title: String, _ action: Selector, _ key: String,
                   _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }
}
