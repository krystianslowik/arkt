import AppKit

/// The target of Edit > Undo (Cmd-Z, KB-011): reopens the most recently closed tab or Peek (BH-074, BH-150) when
/// the key browser window has something to reopen and no text is being edited there; otherwise Undo goes down the
/// responder chain as usual (a text field, a page's editor, the command bar).
///
/// A page keeps Cmd-Z first: the engine hands the main menu only the key equivalents the page did not handle
/// (`ArktBrowserWindow::HandleKeyboardEvent`), so a web app with its own undo keeps it. What reaches the menu from a
/// page that is not editing text reopens. A page's text field is recognised by the page view's text input type, a
/// password field included (its input context is nil there).
///
/// The menu item holds its target weakly: the app keeps the router alive.
@MainActor
public final class ReopenUndoRouter: NSObject, NSMenuItemValidation {
  private let window: @MainActor () -> NSWindow?

  /// `window`: the window whose stack Cmd-Z walks; the key window in the app.
  public init(window: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow }) {
    self.window = window
  }

  /// Edit > Undo.
  @objc public func undo(_ sender: Any?) {
    if let controller = reopeningController() {
      controller.reopenClosed()
      return
    }
    NSApp.sendAction(#selector(UndoActions.undo(_:)), to: nil, from: sender)
  }

  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if reopeningController() != nil { return true }
    guard let target = NSApp.target(forAction: #selector(UndoActions.undo(_:)), to: nil, from: menuItem) else {
      return false
    }
    if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(menuItem) }
    if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(menuItem) }
    return true
  }

  /// The browser window controller that Cmd-Z reopens in now, if any.
  private func reopeningController() -> ShellWindowController? {
    guard let window = window(), let controller = window.windowController as? ShellWindowController,
          controller.canReopenClosed, !Self.isEditingText(window.firstResponder) else { return nil }
    return controller
  }

  /// A text view (a field editor), or a page with an editable field focused: Chromium's page view reports the focused
  /// field's text input type (0, none, when nothing editable has the focus; a password field included otherwise),
  /// and any other view counts when it has an input context.
  static func isEditingText(_ responder: NSResponder?) -> Bool {
    guard let responder else { return false }
    if responder is NSText { return true }
    if responder.responds(to: textInputTypeSelector),
       let type = (responder.value(forKey: textInputTypeKey) as? NSNumber)?.intValue {
      return type != 0
    }
    return (responder as? NSView)?.inputContext != nil
  }

  /// `RenderWidgetHostViewCocoa.textInputType` (`ui::TextInputType`, `TEXT_INPUT_TYPE_NONE` is 0). Its input context is
  /// nil in a password field, so the input context alone would let Cmd-Z there reopen a tab.
  private static let textInputTypeKey = "textInputType"
  private static let textInputTypeSelector = NSSelectorFromString(textInputTypeKey)
}

/// Names the standard `undo:` action for `#selector`.
@objc private protocol UndoActions {
  func undo(_ sender: Any?)
}
