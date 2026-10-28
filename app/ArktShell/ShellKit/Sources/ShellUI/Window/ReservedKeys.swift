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
///
/// The digit row and the punctuation keys (`matchesKeyCode`) also match by key code on every layout: AZERTY types
/// "&" on the 1 key and QWERTZ types "-" on the slash key, so the typed character is not the menu's key. Matching
/// more than the menu does is harmless, because a reserved key only goes to the main menu first and the menu
/// decides; matching less drops the key when a page has focus (#497).
public struct ReservedKeys: Sendable {
  public struct Key: Hashable, Sendable {
    public let keyCode: UInt16
    /// The lowercase character the key types without modifiers; empty for keys that type none (arrows).
    public let character: String
    /// Device-independent modifiers, `.function` and `.numericPad` excluded.
    public let modifiers: UInt
    /// Whether the key code matches whatever the layout types on that key (digit row, punctuation). Letters stay
    /// off: AZERTY's Z key sits where W is, and Cmd-Z there belongs to the page.
    public let matchesKeyCode: Bool

    public init(keyCode: Int, character: String, modifiers: NSEvent.ModifierFlags, matchesKeyCode: Bool = false) {
      self.keyCode = UInt16(keyCode)
      self.character = character
      self.modifiers = modifiers.rawValue
      self.matchesKeyCode = matchesKeyCode
    }
  }

  public let keys: [Key]

  public init(_ keys: [Key]) { self.keys = keys }

  /// Cmd-T, Shift-Cmd-T (Reopen Closed Tab, KB-010, #346), Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q, Cmd-D (KB-012,
  /// #108), Shift-Cmd-K (Clear Today Tabs, KB-019, #110), Cmd-Opt-Right, Cmd-Opt-Left, and the tab switcher's
  /// Ctrl-Tab and Ctrl-Shift-Tab (#103; `ShellWindow.sendEvent` already hands those to the switcher before any view).
  /// The copy-link keys (KB-013 to KB-016, #118) are here too: a page must not swallow them. Incognito
  /// (Shift-Cmd-N) joins when Arkt has it. Cmd-Z stays the page's first (`ReopenUndoRouter`).
  ///
  /// #489: every main-menu key equivalent without Cmd is reserved too: Space 1 to 9 (Ctrl-1 ... Ctrl-9) and the Split
  /// View items (Ctrl-Shift-=, -, ], [, 1 ... 4). A focused page takes any key equivalent first, and the engine hands
  /// only the Cmd keys it did not use back to the menu (`ArktBrowserWindow::HandleKeyboardEvent`), so without this a
  /// page that has focus (after every reload) drops them.
  public static let arkt = ReservedKeys([
    Key(keyCode: kVK_ANSI_T, character: "t", modifiers: .command),
    Key(keyCode: kVK_ANSI_T, character: "t", modifiers: [.command, .shift]),
    Key(keyCode: kVK_ANSI_L, character: "l", modifiers: .command),
    Key(keyCode: kVK_ANSI_W, character: "w", modifiers: .command),
    Key(keyCode: kVK_ANSI_W, character: "w", modifiers: [.command, .shift]),
    Key(keyCode: kVK_ANSI_N, character: "n", modifiers: .command),
    Key(keyCode: kVK_ANSI_Q, character: "q", modifiers: .command),
    Key(keyCode: kVK_ANSI_D, character: "d", modifiers: .command),
    Key(keyCode: kVK_ANSI_C, character: "c", modifiers: [.command, .shift]),             // KB-013
    Key(keyCode: kVK_ANSI_C, character: "c", modifiers: [.command, .shift, .option]),    // KB-014
    Key(keyCode: kVK_ANSI_C, character: "c", modifiers: [.command, .shift, .control]),   // KB-015
    Key(keyCode: kVK_ANSI_V, character: "v", modifiers: [.command, .option]),            // KB-016
    Key(keyCode: kVK_ANSI_K, character: "k", modifiers: [.command, .shift]),             // KB-019 (#110)
    Key(keyCode: kVK_RightArrow, character: "", modifiers: [.command, .option]),
    Key(keyCode: kVK_LeftArrow, character: "", modifiers: [.command, .option]),
    Key(keyCode: kVK_Tab, character: "", modifiers: .control),
    Key(keyCode: kVK_Tab, character: "", modifiers: [.control, .shift]),
  ] + spaceKeys + splitKeys)

  /// Ctrl-1 ... Ctrl-9 (KB-035, BH-041: `SpacesMenu`).
  private static let spaceKeys: [Key] = digits.map {
    Key(keyCode: $0.code, character: $0.character, modifiers: .control, matchesKeyCode: true)
  }

  /// Ctrl-Shift-=, -, ], [ and Ctrl-Shift-1 ... 4 (KB-070 to KB-072: `SplitMenu`): the unshifted US characters, and
  /// the US key codes on any layout (#497).
  private static let splitKeys: [Key] = (
    [(kVK_ANSI_Equal, "="), (kVK_ANSI_Minus, "-"), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_LeftBracket, "[")]
      + digits.prefix(4).map { ($0.code, $0.character) }
  ).map { Key(keyCode: $0.0, character: $0.1, modifiers: [.control, .shift], matchesKeyCode: true) }

  private static let digits: [(code: Int, character: String)] = [
    (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
    (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
  ]

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
      if key.matchesKeyCode, key.keyCode == keyCode { return true }
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
