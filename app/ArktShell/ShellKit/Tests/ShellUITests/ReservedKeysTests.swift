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
    (kVK_ANSI_Q, "q", NSEvent.ModifierFlags.command.rawValue),
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

  /// Arrow keys arrive with `.function` and `.numericPad`; Caps Lock changes nothing.
  @Test func `space switching arrows match with their extra device flags`() {
    let flags: NSEvent.ModifierFlags = [.command, .option, .function, .numericPad]
    #expect(keys.matches(keyCode: UInt16(kVK_RightArrow), character: nil, modifiers: flags))
    #expect(keys.matches(keyCode: UInt16(kVK_LeftArrow), character: nil, modifiers: flags))
    #expect(keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "t", modifiers: [.command, .capsLock]))
  }

  @Test func `extra or missing modifiers do not match`() {
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_T), character: "t", modifiers: [.command, .shift]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "w", modifiers: [.command, .option]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_W), character: "w", modifiers: [.command, .control]))
    #expect(!keys.matches(keyCode: UInt16(kVK_ANSI_Q), character: "q", modifiers: []))
    #expect(!keys.matches(keyCode: UInt16(kVK_RightArrow), character: nil, modifiers: [.command, .function]))
    #expect(!keys.matches(keyCode: UInt16(kVK_LeftArrow), character: nil, modifiers: [.option, .function]))
  }

  /// Pages keep every other shortcut, as in Chrome: Cmd-S, Cmd-D, Cmd-Z, Cmd-F, Cmd-R.
  @Test(arguments: [(kVK_ANSI_S, "s"), (kVK_ANSI_D, "d"), (kVK_ANSI_Z, "z"), (kVK_ANSI_F, "f"), (kVK_ANSI_R, "r")])
  func `other command keys are not reserved`(keyCode: Int, character: String) {
    #expect(!keys.matches(keyCode: UInt16(keyCode), character: character, modifiers: .command))
  }
}
