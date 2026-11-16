import AppKit
import Testing
@testable import ShellUI

/// BH-199: the editor warns when a recorded key is one macOS takes first. The list is static (spec section 1,
/// "System shortcuts"), so the check never reads the user's keyboard preferences.
@MainActor
struct SystemShortcutsTests {
  private func key(_ scalar: Int) -> String { String(UnicodeScalar(scalar)!) }

  @Test func inputSourceSwitchingKeysAreSystemShortcuts() {
    #expect(SystemShortcuts.contains(ShortcutBinding(key: " ", modifiers: .control)))
    #expect(SystemShortcuts.contains(ShortcutBinding(key: " ", modifiers: [.control, .option])))
  }

  @Test func missionControlDesktopKeysAreSystemShortcuts() {
    for digit in 1...9 {
      #expect(SystemShortcuts.contains(ShortcutBinding(key: "\(digit)", modifiers: .control)), "Control \(digit)")
    }
    for arrow in [NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey] {
      #expect(SystemShortcuts.contains(ShortcutBinding(key: key(arrow), modifiers: .control)))
    }
  }

  @Test func spotlightScreenshotsAndTheAppSwitcherAreSystemShortcuts() {
    #expect(SystemShortcuts.contains(ShortcutBinding(key: " ", modifiers: .command)))
    #expect(SystemShortcuts.contains(ShortcutBinding(key: " ", modifiers: [.command, .option])))
    #expect(SystemShortcuts.contains(ShortcutBinding(key: "\t", modifiers: .command)))
    // The recorder stores what the key types with Shift held: "#" on a US layout, "3" from a menu item.
    for (shifted, digit) in [("#", "3"), ("$", "4"), ("%", "5")] {
      #expect(SystemShortcuts.contains(ShortcutBinding(key: shifted, modifiers: [.command, .shift])))
      #expect(SystemShortcuts.contains(ShortcutBinding(key: digit, modifiers: [.command, .shift])))
    }
    #expect(SystemShortcuts.contains(ShortcutBinding(key: "q", modifiers: [.command, .control])))
  }

  @Test func appKeysAndNearMissesAreNotSystemShortcuts() {
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: "t", modifiers: .command)))
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: "1", modifiers: .command)))
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: "1", modifiers: [.control, .shift])))
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: "0", modifiers: .control)))
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: " ", modifiers: [.control, .shift])))
    #expect(!SystemShortcuts.contains(ShortcutBinding(key: "k", modifiers: [.control, .option])))
  }

  /// Settings uses the list unless a caller injects another source.
  @Test func settingsServicesCheckTheListByDefault() {
    let services = SettingsServices()
    #expect(services.isSystemShortcut(ShortcutBinding(key: "2", modifiers: .control)))
    #expect(!services.isSystemShortcut(ShortcutBinding(key: "t", modifiers: .command)))
  }
}
