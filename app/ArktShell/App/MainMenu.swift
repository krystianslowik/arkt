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
      .separator(),
      item("Import from Arc...", #selector(AppDelegate.importFromArc(_:)), "", []),       // E4c, no shortcut
    ]))
    // KB-033, KB-034 (Cmd-Opt-Right / Left) and KB-035, BH-041 (Ctrl-1 ... Ctrl-9).
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    var spaces: [NSMenuItem] = [
      item("Next Space", #selector(ShellWindowController.nextSpace(_:)), right, [.command, .option]),
      item("Previous Space", #selector(ShellWindowController.previousSpace(_:)), left, [.command, .option]),
      .separator(),
    ]
    for n in 1...9 {
      let space = item("Space \(n)", #selector(ShellWindowController.goToSpace(_:)), "\(n)", [.control])
      space.tag = n - 1
      spaces.append(space)
    }
    main.addItem(submenu(title: "Spaces", items: spaces))
    // KB-018, BH-032: Cmd-Shift-D. ShellWindowController.validateMenuItem titles it Show / Hide Toolbar.
    main.addItem(submenu(title: "View", items: [
      item("Show Toolbar", #selector(ShellWindowController.toggleToolbar(_:)), "D"),
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
