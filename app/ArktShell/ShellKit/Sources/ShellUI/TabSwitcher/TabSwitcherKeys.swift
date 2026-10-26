import AppKit
import Carbon.HIToolbox

/// What a raw key event does to the switcher.
public enum TabSwitcherKeyAction: Equatable, Sendable {
  /// Not the switcher's: the event goes on as usual.
  case pass
  /// Ctrl-Tab or Ctrl-Shift-Tab with the switcher closed.
  case open(TabSwitcherSession.Direction)
  /// Tab, Shift-Tab or Ctrl-` while open.
  case move(TabSwitcherSession.Direction)
  /// W while open (BH-010, KB-025).
  case closeHighlighted
  /// Esc while open: stay on the current tab.
  case cancel
  /// Ctrl released while open: show the highlighted tab.
  case commit
  /// Any other key while open: the switcher closes as a cancel and the key is handled normally (so Cmd-W while
  /// cycling closes the current tab).
  case dismissThenPass
}

/// The switcher is a modifier-held overlay driven by raw events: it opens on the Ctrl-Tab key-down and lives as long
/// as Ctrl stays down (`flagsChanged`). While it is open, Tab, Shift-Tab, backtick, W and Esc are swallowed.
public enum TabSwitcherKeys {
  /// The modifiers compared: Cmd, Shift, Option and Control (Caps Lock and the function flag change nothing).
  static func significant(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.command, .shift, .option, .control])
  }

  /// `character` is what the key types without modifiers. W matches by that character when the layout types an ASCII
  /// letter there (AZERTY's W key types "z" and does not close), and by key code otherwise (a Cyrillic layout).
  public static func action(forKeyDown keyCode: UInt16, character: String?, modifiers: NSEvent.ModifierFlags,
                            isOpen: Bool) -> TabSwitcherKeyAction {
    let flags = significant(modifiers)
    let isTab = keyCode == UInt16(kVK_Tab)
    guard isOpen else {
      guard isTab else { return .pass }
      switch flags {
      case [.control]: return .open(.forward)
      case [.control, .shift]: return .open(.backward)
      default: return .pass
      }
    }
    if flags.contains(.command) || flags.contains(.option) { return .dismissThenPass }
    if isTab { return .move(flags.contains(.shift) ? .backward : .forward) }
    if keyCode == UInt16(kVK_ANSI_Grave) { return .move(.backward) }
    if keyCode == UInt16(kVK_Escape) { return .cancel }
    if isW(keyCode: keyCode, character: character) { return .closeHighlighted }
    return .dismissThenPass
  }

  /// Ctrl going up while the switcher is open commits.
  public static func action(forFlagsChanged modifiers: NSEvent.ModifierFlags, isOpen: Bool) -> TabSwitcherKeyAction {
    isOpen && !modifiers.contains(.control) ? .commit : .pass
  }

  /// `event` as an action, for key-down and flags-changed events; everything else passes.
  public static func action(for event: NSEvent, isOpen: Bool) -> TabSwitcherKeyAction {
    switch event.type {
    case .keyDown:
      action(forKeyDown: event.keyCode, character: event.characters(byApplyingModifiers: []),
             modifiers: event.modifierFlags, isOpen: isOpen)
    case .flagsChanged:
      action(forFlagsChanged: event.modifierFlags, isOpen: isOpen)
    default:
      .pass
    }
  }

  private static func isW(keyCode: UInt16, character: String?) -> Bool {
    let character = character?.lowercased() ?? ""
    let typesASCII = character.unicodeScalars.count == 1 && character.unicodeScalars.allSatisfy(\.isASCII)
    return typesASCII ? character == "w" : keyCode == UInt16(kVK_ANSI_W)
  }
}
