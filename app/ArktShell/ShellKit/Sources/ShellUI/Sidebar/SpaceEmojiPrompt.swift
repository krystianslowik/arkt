import AppKit

/// "Emoji..." on the Space header's Icon menu (D1 on #279): a sheet with one text field, opened together with the
/// system Character Viewer so an emoji can be picked or typed. Set Icon is enabled only while the field holds exactly
/// one emoji (`SpaceIconInfo.validatedEmoji(_:)`); the caller still validates what it writes. The wording is [I].
@MainActor
final class SpaceEmojiPrompt: NSObject, NSTextFieldDelegate {
  static let setTitle = "Set Icon"

  let alert: NSAlert
  let field: NSTextField
  private let setButton: NSButton

  init(current: String?) {
    let alert = NSAlert()
    alert.messageText = "Space Emoji"
    alert.informativeText = "Type one emoji, or pick one in the Character Viewer."
    let field = NSTextField(string: current ?? "")
    field.placeholderString = "Emoji"
    field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
    alert.accessoryView = field
    setButton = alert.addButton(withTitle: Self.setTitle)
    alert.addButton(withTitle: "Cancel")
    self.alert = alert
    self.field = field
    super.init()
    field.delegate = self
    updateSetButton()
  }

  /// Set Icon can be pressed.
  var canSet: Bool { setButton.isEnabled }

  func controlTextDidChange(_ notification: Notification) { updateSetButton() }

  private func updateSetButton() {
    setButton.isEnabled = SpaceIconInfo.validatedEmoji(field.stringValue) != nil
  }

  /// Shows the sheet on `window` with the Character Viewer. `answer` gets the field's text after Set Icon, nil after
  /// Cancel. The prompt keeps itself alive until the sheet ends.
  func begin(on window: NSWindow, answer: @escaping @MainActor (String?) -> Void) {
    alert.beginSheetModal(for: window) { [self] response in
      answer(response == .alertFirstButtonReturn ? self.field.stringValue : nil)
    }
    alert.window.makeFirstResponder(field)
    NSApp.orderFrontCharacterPalette(field)
  }
}
