import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShellUI

/// Which raw key events the switcher takes (design "Keys and what they do" and "Dismiss rules").
struct TabSwitcherKeysTests {
  private func keyDown(_ keyCode: Int, _ character: String, _ modifiers: NSEvent.ModifierFlags,
                       open: Bool) -> TabSwitcherKeyAction {
    TabSwitcherKeys.action(forKeyDown: UInt16(keyCode), character: character, modifiers: modifiers, isOpen: open)
  }

  // MARK: Closed

  @Test func `ctrl tab opens forward and ctrl shift tab backward`() {
    #expect(keyDown(kVK_Tab, "\t", .control, open: false) == .open(.forward))
    #expect(keyDown(kVK_Tab, "\t", [.control, .shift], open: false) == .open(.backward))
  }

  @Test func `caps lock and the function flag do not change the match`() {
    #expect(keyDown(kVK_Tab, "\t", [.control, .capsLock, .function], open: false) == .open(.forward))
  }

  @Test(arguments: [
    (kVK_Tab, "\t", NSEvent.ModifierFlags([]).rawValue),
    (kVK_Tab, "\t", NSEvent.ModifierFlags([.control, .command]).rawValue),
    (kVK_Tab, "\t", NSEvent.ModifierFlags([.control, .option]).rawValue),
    (kVK_ANSI_Grave, "`", NSEvent.ModifierFlags.control.rawValue),     // only while open
    (kVK_ANSI_W, "w", NSEvent.ModifierFlags.control.rawValue),
    (kVK_Escape, "\u{1b}", NSEvent.ModifierFlags([]).rawValue),
  ])
  func `other keys pass while closed`(keyCode: Int, character: String, modifiers: UInt) {
    #expect(keyDown(keyCode, character, NSEvent.ModifierFlags(rawValue: modifiers), open: false) == .pass)
  }

  // MARK: Open

  @Test func `tab moves forward and shift tab or backtick backward`() {
    #expect(keyDown(kVK_Tab, "\t", .control, open: true) == .move(.forward))
    #expect(keyDown(kVK_Tab, "\u{19}", [.control, .shift], open: true) == .move(.backward))
    #expect(keyDown(kVK_ANSI_Grave, "`", .control, open: true) == .move(.backward))
    #expect(keyDown(kVK_ANSI_Grave, "`", [.control, .shift], open: true) == .move(.backward))
  }

  @Test func `w closes the highlighted row and escape cancels`() {
    #expect(keyDown(kVK_ANSI_W, "w", .control, open: true) == .closeHighlighted)
    #expect(keyDown(kVK_Escape, "\u{1b}", .control, open: true) == .cancel)
  }

  /// A layout that types another letter on the W key (Cyrillic) still closes; AZERTY's Z on that key does not.
  @Test func `w matches by character, else by key code`() {
    #expect(keyDown(kVK_ANSI_W, "ц", .control, open: true) == .closeHighlighted)
    #expect(keyDown(kVK_ANSI_W, "z", .control, open: true) == .dismissThenPass)
    #expect(keyDown(kVK_ANSI_Z, "w", .control, open: true) == .closeHighlighted)
  }

  /// Cmd-W while cycling closes the current tab the usual way; the switcher does not eat it.
  @Test func `cmd w and any other key dismiss and pass on`() {
    #expect(keyDown(kVK_ANSI_W, "w", [.control, .command], open: true) == .dismissThenPass)
    #expect(keyDown(kVK_ANSI_A, "a", .control, open: true) == .dismissThenPass)
    #expect(keyDown(kVK_Return, "\r", .control, open: true) == .dismissThenPass)
  }

  @Test func `releasing ctrl commits and other flag changes do nothing`() {
    #expect(TabSwitcherKeys.action(forFlagsChanged: [], isOpen: true) == .commit)
    #expect(TabSwitcherKeys.action(forFlagsChanged: .shift, isOpen: true) == .commit)
    #expect(TabSwitcherKeys.action(forFlagsChanged: [.control, .shift], isOpen: true) == .pass)
    #expect(TabSwitcherKeys.action(forFlagsChanged: [], isOpen: false) == .pass)
  }
}
