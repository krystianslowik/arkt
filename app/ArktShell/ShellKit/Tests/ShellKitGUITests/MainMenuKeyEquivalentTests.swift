import AppKit
import Carbon.HIToolbox
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
  /// Every item of the real main menu, submenus included.
  private func allItems() -> [NSMenuItem] {
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

  // MARK: Split View (S5)

  /// RT-38 (passive read, #78): Arc's View menu holds these four directly, with these titles and keys.
  func testSplitViewItemsSitInTheViewMenuWithArcsKeys() throws {
    _ = NSApplication.shared
    let windowsMenu = NSApp.windowsMenu
    defer { NSApp.windowsMenu = windowsMenu }
    let view = try XCTUnwrap(MainMenu.make().items.first { $0.title == "View" }?.submenu)
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

  /// Whether `item`'s key equivalent alone takes `event`: a one-item menu with the same key, aimed at a probe.
  private static func matches(_ item: NSMenuItem, _ event: NSEvent) -> Bool {
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
