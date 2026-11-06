import AppKit

/// Where a popover drawn inside the window (Edit Pin, the theme creator) gives the keyboard back when it closes
/// (#696): the responder that had it when the popover opened, while that one is still on screen in the same window.
/// When it is gone (its tab closed or replaced, the Space changed), the window is left without one, and the shell
/// window gives the keyboard to the current tab's page (`ShellWindowController.focusPageIfKeyboardIsFree`).
@MainActor
struct KeyboardReturn {
  /// A field's editing session counts as the field: the shared field editor will belong to the popover's own field.
  private weak var responder: NSView?
  /// Puts back the sidebar's keyboard cursor, which its view drops on resigning first responder.
  private var restoreCursor: (@MainActor (NSWindow) -> Bool)?

  /// Notes who has `window`'s keyboard now, before the popover takes it.
  init(from window: NSWindow?) {
    let current = window?.firstResponder
    if let editor = current as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
      responder = field
    } else {
      responder = current as? NSView
    }
    restoreCursor = (responder as? any KeyboardCursorHolder)?.keyboardCursorRestorer()
  }

  /// Gives `window`'s keyboard back to the noted responder, or to nobody when it is no longer on screen there or is
  /// inside `leaving`, a view about to leave the screen (the page of a Space the sidebar moves away from). A text
  /// field gets it back as a click into it does: editing again, with all of its text selected.
  func give(in window: NSWindow, leaving: NSView? = nil) {
    if let view = responder, view.window === window, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty,
       leaving.map({ !view.isDescendant(of: $0) }) ?? true {
      if let restoreCursor {
        if restoreCursor(window) { return }
      } else if window.makeFirstResponder(view),
                window.firstResponder === view || (window.firstResponder as? NSText)?.delegate === view {
        return                                // a field holds the keyboard through the field editor
      }
    }
    window.makeFirstResponder(nil)
  }
}

/// A sidebar view whose keyboard focus is a row or tile cursor (Ctrl-Space, BH-019) that it drops when it resigns
/// first responder.
@MainActor
protocol KeyboardCursorHolder: NSView {
  /// A way to put the cursor it holds now back and take the keyboard again, true when it did; nil without a cursor.
  /// The cursor follows its node: false when the node is gone.
  func keyboardCursorRestorer() -> (@MainActor (NSWindow) -> Bool)?
}

extension SidebarOutlineView: KeyboardCursorHolder {
  func keyboardCursorRestorer() -> (@MainActor (NSWindow) -> Bool)? {
    guard let row = keyboardFocusRow, let item = item(atRow: row) as? NSObject else { return nil }
    return { [weak self] window in
      guard let self else { return false }
      let row = self.row(forItem: item)
      guard row >= 0, isKeyboardFocusable(row) else { return false }
      keyboardFocusRow = row
      guard window.makeFirstResponder(self), window.firstResponder === self else {
        keyboardFocusRow = nil
        return false
      }
      return true
    }
  }
}

extension FavoritesCollectionView: KeyboardCursorHolder {
  func keyboardCursorRestorer() -> (@MainActor (NSWindow) -> Bool)? {
    guard let id = keyboardCursor?() else { return nil }
    return { [weak self] window in
      guard let self, restoreKeyboardCursor?(id) == true else { return false }
      guard window.makeFirstResponder(self), window.firstResponder === self else {
        onKeyboardFocusResigned?()
        return false
      }
      return true
    }
  }
}
