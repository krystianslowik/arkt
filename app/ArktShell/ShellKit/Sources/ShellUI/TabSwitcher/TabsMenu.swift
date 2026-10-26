import AppKit

/// The Tabs menu (#103): keyboard tab navigation. Every item has a nil target and reaches the main window's
/// `ShellWindowController` through the responder chain. The Ctrl-Tab switcher has no item: it is driven by raw key
/// events (`TabSwitcherController`), since a menu key cannot follow Ctrl's release.
/// PARITY(NEEDS-RUNTIME-CHECK): Arc's titles and the place of this menu.
@MainActor
public enum TabsMenu {
  public static let title = "Tabs"

  public static func items() -> [NSMenuItem] {
    let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    var items: [NSMenuItem] = [
      item("Next Tab", #selector(ShellWindowController.nextSidebarTab(_:)), down, [.command, .option]),   // KB-028
      item("Previous Tab", #selector(ShellWindowController.previousSidebarTab(_:)), up, [.command, .option]),  // KB-029
      // KB-030: Cmd-} / Cmd-{ as hidden aliases, still live as keys. PARITY(NEEDS-RUNTIME-CHECK RT-02).
      hiddenAlias("Next Tab", #selector(ShellWindowController.nextSidebarTab(_:)), "}"),
      hiddenAlias("Previous Tab", #selector(ShellWindowController.previousSidebarTab(_:)), "{"),
      .separator(),
      item("Cycle Tab Forward", #selector(ShellWindowController.cycleRecentTabForward(_:)), right,
           [.command, .control]),                                                                // KB-026
      item("Cycle Tab Backward", #selector(ShellWindowController.cycleRecentTabBackward(_:)), left,
           [.command, .control]),                                                                // KB-027
      .separator(),
      item("Reveal Current Tab", #selector(ShellWindowController.revealCurrentTab(_:)), " ", [.control]),  // KB-036
      .separator(),
    ]
    for number in 1...8 {                                                                        // KB-020
      let goTo = item("Go to Sidebar Item \(number)", #selector(ShellWindowController.goToSidebarItem(_:)),
                      "\(number)", [.command])
      goTo.tag = number
      items.append(goTo)
    }
    let last = item("Go to Last Sidebar Item", #selector(ShellWindowController.goToSidebarItem(_:)), "9",
                    [.command])                                                                  // KB-021
    last.tag = 9
    items.append(last)
    return items
  }

  private static func item(_ title: String, _ action: Selector, _ key: String,
                           _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }

  private static func hiddenAlias(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
    let alias = item(title, action, key, [.command])
    alias.isHidden = true
    alias.allowsKeyEquivalentWhenHidden = true
    return alias
  }
}
