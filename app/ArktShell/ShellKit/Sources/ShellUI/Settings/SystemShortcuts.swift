import AppKit

/// The macOS shortcuts that take a key before any app sees it, at their system defaults (BH-199; spec section 1,
/// "System shortcuts"). The shortcut editor warns "System shortcuts may take priority over this shortcut" for these.
///
/// A static list, not the user's live settings: macOS has no public API that reports the system shortcuts as the
/// characters the recorder stores (Carbon's `CopySymbolicHotKeys` returns key codes, read from the user's
/// preferences, that would need translating through the current layout). The warning says "may", so a shortcut the
/// user turned off in System Settings still warns. Arkt binds some of these keys itself: Ctrl-Space (Reveal Current
/// Tab, KB-036) and Ctrl-1 ... Ctrl-9 (Go to Space, KB-035).
@MainActor
public enum SystemShortcuts {
  /// Input sources, Mission Control, Spotlight, screenshots, the app switcher and Lock Screen.
  static let bindings: [ShortcutBinding] = {
    func key(_ scalar: Int) -> String { String(UnicodeScalar(scalar)!) }
    var bindings = [
      ShortcutBinding(key: " ", modifiers: .control),                        // Select the previous input source
      ShortcutBinding(key: " ", modifiers: [.control, .option]),             // Select the next input source
      ShortcutBinding(key: " ", modifiers: .command),                        // Spotlight
      ShortcutBinding(key: " ", modifiers: [.command, .option]),             // Finder search window
      ShortcutBinding(key: "\t", modifiers: .command),                       // App switcher
      ShortcutBinding(key: "\t", modifiers: [.command, .shift]),
      ShortcutBinding(key: "q", modifiers: [.command, .control]),            // Lock Screen
    ]
    // Mission Control, Application windows, Move left / right a space.
    for arrow in [NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey] {
      bindings.append(ShortcutBinding(key: key(arrow), modifiers: .control))
    }
    // Switch to Desktop 1 ... 9.
    bindings += (1...9).map { ShortcutBinding(key: "\($0)", modifiers: .control) }
    // Screenshots: the digit as a menu item stores it, and the character a US layout types with Shift, as the
    // recorder stores it.
    for (digit, shifted) in [("3", "#"), ("4", "$"), ("5", "%")] {
      bindings.append(ShortcutBinding(key: digit, modifiers: [.command, .shift]))
      bindings.append(ShortcutBinding(key: shifted, modifiers: [.command, .shift]))
    }
    return bindings
  }()

  public static func contains(_ binding: ShortcutBinding) -> Bool { bindings.contains(binding) }
}
