import AppKit
import XCTest
@testable import ShellUI

/// The Tabs menu (#103) in the real main menu: its keys, actions and Cmd-} / Cmd-{ hidden aliases.
@MainActor
final class TabsMenuTests: XCTestCase {
  private func tabsMenu() throws -> NSMenu {
    _ = NSApplication.shared
    let main = MainMenu.make(commands: AppCommands()).menu
    let titles = main.items.map(\.title)
    let spaces = try XCTUnwrap(titles.firstIndex(of: "Spaces"))
    XCTAssertEqual(titles[spaces + 1], TabsMenu.title, "Tabs follows Spaces")
    return try XCTUnwrap(main.items[spaces + 1].submenu)
  }

  func testTheTabsMenuBindsTheKeyboardNavigationKeys() throws {
    let menu = try tabsMenu()
    let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    let expected: [(Selector, String, NSEvent.ModifierFlags)] = [
      (#selector(ShellWindowController.nextSidebarTab(_:)), down, [.command, .option]),
      (#selector(ShellWindowController.previousSidebarTab(_:)), up, [.command, .option]),
      (#selector(ShellWindowController.nextSidebarTab(_:)), "}", [.command]),
      (#selector(ShellWindowController.previousSidebarTab(_:)), "{", [.command]),
      (#selector(ShellWindowController.cycleRecentTabForward(_:)), right, [.command, .control]),
      (#selector(ShellWindowController.cycleRecentTabBackward(_:)), left, [.command, .control]),
      (#selector(ShellWindowController.revealCurrentTab(_:)), " ", [.control]),
    ]
    for (action, key, modifiers) in expected {
      let item = menu.items.first { $0.action == action && $0.keyEquivalent == key }
      XCTAssertNotNil(item, "\(action) on \(key)")
      XCTAssertEqual(item?.keyEquivalentModifierMask, modifiers, "\(action)")
      XCTAssertNil(item?.target, "reaches the window controller through the responder chain")
    }
    let aliases = menu.items.filter(\.isHidden)
    XCTAssertEqual(aliases.map(\.keyEquivalent), ["}", "{"])
    XCTAssertTrue(aliases.allSatisfy(\.allowsKeyEquivalentWhenHidden))
  }

  func testCommandOneToNineCarryTheirNumberAsTag() throws {
    let menu = try tabsMenu()
    let goTo = menu.items.filter { $0.action == #selector(ShellWindowController.goToSidebarItem(_:)) }
    XCTAssertEqual(goTo.map(\.keyEquivalent), (1...9).map(String.init))
    XCTAssertEqual(goTo.map(\.tag), Array(1...9))
    XCTAssertEqual(goTo.last?.title, "Go to Last Sidebar Item")
    XCTAssertTrue(goTo.allSatisfy { $0.keyEquivalentModifierMask == [.command] })
  }

  /// No other item of the main menu takes the new keys.
  func testNoOtherItemBindsTheTabsMenuKeys() throws {
    let menu = try tabsMenu()
    let ours = Set(menu.items.map { "\($0.keyEquivalent)|\($0.keyEquivalentModifierMask.rawValue)" })
    var all: [NSMenuItem] = []
    func collect(_ menu: NSMenu) {
      for item in menu.items {
        all.append(item)
        if let submenu = item.submenu { collect(submenu) }
      }
    }
    collect(MainMenu.make(commands: AppCommands()).menu)
    let others = all.filter { $0.menu?.title != TabsMenu.title && !$0.keyEquivalent.isEmpty }
    for item in others {
      XCTAssertFalse(ours.contains("\(item.keyEquivalent)|\(item.keyEquivalentModifierMask.rawValue)"), item.title)
    }
  }
}
