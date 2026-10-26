import AppKit
import Carbon.HIToolbox

/// The shortcuts Arkt handles before the page sees them (week-3 results, W3-8 step 3, "Reserved keys"): the Arkt
/// items whose keys Chromium reserves for the same purpose (new tab, close tab, close window, new window, quit,
/// next and previous tab), plus Cmd-L. `ShellWindow.performKeyEquivalent(with:)` checks them before the focused view
/// (a web page takes every key equivalent first), so a page cannot swallow Cmd-W or Cmd-Q.
///
/// A key that types an ASCII character matches by that character, so a layout that moves the letter (AZERTY's Z on
/// the W key, Dvorak's Y on the T key) reserves its own W and leaves Cmd-Z and Cmd-Y to the page. A key that types
/// no ASCII character (a Cyrillic layout) matches by its virtual key code (`kVK_ANSI_W` for the W key), as the main
/// menu does for such layouts. Keys without a character (arrows) match by key code. Modifiers must match exactly:
/// Shift-Cmd-T is not Cmd-T.
public struct ReservedKeys: Sendable {
  public struct Key: Hashable, Sendable {
    public let keyCode: UInt16
    /// The lowercase character the key types without modifiers; empty for keys that type none (arrows).
    public let character: String
    /// Device-independent modifiers, `.function` and `.numericPad` excluded.
    public let modifiers: UInt

    public init(keyCode: Int, character: String, modifiers: NSEvent.ModifierFlags) {
      self.keyCode = UInt16(keyCode)
      self.character = character
      self.modifiers = modifiers.rawValue
    }
  }

  public let keys: [Key]

  public init(_ keys: [Key]) { self.keys = keys }

  /// Cmd-T, Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q, Cmd-D (KB-012, #108), Cmd-Opt-Right, Cmd-Opt-Left. Reopen
  /// (Shift-Cmd-T), the tab switcher (Ctrl-Tab) and Incognito (Shift-Cmd-N) join when Arkt has them.
  public static let arkt = ReservedKeys([
    Key(keyCode: kVK_ANSI_T, character: "t", modifiers: .command),
    Key(keyCode: kVK_ANSI_L, character: "l", modifiers: .command),
    Key(keyCode: kVK_ANSI_W, character: "w", modifiers: .command),
    Key(keyCode: kVK_ANSI_W, character: "w", modifiers: [.command, .shift]),
    Key(keyCode: kVK_ANSI_N, character: "n", modifiers: .command),
    Key(keyCode: kVK_ANSI_Q, character: "q", modifiers: .command),
    Key(keyCode: kVK_ANSI_D, character: "d", modifiers: .command),
    Key(keyCode: kVK_RightArrow, character: "", modifiers: [.command, .option]),
    Key(keyCode: kVK_LeftArrow, character: "", modifiers: [.command, .option]),
  ])

  /// The modifiers a key equivalent is compared on: Cmd, Shift, Option and Control. Arrow keys also carry
  /// `.function` and `.numericPad`, and Caps Lock changes nothing.
  static func significant(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.command, .shift, .option, .control])
  }

  /// Whether a key press with this key code, unmodified character and modifiers is reserved.
  public func matches(keyCode: UInt16, character: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
    let flags = Self.significant(modifiers).rawValue
    let character = character?.lowercased() ?? ""
    let typesASCII = character.unicodeScalars.count == 1 && character.unicodeScalars.allSatisfy(\.isASCII)
    return keys.contains { key in
      guard key.modifiers == flags else { return false }
      guard !key.character.isEmpty, typesASCII else { return key.keyCode == keyCode }
      return key.character == character
    }
  }

  /// Whether `event` is a reserved key press. Only key-down events match.
  public func matches(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    return matches(keyCode: event.keyCode, character: Self.unmodifiedCharacter(of: event),
                   modifiers: event.modifierFlags)
  }

  /// The character the key types without Cmd, Option or Control (Shift kept off too, so Shift-Cmd-W gives "w").
  private static func unmodifiedCharacter(of event: NSEvent) -> String? {
    event.characters(byApplyingModifiers: [])
  }
}
