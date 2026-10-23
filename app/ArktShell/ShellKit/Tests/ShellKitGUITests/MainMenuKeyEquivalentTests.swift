import AppKit
import XCTest
@testable import ShellUI

/// Stands in for the app target's `AppDelegate` so the real `App/MainMenu.swift` (linked into this target as
/// `MainMenu.swift`) compiles here; only its action selectors are needed.
@MainActor
final class AppDelegate: NSObject {
  @objc func importFromArc(_ sender: Any?) {}
  @objc func showArchive(_ sender: Any?) {}
}

/// `CommandBarPanel.sendEvent` takes Cmd-Return and Opt-Return before anything else in the panel (KB-085). That
/// hides no menu action only while no menu item binds those keys, so the real main menu is built and checked.
@MainActor
final class MainMenuKeyEquivalentTests: XCTestCase {
  func testNoMenuItemBindsCommandOrOptionReturn() {
    _ = NSApplication.shared
    let windowsMenu = NSApp.windowsMenu
    defer { NSApp.windowsMenu = windowsMenu }   // make() sets it
    var items: [NSMenuItem] = []
    func collect(_ menu: NSMenu) {
      for item in menu.items {
        items.append(item)
        if let submenu = item.submenu { collect(submenu) }
      }
    }
    collect(MainMenu.make())
    XCTAssertTrue(items.contains { $0.keyEquivalent == "t" && $0.action == #selector(ShellWindowController.newTab(_:)) },
                  "the app's menu was built")
    let returnKeys: Set<String> = ["\r", "\n", "\u{3}"]                  // Return, newline, keypad Enter
    for item in items where returnKeys.contains(item.keyEquivalent) {
      XCTAssertTrue(item.keyEquivalentModifierMask.isDisjoint(with: [.command, .option]),
                    "\(item.title) binds Cmd- or Opt-Return, which the command bar takes first")
    }
  }
}
