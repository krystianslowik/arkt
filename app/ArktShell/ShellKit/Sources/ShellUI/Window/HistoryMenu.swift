import AppKit
import Carbon.HIToolbox

/// The main menu's History menu. Cmd-Left and Cmd-Right are hidden second keys of Back and Forward (KB-031, KB-032,
/// #948), as in Chrome and Safari, except while the keyboard is in editable text, where they move the caret to the
/// line start or end.
///
/// A page keeps them first: they are not reserved keys (`ReservedKeys`), so a focused page sees them before the menu,
/// and the menu hears only the ones the page did not use (the engine hands those back,
/// `ArktBrowserWindow::HandleKeyboardEvent`; WKWebView sends them on again). A shell text field (the command bar, the
/// address bar, a rename field) gets no such turn: AppKit asks the main menu before the field editor's `keyDown`, and
/// a disabled item still takes its key. So this menu declines the two keys while the event's window edits text.
@MainActor
public final class HistoryMenu: NSMenu {
  /// `NSMenu` declares this outside the main actor; AppKit calls it on the main thread.
  public nonisolated override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if Self.isHistoryArrow(event) {
      let windowNumber = event.windowNumber
      if MainActor.assumeIsolated({ Self.editsText(windowNumber: windowNumber) }) { return false }
    }
    return super.performKeyEquivalent(with: event)
  }

  /// Cmd-Left or Cmd-Right, without Shift, Option or Control.
  nonisolated static func isHistoryArrow(_ event: NSEvent) -> Bool {
    event.type == .keyDown && ReservedKeys.significant(event.modifierFlags) == .command
      && (event.keyCode == UInt16(kVK_LeftArrow) || event.keyCode == UInt16(kVK_RightArrow))
  }

  /// Whether the event's window has the keyboard in editable text: a field editor, or a page with an editable field
  /// focused.
  static func editsText(windowNumber: Int) -> Bool {
    ReopenUndoRouter.isEditingText(NSApp.window(withWindowNumber: windowNumber)?.firstResponder)
  }
}
