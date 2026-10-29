import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShellUI

/// W3-7 part D step 6: the reserved-key matcher (week-3 results, W3-8 step 3, "Reserved keys").
struct ReservedKeysTests {
  private let keys = ReservedKeys.arkt

  @Test(arguments: [
    (kVK_ANSI_T, "t", NSEvent.ModifierFlags.command.rawValue),
    (kVK_ANSI_L, "l", NSEvent.ModifierFlags.command.rawValue),
    (kVK_ANSI_W, "w", NSEvent.ModifierFlags.command.rawValue),
    (kVK_ANSI_W, "w", NSEvent.ModifierFlags([.command, .shift]).rawValue),
    (kVK_ANSI_N, "n", NSEvent.ModifierFlags.command.rawValue),
    (kVK_ANSI_N, "n", NSEvent.ModifierFlags([.command, .shift]).rawValue),    // KB-007 (#487)
    (kVK_ANSI_N, "n", NSEvent.ModifierFlags([.command, .control]).rawValue),  // KB-006 (#487)
    (kVK_ANSI_Q, "q", NSEvent.ModifierFlags.command.rawValue),
    (kVK_ANSI_D, "d", NSEvent.ModifierFlags.command.rawValue),    // KB-012 (#108)
    (kVK_ANSI_T, "t", NSEvent.ModifierFlags([.command, .shift]).rawValue),   // KB-010 (#346): reopen
    (kVK_ANSI_C, "c", NSEvent.ModifierFlags([.command, .shift]).rawValue),             // KB-013 (#118)
    (kVK_ANSI_C, "c", NSEvent.ModifierFlags([.command, .shift, .option]).rawValue),    // KB-014 (#118)
    (kVK_ANSI_C, "c", NSEvent.ModifierFlags([.command, .shift, .control]).rawValue),   // KB-015 (#118)
    (kVK_ANSI_V, "v", NSEvent.ModifierFlags([.command, .option]).rawValue),            // KB-016 (#118)
    (kVK_ANSI_K, "k", NSEvent.ModifierFlags([.command, .shift]).rawValue),             // KB-019 (#110): clear Today
  ])
  func `every reserved letter key matches`(keyCode: Int, character: String, modifiers: UInt) {
    #expect(keys.matches(keyCode: UInt16(keyCode), character: character,
                         modifiers: NSEvent.ModifierFlags(rawValue: modifiers)))
  }

  /// A layout that types other letters keeps the key codes (a Cyrillic layout reports `kVK_ANSI_W` for the W key).
  @Test func `the key code matches whatever the layout types`() {
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "ц", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_Q), character: "й", modifiers: .command))
  }

  /// A layout that moves the letter (AZERTY's Q sits on `kVK_ANSI_A`) still matches by its character.
  @Test func `the character matches on a layout that moves the letter`() {
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_A), character: "q", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_A), character: "Q", modifiers: .command))
  }

  /// AZERTY puts Z and A on the W and Q keys: Cmd-Z (undo in a web editor) and Cmd-A stay the page's.
  @Test func `azerty undo and select all are not reserved`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "z", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Q), character: "a", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_Z), character: "w", modifiers: .command), "AZERTY's own W key")
  }

  /// Dvorak types Y, P and comma on the T, L and W keys: Cmd-Y, Cmd-P and Cmd-, are not reserved.
  @Test func `dvorak keys on reserved key codes are not reserved`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "y", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_L), character: "p", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: ",", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_Comma), character: "w", modifiers: .command), "Dvorak's W key")
  }

  /// A Cyrillic layout types no ASCII letter: the key code decides.
  @Test func `cyrillic layouts match by key code`() {
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "е", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "ц", modifiers: [.command, .shift]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Z), character: "я", modifiers: .command))
  }

  /// Arrow keys arrive with `.function` and `.numericPad`; Caps Lock changes nothing.
  @Test func `space switching arrows match with their extra device flags`() {
    let flags: NSEvent.ModifierFlags = [.command, .option, .function, .numericPad]
    #expect(keys.matches(keyCode: UInt16(kVK_RightArrow), character: nil, modifiers: flags))
    #expect(keys.matches(keyCode: UInt16(kVK_LeftArrow), character: nil, modifiers: flags))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "t", modifiers: [.command, .capsLock]))
  }

  @Test func `extra or missing modifiers do not match`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "t", modifiers: [.command, .option]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "w", modifiers: [.command, .option]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "w", modifiers: [.command, .control]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Q), character: "q", modifiers: []))
    #expect(!keys.matches(keyCode: UInt16(kVK_RightArrow), character: nil, modifiers: [.command, .function]))
    #expect(!keys.matches(keyCode: UInt16(kVK_LeftArrow), character: nil, modifiers: [.option, .function]))
  }

  /// Pages keep every other shortcut, as in Chrome: Cmd-S, Cmd-Z, Cmd-F, Cmd-R. Cmd-D left this list with
  /// KB-012 (#108): it pins the current tab (BH-055).
  @Test(arguments: [(kVK_ANSI_S, "s"), (kVK_ANSI_Z, "z"), (kVK_ANSI_F, "f"), (kVK_ANSI_R, "r")])
  func `other command keys are not reserved`(keyCode: Int, character: String) {
    #expect(!keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: .command))
  }

  /// #103: the tab switcher's keys are reserved, as Chromium reserves them for its own tab cycling.
  @Test func `ctrl tab and ctrl shift tab are reserved`() {
    #expect(keys.matches(keyCode: UInt16(kVK_Tab), character: "\t", modifiers: .control))
    #expect(keys.matches(keyCode: UInt16(kVK_Tab), character: "\t", modifiers: [.control, .shift]))
    #expect(!keys.matches(keyCode: UInt16(kVK_Tab), character: "\t", modifiers: []))
  }

  /// KB-019 (#110): Shift-Cmd-K clears the current Space's Today tabs; Cmd-K alone stays the page's.
  @Test func `clear today is reserved with shift only`() {
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_K), character: "k", modifiers: [.command, .shift]))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_K), character: "K", modifiers: [.command, .shift]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_K), character: "k", modifiers: .command))
  }

  /// #489: a focused page takes Ctrl-1 ... Ctrl-9 as key equivalents and `ArktBrowserWindow::HandleKeyboardEvent`
  /// only hands Cmd keys back to the menu, so Space switching stops once a page has focus. They are reserved.
  @Test(arguments: [
    (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
    (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
  ])
  func `ctrl digit keys are reserved`(keyCode: Int, character: String) {
    #expect(keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: .control))
  }

  /// Digits alone are page text, Cmd-digit is Chromium's own (not an Arkt item), Ctrl-0 and Ctrl-letter stay the
  /// page's.
  @Test func `digits without exactly control are not reserved`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "1", modifiers: []))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "1", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "1", modifiers: [.control, .option]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_0), character: "0", modifiers: .control))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_A), character: "a", modifiers: .control))
  }

  /// #497: AZERTY types "&", "é", quote, apostrophe, "(", "§", "è", "!" and "ç" on the digit row without Shift, so the
  /// Space keys must match by key code there (the character is not the digit).
  @Test(arguments: [
    (kVK_ANSI_1, "&"), (kVK_ANSI_2, "é"), (kVK_ANSI_3, "\""), (kVK_ANSI_4, "'"), (kVK_ANSI_5, "("),
    (kVK_ANSI_6, "§"), (kVK_ANSI_7, "è"), (kVK_ANSI_8, "!"), (kVK_ANSI_9, "ç"),
  ])
  func `azerty digit row keys are reserved for spaces`(keyCode: Int, character: String) {
    #expect(keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: .control))
  }

  /// #497: the menu also takes Ctrl with the numeric keypad digits as Space 1 ... 9.
  @Test(arguments: [
    (kVK_ANSI_Keypad1, "1"), (kVK_ANSI_Keypad4, "4"), (kVK_ANSI_Keypad5, "5"), (kVK_ANSI_Keypad9, "9"),
  ])
  func `keypad digit keys are reserved for spaces`(keyCode: Int, character: String) {
    for flags: NSEvent.ModifierFlags in [[.control, .numericPad], [.control, .shift, .numericPad]] {
      #expect(keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: flags))
      #expect(keys.matches(keyCode: UInt16(keyCode), character: "", modifiers: flags))
      #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Keypad0), character: "0", modifiers: flags))
    }
    #expect(!keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: [.command, .numericPad]))
  }

  /// #497: the Split View switch keys (Ctrl-Shift-1 ... 4) on AZERTY, and "-", "=" and the bracket keys, which sit on
  /// other key codes or type other characters there.
  @Test func `azerty split keys are reserved`() {
    let flags: NSEvent.ModifierFlags = [.control, .shift]
    for (code, character) in [(kVK_ANSI_1, "&"), (kVK_ANSI_2, "é"), (kVK_ANSI_3, "\""), (kVK_ANSI_4, "'")] {
      #expect(keys.matches(keyCode: UInt16(code), character: character, modifiers: flags), "switch \(character)")
    }
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_6), character: "-", modifiers: flags), "AZERTY's minus key")
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_Equal), character: "=", modifiers: flags))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_RightBracket), character: "$", modifiers: flags), "the ] key")
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_LeftBracket), character: "^", modifiers: flags), "the [ key")
  }

  /// #497: QWERTZ keeps the digit row, moves Z and Y, and types "-" on the slash key.
  @Test func `qwertz keys`() {
    for (code, character) in [(kVK_ANSI_1, "1"), (kVK_ANSI_5, "5"), (kVK_ANSI_9, "9")] {
      #expect(keys.matches(keyCode: UInt16(code), character: character, modifiers: .control))
    }
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_Slash), character: "-", modifiers: [.control, .shift]),
            "QWERTZ's minus key")
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_RightBracket), character: "+", modifiers: [.control, .shift]))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_LeftBracket), character: "ü", modifiers: [.control, .shift]))
    // Z and Y trade places: Cmd-Z (undo) on QWERTZ's Z key is the page's, Cmd-W is still the W key.
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Y), character: "z", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Z), character: "y", modifiers: .command))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "w", modifiers: .command))
  }

  /// #497: matching a digit-row key by key code must not reserve other modifiers or the zero key.
  @Test func `layout keys keep exact modifiers`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "&", modifiers: []))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "&", modifiers: .command))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_1), character: "&", modifiers: [.control, .option]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_0), character: "à", modifiers: .control))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Q), character: "a", modifiers: .control))
  }

  /// #489: every main-menu key equivalent without Cmd is reserved, because a focused page swallows it and the engine
  /// hands back only Cmd keys. Guards the Space items (Ctrl-1 ... Ctrl-9) and the Split View items (Ctrl-Shift-...).
  @MainActor
  @Test func `every menu key without command is reserved`() {
    _ = NSApplication.shared             // `SpacesMenu` reads `NSApp` when it is created
    let spaces = SpacesMenu(leading: [], trailing: [])
    spaces.entries = { (0..<12).map { SpacesMenu.Entry(id: SpaceID(), title: "S\($0)") } }
    spaces.refreshList()
    let items = Self.flattened(spaces.items + SplitMenu.items())
    let keyed = items.filter { !$0.keyEquivalent.isEmpty && !$0.keyEquivalentModifierMask.contains(.command) }
    #expect(keyed.count >= 9 + 8, "the Space and Split View items carry keys")
    for item in keyed {
      let reserved = keys.matches(keyCode: UInt16.max, character: item.keyEquivalent,
                                  modifiers: item.keyEquivalentModifierMask)
      #expect(reserved, "\(item.title) is reserved")
    }
  }

  @MainActor
  private static func flattened(_ items: [NSMenuItem]) -> [NSMenuItem] {
    items.flatMap { [$0] + flattened($0.submenu?.items ?? []) }
  }
}
